open Ppx_core.Std
open Parsetree

(* extension is triggered by keword 'nk' *)
let ext_keyw = "nk"
let ext_keyw_pred = ext_keyw ^ "_pred"

(** expands `s` in `let%nk x = {| s |}` *)
let expand_nk_string ~loc ~pred s =
  let pos = Location.(loc.loc_start) in
  (* string starts after '{' and '|' *)
  let pos = Lexing.{ pos with pos_cnum = pos.pos_cnum + 2 } in
  let parser =
    let open Frenetic_NetKAT_PPX_Parser in
    if pred then pred_eof else pol_eof
  in
  try New_Lexer.parse_string ~ppx:true ~pos s parser with
  | New_Lexer.LexError (pos, s) ->
    let loc = Location.{ loc_start = pos; loc_end = pos; loc_ghost = false} in
    Location.raise_errorf ~loc "%s" s
  | New_Lexer.ParseError (token, loc_start, loc_end) ->
    let loc = Location.{ loc_start; loc_end; loc_ghost = false} in
    New_Lexer.show_token token
    |> Location.raise_errorf ~loc "parse error while reading token '%s'"

(** expands `e` in `let%nk x = e` *)
let expand_bound_expr ~pred expr =
  let loc = expr.pexp_loc in
  match expr.pexp_desc with
  (* only expand e if e = {| s |} *)
  | Pexp_constant (Pconst_string (s, Some "")) ->
    { (expand_nk_string ~loc ~pred s) with pexp_loc = loc }
  | _ ->
    Location.raise_errorf ~loc "'let%%%s' may only bind quoted NetKAT" ext_keyw

(** expands `x=e` in `let%nk x = e` *)
let expand_binding ~pred binding =
  { binding with pvb_expr = expand_bound_expr ~pred binding.pvb_expr }

(* expands `let%nk <bindings>` *)
let expand_let_decl ~loc ~path:_ ~pred bindings =
  let module B = Ast_builder.Make(struct let loc = loc end) in
  B.(pstr_value Nonrecursive (List.map (expand_binding ~pred) bindings))

(** expands `let%nk <bindings> in body` *)
let expand_let_expr ~loc ~path:_ ~pred bindings body =
  let module B = Ast_builder.Make(struct let loc = loc end) in
  B.(pexp_let Nonrecursive (List.map (expand_binding ~pred) bindings) body)

(** declare `let%nk x = e` extension *)
let nk_ext_struct pred =
  Extension.V2.declare
    (if pred then ext_keyw_pred else ext_keyw)
    Extension.Context.structure_item
    Ast_pattern.(pstr (pstr_value nonrecursive __ ^:: nil))
    (expand_let_decl ~pred)

(** declare `let%nk x = e in b` extension *)
let nk_ext_expr pred =
  Extension.V2.declare
    (if pred then ext_keyw_pred else ext_keyw)
    Extension.Context.expression
    Ast_pattern.(single_expr_payload (pexp_let nonrecursive __ __))
    (expand_let_expr ~pred)
;;

Ppx_driver.register_transformation "netkat"
  ~extensions:[ nk_ext_expr true ; nk_ext_struct true ;
                nk_ext_expr false; nk_ext_struct false; ]
;;
