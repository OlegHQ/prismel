let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected FunctionConstantValues rejection"

let () =
  let open Binding_function_constant_values_safe_package in
  validate_handoff ();
  let constants = ok (create ~max_constants:4) in
  ignore (ok (set_single constants ~index:0 ~data_type:Bool (Bool_value true)));
  ignore (ok (set_range constants ~start:1 ~length:2 ~data_type:Int32
    [ Int32_value 2l; Int32_value 3l ]));
  let before = snapshot constants in
  error (set_single constants ~index:4 ~data_type:Bool (Bool_value false));
  error (set_single constants ~index:0 ~data_type:Float32 (Int32_value 1l));
  error (set_single constants ~index:0 ~data_type:(Unsupported 99) (Int32_value 1l));
  error (set_range constants ~start:3 ~length:2 ~data_type:Int32 [ Int32_value 1l; Int32_value 2l ]);
  error (set_range constants ~start:1 ~length:2 ~data_type:Int32 [ Int32_value 1l ]);
  error (set_range constants ~start:1 ~length:2 ~data_type:Int32
    [ Int32_value 1l; Float32_value 2. ]);
  if snapshot constants <> before then failwith "failed constant mutation was not atomic";
  ignore (ok (set_single constants ~index:1 ~data_type:UInt32 (UInt32_value Int32.min_int)));
  (match snapshot constants with
   | (0, Bool, Bool_value true) :: (1, UInt32, UInt32_value value) :: _ when value = Int32.min_int -> ()
   | _ -> failwith "typed constant snapshot/replacement");
  reset constants;
  if snapshot constants <> [] then failwith "constant reset";
  Printf.printf
    "FunctionConstantValues safe package: callable3 reset/single/range type/index/cardinality/atomic snapshot passed\n%!"
