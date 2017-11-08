open Core

[@@@ocaml.warning "-30"]

let fprintf = Format.fprintf


(** {2} fields and values *)
type field = string [@@deriving sexp, show, compare, eq, hash]
type value = int [@@deriving sexp, show, compare, eq, hash]

type 'field header_val = 'field * value [@@deriving sexp, compare, eq, hash]


(** {2} predicates and policies *)

(* local/meta fields *)
type 'field meta_init =
  | Alias of 'field
  | Const of value
  [@@deriving sexp, compare, hash]

type 'field pred =
  | True
  | False
  | Test of 'field header_val
  | And of 'field pred * 'field pred
  | Or of 'field pred * 'field pred
  | Neg of 'field pred
  [@@deriving sexp, compare, hash]

type 'field  policy =
  | Filter of 'field pred
  | Modify of 'field header_val
  | Seq of 'field policy * 'field policy
  | Ite of 'field pred * 'field policy * 'field policy
  | While of 'field pred * 'field policy
  | Choice of ('field policy * Prob.t) list
  | Let of { id : 'field; init : 'field meta_init; mut : bool; body : 'field policy }
  [@@deriving sexp, compare, hash]

let pp_hv op fmt hv =
  fprintf fmt "@[%s%s%d@]" (fst hv) op (snd hv)

let pp_policy fmt (p : string policy) =
  let rec do_pol ctxt fmt (p : string policy) =
    match p with
    | Filter pred -> do_pred ctxt fmt pred
    | Modify hv -> pp_hv "<-" fmt hv
    | Seq (p1, p2) ->
      begin match ctxt with
        | `PAREN
        | `SEQ_L
        | `SEQ_R -> fprintf fmt "@[%a;@ %a@]" (do_pol `SEQ_L) p1 (do_pol `SEQ_R) p2
        | _ -> fprintf fmt "@[(@[%a;@ %a@])@]" (do_pol `SEQ_L) p1 (do_pol `SEQ_R) p2
      end
    | While (a,p) ->
      fprintf fmt "@[WHILE@ @[<2>%a@]@ DO@ @[<2>%a@]@]"
        (do_pred `COND) a (do_pol `While) p
    | Ite (a, p, q) ->
      fprintf fmt "@[IF@ @[<2>%a@]@ THEN@ @[<2>%a@]@ ELSE@ @[<2>%a@]@]"
        (do_pred `COND) a (do_pol `ITE_L) p (do_pol `ITE_R) q
    | Let { id; init; mut; body } ->
      fprintf fmt "@[@[%a@]@ IN@ @[<0>%a@]"
        do_binding (id, init, mut) (do_pol `PAREN) body
    | Choice ps ->
      fprintf fmt "@[?{@;<1-2>";
      List.iter ps ~f:(fun (p,q) ->
        fprintf fmt "@[%a@ %@@ %a;@;@]" (do_pol `CHOICE) p Q.pp_print q);
      fprintf fmt "@;<1-0>}@]"
  and do_pred ctxt fmt (p : string pred) =
    match p with
    | True -> fprintf fmt "@[1@]"
    | False -> fprintf fmt "@[0@]"
    | Test hv -> pp_hv "=" fmt hv
    | Neg p -> fprintf fmt "@[¬%a@]" (do_pred `Neg) p
    | Or (a1, a2) ->
      begin match ctxt with
        | `PAREN
        | `Or -> fprintf fmt "@[%a@ or@ %a@]" (do_pred `Or) a1 (do_pred `Or) a2
        | _ -> fprintf fmt "@[(@[%a@ or@ %a@])@]" (do_pred `Or) a1 (do_pred `Or) a2
      end
    | And (p1, p2) ->
      begin match ctxt with
        | `PAREN
        | `SEQ_L
        | `SEQ_R -> fprintf fmt "@[%a;@ %a@]" (do_pred `SEQ_L) p1 (do_pred `SEQ_R) p2
        | _ -> fprintf fmt "@[(@[%a;@ %a@])@]" (do_pred `SEQ_L) p1 (do_pred `SEQ_R) p2
      end
  and do_binding fmt (id, init, mut) =
    fprintf fmt "%s@ %s@ :=@ %s"
      (if mut then "var" else "let")
      id
      (match init with
        | Alias f -> f
        | Const v -> Int.to_string v)

  in
  do_pol `PAREN fmt p


(** constructors *)
module Constructors = struct
  (* module Dumb = struct *)
    let drop = Filter False
    let skip = Filter True
    let test hv = Test hv
    let filter a = Filter a
    let modify hv = Modify hv
    let neg a = Neg a
    let disj a b = Or (a,b)
    let seq p q = Seq (p, q)
    let choice ps = Choice ps
    let ite a p q = Ite (a, p, q)
    let whl a p = While (a, p)
    let mk_while a p = While (a, p)

    let seqi n ~f =
      Array.init n ~f
      |> Array.fold ~init:skip ~f:seq

    let choicei n ~f =
      Array.init n ~f
      |> Array.to_list
      |> choice

    let mk_big_ite ~default = List.fold ~init:default ~f:(fun q (a, p) -> ite a p q)

end

  (* module Smart = struct
    let drop = Dumb.drop
    let skip = Dumb.skip
    let test = Dumb.test
    let modify = Dumb.modify

    let neg a =
      match a.p with
      | Neg { p } -> { a with p }
      | _ -> Dumb.neg a

    let disj a b =
      if a = skip || b = drop then a else
      if b = skip || a = drop then b else
      Dumb.disj a b

    let seq p q =
      (* use physical equality? *)
      if p = drop || q = skip then p else
      if q = drop || p = skip then q else
      Dumb.seq p q

    let choice ps =
      (* smash equal -> requires hashconsing *)
      match List.filter ps ~f:(fun (p,r) -> not Q.(equal r zero)) with
      | [(p,r)] -> assert Q.(equal r one); p
      | ps -> Dumb.choice ps

    let ite a p q =
      if a = drop then q else
      if a = skip then p else
      (* if p = q then p else *)
      Dumb.ite a p q

    let mk_while a p =
      if a = drop then skip else
      Dumb.mk_while a p

    let seqi n ~f =
      Array.init n ~f
      |> Array.fold ~init:skip ~f:seq

    let choicei n ~f =
      Array.init n ~f
      |> Array.to_list
      |> choice

    let mk_union = disj
    let mk_big_union ~init = List.fold ~init ~f:(fun p q -> if p = drop then q
                                                  else mk_union p q)
    let mk_big_ite ~default = List.fold ~init:default ~f:(fun q (a, p) -> ite a p q)

  end
end *)
module Syntax = struct
  include Constructors
  let ( ?? ) hv = filter (test hv)
  let ( ??? ) hv = test hv
  let ( !! ) hv = modify hv
  let ( >> ) p q = Seq(p, q)
  let ( & ) a b = disj a b
  let ( ?@ ) dist = choice dist (* ?@[p , 1//2; q , 1//2] *)
  let ( // ) m n = Q.(m // n)
  let ( @ ) p r = (p,r)
end
