open Metal

external fail_render_encoder_resource_use_after : int -> unit =
  "caml_prismel_test_metal_fail_render_encoder_use_resources_after"

let get = function Ok value -> value | Error error -> failwith error.message
let expect kind = function
  | Error error when error.kind=kind -> ()
  | Error error -> failwith("unexpected Metal error: "^error.message)
  | Ok _ -> failwith"expected Metal operation to fail"

let source = {|
#include <metal_stdlib>
using namespace metal;
struct O { float4 position [[position]]; };
struct A { texture2d<float,access::sample> image [[id(0)]]; sampler sampling [[id(1)]]; };
vertex O vertex_main(device const float2 *p [[buffer(0)]], uint i [[vertex_id]]) {
  O o; o.position=float4(p[i],0.,1.); return o;
}
fragment float4 fragment_main(O o [[stage_in]], constant A& args [[buffer(1)]]) {
  return args.image.sample(args.sampling,float2(.5));
}
fragment float4 fragment_solid(O o [[stage_in]]) { return float4(.25,.5,.75,1.); }
fragment float4 fragment_direct(O o [[stage_in]],texture2d<float> image [[texture(0)]],sampler sampling [[sampler(1)]]) { return image.sample(sampling,float2(.5)); }
|}

let () =
  let device=get(Device.system_default()) in
  let before=get(Release_queue.stats()) in
  let library=get(Library.compile_source~device source) in
  let fragment=get(Function.find~library "fragment_main") in
  let compiler=get(Compiler.create device) in
  let pipeline=get(Compiler.create_render_pipeline~reflection:true
    ~support_indirect_command_buffers:true~color_formats:[Texture.Rgba8_unorm]
    compiler~library~vertex:"vertex_main"~fragment:"fragment_main") in
  let solid_pipeline=get(Compiler.create_render_pipeline~reflection:true
    ~support_indirect_command_buffers:true~color_formats:[Texture.Rgba8_unorm]
    compiler~library~vertex:"vertex_main"~fragment:"fragment_solid") in
  let direct_pipeline=get(Compiler.create_render_pipeline~reflection:true
    ~color_formats:[Texture.Rgba8_unorm]compiler~library~vertex:"vertex_main"~fragment:"fragment_direct")in
  let argument_encoder=get(Function.argument_encoder fragment~buffer_index:1L) in
  let vertices=Bytes.create 24 in
  List.iteri(fun i value->Bytes.set_int32_le vertices(i*4)(Int32.bits_of_float value))
    [-1.;-1.;3.;-1.;-1.;3.];
  let vertex_buffer=get(Buffer.create_copy~device~storage:Buffer.Shared vertices) in
  let scale_root_count=1024 in
  let scale_buffers=Array.init scale_root_count(fun _->
    get(Buffer.create~device~length:8L~storage:Buffer.Shared()))in
  let scale_draws=Array.init(scale_root_count*4)(fun index->
    let buffer=Array.unsafe_get scale_buffers(index mod scale_root_count)in
    ({prepared_pipeline=pipeline;
      prepared_bindings=[|{Render_encoder.Private.prepared_stage=
        Render_encoder.Vertex;prepared_index=0;prepared_offset=0L;
        prepared_buffer=buffer}|];
      prepared_primitive=Render_encoder.Triangle;
      prepared_index_type=Render_encoder.Uint16;
      prepared_index_buffer=buffer;prepared_index_offset=0L;
      prepared_index_count=3L}
      :Render_encoder.Private.prepared_indexed_draw))in
  let scale_prepared=get(Render_encoder.Private.prepare_indexed_draws device
    scale_draws)in
  if Render_encoder.Private.prepared_indexed_root_counts scale_prepared<>
      (1,scale_root_count)then
    failwith"prepared indexed root cardinality was not identity-deduplicated";
  let sampled=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
    ~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:1~height:1())) in
  let region={Texture.x=0;y=0;z=0;width=1;height=1;depth=1} in
  get(Texture.write_bytes sampled~region~mip_level:0~slice:0~bytes_per_row:4
    ~bytes_per_image:4(Bytes.of_string"\x11\x22\x33\xff"));
  let sampler=get(Sampler.create~device{(Sampler.default())with support_argument_buffers=true}) in
  let argument_buffer=get(Buffer.create~device
    ~length:(Shader_argument_encoder.encoded_length argument_encoder)
    ~storage:Buffer.Shared()) in
  get(Shader_argument_encoder.set_argument_buffer argument_encoder argument_buffer~offset:0L());
  get(Shader_argument_encoder.set argument_encoder~index:0L(Shader_argument_encoder.Texture sampled));
  get(Shader_argument_encoder.set argument_encoder~index:1L(Shader_argument_encoder.Sampler sampler));
  let argument_generation=Buffer.generation argument_buffer in
  let argument_bytes=get(Buffer.read_bytes argument_buffer~offset:0L~length:(Int64.to_int(Buffer.length argument_buffer)))in
  let descriptor=Indirect_command_buffer.descriptor~inherit_buffers:false
    ~inherit_pipeline_state:false~max_vertex_buffer_bind_count:1
    ~max_fragment_buffer_bind_count:2~command_types:[Indirect_command_buffer.Indirect_draw]() in
  let icb=get(Indirect_command_buffer.create~device~storage:Buffer.Shared~max_command_count:1 descriptor) in
  let indirect=get(Indirect_command_buffer.Render_command.at icb 0) in
  get(Indirect_command_buffer.Render_command.set_pipeline indirect pipeline);
  get(Indirect_command_buffer.Render_command.set_vertex_buffer indirect~index:0~offset:0L vertex_buffer);
  get(Indirect_command_buffer.Render_command.set_fragment_buffer indirect~index:1~offset:0L argument_buffer);
  get(Indirect_command_buffer.Render_command.draw_primitives indirect
    ~primitive:Indirect_command_buffer.Render_command.Triangle~vertex_start:0~vertex_count:3());
  let target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
    ~usage:[Texture.Render_target]~format:Texture.Rgba8_unorm~width:1~height:1())) in
  let queue=get(Command_queue.create device) in
  let prepared_native_pass=get(Render_pass_descriptor.create~width:1~height:1())in
  get(Render_pass_descriptor.set_attachments prepared_native_pass~color:target
    ~clear:(0.,0.,0.,1.)());
  let prepared_vertex_resources=get(Render_encoder.prepare_resources device
    [Render_encoder.Buffer_resource vertex_buffer])in
  let prepared_fragment_resources=get(Render_encoder.prepare_resources device
    [Render_encoder.Buffer_resource argument_buffer])in
  let prepared_texture_resources=get(Render_encoder.prepare_resources device
    [Render_encoder.Texture_resource sampled])in
  let chunk_buffers=Array.init 65(fun _->get(Buffer.create~device
    ~length:4L~storage:Buffer.Shared()))in
  let prepared_chunk_resources=get(Render_encoder.prepare_resources device
    (Array.to_list(Array.map(fun buffer->Render_encoder.Buffer_resource buffer)
      chunk_buffers)))in
  let prepared_resource_uses:Render_encoder.prepared_resource_use array=[|
    {resources=prepared_vertex_resources;usage=[Render_encoder.Read];
     stages=[Render_encoder.Vertex]};
    {resources=prepared_fragment_resources;usage=[Render_encoder.Read];
     stages=[Render_encoder.Fragment]};
    {resources=prepared_texture_resources;usage=[Render_encoder.Sample];
     stages=[Render_encoder.Fragment]};
    {resources=prepared_chunk_resources;usage=[Render_encoder.Read];
     stages=[Render_encoder.Vertex]};
    {resources=prepared_chunk_resources;usage=[Render_encoder.Read];
     stages=[Render_encoder.Fragment]}
  |]in
  let invalid_resource_uses:Render_encoder.prepared_resource_use array=[|
    Array.unsafe_get prepared_resource_uses 0;
    {resources=prepared_fragment_resources;usage=[];
     stages=[Render_encoder.Fragment]}
  |]in
  (* A later native useResources failure must not unroot an earlier set that is
     already encoded into the same command buffer. The fault hook is private to
     this native conformance executable and never enters the Metal API. *)
  let partial_first_buffer=get(Buffer.create~device~length:8L
    ~storage:Buffer.Shared())in
  let partial_second_buffer=get(Buffer.create~device~length:8L
    ~storage:Buffer.Shared())in
  let partial_first=get(Render_encoder.prepare_resources device
    [Render_encoder.Buffer_resource partial_first_buffer])in
  let partial_second=get(Render_encoder.prepare_resources device
    [Render_encoder.Buffer_resource partial_second_buffer])in
  let partial_uses:Render_encoder.prepared_resource_use array=[|
    {resources=partial_first;usage=[Render_encoder.Read];
     stages=[Render_encoder.Vertex]};
    {resources=partial_second;usage=[Render_encoder.Read];
     stages=[Render_encoder.Fragment]}
  |]in
  let partial_command=get(Command_buffer.create queue())in
  let partial_render=get(Render_encoder.create partial_command~target())in
  fail_render_encoder_resource_use_after 1;
  expect Native_error
    (Render_encoder.use_prepared_resource_sets partial_render partial_uses);
  expect Parent_has_dependents
    (Render_encoder.destroy_prepared_resources partial_first);
  get(Render_encoder.destroy_prepared_resources partial_second);
  get(Render_encoder.end_encoding partial_render);
  get(Command_buffer.commit partial_command);
  get(Command_buffer.wait_until_completed partial_command);
  get(Render_encoder.destroy_prepared_resources partial_first);
  get(Command_buffer.destroy partial_command);
  get(Buffer.destroy partial_first_buffer);
  get(Buffer.destroy partial_second_buffer);
  let viewport:Render_encoder.viewport=
    {x=0.;y=0.;width=1.;height=1.;znear=0.;zfar=1.}in
  let scissor:Render_encoder.scissor={x=0;y=0;width=1;height=1}in
  expect Invalid_argument(
    Render_encoder.Private.prepare_indirect_render_pass device
      prepared_native_pass~cull:Render_encoder.No_cull~viewport~scissor
      ~pipeline~commands:icb~location:0~length:0
      ~resource_uses:prepared_resource_uses());
  let prepared_indirect_pass=get(
    Render_encoder.Private.prepare_indirect_render_pass device
      prepared_native_pass~cull:Render_encoder.No_cull~viewport~scissor
      ~pipeline~commands:icb~location:0~length:1
      ~resource_uses:prepared_resource_uses())in
  let solid_target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
    ~usage:[Texture.Render_target]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let solid_icb=get(Indirect_command_buffer.create~device~storage:Buffer.Shared~max_command_count:1 descriptor)in
  let solid_indirect=get(Indirect_command_buffer.Render_command.at solid_icb 0)in
  get(Indirect_command_buffer.Render_command.set_pipeline solid_indirect solid_pipeline);
  get(Indirect_command_buffer.Render_command.set_vertex_buffer solid_indirect~index:0~offset:0L vertex_buffer);
  get(Indirect_command_buffer.Render_command.draw_primitives solid_indirect~primitive:Indirect_command_buffer.Render_command.Triangle~vertex_start:0~vertex_count:3());
  for iteration=1 to 100 do let command=get(Command_buffer.create queue())in let render=get(Render_encoder.create command~target:solid_target())in get(Render_encoder.set_pipeline render solid_pipeline);get(Render_encoder.use_resources render[Render_encoder.Buffer_resource vertex_buffer]~usage:[Render_encoder.Read]~stages:[Render_encoder.Vertex]);get(Render_encoder.execute_indirect_commands render solid_icb~location:0~length:1);get(Render_encoder.end_encoding render);get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);let actual=get(Texture.read_bytes solid_target~region~mip_level:0~slice:0~bytes_per_row:4~bytes_per_image:4)in if actual<>Bytes.of_string"\x40\x80\xbf\xff"then failwith(Printf.sprintf"plain render ICB iteration=%d actual=%02x,%02x,%02x,%02x"iteration(Char.code(Bytes.get actual 0))(Char.code(Bytes.get actual 1))(Char.code(Bytes.get actual 2))(Char.code(Bytes.get actual 3)))done;
  let direct_target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
    ~usage:[Texture.Render_target]~format:Texture.Rgba8_unorm~width:1~height:1())) in
  let bindings_target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Render_target]~format:Texture.Rgba8_unorm~width:1~height:1()))in
  let direct_bindings_once()=let command=get(Command_buffer.create queue())in let render=get(Render_encoder.create command~target:bindings_target())in get(Render_encoder.set_pipeline render direct_pipeline);get(Render_encoder.set_vertex_buffer render~index:0~offset:0L vertex_buffer);get(Render_encoder.set_fragment_texture render~index:0 sampled);get(Render_encoder.set_fragment_sampler render~index:1 sampler);get(Render_encoder.draw_triangles render~first:0~count:3());get(Render_encoder.end_encoding render);get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);get(Texture.read_bytes bindings_target~region~mip_level:0~slice:0~bytes_per_row:4~bytes_per_image:4)in
  for iteration=1 to 1000 do if direct_bindings_once()<>Bytes.of_string"\x11\x22\x33\xff"then failwith(Printf.sprintf"persistent direct texture/sampler iteration=%d"iteration)done;
  let expected=Bytes.of_string"\x11\x22\x33\xff"in
  Gc.full_major();
  for iteration=1 to 1000 do
    if iteration mod 10=0 then Gc.full_major();
    get(Shader_argument_encoder.set_argument_buffer argument_encoder argument_buffer~offset:0L());
    get(Shader_argument_encoder.set argument_encoder~index:0L(Shader_argument_encoder.Texture sampled));
    get(Shader_argument_encoder.set argument_encoder~index:1L(Shader_argument_encoder.Sampler sampler));
    let direct_command=get(Command_buffer.create queue())in
    let direct=get(Render_encoder.create direct_command~target:direct_target())in
    get(Render_encoder.set_pipeline direct pipeline);get(Render_encoder.set_vertex_buffer direct~index:0~offset:0L vertex_buffer);
    get(Render_encoder.set_fragment_buffer direct~index:1~offset:0L argument_buffer);
    get(Render_encoder.use_resources direct[Render_encoder.Buffer_resource vertex_buffer]
      ~usage:[Render_encoder.Read]~stages:[Render_encoder.Vertex]);
    get(Render_encoder.use_resources direct[Render_encoder.Buffer_resource argument_buffer]
      ~usage:[Render_encoder.Read]~stages:[Render_encoder.Fragment]);
    get(Render_encoder.use_resources direct[Render_encoder.Texture_resource sampled]
      ~usage:[Render_encoder.Sample]~stages:[Render_encoder.Fragment]);
    get(Render_encoder.draw_triangles direct~first:0~count:3());get(Render_encoder.end_encoding direct);
    get(Command_buffer.commit direct_command);get(Command_buffer.wait_until_completed direct_command);get(Command_buffer.destroy direct_command);
    let actual=get(Texture.read_bytes direct_target~region~mip_level:0~slice:0~bytes_per_row:4~bytes_per_image:4)in
    if actual<>expected then let now=get(Buffer.read_bytes argument_buffer~offset:0L~length:(Int64.to_int(Buffer.length argument_buffer)))and recovery=direct_bindings_once()=expected in failwith(Printf.sprintf"direct argument-buffer control iteration=%d actual=%02x,%02x,%02x,%02x bytes_same=%b generation=%Ld/%Ld alignment=%Ld length=%Ld recovery=%b"iteration(Char.code(Bytes.get actual 0))(Char.code(Bytes.get actual 1))(Char.code(Bytes.get actual 2))(Char.code(Bytes.get actual 3))(now=argument_bytes)(Buffer.generation argument_buffer)argument_generation(Shader_argument_encoder.alignment argument_encoder)(Shader_argument_encoder.encoded_length argument_encoder)recovery)
  done;
  if Buffer.generation argument_buffer<>argument_generation then failwith"argument buffer generation changed";
  if get(Buffer.read_bytes argument_buffer~offset:0L~length:(Int64.to_int(Buffer.length argument_buffer)))<>argument_bytes then failwith"argument buffer encoded bytes drifted";
  for _frame=1 to 10 do
    let command=get(Command_buffer.create queue()) in
    let render=get(Render_encoder.create command~target()) in
    get(Render_encoder.set_pipeline render pipeline);
    if _frame=1 then expect Invalid_argument
      (Render_encoder.use_prepared_resource_sets render invalid_resource_uses);
    get(Render_encoder.use_prepared_resource_sets render prepared_resource_uses);
    get(Render_encoder.execute_indirect_commands render icb~location:0~length:1);
    get(Render_encoder.end_encoding render);get(Command_buffer.commit command);
    get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);
    let pixels=get(Texture.read_bytes target~region~mip_level:0~slice:0
      ~bytes_per_row:4~bytes_per_image:4) in
    if pixels<>expected then failwith(Printf.sprintf"render ICB argument pixels actual=%02x,%02x,%02x,%02x"(Char.code(Bytes.get pixels 0))(Char.code(Bytes.get pixels 1))(Char.code(Bytes.get pixels 2))(Char.code(Bytes.get pixels 3)))
  done;
  for _frame=1 to 10 do
    let command=get(Command_buffer.create queue())in
    get(Render_encoder.Private.execute_prepared_indirect_render_pass command
      prepared_indirect_pass);
    get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);
    get(Command_buffer.destroy command);
    let pixels=get(Texture.read_bytes target~region~mip_level:0~slice:0
      ~bytes_per_row:4~bytes_per_image:4)in
    if pixels<>expected then failwith(Printf.sprintf
      "prepared render ICB argument pixels actual=%02x,%02x,%02x,%02x"
      (Char.code(Bytes.get pixels 0))(Char.code(Bytes.get pixels 1))
      (Char.code(Bytes.get pixels 2))(Char.code(Bytes.get pixels 3)))
  done;
  let dropped_command,dropped_resources_weak,dropped_buffer_weak=
    let dropped_buffer=get(Buffer.create~device~length:4L~storage:Buffer.Shared())in
    let dropped_resources=get(Render_encoder.prepare_resources device
      [Render_encoder.Buffer_resource dropped_buffer])in
    let resources_weak=Weak.create 1 and buffer_weak=Weak.create 1 in
    Weak.set resources_weak 0(Some dropped_resources);
    Weak.set buffer_weak 0(Some dropped_buffer);
    let dropped_uses=Array.append prepared_resource_uses[|
      {Render_encoder.resources=dropped_resources;usage=[Render_encoder.Read];
       stages=[Render_encoder.Vertex]}
    |]in
    let dropped_pass=get(
      Render_encoder.Private.prepare_indirect_render_pass device
        prepared_native_pass~cull:Render_encoder.No_cull~viewport~scissor
        ~pipeline~commands:icb~location:0~length:1
        ~resource_uses:dropped_uses())in
    let command=get(Command_buffer.create_unretained queue)in
    get(Render_encoder.Private.execute_prepared_indirect_render_pass command
      dropped_pass);
    command,resources_weak,buffer_weak
  in
  Gc.full_major();
  let dropped_resources=match Weak.get dropped_resources_weak 0 with
    |Some resources->resources
    |None->failwith"prepared resource wrapper was not completion-rooted"in
  let dropped_buffer=match Weak.get dropped_buffer_weak 0 with
    |Some buffer->buffer
    |None->failwith"prepared buffer wrapper was not completion-rooted"in
  get(Command_buffer.commit dropped_command);
  get(Command_buffer.wait_until_completed dropped_command);
  get(Command_buffer.destroy dropped_command);
  get(Render_encoder.destroy_prepared_resources dropped_resources);
  get(Buffer.destroy dropped_buffer);
  (match get(Counters.sets device)with
   |[]->()
   |counter_set::_->
       let descriptor=get(Counters.Descriptor.create device
         ~set_name:counter_set.name~sample_count:4L~storage:Buffer.Shared())in
       let sample_weak=Weak.create 1 in
       let attach_sample()=
         let samples=get(Counters.Descriptor.create_buffer descriptor)in
         Weak.set sample_weak 0(Some samples);
         get(Counters.set_render_pass_attachment prepared_native_pass~index:0
           samples~start_vertex:0L~end_vertex:1L~start_fragment:2L
           ~end_fragment:3L)
       in
       attach_sample();Gc.full_major();
       let samples=match Weak.get sample_weak 0 with
         |Some samples->samples
         |None->failwith"render-pass sample wrapper was not descriptor-rooted"in
       get(Counters.clear_render_pass_attachment prepared_native_pass~index:0);
       get(Resource100.Sample_buffer.destroy samples);
       get(Counters.Descriptor.destroy descriptor));
  let retained_command=get(Command_buffer.create queue())in
  get(Render_encoder.Private.execute_prepared_indirect_render_pass
    retained_command prepared_indirect_pass);
  expect Parent_has_dependents
    (Render_encoder.destroy_prepared_resources prepared_vertex_resources);
  get(Command_buffer.commit retained_command);
  get(Command_buffer.wait_until_completed retained_command);
  get(Command_buffer.destroy retained_command);
  get(Render_encoder.destroy_prepared_resources prepared_chunk_resources);
  get(Render_encoder.destroy_prepared_resources prepared_texture_resources);
  get(Render_encoder.destroy_prepared_resources prepared_fragment_resources);
  get(Render_encoder.destroy_prepared_resources prepared_vertex_resources);
  get(Render_pass_descriptor.destroy prepared_native_pass);
  get(Command_queue.destroy queue);get(Texture.destroy bindings_target);get(Texture.destroy direct_target);get(Texture.destroy target);get(Texture.destroy solid_target);
  get(Indirect_command_buffer.Render_command.destroy solid_indirect);get(Indirect_command_buffer.destroy solid_icb);
  get(Indirect_command_buffer.Render_command.destroy indirect);get(Indirect_command_buffer.destroy icb);
  get(Shader_argument_encoder.destroy argument_encoder);get(Buffer.destroy argument_buffer);
  Array.iter(fun buffer->get(Buffer.destroy buffer))chunk_buffers;
  Array.iter(fun buffer->get(Buffer.destroy buffer))scale_buffers;
  get(Sampler.destroy sampler);get(Texture.destroy sampled);get(Buffer.destroy vertex_buffer);
  get(Render_pipeline.destroy direct_pipeline);get(Render_pipeline.destroy solid_pipeline);get(Render_pipeline.destroy pipeline);get(Compiler.destroy compiler);get(Function.destroy fragment);
  get(Library.destroy library);get(Device.destroy device);ignore(get(Release_queue.drain()));
  let after=get(Release_queue.stats())in
  if after.live_handles<>before.live_handles-1 then failwith"render ICB argument handle delta";
  print_endline"Metal render ICB argument-buffer: direct/prepared exact frames, zero delta"
