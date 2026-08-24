let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4ComputePipeline rejection"

let () =
  let open Binding_metal4_compute_pipeline_safe_package in
  validate_handoff ();
  error (create ~available:false);
  let descriptor = ok (create ~available:true) in
  if ok (snapshot descriptor) <> None || retained_tokens descriptor <> [] then failwith "native reset defaults";
  ignore (ok (configure descriptor ~function_token:4 ~linked_functions_token:(Some 5)
    ~max_threads:256 ~threadgroup_multiple:true));
  if ok (snapshot descriptor) <> Some (4, Some 5, 256, true)
     || retained_tokens descriptor <> [ 4; 5 ] then failwith "configured lifetime graph";
  error (configure descriptor ~function_token:0 ~linked_functions_token:None
    ~max_threads:256 ~threadgroup_multiple:false);
  if retained_tokens descriptor <> [ 4; 5 ] then failwith "failed configuration mutated graph";
  ignore (ok (reset descriptor)); ignore (ok (reset descriptor));
  if ok (snapshot descriptor) <> None || retained_tokens descriptor <> [] then failwith "idempotent reset release";
  destroy descriptor; destroy descriptor;
  error (reset descriptor); error (snapshot descriptor);
  error (configure descriptor ~function_token:4 ~linked_functions_token:None
    ~max_threads:256 ~threadgroup_multiple:false);
  Printf.printf
    "MTL4ComputePipeline safe package: callable1 macOS26/defaults/idempotence/destroyed/lifetime passed\n%!"
