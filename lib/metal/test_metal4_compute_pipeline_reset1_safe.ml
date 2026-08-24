open Metal
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"pp_error error)
let reject kind=function Error error when error.kind=kind->()|Error error->failwith(Format.asprintf"%a"pp_error error)|Ok _->failwith"expected MTL4 compute reset rejection"
let ()=match Metal4_compute_pipeline_descriptor.create()with
|Error error when error.kind=Unsupported||error.kind=Native_error->print_endline"MTL4ComputePipeline reset1 safe: skipped (macOS26 unavailable)"
|Error error->failwith(Format.asprintf"%a"pp_error error)
|Ok descriptor->
 if Metal4_compute_pipeline_descriptor.snapshot descriptor<>(None,0L,false)then failwith"nondefault create";
 reject Invalid_argument(Metal4_compute_pipeline_descriptor.configure descriptor~max_threads:64L~threadgroup_multiple:true());
 (match Device.system_default()with
  |Error _->()
  |Ok device->
    let source="#include <metal_stdlib>\nusing namespace metal;\nkernel void reset1(device uint *out [[buffer(0)]]) { out[0] = 1; }\n"in
    let library=get(Library.compile_source~device source)in
    let function_=get(Function.find~library "reset1")in
    let child=get(Function_specialization.Function_descriptor.create function_~name:"reset1")in
    get(Metal4_compute_pipeline_descriptor.configure descriptor~function_descriptor:child~max_threads:64L~threadgroup_multiple:true());
    reject Parent_has_dependents(Function_specialization.Function_descriptor.destroy child);
    get(Metal4_compute_pipeline_descriptor.reset descriptor);
    get(Function_specialization.Function_descriptor.destroy child);
    get(Function.destroy function_);get(Library.destroy library);get(Device.destroy device));
 for _=1 to 20 do get(Metal4_compute_pipeline_descriptor.reset descriptor)done;
 if Metal4_compute_pipeline_descriptor.snapshot descriptor<>(None,0L,false)then failwith"nondefault reset";
 get(Metal4_compute_pipeline_descriptor.destroy descriptor);
 reject Destroyed(Metal4_compute_pipeline_descriptor.reset descriptor);
 print_endline"MTL4ComputePipeline reset1 safe: exact1 defaults/idempotence/destroy passed"
