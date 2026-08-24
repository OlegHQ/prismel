open Metal

let get = function Ok value -> value | Error value -> failwith value.message
let fail message = failwith message

let () =
  let device = get (Device.create ()) in
  let library = get (Library.compile device
    "#include <metal_stdlib>\nusing namespace metal; kernel void p4(device uint *x [[buffer(0)]]) { x[0]=4; }") in
  let function_ = get (Function.create library "p4") in
  let immutable = get (Pipeline_buffer_descriptor.create ~mutability:Immutable ()) in
  if Pipeline_buffer_descriptor.mutability immutable <> Immutable then
    fail "immutable descriptor snapshot drift";
  let pipeline = get (Compute_pipeline.create
    ~buffer_descriptors:[0,Some immutable;1,None] function_) in
  let queue = get (Command_queue.create device) in
  let command = get (Command_buffer.create queue ()) in
  let output = get (Buffer.create device ~length:4 ~storage:Shared) in
  let encoder = get (Compute_encoder.create command) in
  get (Compute_encoder.set_pipeline encoder pipeline);
  get (Compute_encoder.set_buffer encoder ~index:0 output);
  get (Compute_encoder.dispatch_threads encoder ~threads:(1,1,1)
    ~threads_per_threadgroup:(1,1,1));
  get (Compute_encoder.end_encoding encoder);
  get (Command_buffer.commit command);
  get (Command_buffer.wait_until_completed command);
  let bytes = get (Buffer.read output ~offset:0 ~length:4) in
  if Bytes.get_uint8 bytes 0 <> 4 then fail "compute readback drift";
  let render = get (Render_pipeline.Mesh_tile.descriptor
    Render_pipeline.Mesh_tile.Render_descriptor) in
  get (Render_pipeline.Mesh_tile.set_descriptor_buffer render
    Render_pipeline.Mesh_tile.Vertex_buffers ~index:0 (Some immutable));
  let values = get (Render_pipeline.Mesh_tile.descriptor_buffer_mutabilities
    render Render_pipeline.Mesh_tile.Vertex_buffers) in
  if values.(0) <> Render_pipeline.Mesh_tile.Immutable then
    fail "render descriptor copied mutability drift";
  get (Render_pipeline.Mesh_tile.set_descriptor_buffer render
    Render_pipeline.Mesh_tile.Vertex_buffers ~index:0 None);
  let reset = get (Render_pipeline.Mesh_tile.descriptor_buffer_mutabilities
    render Render_pipeline.Mesh_tile.Vertex_buffers) in
  if reset.(0) <> Render_pipeline.Mesh_tile.Default then
    fail "nil reset default drift";
  (match Render_pipeline.Mesh_tile.set_descriptor_buffer render
     Render_pipeline.Mesh_tile.Vertex_buffers ~index:31 None with
   | Error {kind=Invalid_argument;_} -> () | _ -> fail "slot bound accepted");
  get (Render_pipeline.Mesh_tile.destroy_descriptor render);
  get (Pipeline_buffer_descriptor.destroy immutable);
  get (Compute_pipeline.destroy pipeline);
  get (Function.destroy function_); get (Library.destroy library);
  get (Buffer.destroy output); get (Command_buffer.destroy command);
  get (Command_queue.destroy queue); get (Device.destroy device)
