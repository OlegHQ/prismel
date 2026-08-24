let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected StageInputOutputDescriptor rejection"

let () =
  let open Binding_stage_input_output_safe_package in
  validate_handoff ();
  let descriptor = ok (create ~max_attributes:3 ~max_buffers:2) in
  ignore (ok (set_layout descriptor ~index:0 (Some { stride = 16 })));
  let source = { format = Float3; offset = 4; buffer_index = 0 } in
  ignore (ok (set_attribute descriptor ~index:1 (Some source)));
  if ok (attribute descriptor ~index:1) <> Some source || retained_attribute_count descriptor <> 1 then
    failwith "attribute ownership graph";
  let attributes = attributes_snapshot descriptor in
  let layouts = layouts_snapshot descriptor in
  attributes.(1) <- None; layouts.(0) <- None;
  if retained_attribute_count descriptor <> 1 then failwith "descriptor snapshots aliased arrays";
  error (set_attribute descriptor ~index:3 (Some source));
  error (set_attribute descriptor ~index:0 (Some { source with buffer_index = 2 }));
  error (set_attribute descriptor ~index:0 (Some { source with format = Invalid }));
  error (set_attribute descriptor ~index:0 (Some { source with offset = 8 }));
  error (set_attribute descriptor ~index:0 (Some { source with buffer_index = 1 }));
  error (set_layout descriptor ~index:2 (Some { stride = 8 }));
  error (set_layout descriptor ~index:1 (Some { stride = 0 }));
  if retained_attribute_count descriptor <> 1 then failwith "failed validation mutated descriptor";
  reset descriptor;
  if retained_attribute_count descriptor <> 0 then failwith "reset did not release attributes";
  Printf.printf
    "StageInputOutputDescriptor safe package: callable7 metadata3 excluded; graph/index/format/buffer/stride/snapshot passed\n%!"
