let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4ArgumentTable rejection"

let () =
  let open Binding_metal4_argument_table_safe_package in
  validate_handoff ();
  error (create ~available:false ~device:7 ~slot_kinds:[| Buffer |]);
  error (create ~available:true ~device:7 ~slot_kinds:[| Texture |]);
  let table = ok (create ~available:true ~device:7 ~slot_kinds:[| Buffer; Acceleration_structure |]) in
  let buffer = { token = 1; device = 7; kind = Buffer; destroyed = false } in
  let replacement = { token = 2; device = 7; kind = Buffer; destroyed = false } in
  ignore (ok (set_resource table ~buffer_index:0 buffer));
  ignore (ok (set_resource table ~buffer_index:0 replacement));
  if retained_tokens table <> [ 2 ] then failwith "atomic retained replacement";
  error (set_resource table ~buffer_index:2 buffer);
  error (set_resource table ~buffer_index:1 buffer);
  error (set_resource table ~buffer_index:0 { buffer with device = 8 });
  error (set_resource table ~buffer_index:0 { buffer with destroyed = true });
  if retained_tokens table <> [ 2 ] then failwith "failed replacement mutated binding";
  ignore (ok (submit table));
  error (set_resource table ~buffer_index:0 buffer);
  error (submit table);
  complete table;
  ignore (ok (set_resource table ~buffer_index:0 buffer));
  destroy table; destroy table;
  if retained_tokens table <> [] then failwith "destroy did not release resources";
  error (set_resource table ~buffer_index:0 buffer);
  Printf.printf
    "MTL4ArgumentTable safe package: callable1 availability/state/index/kind/device/destroyed/replacement passed\n%!"
