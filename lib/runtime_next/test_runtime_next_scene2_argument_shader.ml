open Metal
let get=function Ok x->x|Error e->failwith e.message
let ()=
  let device=get(Device.system_default())in
  let before=get(Release_queue.stats())in
  let direct=get(Library.compile_source~device Runtime_next.Private.scene2_textured_direct)in
  let argument=get(Library.compile_source~device Runtime_next.Private.scene2_textured_argument)in
  let direct_fragment=get(Function.find~library:direct"scene_fragment")in
  let argument_fragment=get(Function.find~library:argument"scene_fragment_argument")in
  let argument_compiler=get(Compiler.create device)in
  let pipeline=get(Compiler.create_render_pipeline~reflection:true~color_formats:[Texture.Rgba8_unorm]argument_compiler~library:argument~vertex:"scene_vertex"~fragment:"scene_fragment_argument")in
  let direct_compiler=get(Compiler.create device)in
  let direct_pipeline=get(Compiler.create_render_pipeline~reflection:true~color_formats:[Texture.Rgba8_unorm]direct_compiler~library:direct~vertex:"scene_vertex"~fragment:"scene_fragment")in
  let encoder=get(Function.argument_encoder argument_fragment~buffer_index:1L)in
  assert(Shader_argument_encoder.encoded_length encoder>0L);
  assert(Shader_argument_encoder.alignment encoder>0L);
  (match Function.argument_encoder argument_fragment~buffer_index:(-1L) with Error e when e.kind=Invalid_argument->()|_->failwith"malformed argument binding accepted");
  let vertices=Bytes.make(3*68)'\000'in
  let put i x y u v=let base=i*68 in Bytes.set_int64_le vertices base(Int64.bits_of_float x);Bytes.set_int64_le vertices(base+8)(Int64.bits_of_float y);Bytes.set_int32_le vertices(base+48)Int32.minus_one;Bytes.set_int64_le vertices(base+52)(Int64.bits_of_float u);Bytes.set_int64_le vertices(base+60)(Int64.bits_of_float v)in
  put 0(-1.)(-1.)0. 1.;put 1 3.(-1.)2. 1.;put 2(-1.)3. 0.(-1.);
  let vertex_buffer=get(Buffer.create_copy~device~storage:Buffer.Shared vertices)in
  let sampled=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let region={Texture.x=0;y=0;z=0;width=1;height=1;depth=1}in
  get(Texture.write_bytes sampled~region~mip_level:0~slice:0~bytes_per_row:4~bytes_per_image:4(Bytes.of_string"\x11\x22\x33\xff"));
  let sampler=get(Sampler.create~device(Sampler.default()))in
  let argument_buffer=get(Buffer.create~device~length:(Shader_argument_encoder.encoded_length encoder)~storage:Buffer.Shared())in
  get(Shader_argument_encoder.set_argument_buffer encoder argument_buffer~offset:0L());
  get(Shader_argument_encoder.set encoder~index:0L(Shader_argument_encoder.Texture sampled));
  get(Shader_argument_encoder.set encoder~index:1L(Shader_argument_encoder.Sampler sampler));
  let target()=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Render_target]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let direct_target=target()and argument_target=target()and queue=get(Command_queue.create device)in
  let render pipeline target bind=let command=get(Command_buffer.create queue())in let pass=get(Render_encoder.create command~target())in get(Render_encoder.set_pipeline pass pipeline);get(Render_encoder.set_vertex_buffer pass~index:0~offset:0L vertex_buffer);bind pass;get(Render_encoder.draw_triangles pass~first:0~count:3());get(Render_encoder.end_encoding pass);get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);get(Texture.read_bytes target~region~mip_level:0~slice:0~bytes_per_row:4~bytes_per_image:4)in
  let direct_pixels=render direct_pipeline direct_target(fun pass->get(Render_encoder.set_fragment_texture pass~index:1 sampled);get(Render_encoder.set_fragment_sampler pass~index:2 sampler))in
  let argument_pixels=render pipeline argument_target(fun pass->get(Render_encoder.set_fragment_buffer pass~index:1~offset:0L argument_buffer))in
  if direct_pixels<>argument_pixels||direct_pixels<>Bytes.of_string"\x11\x22\x33\xff"then failwith"direct/argument-buffer pixel mismatch"else();
  get(Shader_argument_encoder.destroy encoder);
  get(Command_queue.destroy queue);get(Texture.destroy argument_target);get(Texture.destroy direct_target);get(Buffer.destroy argument_buffer);get(Sampler.destroy sampler);get(Texture.destroy sampled);get(Buffer.destroy vertex_buffer);
  get(Render_pipeline.destroy direct_pipeline);get(Compiler.destroy direct_compiler);get(Render_pipeline.destroy pipeline);get(Compiler.destroy argument_compiler);
  get(Function.destroy argument_fragment);get(Function.destroy direct_fragment);
  get(Library.destroy argument);get(Library.destroy direct);get(Device.destroy device);
  ignore(get(Release_queue.drain()));
  let after=get(Release_queue.stats())in
  if after.live_handles<>before.live_handles-1 then failwith"argument shader live-handle delta"else();
  print_endline"runtime-next scene2 direct/argument shader compile and reflection"
