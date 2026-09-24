let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4 stitched-function rejection"

let () =
  let open Binding_metal4_stitched_function_safe_package in
  validate_handoff ();
  let first = { token = 1; device = 7; destroyed = false } in
  let second = { token = 2; device = 7; destroyed = false } in
  let graph = { token = 9; device = 7; functions = [ first; second ]; destroyed = false } in
  let descriptor = ok (create ~device:7 ~descriptors:(Some [ first; second ]) ~graph:(Some graph)) in
  if retained_tokens descriptor <> [ 9; 1; 2 ] || function_graph descriptor <> Some graph then
    failwith "stitched retained graph pair";
  let before = retained_tokens descriptor in
  error (set_pair descriptor ~descriptors:(Some [ first ]) ~graph:(Some graph));
  error (set_pair descriptor ~descriptors:(Some [ first; first ])
    ~graph:(Some { graph with functions = [ first; first ] }));
  error (set_pair descriptor ~descriptors:(Some [ first; { second with device = 8 } ]) ~graph:(Some graph));
  error (set_pair descriptor ~descriptors:(Some [ first; second ]) ~graph:(Some { graph with destroyed = true }));
  error (set_pair descriptor ~descriptors:None ~graph:(Some graph));
  if retained_tokens descriptor <> before then failwith "failed pair validation mutated graph";
  ignore (ok (set_pair descriptor ~descriptors:None ~graph:None));
  if retained_tokens descriptor <> [] then failwith "nullable pair release";
  destroy descriptor; destroy descriptor;
  error (set_pair descriptor ~descriptors:(Some [ first; second ]) ~graph:(Some graph));
  Printf.printf
    "MTL4StitchedFunctionDescriptor safe package: callable2 metadata1 excluded; pair/device/array/cardinality/lifetime passed\n%!"
