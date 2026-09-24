let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected ArgumentEncoder rejection"
let resource ?(destroyed=false) token device kind = Some { Binding_argument_encoder_safe_package.token; device; kind; destroyed }

let () =
  let open Binding_argument_encoder_safe_package in
  validate_handoff ();
  let original = [| resource 1 7 Buffer; None; None |] in
  let input = [| resource 2 7 Buffer; None |] in
  let validated = ok (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=1;length=2} input) in
  input.(0) <- None;
  if validated.(0) = None then failwith "argument array was not snapshotted";
  let next = ok (replace_atomic original ~range:{location=1;length=2} validated) in
  if original.(1) <> None || next.(1) = None then failwith "argument replacement was not atomic";
  error (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=2;length=2} validated);
  error (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=0;length=1} validated);
  error (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=0;length=1} [|resource 3 8 Buffer|]);
  error (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=0;length=1} [|resource 3 7 Texture|]);
  error (validate_array ~capacity:3 ~device:7 ~expected:Buffer ~range:{location=0;length=1} [|resource ~destroyed:true 3 7 Buffer|]);
  let parent = { token=4; device=7; parent=None; destroyed=false } in
  let child = ok (nested ~parent ~token:2) in
  if child.parent <> Some parent || child.device <> 7 then failwith "nested encoder ownership";
  parent.destroyed <- true; error (nested ~parent ~token:3);
  (match constant_policy with Availability_only -> ());
  Printf.printf "ArgumentEncoder safe package: callable32; atomic arrays, same-device/kind/lifetime rejection, nested retention, availability-only constant-data policy passed\n%!"
