open Metal
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"pp_error error)
let expect kind=function Error error when error.kind=kind->()|Error error->failwith error.message|Ok _->failwith"expected rejection"
let ()=match Device.system_default()with Error _->print_endline"parallel-render7: skipped"|Ok device->
  let queue=get(Command_queue.create device)in
  for iteration=0 to 255 do
    let texture=get(Texture.create ~device(Texture.descriptor_2d ~storage:Buffer.Shared ~usage:[Texture.Render_target] ~format:Texture.Bgra8_unorm ~width:4 ~height:4()))in
    let pass=get(Render_pass_descriptor.create ~width:4 ~height:4())in
    get(Render_pass_descriptor.set_attachments pass~color:texture());
    let command=get(Command_buffer.create queue())in
    let parent=get(Command_buffer.create_parallel_render_encoder_with_descriptor command pass)in
    get(Parallel_render_encoder.set_color_store parent~index:0 Parallel_render_encoder.Store Parallel_render_encoder.No_options);
    get(Parallel_render_encoder.set_depth_store parent Parallel_render_encoder.Dont_care Parallel_render_encoder.No_options);
    get(Parallel_render_encoder.set_stencil_store parent Parallel_render_encoder.Dont_care Parallel_render_encoder.No_options);
    let first=get(Parallel_render_encoder.create_child parent)in
    let second=get(Parallel_render_encoder.create_child parent)in
    expect Invalid_state(Parallel_render_encoder.end_encoding parent);
    get(Parallel_render_encoder.end_child second);get(Parallel_render_encoder.end_child first);
    get(Parallel_render_encoder.end_encoding parent);
    expect Parent_has_dependents(Texture.destroy texture);
    get(Render_pass_descriptor.destroy pass);get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);
    get(Texture.destroy texture);get(Command_buffer.destroy command);
    if iteration=255 then print_endline"parallel-render7 safe: 256 ownership/order passes ok"
  done;
  get(Command_queue.destroy queue);get(Device.destroy device)
