let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected IndirectCommand rejection"

let () =
  let open Binding_indirect_command_safe_package in
  validate_handoff ();
  let buffer = { token = 1; device = 7; length = 128; destroyed = false } in
  let pipeline = { token = 2; device = 7; length = 0; destroyed = false } in
  let command = empty ~device:7 ~max_slots:2 in
  let command = ok (set_binding command ~slot:0 { resource = buffer; offset = 16; stride = Some 8 }) in
  let command = ok (set_pipeline command pipeline) in
  if retained_tokens command <> [ 2; 1 ] then failwith "per-slot retained graph";
  error (set_binding command ~slot:2 { resource = buffer; offset = 0; stride = None });
  error (set_binding command ~slot:1 { resource = buffer; offset = 129; stride = None });
  error (set_binding command ~slot:1 { resource = buffer; offset = 0; stride = Some 0 });
  error (set_binding command ~slot:1 { resource = { buffer with device = 8 }; offset = 0; stride = None });
  ignore (ok (validate_draw command ~vertex_count:3 ~instance_count:1));
  error (validate_draw command ~vertex_count:0 ~instance_count:1);
  ignore (ok (validate_indexed_draw command ~index_buffer:buffer ~index_offset:4 ~index_count:10 ~index_size:2));
  error (validate_indexed_draw command ~index_buffer:buffer ~index_offset:3 ~index_count:10 ~index_size:2);
  ignore (ok (validate_patch_draw command ~patch_start:0 ~patch_count:2 ~control_points:3
    ~patch_indices:(Some buffer) ~tessellation:buffer ~tessellation_offset:0
    ~tessellation_stride:16 ~instance_count:2));
  error (validate_patch_draw command ~patch_start:127 ~patch_count:2 ~control_points:3
    ~patch_indices:(Some buffer) ~tessellation:buffer ~tessellation_offset:0
    ~tessellation_stride:16 ~instance_count:2);
  let reset = reset command in
  if retained_tokens reset <> [] || retained_tokens command <> [ 2; 1 ] then
    failwith "atomic reset did not release only the replacement graph";
  Printf.printf
    "IndirectCommand safe package: callable12 slot graph/offset/stride/cardinality/device/patch/reset passed\n%!"
