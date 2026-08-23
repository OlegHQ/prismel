open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)
let check condition message = if not condition then failwith message

let () =
  let device = get (Device.system_default ()) in
  let library =
    get (Library.compile_source ~device
      "#include <metal_stdlib>\nusing namespace metal;\nkernel void table_kernel(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = i; }\n")
  in
  let function_ = get (Function.find ~library "table_kernel") in
  let pipeline = get (Compute_pipeline.create function_) in
  let visible = get (Visible_function_table.create ~pipeline ~capacity:4) in
  let intersection = get (Intersection_function_table.create ~pipeline ~capacity:4) in
  check (Visible_function_table.capacity visible = 4) "visible capacity drift";
  check (Intersection_function_table.capacity intersection = 4) "intersection capacity drift";
  get (Visible_function_table.set_function visible ~index:0 None);
  get (Intersection_function_table.set_function intersection ~index:0 None);
  get (Intersection_function_table.set_visible_table intersection ~buffer_index:0 (Some visible));
  let buffer = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
  get (Intersection_function_table.set_buffer intersection ~index:0 ~offset:16L (Some buffer));
  check (Visible_function_table.resource_id visible <> 0L) "visible resource ID empty";
  check (Intersection_function_table.resource_id intersection <> 0L) "intersection resource ID empty";
  check
    (Result.is_error (Visible_function_table.set_function visible ~index:4 None))
    "out-of-range visible binding accepted";
  (match Function_handle.create ~pipeline ~function_ with
  | Error error -> check (error.kind = Unsupported) "function-handle rejection was not typed"
  | Ok handle ->
      get (Visible_function_table.set_function visible ~index:1 (Some handle));
      get (Intersection_function_table.set_function intersection ~index:1 (Some handle));
      get (Function_handle.destroy handle));
  get (Intersection_function_table.destroy intersection);
  get (Visible_function_table.destroy visible);
  get (Buffer.destroy buffer);
  get (Compute_pipeline.destroy pipeline);
  get (Function.destroy function_);
  get (Library.destroy library);
  get (Device.destroy device);
  ignore (get (Release_queue.drain ()));
  print_endline "Metal safe function tables: lifecycle/device/capacity execute-or-reject passed"
