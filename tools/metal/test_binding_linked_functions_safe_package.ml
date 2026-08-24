let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected LinkedFunctions rejection"

let () =
  let open Binding_linked_functions_safe_package in
  validate_handoff ();
  let first = { token = 1; device = 7; destroyed = false } in
  let second = { token = 2; device = 7; destroyed = false } in
  let linked = create ~device:7 in
  let source = ref [ first ] in
  ignore (ok (set_binary_functions linked (Some !source)));
  source := [];
  if ok (binary_functions linked) <> Some [ first ] then failwith "binary array snapshot";
  ignore (ok (set_private_functions linked (Some [ second ])));
  ignore (ok (set_groups linked (Some [ "zeta", [ second ]; "alpha", [ first ] ])));
  (match ok (groups linked) with
   | Some (("alpha", _) :: ("zeta", _) :: []) -> ()
   | _ -> failwith "deterministic group order");
  let before = retained_tokens linked in
  error (set_binary_functions linked (Some [ { first with device = 8 } ]));
  error (set_private_functions linked (Some [ first; first ]));
  error (set_groups linked (Some [ "dup", [ first ]; "dup", [ second ] ]));
  error (set_groups linked (Some [ String.make 1 (Char.chr 0xc0), [ first ] ]));
  error (set_groups linked (Some [ "bad", [ { first with destroyed = true } ] ]));
  if retained_tokens linked <> before then failwith "failed validation mutated retained graph";
  ignore (ok (set_binary_functions linked None));
  destroy linked; destroy linked;
  if retained_tokens linked <> [] then failwith "destroy did not release graph";
  error (binary_functions linked); error (set_groups linked None);
  Printf.printf
    "LinkedFunctions safe package: callable9 arrays6/groups3 device/atomic/UTF-8/duplicate/lifetime passed\n%!"
