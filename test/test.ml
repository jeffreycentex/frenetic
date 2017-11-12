open Core
open Probnetkat
open Symbolic
open Syntax

module Fdd_eq = struct
  include Fdd
  let pp fmt fdd = Format.fprintf fmt "%s" (to_string fdd)
end

let fdd_eq = (module Fdd_eq : Alcotest.TESTABLE with type t = Fdd.t)

module Fdd_equiv = struct
  include Fdd_eq
  let equal = equivalent
end

let fdd_equiv = (module Fdd_equiv : Alcotest.TESTABLE with type t = Fdd.t) 

let test kind name p q = 
  (name, `Quick, fun () -> Alcotest.check kind "" (Fdd.of_pol p) (Fdd.of_pol q))

let test_not kind p q =
  test (Alcotest.neg kind) p q

let basic_positive = [

  (* predicate *)
  test fdd_equiv "predicate sequentially composed on right"
    PNK.( ite (???("X",0)) (!!("X", 1)) skip 
          >> filter( neg (???("X", 0)) )
    )
    PNK.( ite (???("X",0)) (!!("X", 1)) skip );

  (* degenerate non-terminating loop *)
  test fdd_equiv "degenerate non-terminating loop"
    PNK.( whl True skip )
    PNK.( drop );

  (* non-degenerate non-terminating loop *)
  test fdd_equiv "non-degenerate non-terminating loop"
    PNK.( whl True @@ ?@[
            !!("x", 0) @ 1//3;
            ??("x", 1) @ 2//3;
          ] 
    )
    PNK.( drop );

  (* coin flip example *)
  test fdd_equiv "coin flip terminates"
    PNK.(
      whl (???("c",0)) (
        ?@[ !!("c", 1) @ 1//2; skip @ 1//2 ]
      )
    )
    PNK.(
      ite (???("c", 0)) 
        (!!("c", 1)) 
        skip
      );

  (* distributivity *)
  test fdd_equiv "distributivity ; ⊕"
    PNK.(
      ?@[
        !!("a", 0) @ 1//2;
        !!("a", 1) @ 1//2;
      ] >>
      ?@[
        !!("b", 0) @ 1//2;
        !!("b", 1) @ 1//2;
      ]
    )
    PNK.(
      ?@[
        !!("a", 0) >> !!("b", 0) , 1//4;
        !!("a", 0) >> !!("b", 1) , 1//4;
        !!("a", 1) >> !!("b", 0) , 1//4;
        !!("a", 1) >> !!("b", 1) , 1//4;
      ]
    );

  (* sparse multi-coin convergence *)
  begin 
  let field i = sprintf "Y%d" i in
  let multi_coin m n =
    let open PNK in
    (!!("X", 0)) >>
    whl (neg @@ conji m ~f:(fun i -> ???(field i, 0))) begin
      seqi m ~f:(fun i ->
        ite (???("X", i)) (
          uniform n ~f:(fun j ->
            !!(field i, j)
          ) >>
          !! ("X", (i+1) mod m)
        ) (
          skip
        )
      )
    end >> (!!("X", 0))
  in
  let m, n = 4,2 in
  test fdd_equiv "multi-coin convergence" 
    PNK.( !!("X", 0) >> seqi m ~f:(fun i -> !!(field i, 0)) )
    (multi_coin m n)
  end;

  (* fdd equivalence *)
  test fdd_equiv "equivalent but not equal fdds: equivalent"
    PNK.( ite (???("x", 0)) skip         skip )
    PNK.( ite (???("x", 0)) (!!("x", 0)) skip );
  test_not fdd_eq "equivalent but not equal fdds: not equal"
    PNK.( ite (???("x", 0)) skip         skip )
    PNK.( ite (???("x", 0)) (!!("x", 0)) skip );


]

let basic_negative = [
  test_not fdd_eq "skip ≠ drop" PNK.skip PNK.drop;

]

(* let qcheck_tests = [
  "round-trip", `Quick, fun () -> QCheck.Test.check_exn failing
] *)

let () =
  Alcotest.run "Probnetkat" [
    "fdd positive", basic_positive;
    "fdd negative", basic_negative;
    (* "qcheck", qcheck_tests; *)
  ]
