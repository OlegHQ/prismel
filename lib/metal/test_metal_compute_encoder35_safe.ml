open Metal
let fail fmt=Printf.ksprintf failwith fmt
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a"pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->fail "wrong error: %s"(Format.asprintf "%a"pp_error e)|Ok _->fail "expected rejection"
let source={|#include <metal_stdlib>
using namespace metal;
kernel void compute35(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] += 3; }
|}
let ()=
  match Device.system_default()with Error _->print_endline"compute encoder35: skipped (no device)"|Ok device->
  let queue=get(Command_queue.create device)in
  let library=get(Library.compile_source~device source)in
  let function_=get(Function.find~library "compute35")in
  let pipeline=get(Compute_pipeline.create function_)in
  let buffer=get(Buffer.create~device~length:16L~storage:Buffer.Shared())in
  let texture=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let sampler=get(Sampler.create~device(Sampler.default()))in
  let visible=get(Visible_function_table.create~pipeline~capacity:1)in
  let intersection=get(Intersection_function_table.create~pipeline~capacity:1)in
  let acceleration=get(Acceleration_structure.create~device~size:256L)in
  let command=get(Command_buffer.create queue())in
  let encoder=get(Compute_encoder.create command)in
  expect Invalid_argument(Compute_encoder.set_buffers encoder~start:0[]);
  expect Invalid_argument(Compute_encoder.set_buffer_with_stride encoder~index:0~offset:1L~stride:4L None);
  expect Invalid_argument(Compute_encoder.set_sampler encoder~index:0~lod_min:2.~lod_max:1.(Some sampler));
  get(Compute_encoder.set_pipeline encoder pipeline);
  get(Compute_encoder.set_buffers encoder~start:0[Some buffer,0L,4L]);
  get(Compute_encoder.set_buffer_offset encoder~index:0~offset:0L~stride:4L());
  get(Compute_encoder.set_bytes_with_stride encoder~index:1~stride:4L(Bytes.of_string "abcd"));
  get(Compute_encoder.set_textures encoder~start:0[Some texture]);
  get(Compute_encoder.set_sampler encoder~index:0~lod_min:0.~lod_max:1.(Some sampler));
  get(Compute_encoder.set_samplers encoder~start:1[Some sampler]);
  get(Compute_encoder.set_acceleration_structure encoder~index:2(Some acceleration));
  get(Compute_encoder.set_visible_function_table encoder~index:3(Some visible));
  get(Compute_encoder.set_visible_function_tables encoder~start:4[Some visible]);
  get(Compute_encoder.set_intersection_function_table encoder~index:5(Some intersection));
  get(Compute_encoder.set_intersection_function_tables encoder~start:6[Some intersection]);
  get(Compute_encoder.dispatch_threads encoder~threads:(4,1,1)~threadgroup:(1,1,1));
  get(Compute_encoder.end_encoding encoder);
  List.iter(fun destroy->expect Parent_has_dependents(destroy()))
    [ (fun()->Buffer.destroy buffer);(fun()->Texture.destroy texture);(fun()->Sampler.destroy sampler);
      (fun()->Visible_function_table.destroy visible);(fun()->Intersection_function_table.destroy intersection);
      (fun()->Acceleration_structure.destroy acceleration) ];
  get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);
  let bytes=get(Buffer.read_bytes buffer~offset:0L~length:16)in
  for i=0 to 3 do if Bytes.get_int32_le bytes(i*4)<>3l then fail"compute output mismatch" done;
  get(Buffer.destroy buffer);get(Texture.destroy texture);get(Sampler.destroy sampler);
  get(Visible_function_table.destroy visible);get(Intersection_function_table.destroy intersection);
  get(Acceleration_structure.destroy acceleration);get(Compute_pipeline.destroy pipeline);
  get(Function.destroy function_);get(Library.destroy library);get(Command_queue.destroy queue);get(Device.destroy device);
  print_endline"compute encoder35 safe: ok"
