open Packet
open NetCore_Types
open NetCore_Util
open SDN_Headers
open Unix
open NetCore_Gensym

(* The [Sat] module provides a representation of formulas in
   first-order logic, a representation of packets, and a function for
   testing their satisfiability. *)
module Sat = struct

  type zVar = string

  type zSort = 
    | SPacket
    | SInt
    | SSet 
    | SBool
    | SFunction of (zSort list) * zSort
    | SMacro of ((zVar * zSort) list) * zSort

  type zTerm = 
    | TUnit 
    | TVar of zVar
    | TInt of Int64.t
    | TPkt of switchId * portId * packet
    | TApp of zTerm * (zTerm list)

  type zFormula =
    | ZTerm of zTerm
    | ZTrue
    | ZFalse 
    | ZNot of zFormula
    | ZAnd of zFormula list
    | ZOr of zFormula list
    | ZEquals of zFormula * zFormula
    | ZComment of string * zFormula
    | ZForall of ((zVar * zSort) list) * zFormula
    | ZIf of zFormula * zFormula * zFormula

  type zDeclare = 
    | ZDeclareVar of zVar * zSort
    | ZDefineVar of zVar * zSort * zFormula
    | ZDeclareAssert of zFormula

  type zProgram = 
    | ZProgram of zDeclare list

  (* fresh variables *)
  let fresh_cell = ref []

  let fresh s = 
    let l = !fresh_cell in  
    let n = List.length l in 
    let x = match s with
      | SPacket -> 
        Printf.sprintf "_pkt%d" n
      | SInt -> 
        Printf.sprintf "_n%d" n
      | SSet -> 
        Printf.sprintf "_s%d" n 
      | SFunction _ -> 
        Printf.sprintf "_f%d" n 
      | _ -> failwith "not implemented in fresh" in 
    fresh_cell := ZDeclareVar(x,s)::l;
    x



  let reset () = 
    fresh_cell := []

  (* serialization *)
  let serialize_located_packet (sw,pt,pkt) = 
    Printf.sprintf "(Packet %s %s %s %s)" 
      (Int64.to_string sw) 
      (Int32.to_string pt)
      (Int64.to_string pkt.dlSrc)
      (Int64.to_string pkt.dlDst)


  let rec serialize_sort = function
    | SInt -> 
      "Int"
    | SPacket -> 
      "Packet"
    | SBool ->
      "Bool"
    | SSet -> 
      Printf.sprintf "Set"
    | SFunction(sortlist,sort2) -> 
      Printf.sprintf "(%s) %s" 
        (intercalate serialize_sort " " sortlist)
        (serialize_sort sort2)
    | SMacro(args,ret) -> 
      let serialize_arglist args = 
	(intercalate (fun (a, t) -> Printf.sprintf "(%s %s)" a (serialize_sort t)) " " args) in
      Printf.sprintf "(%s) %s"
	(serialize_arglist args)
	(serialize_sort ret)

  let serialize_arglist args = 
    (intercalate (fun (a, t) -> Printf.sprintf "(%s %s)" a (serialize_sort t)) " " args)

	 

  let rec serialize_term term : string = 
    match term with 
      | TUnit -> 
        "()"
      | TVar x -> 
	x
      | TPkt (sw,pt,pkt) -> 
	serialize_located_packet (sw,pt,pkt)
      | TInt n -> 
	Printf.sprintf "%s" 
          (Int64.to_string n)
      | TApp (term1, terms) -> 
	Printf.sprintf "(%s %s)" (serialize_term term1) (intercalate serialize_term " " terms)

  let serialize_comment c = 
    Printf.sprintf "%s" c

  let rec serialize_formula = function
    | ZTrue -> 
      Printf.sprintf "true"
    | ZFalse -> 
      Printf.sprintf "false"
    | ZNot f1 -> 
      Printf.sprintf "(not %s)" (serialize_formula f1)
    | ZEquals (t1, t2) -> 
      Printf.sprintf "(equals %s %s)" (serialize_formula t1) (serialize_formula t2)
    | ZAnd([]) -> 
      Printf.sprintf "true"
    | ZAnd([f]) -> 
      Printf.sprintf "%s" (serialize_formula f)
    | ZAnd(f::fs) -> 
      Printf.sprintf "(and %s %s)" (serialize_formula f) (serialize_formula (ZAnd(fs)))
    | ZOr([]) -> 
      Printf.sprintf "false"
    | ZOr([f]) -> 
      Printf.sprintf "%s" (serialize_formula f)
    | ZOr(f::fs) -> 
      Printf.sprintf "(or %s %s)" (serialize_formula f) (serialize_formula (ZOr(fs)))
    | ZComment(c, f) -> 
      Printf.sprintf "\n;%s\n%s\n; END %s\n" c (serialize_formula f) c
    | ZForall (args, form) ->
      Printf.sprintf "(forall (%s) %s)" (serialize_arglist args) (serialize_formula form)
    | ZTerm t -> serialize_term t
    | ZIf (i, t, e) -> Printf.sprintf "(ite %s %s %s)" 
      (serialize_formula i) (serialize_formula t) (serialize_formula e)

  let serialize_declare d = 
    match d with 
      | ZDefineVar (x, s, b) -> 
	Printf.sprintf "(define-fun %s %s %s)" x (serialize_sort s) (serialize_formula b)
      | ZDeclareVar (x, s) ->
        (match s with 
          | SFunction _ -> Printf.sprintf "(declare-fun %s %s)" x (serialize_sort s)
	  | SMacro _ -> failwith "macros should be in ZDefineVar"
	  | SPacket -> ";; declaring packet "^x^"\n" ^
	    "(declare-var "^x^" "^(serialize_sort s)^")" ^
	    "(declare-var "^x^"-int1 Int)" ^ 
	    "(declare-var "^x^"-int2 Int)" ^
	    "(declare-var "^x^"-int3 Int)" ^
	    "(declare-var "^x^"-int4 Int)" ^
	    "(declare-var "^x^"-int5 Int)" ^
	    "(declare-var "^x^"-int6 Int)" ^
	    "(declare-var "^x^"-int7 Int)" ^
	    "(declare-var "^x^"-int8 Int)" ^
	    "(declare-var "^x^"-int9 Int)" ^
	    "(declare-var "^x^"-int10 Int)" ^
	    "(declare-var "^x^"-int11 Int)" ^
	    "(declare-var "^x^"-int12 Int)" ^
	    "(assert (= "^x^"" ^
		"(packet "^x^"-int11 "^x^"-int10 "^x^"-int9" ^
		  " "^x^"-int8 "^x^"-int7 "^x^"-int6" ^
		  " "^x^"-int5 "^x^"-int12 "^x^"-int4" ^
		  " "^x^"-int3 "^x^"-int2 "^x^"-int1)))\n" ^
	    ";; end declaration"
          | _ -> Printf.sprintf "(declare-var %s %s)" x (serialize_sort s)
	)
      | ZDeclareAssert(f) -> 
        Printf.sprintf "(assert %s)" (serialize_formula f)


  let define_z3_fun (name : string) (arglist : (zVar * zSort) list)  (rettype : zSort) (body : zFormula)  = 
    let args = List.map (fun (a, t) -> TVar a) arglist in
    let argtypes = List.map (fun (a, t) -> t) arglist in
    [ZDeclareVar (name, SFunction (argtypes, rettype)); ZDeclareAssert (ZForall (arglist, ZEquals (ZTerm (TApp ((TVar name), args)), body))) ]

  let foo = 4

  let define_z3_macro (name : string) (arglist : (zVar * zSort) list)  (rettype : zSort) (body : zFormula)  = 
    [ZDefineVar (name, SMacro (arglist, rettype), body)]


  let zApp x = (fun l -> ZTerm (TApp (x, l)))

  let z3_fun (arglist : (zVar * zSort) list) (rettype : zSort) (body : zFormula) : zTerm = 
    let l = !fresh_cell in
    let name = to_string (gensym ()) in
    fresh_cell := (define_z3_fun name arglist rettype body) @ l;
    TVar name

  let z3_macro (name : string) (arglist : (zVar * zSort) list) (rettype : zSort)(body : zFormula) : zTerm = 
    let l = !fresh_cell in
    let name = name ^ "_" ^ to_string (gensym ()) in
    fresh_cell := (define_z3_macro name arglist rettype body) @ l;
    TVar name

  let z3_static =

    (*some convenience functions to make z3 function definitions more readable*)

    let x = (ZTerm (TVar "x")) in
    let y = (ZTerm (TVar "y")) in
    let s = (ZTerm (TVar "s")) in
    let s1 = (ZTerm (TVar "s1")) in
    let s2 = (ZTerm (TVar "s2")) in
    let z3app2 f = 
      (fun sp xp -> match sp, xp with 
	| (ZTerm (TVar s)), (ZTerm (TVar x)) -> ZTerm (TApp ((TVar f ), [(TVar s);(TVar x)]))
	| _ -> failwith "need to apply functions to variables as of right now.") in
    let z3app3 f = (fun sp xp yp -> match sp, xp, yp with 
      | (ZTerm (TVar s)), (ZTerm (TVar x)), (ZTerm (TVar y)) -> ZTerm (TApp ((TVar f ), [(TVar s);(TVar x); (TVar y)]))
      | _ -> failwith "need to apply functions to variables as of right now.") in
    let select = z3app2 "select" in
    let store = z3app3 "store" in
    let set_diff = z3app2 "set_diff" in
    let map = (fun fp l1p l2p -> match fp, l1p, l2p with 
      | f, (ZTerm (TVar l1)), ZTerm (TVar l2) -> ZTerm (TApp ( (TApp (TVar "_", [TVar "map"; TVar f]  )), [(TVar l1); (TVar l2)]))
      | _ -> failwith "need to apply functions to variables as of right now.") in
    let nopacket = (ZTerm (TVar "nopacket")) in
    let set_empty = (ZTerm (TVar "set_empty")) in
    
    (* actual z3 function definitions *)

    (define_z3_fun "packet_and"  [("x", SPacket); ("y", SPacket)] SPacket
       (ZIf (ZAnd 
	       [ZNot (ZEquals (x, nopacket)); 
		ZEquals (x, y)], 
	     x, nopacket))) @  

      define_z3_fun "packet_or" [("x", SPacket); ("y", SPacket)] SPacket
       (ZIf (ZEquals (x, nopacket), y, x)) @

      define_z3_fun "packet_diff" [("x", SPacket); ("y", SPacket)] SPacket
       (ZIf (ZEquals (x,y), nopacket, x)) @

      define_z3_macro "set_mem" [("x", SPacket); ("s", SSet)] SBool
       (ZNot (ZEquals ((select s x), nopacket))) @

      define_z3_macro "set_add" [("s", SSet); ("x", SPacket)] SSet 
       (store s x x) @

      define_z3_macro "set_inter" [("s1", SSet); ("s2", SSet)] SSet
       (map "packet_and" s1 s2) @

      define_z3_macro "set_union" [("s1", SSet); ("s2", SSet)] SSet
       (map "packet_or" s1 s2) @ 

      define_z3_macro "set_diff" [("s1", SSet); ("s2", SSet)] SSet 
       (map "packet_diff" s1 s2) @

      define_z3_macro "set_subseteq" [("s1", SSet); ("s2", SSet)] SBool 
       (ZEquals (set_empty, (set_diff s1 s2))) 


  let pervasives : string = 
    "(set-option :macro-finder true)
(declare-datatypes 
 () 
 ((Packet 
   (nopacket )
   (packet 
    (Switch Int) 
    (EthDst Int) 
    (EthType Int) 
    (Vlan Int) 
    (VlanPcp Int) 
    (IPProto Int) 
    (IP4Src Int) 
    (IP4Dst Int) 
    (TCPSrcPort Int) 
    (TCPDstPort Int) 
    (EthSrc Int) 
    (InPort Int)))))" ^ "\n" ^ 
      "(define-sort Set () (Array Packet Packet))" ^ "\n (check-sat) \n"^ 
      "(define-fun set_empty () Set ((as const Set) nopacket))" ^ "\n" ^
      (intercalate serialize_declare "\n" z3_static)^ "\n" 
      
      
  let serialize_program p g : string = 
    let ZProgram(ds) = p in 
    let ds' = List.flatten [!fresh_cell; ds; g] in 
    Printf.sprintf "%s%s\n(check-sat)\n"
      pervasives (intercalate serialize_declare "\n" ds') 

  let solve prog global : bool = 
    let s = serialize_program prog global in 
    (* Printf.eprintf "%s" s; *)
    let z3_out,z3_in = open_process "z3 -in -smt2 -nw" in 
    let _ = output_string z3_in s in
    let _ = flush z3_in in 
    let _ = close_out z3_in in 
    let b = Buffer.create 17 in 
    (try
       while true do
         Buffer.add_string b (input_line z3_out);
         Buffer.add_char b '\n';
       done
     with End_of_file -> ());
    Buffer.contents b = "sat\nsat\n"
end

module Verify_Graph = struct
  open Topology
  open NetKAT_Types
  module S = SDN_Types
	
  let longest_shortest graph = 
    let vertices = Topology.get_vertices graph in
    let f acc v = 
      List.fold_left 
        (fun acc v' -> 
	  try
	    let p = Topology.shortest_path graph v v'  in
            max (List.length p) acc
	  with _ -> acc) (* TODO(mmilano): should be acc, not 0 right? *)
        0 vertices in 
    List.fold_left f 0 vertices

  let unfold_graph graph =
    let edges = Topology.get_edges graph in
    let src_port_vals h =
      let swSrc =
	(match Link.src h with
	  | Node.Switch (str, id) -> VInt.Int64 id
	  | _ -> failwith "Switch not in proper form" ) in
      let swDst =
	(match Link.dst h with
	  | Node.Switch (str, id) -> VInt.Int64 id
	  | _ -> failwith"Switch not in proper form" ) in
      let prtSrc = 
	let val64 = Int64.of_int32 (Link.srcport h) in
	VInt.Int64 val64
      in
      let prtDst = 
	let val64 = Int64.of_int32 (Link.dstport h) in
	VInt.Int64 val64 in
      (swSrc, prtSrc, swDst, prtDst) in
    let rec create_pol edgeList =
      match edgeList with
	| h::[] ->
	  let (swSrc, prtSrc, swDst, prtDst) = src_port_vals h in
	  Seq ( Seq (Filter (Test (Switch, swSrc)),
		     Filter (Test( Header S.InPort, prtSrc))),
		Seq (Mod (Switch, swDst), Mod (Header S.InPort, prtDst)))
	| h::t -> 
	  let (swSrc, prtSrc, swDst, prtDst) = src_port_vals h in
	  Seq ( Seq ( Seq (Filter (Test (Switch, swSrc)), 
			   Filter (Test (Header SDN_Types.InPort, prtSrc))),
		      Seq (Mod (Switch, swDst), Mod (Header S.InPort, prtDst))),
		create_pol t)
	| _ -> failwith "non-empty lists only for now." in 
    create_pol edges

  let parse_graph ptstar = 
    let graph = Topology.empty in 
    let rec parse_links (graph: Topology.t) (pol: policy): Topology.t = 
      let assemble switch1 port1 switch2 port2 : Topology.t =
	match port1, port2 with 
	  | VInt.Int64 port1, VInt.Int64 port2 -> 
	    let (node1: Node.t) = Node.Switch ("fresh tag", VInt.get_int64 switch1) in
	    let (node2: Node.t) = Node.Switch ("fresh tag", VInt.get_int64 switch2) in
	    Topology.add_switch_edge graph node1 (Int64.to_int32 port1) node2 (Int64.to_int32 port2)
	  | _,_ -> failwith "need int64 people" in 
      match pol with
	| Seq (Filter(And (Test (Switch, switch1), Test (Header SDN_Types.InPort, port1))),
	       Seq (Mod (Switch, switch2), Mod (Header S.InPort, port2)))
	  -> (assemble switch1 port1 switch2 port2)
	  
	| Par
	    (Seq (Filter(And (Test (Switch, switch1), Test (Header SDN_Types.InPort, port1))),
		  Seq (Mod (Switch, switch2), Mod (Header S.InPort, port2))), t)
	  -> parse_links (assemble switch1 port1 switch2 port2) t
	| _ -> failwith (Printf.sprintf "unimplemented") in 
    match ptstar with
      | Star (Seq (p, t)) -> parse_links graph t
      | _ -> failwith "graph parsing assumes input is of the form (p;t)*"
end
  
module Verify = struct
  open Sat
  open SDN_Types
  open NetKAT_Types

  let all_fields =
      [ Header InPort 
      ; Header EthSrc
      ; Header EthDst
      ; Header EthType
      ; Header Vlan
      ; Header VlanPcp
      ; Header IPProto
      ; Header IP4Src
      ; Header IP4Dst
      ; Header TCPSrcPort
      ; Header TCPDstPort
      ; Switch 
]

  let encode_header (header: header) (pkt:zVar) : zTerm =
    match header with
      | Header InPort -> 
        TApp (TVar "InPort", [TVar pkt])
      | Header EthSrc -> 
        TApp (TVar "EthSrc", [TVar pkt])
      | Header EthDst -> 
        TApp (TVar "EthDst", [TVar pkt])
      | Header EthType ->  
        TApp (TVar "EthType", [TVar pkt])
      | Header Vlan ->  
        TApp (TVar "Vlan", [TVar pkt])
      | Header VlanPcp ->
        TApp (TVar "VlanPcp", [TVar pkt])
      | Header IPProto ->  
        TApp (TVar "IPProto", [TVar pkt])
      | Header IP4Src ->  
        TApp (TVar "IP4Src", [TVar pkt])
      | Header IP4Dst ->  
        TApp (TVar "IP4Dst", [TVar pkt])
      | Header TCPSrcPort ->  
        TApp (TVar "TCPSrcPort", [TVar pkt])
      | Header TCPDstPort ->  
        TApp (TVar "TCPDstPort", [TVar pkt])
      | Switch -> 
        TApp (TVar "Switch", [TVar pkt])

  let encode_packet_equals = 
    let hash = Hashtbl.create 0 in 
    (fun (pkt1: zVar) (pkt2: zVar) (except :header)  -> 
      ZTerm (TApp (
	(if false && Hashtbl.mem hash except
	 then
	    Hashtbl.find hash except
	 else
	    let l = 
	      List.fold_left 
		(fun acc hd -> 
		  if  hd = except then 
		    acc 
		  else
		    ZEquals (ZTerm (encode_header hd "x"), ZTerm( encode_header hd "y"))::acc) 
		[] all_fields in 
	    let new_except = (z3_macro ("packet_equals_except_" ^ (*todo: how to serialize headers? serialize_ except*) "" ) 
				[("x", SPacket);("y", SPacket)] SBool  
				(ZAnd(l))) in
	    Hashtbl.add hash except new_except;
	    new_except), 
	[TVar pkt1; TVar pkt2])))
      
  let encode_vint (v: VInt.t): zTerm = 
    TInt (VInt.get_int64 v)


  let rec forwards_pred (pred : pred) (pkt : zVar) : zFormula = 
    let wrap (expr : zFormula) = (zApp (z3_macro "forwards_pred" [] SBool expr) []) in 
    match pred with
      | False -> 
	wrap ZFalse
      | True -> 
	wrap ZTrue
      | Test (hdr, v) -> 
	wrap (ZEquals (ZTerm (encode_header hdr pkt), ZTerm (encode_vint v)))
      | Neg p ->
        wrap (ZNot (forwards_pred p pkt))
      | And (pred1, pred2) -> 
	(ZAnd [forwards_pred pred1 pkt; 
	       forwards_pred pred2 pkt])
      | Or (pred1, pred2) -> 
	(ZOr [forwards_pred pred1 pkt;
              forwards_pred pred2 pkt])

  let rec forward_pol (pol:policy) (pkt:zVar) (set:zVar) : zFormula =
    let parg1 = TVar "parg1" in let parg2 = TVar "parg2" in let sarg1 = TVar "sarg1" in let sarg2 = TVar "sarg2" in let sarg3 = TVar "sarg3" in
    let wrap s pkts sets expr = 
      let args = (List.map (fun pkt -> pkt, SPacket) pkts) @ (List.map (fun set -> set, SSet) sets) in
      (zApp (z3_macro ("forwards_pol_" ^ s) args SBool expr) (List.map (fun e -> TVar e) (pkts@sets))) in 
    
    match pol with
      | Filter pred ->
        wrap "Filter" [pkt] [set]
                 (ZAnd [forwards_pred pred "parg1";
                       ZEquals(ZTerm (TApp(TVar "set_add", [parg1; 
                                    TApp(TVar "set_empty", [])])), 
                               ZTerm sarg1)])
      | Mod(f,v) -> 
        let pkt' = fresh SPacket in 
        wrap "Mod" [pkt;pkt'] [set]
                 (ZAnd [encode_packet_equals "parg1" "parg2" f;
                       ZEquals(ZTerm (encode_header f "parg2"), ZTerm (encode_vint v));
                       ZEquals(ZTerm (TApp(TVar "set_add", [parg2; 
                                    TApp(TVar "set_empty", [])])), 
                               ZTerm(sarg1))])
      | Par(pol1,pol2) -> 
        let set1 = fresh SSet in 
        let set2 = fresh SSet in 
        wrap "Par" [pkt] [set1;set2;set]
          (ZAnd[forward_pol pol1 "parg1" "sarg1";
                forward_pol pol2 "parg1" "sarg2";
                ZEquals(ZTerm (TApp(TVar "set_union", [sarg1;
						       sarg2])),
                        ZTerm (sarg3))])
      | Seq(pol1,pol2) -> 
	let set' = fresh SSet in 
	    let map = (fun fp l1p -> match fp, l1p with 
	      | (TVar f), l1 -> ZTerm (TApp ( (TApp (TVar "_", [TVar "map"; TVar f]  )), [(TVar l1)]))
	      | _ -> failwith "need to apply functions to variables as of right now.") in
	    let x = ZTerm (TVar "x") in
	    let nopacket = (ZTerm (TVar "nopacket")) in
	    let subset _ _ = ZFalse in (*TODO: implement subset*)
	    
	      
            (ZAnd [forward_pol pol1 pkt set';  
		   (ZEquals ((map 
		      (z3_fun [("x", SPacket)] SPacket 
			 (ZIf ((subset (forward_pol pol2 "x" "s") set), x, nopacket )))
		      (*nOt quite, but you're getting there.  This filters the inital set to only contain elements which will yield the final set.
		      Too bad z3 has no fold concept.*)
		      set'), ZTerm (TVar set)))
		  ])  
      | Star _  -> failwith "NetKAT program not in form (p;t)*"
      | Choice _-> failwith "I'm not rightly sure what a \"choice\" is "
			
(*   let rec forwards (pol:policy) (pkt1:zVar) (pkt2: zVar) : zFormula = *)
(*     match pol with *)
(*       | Filter pr ->  *)
(*         ZComment ("Filter", (ZAnd[forwards_pred pr pkt1; encode_packet_equals pkt1 pkt2 []])) *)
(*       | Mod (hdr, v) ->  *)
(* 	ZComment ("Mod", ZAnd [ZEquals (encode_header hdr pkt2, encode_vint v); *)
(* 			       encode_packet_equals pkt1 pkt2 [hdr]]) *)
(*       | Par (p1, p2) ->  *)
(* 	ZComment ("Par", ZOr [forwards p1 pkt1 pkt2; *)
(* 			      forwards p2 pkt1 pkt2]) *)
(*       | Seq (p1, p2) ->  *)
(* 	let pkt' = fresh SPacket in *)
(* 	ZComment ("Seq", ZAnd [forwards p1 pkt1 pkt'; *)
(* 			       forwards p2 pkt' pkt2]) *)
(*       | Star p1 -> failwith "NetKAT program not in form (p;t)*" *)
		
(*   let forwards_star_history k p_t_star pkt1 pkt2 : zFormula =  *)
(*     if k = 0 then  *)
(*       ZEquals (TVar pkt1, TVar pkt2) *)
(*     else  *)
(*       let pkt' = fresh SPacket in *)
(*       let pkt'' = fresh SPacket in *)
(*       let formula, histr = forwards_star_history (k-1) p_t_star pkt'' pkt2 in *)
(*       ZAnd [ forwards pol pkt1 pkt'; *)
(*              forwards topo pkt' pkt''; *)
(*              formula ], new_history in  *)
(*       let form, hist = inner_forwards k p_t_star pkt1 pkt2 in *)
(*       (ZAnd [form; expr hist])::(forwards_star_history (k-1) p_t_star pkt1 pkt2) in  *)
(*   ZOr (forwards_star_history k p_t_star pkt1 pkt2) *)
(*   let forwards_star  = forwards_star_history noop_expr *)
end

(* let generate_program expr inp p_t_star outp k x y=  *)
(*   let prog =  *)
(*     Sat.ZProgram [ Sat.ZDeclareAssert (Verify.forwards_pred inp x) *)
(*                  ; Sat.ZDeclareAssert (Verify.forwards_star_history expr k p_t_star x y ) *)
(*                  ; Sat.ZDeclareAssert (Verify.forwards_pred outp y) ] in prog *)

(* let run_solve oko prog str = assert false *)
(* (\*   let global_eq = *\) *)
(* (\* 	match !Verify.global_bindings with *\) *)
(* (\* 	  | [] -> [] *\) *)
(* (\* 	  | _ -> [Sat.ZDeclareAssert (Sat.ZAnd !Verify.global_bindings)] in *\) *)
(* (\*   let run_result = ( *\) *)
(* (\* 	match oko, Sat.solve prog global_eq with  *\) *)
(* (\* 	  | Some ok, sat ->  *\) *)
(* (\* 		if ok = sat then  *\) *)
(* (\* 		  true *\) *)
(* (\* 		else *\) *)
(* (\* 		  (Printf.printf "[Verify.check %s: expected %b got %b]\n%!" str ok sat; false) *\) *)
(* (\* 	  | None, sat ->  *\) *)
(* (\* 		(Printf.printf "[Verify.check %s: %b]\n%!" str sat; false)) in *\) *)
(* (\*   Sat.fresh_cell := []; Verify.global_bindings := []; run_result *\) *)
	
(* (\* let combine_programs progs =  *\) *)
(* (\*   Sat.ZProgram (List.flatten (List.map (fun prog -> match prog with  *\) *)
(* (\* 	| Sat.ZProgram (asserts) -> asserts) progs)) *\) *)

(* (\* let make_vint v = VInt.Int64 (Int64.of_int v) *\) *)

(* (\* let check_equivalent pt1 pt2 str =  *\) *)
(* (\*   	(\\*global_bindings := (ZEquals (TVar pkt1, TVar pkt2))::!global_bindings;*\\) *\) *)
(* (\*   let graph1, graph2 = Verify_Graph.parse_graph pt1, Verify_Graph.parse_graph pt2 in *\) *)
(* (\*   let length1, length2 = Verify_Graph.longest_shortest graph1, Verify_Graph.longest_shortest graph2 in *\) *)
(* (\*   let k = if length1 > length2 then length1 else length2 in *\) *)
(* (\*   let k_z3 = Sat.fresh Sat.SInt in *\) *)
(* (\*   let x = Sat.fresh Sat.SPacket in *\) *)
(* (\*   let y1 = Sat.fresh Sat.SPacket in *\) *)
(* (\*   let y2 = Sat.fresh Sat.SPacket in *\) *)
(* (\*   let fix_k = (fun n -> Sat.ZEquals (Sat.TVar k_z3, Verify.encode_vint (make_vint (List.length n)))) in *\) *)
(* (\*   let prog1 = generate_program false fix_k NetKAT_Types.True pt1 NetKAT_Types.True k x y1 in *\) *)
(* (\*   let prog2 = generate_program false fix_k  NetKAT_Types.True pt2 NetKAT_Types.True k x y2 in *\) *)
(* (\*   let prog = combine_programs  *\) *)
(* (\* 	[Sat.ZProgram [Sat.ZDeclareAssert (Sat.ZEquals (Sat.TVar x, Sat.TVar x));  *\) *)
(* (\* 		       Sat.ZDeclareAssert (Sat.ZNot (Sat.ZEquals (Sat.TVar y1, Sat.TVar y2)))];  *\) *)
(* (\* 	 prog1;  *\) *)
(* (\* 	 prog2] in *\) *)
(* (\*   run_solve (Some false) prog str *\) *)

(* let check_specific_k_history expr str inp p_t_star outp oko (k : int) : bool =  *)
(*   let x = Sat.fresh Sat.SPacket in  *)
(*   let y = Sat.fresh Sat.SPacket in  *)
(*   let prog = generate_program expr inp p_t_star outp k x y in *)
(*   run_solve oko prog str *)

(* let check_maybe_dup expr str inp p_t_star outp (oko : bool option) : bool =  *)
(*   let res_graph = Verify_Graph.parse_graph p_t_star in *)
(*   let longest_shortest_path = Verify_Graph.longest_shortest *)
(*     res_graph in *)
(*   check_specific_k_history expr str inp p_t_star outp oko longest_shortest_path *)
  
(* (\* str: name of your test (unique ID)   *)
(*    inp: initial packet *)
(*    pol: policy to test *)
(*    outp: fully-transformed packet  *)
(*    oko: bool option.  has to be Some.  True if you think it should be satisfiable. *)
(* *\) *)
let check a b c d e = assert true

