open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a"pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "wrong rejection: %a"pp_error e)|Ok _->failwith"expected rejection"
let ml_source={|#include <metal_stdlib>
using namespace metal;
kernel void metal4_ml_fixture(device uint *out [[buffer(0)]]) { out[0]=32; }
|}
let ()=match Device.system_default()with
|Error _->print_endline"metal4 callable safe: skipped (no device)"
|Ok device->
 match Command4.Allocator.create device with
 |Error e when e.kind=Unsupported||e.kind=Native_error->ignore(Device.destroy device);print_endline"metal4 callable safe: skipped (Metal4 unavailable)"
 |Error e->failwith(Format.asprintf "%a"pp_error e)
 |Ok allocator->
  let ml_library=get(Library.compile_source~device ml_source)in
  let ml_descriptor=get(Machine_learning.Descriptor.create~library:ml_library
    ~function_name:"metal4_ml_fixture"~label:"ml"())in
  let returned_library,returned_name=get(Machine_learning.Descriptor.function_ ml_descriptor)in
  if returned_library!=ml_library||returned_name<>"metal4_ml_fixture"then failwith"ML function identity drift";
  get(Machine_learning.Descriptor.set_input_dimensions ml_descriptor~index:0L[|1L;4L|]);
  if get(Machine_learning.Descriptor.input_dimensions ml_descriptor~index:0L)<>Some[|1L;4L|]then failwith"ML dimensions drift";
  expect Invalid_argument(Machine_learning.Descriptor.set_input_dimensions ml_descriptor~index:256L[|1L|]);
  get(Machine_learning.Descriptor.reset ml_descriptor);
  let constants=get(Function_specialization.Constants.create_empty())in
  let specialized=get(Function_specialization.Specialized.create~name:"specialized"~constants())in
  let _,name,returned_constants=get(Function_specialization.Specialized.get specialized)in
  if name<>Some"specialized"||Option.is_none returned_constants then failwith"specialized descriptor drift";
  get(Function_specialization.Specialized.set specialized());
  let stitched=get(Function_specialization.Stitched.create[])in
  if get(Function_specialization.Stitched.get stitched)<>[]then failwith"stitched descriptor drift";
  get(Function_specialization.Stitched.set stitched[]);
  let binary_descriptor=get(Binary_function.Descriptor.create())in
  get(Binary_function.Descriptor.set binary_descriptor Binary_function.Descriptor.Vertex []);
  if get(Binary_function.Descriptor.get binary_descriptor Binary_function.Descriptor.Vertex)<>[]then failwith"binary descriptor reset drift";
  get(Binary_function.Descriptor.reset binary_descriptor);
  let source=get(Buffer.create~device~length:1024L~storage:Buffer.Shared())in
  let destination=get(Buffer.create~device~length:1024L~storage:Buffer.Shared())in
  let counter=get(Command4.Counter_heap.create device~kind:Command4.Counter_heap.Timestamp~count:8L)in
  let kind,count,_=get(Command4.Counter_heap.info counter)in
  if kind<>Command4.Counter_heap.Timestamp||count<>8L then failwith"counter enum mapping drift";
  let commands=get(Command4.Command_buffer.create allocator())in
  let residency=get(Residency_set.create~device(Residency_set.make_descriptor~initial_capacity:1()))in
  expect Invalid_argument(Command4.Command_buffer.resolve_counter commands counter
    ~location:0L~length:1L~destination~destination_offset:1020L());
  get(Command4.Command_buffer.push_debug_group commands "command-buffer");
  get(Command4.Command_buffer.pop_debug_group commands);
  get(Command4.Command_buffer.use_residency_sets commands [residency]);
  get(Command4.Command_buffer.write_timestamp commands counter~index:1L);
  get(Command4.Command_buffer.resolve_counter commands counter~location:1L
    ~length:1L~destination~destination_offset:512L());
  let ml_encoder=get(Command4.Machine_learning_encoder.create commands)in
  get(Command4.Machine_learning_encoder.set_argument_table ml_encoder None);
  get(Command4.Machine_learning_encoder.end_encoding ml_encoder);
  let render_target=get(Texture.create~device(Texture.descriptor_2d
    ~storage:Buffer.Shared~usage:[Texture.Render_target]
    ~format:Texture.Bgra8_unorm~width:4~height:4()))in
  let attachment=Command4.Render_encoder.color_attachment render_target in
  let render=get(Command4.Render_encoder.create commands~color_attachments:[attachment])in
  expect Invalid_argument(Command4.Render_encoder.draw render
    Command4.Render_encoder.Triangle~vertex_start:0L~vertex_count:0L~instance_count:1L);
  get(Command4.Render_encoder.set_threadgroup_memory render~length:0L~index:0L~offset:0L());
  get(Command4.Render_encoder.write_timestamp render
    ~granularity:Command4.Render_encoder.Relaxed~after:[Command4.Render_encoder.Vertex]
    counter~index:2L);
  get(Command4.Render_encoder.end_encoding render);
  let encoder=get(Command4.Compute_encoder.create commands)in
  expect Invalid_argument(Command4.Compute_encoder.fill_buffer encoder source~offset:1000L~length:25L~byte:7);
  get(Command4.Compute_encoder.push_debug_group encoder"callable");
  get(Command4.Compute_encoder.insert_debug_signpost encoder"fill-copy");
  get(Command4.Compute_encoder.fill_buffer encoder source~offset:0L~length:256L~byte:7);
  get(Command4.Compute_encoder.copy_buffer encoder~source~source_offset:0L~destination~destination_offset:0L~size:256L);
  get(Command4.Compute_encoder.write_timestamp encoder~granularity:Command4.Compute_encoder.Relaxed counter~index:0L);
  get(Command4.Compute_encoder.pop_debug_group encoder);
  get(Command4.Compute_encoder.end_encoding encoder);
  get(Command4.Command_buffer.end_recording commands);
  expect Parent_has_dependents(Buffer.destroy source);
  let queue=get(Command4.Queue.create device)in
  get(Command4.Queue.add_residency_sets queue[residency]);
  expect Parent_has_dependents(Residency_set.destroy residency);
  get(Command4.Queue.remove_residency_set queue residency);
  let submission=get(Command4.Queue.commit queue[commands])in
  get(Command4.Submission.wait submission);
  let feedback=get(Command4.Submission.feedback submission)in
  if feedback.gpu_duration<0.||feedback.gpu_end_time<feedback.gpu_start_time then failwith"submission feedback drift";
  get(Command4.Counter_heap.invalidate counter~location:0L~length:1L);
  ignore(get(Command4.Counter_heap.resolve counter~location:0L~length:1L));
  get(Command4.Submission.destroy submission);get(Command4.Command_buffer.destroy commands);
  get(Buffer.destroy source);get(Buffer.destroy destination);get(Texture.destroy render_target);get(Command4.Counter_heap.destroy counter);
  get(Residency_set.destroy residency);get(Command4.Queue.destroy queue);get(Command4.Allocator.destroy allocator);
  get(Function_specialization.Stitched.destroy stitched);
  get(Function_specialization.Specialized.destroy specialized);
  get(Function_specialization.Constants.destroy constants);
  get(Machine_learning.Descriptor.destroy ml_descriptor);get(Library.destroy ml_library);
  get(Binary_function.Descriptor.destroy binary_descriptor);get(Device.destroy device);
  print_endline"metal4 callable safe: ok"
