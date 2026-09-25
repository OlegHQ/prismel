open Metal
let fail error=failwith(Format.asprintf"%a"pp_error error)
let get=function Ok x->x|Error e->fail e
let source={|
#include <metal_stdlib>
using namespace metal;
kernel void constructors3(device uint *out [[buffer(0)]]) { out[0]=3; }
|}
let run ()=match Device.system_default()with
|Error _->print_endline"metal device constructors3: skipped (no device)"
|Ok device->
  let library=get(Library.compile_source~device source)in
  let function_=get(Function.find~library "constructors3")in
  let encoder=get(Shader_argument_encoder.of_buffer_binding device function_~index:0L)in
  if Shader_argument_encoder.buffer_index encoder<>0L then failwith"reflected encoder index drift";
  if Device.registry_id(Shader_argument_encoder.device encoder)<>Device.registry_id device then failwith"reflected encoder device drift";
  let event=get(Device.new_shared_event device)in
  get(Shared_event.set_signaled_value event 3L);
  if get(Shared_event.signaled_value event)<>3L then failwith"event value drift";
  get(Shared_event.destroy event);
  get(Shader_argument_encoder.destroy encoder);get(Function.destroy function_);
  get(Library.destroy library);get(Device.destroy device);
  print_endline"metal device constructors3: retained constructors ok"
