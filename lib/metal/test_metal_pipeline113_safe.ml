open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok value -> value | Error e -> fail "%s" (Format.asprintf "%a" pp_error e)
let expect kind = function
  | Error e when e.kind = kind -> ()
  | Error e -> fail "wrong error: %s" (Format.asprintf "%a" pp_error e)
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let library = get (Library.compile_source ~device
    "#include <metal_stdlib>\nusing namespace metal;\nkernel void p113(device uint *out [[buffer(0)]]) { out[0] = 1; }\n") in
  let function_ = get (Function.find ~library "p113") in
  let pipeline = get (Compute_pipeline.create function_) in
  ignore (get (Compute_pipeline.resource_id pipeline));
  ignore (get (Compute_pipeline.required_threads_per_threadgroup pipeline));
  ignore (get (Compute_pipeline.shader_validation pipeline));
  ignore (get (Compute_pipeline.supports_indirect_command_buffers pipeline));
  expect Invalid_argument
    (Compute_pipeline.imageblock_memory_length pipeline
       { Compute_pipeline.width=0L; height=1L; depth=1L });
  get (Compute_pipeline.destroy pipeline);
  expect Destroyed (Compute_pipeline.resource_id pipeline);
  get (Function.destroy function_);
  get (Library.destroy library);
  get (Device.destroy device)
