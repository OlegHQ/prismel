let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4ComputeEncoder rejection"

let () =
  let open Binding_metal4_compute_encoder_safe_package in
  validate_handoff ();
  error (create ~available:false ~device:7);
  let encoder = ok (create ~available:true ~device:7) in
  let owned token = { token; device = 7; destroyed = false } in
  let acceleration token = { owned = owned token } in
  let descriptor = { owned = owned 2; primitive_count = 2 } in
  let buffer = { owned = owned 3; length = 512 } in
  let scratch = { buffer; offset = 0; length = 256 } in
  ignore (ok (build encoder ~destination:(acceleration 1) ~descriptor ~scratch));
  ignore (ok (refit encoder ~source:(acceleration 1) ~descriptor ~destination:(Some (acceleration 4))
    ~scratch ~options:1));
  ignore (ok (write_compacted_size encoder (acceleration 1) { buffer; offset = 8; length = 8 }));
  let tensor token = { owned = owned token; dimensions = [| 4; 5 |] } in
  ignore (ok (copy_tensor encoder ~source:(tensor 5) ~source_origin:[| 1; 1 |]
    ~source_dimensions:[| 2; 3 |] ~destination:(tensor 6) ~destination_origin:[| 0; 2 |]
    ~destination_dimensions:[| 2; 3 |]));
  let before = retained_tokens encoder in
  error (build encoder ~destination:(acceleration 1) ~descriptor ~scratch:{ scratch with length = 64 });
  error (refit encoder ~source:{ owned = { (owned 1) with device = 8 } } ~descriptor
    ~destination:None ~scratch ~options:0);
  error (write_compacted_size encoder (acceleration 1) { buffer; offset = 1; length = 8 });
  error (copy_tensor encoder ~source:(tensor 5) ~source_origin:[| 3; 1 |]
    ~source_dimensions:[| 2; 3 |] ~destination:(tensor 6) ~destination_origin:[| 0; 2 |]
    ~destination_dimensions:[| 2; 3 |]);
  if retained_tokens encoder <> before then failwith "failed encoding mutated retained graph";
  ignore (ok (end_encoding encoder));
  error (build encoder ~destination:(acceleration 1) ~descriptor ~scratch);
  complete encoder;
  if retained_tokens encoder <> [] then failwith "completion retention release";
  destroy encoder; destroy encoder;
  Printf.printf
    "MTL4ComputeEncoder5 safe package: AS4/tensor1 macOS26/state/device/range/cardinality/retention passed\n%!"
