open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a"pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "wrong rejection: %a"pp_error e)|Ok _->failwith"expected rejection"
let ()=match Device.system_default()with
|Error _->print_endline"metal4 callable safe: skipped (no device)"
|Ok device->
 match Command4.Allocator.create device with
 |Error e when e.kind=Unsupported||e.kind=Native_error->ignore(Device.destroy device);print_endline"metal4 callable safe: skipped (Metal4 unavailable)"
 |Error e->failwith(Format.asprintf "%a"pp_error e)
 |Ok allocator->
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
  get(Command4.Counter_heap.invalidate counter~location:0L~length:1L);
  ignore(get(Command4.Counter_heap.resolve counter~location:0L~length:1L));
  get(Command4.Submission.destroy submission);get(Command4.Command_buffer.destroy commands);
  get(Buffer.destroy source);get(Buffer.destroy destination);get(Command4.Counter_heap.destroy counter);
  get(Residency_set.destroy residency);get(Command4.Queue.destroy queue);get(Command4.Allocator.destroy allocator);
  get(Binary_function.Descriptor.destroy binary_descriptor);get(Device.destroy device);
  print_endline"metal4 callable safe: ok"
