let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4MLPipeline rejection"

let () =
  let open Binding_metal4_ml_pipeline_safe_package in
  validate_handoff ();
  error (create ~available:false ~native_label:None);
  let source = Bytes.of_string "classifier" in
  let pipeline = ok (create ~available:true ~native_label:(Some (Bytes.unsafe_to_string source))) in
  Bytes.fill source 0 (Bytes.length source) 'x';
  if ok (label pipeline) <> Some "classifier" then failwith "ML pipeline label snapshot";
  ignore (ok (refresh_label pipeline ~native_label:None));
  if ok (label pipeline) <> None then failwith "nullable ML pipeline label";
  error (refresh_label pipeline ~native_label:(Some (String.make 1 (Char.chr 0xc0))));
  ignore (ok (begin_use pipeline));
  error (begin_use pipeline); error (destroy pipeline);
  ignore (ok (end_use pipeline)); error (end_use pipeline);
  ignore (ok (destroy pipeline)); ignore (ok (destroy pipeline));
  error (label pipeline); error (refresh_label pipeline ~native_label:(Some "x"));
  Printf.printf
    "MTL4MLPipeline5 reconciled: readonly label callable2, metadata3 excluded; macOS26/UTF-8/nil/lifetime/state passed\n%!"
