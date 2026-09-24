let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected AccelerationStructure rejection"

let () =
  let open Binding_acceleration_structure_constructor_safe_package in
  validate_handoff ();
  let buffer = { token = 3; device = 7; length = 256; destroyed = false } in
  let range = { buffer; offset = 16; stride = 16; count = 4; element_size = 12 } in
  let triangle = Triangles (range, None) in
  let descriptor = ok (create ~device:7 (Primitive [ triangle; Bounding_boxes range ])) in
  if retained_tokens descriptor <> [ 3; 3 ] then failwith "descriptor buffer ownership graph";
  error (create ~device:8 (Geometry triangle));
  error (create ~device:7 (Geometry (Triangles ({ range with buffer = { buffer with destroyed = true } }, None))));
  error (create ~device:7 (Geometry (Triangles ({ range with offset = 250 }, None))));
  error (create ~device:7 (Geometry (Triangles ({ range with stride = 8 }, None))));
  error (create ~device:7 (Primitive []));
  error (create ~device:7 (Geometry (Motion [ triangle ])));
  ignore (ok (create ~device:7 (Geometry (Motion [ triangle; triangle ]))));
  ignore (ok (create ~device:7 (Instances range)));
  ignore (ok (create ~device:7 (Indirect_instances range)));
  ignore (ok (create ~device:7 (Motion_keyframe range)));
  let record = { acceleration_structure_index = 2; options = 1; mask = 0xff; intersection_function_table_offset = 0 } in
  ignore (ok (validate_instance_record record));
  error (validate_instance_record { record with mask = 0x100 });
  error (validate_instance_record { record with options = 0x100 });
  Printf.printf
    "AccelerationStructure constructor package: callable10 metadata18 excluded; variants/records/ranges/formats/stride/count/device/ownership passed\n%!"
