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
  let pipeline=get(Compute_pipeline.create~support_indirect_command_buffers:true function_)in
  let buffer=get(Buffer.create~device~length:16L~storage:Buffer.Shared())in
  let texture=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let sampler=get(Sampler.create~device(Sampler.default()))in
  let visible=get(Visible_function_table.create~pipeline~capacity:1)in
  let intersection=get(Intersection_function_table.create~pipeline~capacity:1)in
  let acceleration=get(Acceleration_structure.create~device~size:256L)in
  let samples=get(Resource100.Sample_buffer.create device~sample_count:2L())in
  let fence=get(Fence.create device)in
  let heap=get(Heap.create~device(Heap.make_descriptor~size:1048576L()))in
  let heap2=get(Heap.create~device(Heap.make_descriptor~size:1048576L()))in
  let indirect_args=get(Buffer.create~device~length:12L~storage:Buffer.Shared())in
  let indirect_bytes=Bytes.make 12 '\000' in Bytes.set_int32_le indirect_bytes 0 4l;Bytes.set_int32_le indirect_bytes 4 1l;Bytes.set_int32_le indirect_bytes 8 1l;get(Buffer.write_bytes indirect_args~dst_offset:0L indirect_bytes);
  let stage_args=get(Buffer.create~device~length:24L~storage:Buffer.Shared())in
  let stage_bytes=Bytes.make 24 '\000' in Bytes.set_int32_le stage_bytes 12 1l;Bytes.set_int32_le stage_bytes 16 1l;Bytes.set_int32_le stage_bytes 20 1l;get(Buffer.write_bytes stage_args~dst_offset:0L stage_bytes);
  let range_buffer=get(Buffer.create~device~length:8L~storage:Buffer.Shared())in
  let range_bytes=Bytes.make 8 '\000' in Bytes.set_int32_le range_bytes 4 1l;get(Buffer.write_bytes range_buffer~dst_offset:0L range_bytes);
  let icb_descriptor=Indirect_command_buffer.descriptor~command_types:[Indirect_concurrent_dispatch_threads]~max_kernel_buffer_bind_count:1()in
  let icb=get(Indirect_command_buffer.create~device~max_command_count:1 icb_descriptor)in
  let icmd=get(Indirect_command_buffer.Compute_command.at icb 0)in
  get(Indirect_command_buffer.Compute_command.set_pipeline icmd pipeline);get(Indirect_command_buffer.Compute_command.set_kernel_buffer icmd~index:0~offset:0L buffer);get(Indirect_command_buffer.Compute_command.dispatch_threads icmd~threads:(4,1,1)~threadgroup:(1,1,1));get(Indirect_command_buffer.Compute_command.destroy icmd);
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
  get(Compute_encoder.set_bytes encoder~index:7(Bytes.of_string "abcd"));
  ignore(get(Compute_encoder.dispatch_type encoder));
  get(Compute_encoder.memory_barrier encoder[Compute_encoder.Barrier_buffers;Compute_encoder.Barrier_textures]);
  get(Compute_encoder.memory_barrier_resources encoder[Compute_encoder.Buffer_resource buffer;Compute_encoder.Texture_resource texture]);
  get(Compute_encoder.set_threadgroup_memory_length encoder~index:0~length:0L);
  get(Compute_encoder.set_imageblock encoder~width:1L~height:1L);
  get(Compute_encoder.set_stage_in_region encoder {x=0L;y=0L;z=0L;width=1L;height=1L;depth=1L});
  get(Compute_encoder.set_stage_in_region_indirect encoder stage_args~offset:0L);
  (match Compute_encoder.sample_counters encoder samples~index:0L~barrier:true with Ok()->()|Error e when e.kind=Unsupported->()|Error e->fail"counter sampling: %s"(Format.asprintf"%a"pp_error e));
  get(Compute_encoder.update_fence encoder fence);get(Compute_encoder.wait_for_fence encoder fence);
  get(Compute_encoder.use_heaps encoder[heap]);get(Compute_encoder.use_heaps encoder[heap;heap2]);
  get(Compute_encoder.use_resources encoder[Compute_encoder.Buffer_resource buffer]~usage:[Compute_encoder.Resource_read]);
  get(Compute_encoder.use_resources encoder[Compute_encoder.Buffer_resource buffer;Compute_encoder.Texture_resource texture]~usage:[Compute_encoder.Resource_read]);
  get(Compute_encoder.dispatch_threadgroups_indirect encoder indirect_args~offset:0L~threadgroup:(1,1,1));
  get(Compute_encoder.execute_indirect_commands_from_buffer encoder icb~range_buffer~offset:0L);
  get(Compute_encoder.dispatch_threadgroups encoder~threadgroups:(4,1,1)~threadgroup:(1,1,1));
  get(Compute_encoder.end_encoding encoder);
  List.iter(fun destroy->expect Parent_has_dependents(destroy()))
    [ (fun()->Buffer.destroy buffer);(fun()->Texture.destroy texture);(fun()->Sampler.destroy sampler);
      (fun()->Visible_function_table.destroy visible);(fun()->Intersection_function_table.destroy intersection);
      (fun()->Acceleration_structure.destroy acceleration) ];
  List.iter(fun destroy->expect Parent_has_dependents(destroy()))
    [ (fun()->Fence.destroy fence);
      (fun()->Heap.destroy heap);(fun()->Heap.destroy heap2);(fun()->Buffer.destroy indirect_args);
      (fun()->Buffer.destroy stage_args);(fun()->Buffer.destroy range_buffer);(fun()->Indirect_command_buffer.destroy icb) ];
  get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);
  get(Indirect_command_buffer.destroy icb);
  let bytes=get(Buffer.read_bytes buffer~offset:0L~length:16)in
  for i=0 to 3 do if Bytes.get_int32_le bytes(i*4)<>9l then fail"compute output mismatch" done;
  get(Buffer.destroy buffer);get(Texture.destroy texture);get(Sampler.destroy sampler);
  get(Visible_function_table.destroy visible);get(Intersection_function_table.destroy intersection);
  get(Acceleration_structure.destroy acceleration);get(Compute_pipeline.destroy pipeline);
  get(Resource100.Sample_buffer.destroy samples);
  get(Fence.destroy fence);get(Heap.destroy heap);get(Heap.destroy heap2);
  get(Buffer.destroy indirect_args);get(Buffer.destroy stage_args);get(Buffer.destroy range_buffer);
  get(Function.destroy function_);get(Library.destroy library);get(Command_queue.destroy queue);get(Device.destroy device);
  print_endline"compute encoder35 safe: ok"
