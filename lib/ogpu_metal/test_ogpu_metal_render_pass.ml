open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"wrong render-pass rejection"
let expect_metal kind=function Error e when e.Metal.kind=kind->()|_->failwith"wrong Metal prepared-draw rejection"
let source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V pass_vertex(uint i [[vertex_id]]) {
  constexpr float2 p[4]={{-1.,-1.},{3.,-1.},{-1.,3.},{1.,1.}};
  V v; v.position=float4(p[i],0.,1.); return v;
}
fragment float4 pass_fragment() { return float4(0.,1.,0.,1.); }
vertex V msaa_vertex(uint i [[vertex_id]]) { constexpr float2 p[3]={{-1.,-1.},{1.,-1.},{-1.,1.}};V v;v.position=float4(p[i],0.,1.);return v; }
|}
let shader ()=get(Ogpu.Shader.create{backend="metal";label=Some"render-pass";bytes=Bytes.of_string source;entry_points=[{name="pass_vertex";stage=Vertex};{name="msaa_vertex";stage=Vertex};{name="pass_fragment";stage=Fragment}];bindings=[]})
let layout device=let group=get(Ogpu.Binding.create_layout[])in get(Ogpu.Binding.create_pipeline_layout~device:(Device.Private.handle device)~capabilities:(Device.capabilities device)[0,group])
let portable_pass device target ~clear =
  let texture=get(Render_pass.attachment device target~usage:Ogpu.Render_pass.Render_target)in
  let color : Ogpu.Render_pass.color={texture;resolve=None;load=Clear;store=Store;clear}in
  let descriptor : Ogpu.Render_pass.descriptor={colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=2;y=0;width=2;height=4}}in
  get(Ogpu.Render_pass.create(Device.Private.handle device)descriptor)
let byte pixels x y channel=Char.code(Bytes.get pixels(y*16+x*4+channel))
let verify pixels =for y=0 to 3 do for x=0 to 3 do let expected=if x<2 then(255,0)else(0,255)in if byte pixels x y 0<>fst expected||byte pixels x y 1<>snd expected||byte pixels x y 3<>255 then failwith"render-pass viewport/scissor pixel mismatch"done done
let msaa_pass device target resolve samples =
  let texture=get(Render_pass.attachment device target~usage:Ogpu.Render_pass.Render_target)in
  let resolve=Option.map(fun value->get(Render_pass.attachment device value~usage:Ogpu.Render_pass.Resolve_target))resolve in
  let color:Ogpu.Render_pass.color={texture;resolve;load=Clear;store=(if samples=1 then Store else Resolve);clear=(1.,0.,0.,1.)}in
  get(Ogpu.Render_pass.create(Device.Private.handle device){colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal render pass: skipped (no device)"|Ok device->
  let before=get_metal(Metal.Release_queue.stats())in
  let cache=get(Pipeline.create_cache~capacity:8)in let shader=shader()in
  let descriptor : Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"typed-pass";layout=layout device;vertex=shader;vertex_entry="pass_vertex";fragment=Some shader;fragment_entry=Some"pass_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in
  let pipeline=get(Pipeline.create_render cache device descriptor)in
  let texture_descriptor : Ogpu.Types.texture_descriptor={label=Some"target";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}in
  let target=get(Texture.create device~memory:Texture.Shared~format:Texture.Rgba8_unorm texture_descriptor)in
  let queue=get(Queue.create device)in
  let draw primitive index={Render_pass.pipeline;buffers=[];textures=[];samplers=[];primitive;vertex_start=0;vertex_count=3;index}in
  let run primitive index=let pass=portable_pass device target~clear:(1.,0.,0.,1.)in let encoded=get(Render_pass.create device pass~attachments:[target](draw primitive index))in let receipt=get(Queue.submit_render_pass queue encoded)in get(Queue.wait_through queue receipt.epoch);verify(get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16))in
  run Render_pass.Triangle_list None;
  let indices=get(Buffer.create device~memory:Buffer.Shared{label=Some"indices";size=6L;usage=[Index;Copy_dst]})in let bytes=Bytes.make 6 '\000'in Bytes.set_int16_le bytes 0 0;Bytes.set_int16_le bytes 2 1;Bytes.set_int16_le bytes 4 2;get(Buffer.write_bytes device indices~dst_offset:0L bytes);
  for _=1 to 3 do run Triangle_strip(Some(Uint16,indices,0L,3L))done;
  let stencil_pipeline_result=Pipeline.create_render cache device{descriptor with label=Some"typed-stencil";depth_format=Stencil8}in
  (match stencil_pipeline_result with
  |Error error when error.Ogpu.Error.kind=Ogpu.Error.Unsupported->print_endline"ogpu_metal stencil pixels: skipped (typed Command4 unavailable)"
  |Error error->failwith(Ogpu.Error.to_string error)
  |Ok stencil_pipeline->
    let stencil_descriptor={texture_descriptor with label=Some"stencil";usage=[Render_attachment]}in
    let stencil_texture=get(Texture.create device~memory:Texture.Device_local~format:Texture.Stencil8 stencil_descriptor)in
    let color_texture=get(Render_pass.attachment device target~usage:Ogpu.Render_pass.Render_target)
    and stencil_texture_portable=get(Render_pass.attachment device stencil_texture~usage:Ogpu.Render_pass.Render_target)in
    let stencil_attachment:Ogpu.Render_pass.stencil={texture=stencil_texture_portable;load=Clear;store=Store;clear=0}in
    let face:Ogpu.Render_pass.stencil_face={compare=Always;stencil_fail=Keep;depth_fail=Keep;pass=Replace;read_mask=Int32.minus_one;write_mask=Int32.minus_one}in
    let stencil_state:Ogpu.Render_pass.stencil_state={front=face;back=face;front_reference=1l;back_reference=1l}in
    let stencil_draw={Render_pass.pipeline=stencil_pipeline;buffers=[];textures=[];samplers=[];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in
    for frame=1 to 600 do
      let pass=get(Ogpu.Render_pass.create~stencil_state(Device.Private.handle device){colors=[|Some{texture=color_texture;resolve=None;load=Clear;store=Store;clear=(1.,0.,0.,1.)}|];depth=None;stencil=Some stencil_attachment;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
      let encoded=get(Render_pass.create device pass~attachments:[target;stencil_texture]stencil_draw)in
      if frame=1 then(Queue.inject_next_error queue;expect Ogpu.Error.Device_lost(Queue.submit_render_pass queue encoded));
      let receipt=get(Queue.submit_render_pass queue encoded)in
      get(Queue.wait_through queue receipt.epoch);
      if List.mem frame[1;2;60;600]then let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16)in if byte pixels 0 0 1<>255 then failwith"Command4 stencil pass pixel mismatch"
    done;
    let execute ~load ~clear ~state ~color=
      let attachment={stencil_attachment with load;clear}in
      let pass=get(Ogpu.Render_pass.create~stencil_state:state(Device.Private.handle device){colors=[|Some{texture=color_texture;resolve=None;load=Clear;store=Store;clear=color}|];depth=None;stencil=Some attachment;viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
      let encoded=get(Render_pass.create device pass~attachments:[target;stencil_texture]stencil_draw)in
      let receipt=get(Queue.submit_render_pass queue encoded)in get(Queue.wait_through queue receipt.epoch)
    in
    let comparisons=Ogpu.Render_pass.[Never,false;Less,false;Equal,true;Less_equal,true;Greater,false;Not_equal,false;Greater_equal,true;Always,true]in
    List.iter(fun(compare,passes)->let compare_face:Ogpu.Render_pass.stencil_face={face with compare;pass=Keep}in let compare_state:Ogpu.Render_pass.stencil_state={front=compare_face;back=compare_face;front_reference=9l;back_reference=9l}in execute~load:Clear~clear:9~state:compare_state~color:(1.,0.,0.,1.);let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16)in if(byte pixels 0 0 1=255)<>passes then failwith"Command4 stencil comparison pixel mismatch")comparisons;
    let operations=Ogpu.Render_pass.[Keep,3;Zero,0;Replace,5;Increment_clamp,4;Decrement_clamp,2;Invert,252;Increment_wrap,4;Decrement_wrap,2]in
    List.iter(fun(operation,expected)->let update_face:Ogpu.Render_pass.stencil_face={face with pass=operation}in let update_state:Ogpu.Render_pass.stencil_state={front=update_face;back=update_face;front_reference=5l;back_reference=5l}in execute~load:Clear~clear:3~state:update_state~color:(0.,0.,0.,1.);let verify_face:Ogpu.Render_pass.stencil_face={face with compare=Equal;pass=Keep}in let verify_state:Ogpu.Render_pass.stencil_state={front=verify_face;back=verify_face;front_reference=Int32.of_int expected;back_reference=Int32.of_int expected}in execute~load:Load~clear:0~state:verify_state~color:(1.,0.,0.,1.);let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16)in if byte pixels 0 0 1<>255 then failwith"Command4 stencil operation pixel mismatch")operations;
    let masked_face:Ogpu.Render_pass.stencil_face={compare=Always;stencil_fail=Keep;depth_fail=Keep;pass=Replace;read_mask=Int32.minus_one;write_mask=0x0fl}in
    let masked_state:Ogpu.Render_pass.stencil_state={front=masked_face;back=masked_face;front_reference=0x05l;back_reference=0x35l}in execute~load:Clear~clear:0xa0~state:masked_state~color:(0.,0.,0.,1.);
    let masked_verify:Ogpu.Render_pass.stencil_face={masked_face with compare=Equal;pass=Keep;read_mask=Int32.minus_one;write_mask=Int32.minus_one}in
    let masked_verify_state:Ogpu.Render_pass.stencil_state={front=masked_verify;back=masked_verify;front_reference=0xa5l;back_reference=0xa5l}in execute~load:Load~clear:0~state:masked_verify_state~color:(1.,0.,0.,1.);let masked_pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16)in if byte masked_pixels 0 0 1<>255 then failwith"Command4 stencil masks/reference pixel mismatch";
    let depth_texture=get(Texture.create device~memory:Texture.Device_local~format:Texture.Depth32_float{stencil_descriptor with label=Some"depth"})in
    let depth_portable=get(Render_pass.attachment device depth_texture~usage:Ogpu.Render_pass.Render_target)in
    List.iter(fun(operation,expected)->
      let depth_face:Ogpu.Render_pass.stencil_face={face with depth_fail=operation;pass=Keep}in
      let state:Ogpu.Render_pass.stencil_state={front=depth_face;back=depth_face;front_reference=5l;back_reference=5l}
      and raster:Ogpu.Render_pass.raster_state={cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Never;depth_write=false}in
      let pass=get(Ogpu.Render_pass.create~raster_state:raster~stencil_state:state(Device.Private.handle device){colors=[|Some{texture=color_texture;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}|];depth=Some{texture=depth_portable;load=Clear;store=Store;clear=0.5};stencil=Some{stencil_attachment with load=Clear;clear=3};viewport={x=0;y=0;width=4;height=4};scissor={x=0;y=0;width=4;height=4}})in
      let encoded=get(Render_pass.create device pass~attachments:[target;stencil_texture;depth_texture]stencil_draw)in let receipt=get(Queue.submit_render_pass queue encoded)in get(Queue.wait_through queue receipt.epoch);
      let verify_face:Ogpu.Render_pass.stencil_face={face with compare=Equal;pass=Keep}in let verify_state:Ogpu.Render_pass.stencil_state={front=verify_face;back=verify_face;front_reference=Int32.of_int expected;back_reference=Int32.of_int expected}in execute~load:Load~clear:0~state:verify_state~color:(1.,0.,0.,1.);let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16)in if byte pixels 0 0 1<>255 then failwith"Command4 stencil depth-fail operation pixel mismatch")operations;
    get(Texture.destroy depth_texture);
    get(Texture.destroy stencil_texture));
  let limits=(Device.capabilities device).Ogpu.Capabilities.limits in
  let unsupported={descriptor with sample_count=2;vertex_entry="msaa_vertex"}in expect Ogpu.Error.Invalid_argument(Pipeline.create_render cache device unsupported);
  let msaa_resources=ref[]in
  List.iter(fun samples->if samples<=limits.max_sample_count then let pipeline=get(Pipeline.create_render cache device{descriptor with sample_count=samples;vertex_entry="msaa_vertex"})in let target_descriptor={texture_descriptor with label=Some(Printf.sprintf"msaa-%d"samples);sample_count=samples;usage=[Render_attachment]}in let target=get(Texture.create device~memory:(if samples=1 then Texture.Shared else Device_local)~format:Texture.Rgba8_unorm target_descriptor)in let resolve=if samples=1 then target else get(Texture.create device~memory:Texture.Shared~format:Texture.Rgba8_unorm{texture_descriptor with label=Some(Printf.sprintf"resolve-%d"samples)})in msaa_resources:=(target,resolve,pipeline)::!msaa_resources;let stable=ref None in List.iter(fun _frame->let pass=msaa_pass device target(if samples=1 then None else Some resolve)samples in let msaa_draw={Render_pass.pipeline;buffers=[];textures=[];samplers=[];primitive=Render_pass.Triangle_list;vertex_start=0;vertex_count=3;index=None}in let encoded=get(Render_pass.create device pass~attachments:(if samples=1 then[target]else[target;resolve])msaa_draw)in let receipt=get(Queue.submit_render_pass queue encoded)in get(Queue.wait_through queue receipt.epoch);let pixels=get(Texture.read_bytes device resolve~mip_level:0~bytes_per_row:16)in let now=Bytes.copy pixels in(match!stable with None->stable:=Some now|Some expected when expected=now->()|Some _->failwith"multisample resolve frame drift");if samples>1 then let partial=ref false in for y=0 to 3 do for x=0 to 3 do let green=byte pixels x y 1 in if green>0&&green<255 then partial:=true done done;if not!partial then failwith"multisample diagonal edge was not resolved";if samples=4&&(byte pixels 1 1 0<>128||byte pixels 1 1 1<>128)then failwith"four-sample diagonal resolve pixel changed") [1;2;60;600]) [1;4;9;16];
  let bad=portable_pass device target~clear:(1.,0.,0.,1.)in expect Ogpu.Error.Invalid_argument(Render_pass.create device bad~attachments:[](draw Triangle_list None));
  List.iter(fun(msaa,resolve,_)->get(Texture.destroy msaa);if resolve!=msaa then get(Texture.destroy resolve))!msaa_resources;
  let persistent_indexed=get(Render_pass.create device
    (portable_pass device target~clear:(1.,0.,0.,1.))~attachments:[target]
    (draw Triangle_strip(Some(Uint16,indices,0L,3L))))in
  Render_pass.Private.retain_encoding persistent_indexed;
  for _=1 to 2 do
    let receipt=get(Queue.submit_render_pass queue persistent_indexed)in
    get(Queue.wait_through queue receipt.epoch);
    verify(get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16))
  done;
  get(Render_pass.Private.destroy persistent_indexed);
  let depth_pipeline=get(Pipeline.create_render cache device
    {descriptor with label=Some"prepared-depth";depth_format=Depth32_float})in
  let depth_texture=get(Texture.create device~memory:Texture.Device_local
    ~format:Texture.Depth32_float
    {texture_descriptor with label=Some"prepared-depth";
      usage=[Render_attachment]})in
  let color_attachment=get(Render_pass.attachment device target
    ~usage:Ogpu.Render_pass.Render_target)
  and depth_attachment=get(Render_pass.attachment device depth_texture
    ~usage:Ogpu.Render_pass.Render_target)in
  let depth_pass=get(Ogpu.Render_pass.create(Device.Private.handle device)
    {colors=[|Some{Ogpu.Render_pass.texture=color_attachment;resolve=None;
       load=Clear;store=Store;clear=(1.,0.,0.,1.)}|];
     depth=Some{Ogpu.Render_pass.texture=depth_attachment;load=Clear;
       store=Store;clear=1.};stencil=None;
     viewport={x=0;y=0;width=4;height=4};
     scissor={x=2;y=0;width=2;height=4}})in
  let depth_draw={Render_pass.pipeline=depth_pipeline;buffers=[];textures=[];
    samplers=[];primitive=Triangle_strip;vertex_start=0;vertex_count=3;
    index=Some(Uint16,indices,0L,3L)}in
  let persistent_depth=get(Render_pass.create device depth_pass
    ~attachments:[target;depth_texture]depth_draw)in
  Render_pass.Private.retain_encoding persistent_depth;
  let depth_receipt=get(Queue.submit_render_pass queue persistent_depth)in
  expect Ogpu.Error.Invalid_state(Render_pass.Private.destroy persistent_depth);
  expect Ogpu.Error.Stale_handle
    (Queue.submit_render_pass queue persistent_depth);
  get(Queue.wait_through queue depth_receipt.epoch);
  get(Render_pass.Private.destroy persistent_depth);
  get(Render_pass.Private.destroy persistent_depth);
  verify(get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16));
  get(Texture.destroy depth_texture);
  let icb_pipeline=get(Pipeline.create_render_argument_buffer cache device
    {descriptor with label=Some"typed-pass-icb"})in
  let native_icb_pipeline=match Pipeline.Private.native icb_pipeline with
    |Pipeline.Private.Render pipeline->pipeline|Compute _->assert false in
  let icb_descriptor=Metal.Indirect_command_buffer.descriptor
    ~inherit_buffers:false~inherit_pipeline_state:false
    ~command_types:[Indirect_draw]()in
  let icb=get_metal(Metal.Indirect_command_buffer.create
    ~device:(Device.Private.metal device)~storage:Metal.Buffer.Shared
    ~max_command_count:1 icb_descriptor)in
  let icb_command=get_metal(Metal.Indirect_command_buffer.Render_command.at icb 0)in
  get_metal(Metal.Indirect_command_buffer.Render_command.set_pipeline
    icb_command native_icb_pipeline);
  get_metal(Metal.Indirect_command_buffer.Render_command.draw_primitives
    icb_command~primitive:Triangle~vertex_start:0~vertex_count:3());
  let dummy_texture=get(Texture.create device~memory:Texture.Shared
    ~format:Texture.Rgba8_unorm
    {texture_descriptor with label=Some"prepared-icb-resource";width=1;height=1;
      usage=[Texture_binding]})in
  let prepare resources=get_metal(Metal.Render_encoder.prepare_resources
    (Device.Private.metal device)resources)in
  let vertex_resources=prepare[Metal.Render_encoder.Buffer_resource
    (Buffer.Private.metal indices)]
  and fragment_resources=prepare[Metal.Render_encoder.Buffer_resource
    (Buffer.Private.metal indices)]
  and texture_resources=prepare[Metal.Render_encoder.Texture_resource
    (Texture.Private.metal dummy_texture)]in
  let indirect_draw={Render_pass.pipeline=icb_pipeline;buffers=[];textures=[];
    samplers=[];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in
  let indirect=get(Render_pass.create device
    (portable_pass device target~clear:(1.,0.,0.,1.))~attachments:[target]
    indirect_draw)|>fun pass->Render_pass.with_indirect pass icb
      ~vertex_resources~fragment_resources~texture_resources in
  Render_pass.Private.retain_encoding indirect;
  for _=1 to 2 do
    let receipt=get(Queue.submit_render_pass queue indirect)in
    get(Queue.wait_through queue receipt.epoch);
    verify(get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16))
  done;
  let replay_target=get(Texture.create device~memory:Texture.Shared
    ~format:Texture.Rgba8_unorm
    {texture_descriptor with label=Some"prepared-icb-replay"})in
  let replay_base=get(Render_pass.create_empty device
    (portable_pass device replay_target~clear:(1.,0.,0.,1.))
    ~attachments:[replay_target])in
  let replay=Render_pass.replay_indirect replay_base~template:indirect in
  for _=1 to 2 do
    let receipt=get(Queue.submit_render_pass queue replay)in
    get(Queue.wait_through queue receipt.epoch);
    verify(get(Texture.read_bytes device replay_target~mip_level:0
      ~bytes_per_row:16))
  done;
  get(Render_pass.Private.destroy replay);
  get(Render_pass.Private.destroy indirect);
  get_metal(Metal.Render_encoder.destroy_prepared_resources vertex_resources);
  get_metal(Metal.Render_encoder.destroy_prepared_resources fragment_resources);
  get_metal(Metal.Render_encoder.destroy_prepared_resources texture_resources);
  get_metal(Metal.Indirect_command_buffer.Render_command.destroy icb_command);
  get_metal(Metal.Indirect_command_buffer.destroy icb);
  get(Texture.destroy replay_target);
  get(Texture.destroy dummy_texture);
  let native_pipeline=match Pipeline.Private.native pipeline with
    |Pipeline.Private.Render pipeline->pipeline|Compute _->assert false in
  let native_indices=Buffer.Private.metal indices in
  let binding:Metal.Render_encoder.Private.prepared_indexed_binding=
    {prepared_stage=Vertex;prepared_index=0;prepared_offset=0L;
     prepared_buffer=native_indices}in
  let prepared_draw:Metal.Render_encoder.Private.prepared_indexed_draw=
    {Metal.Render_encoder.Private.prepared_pipeline=native_pipeline;
     prepared_bindings=[||];
     prepared_primitive=Triangle;prepared_index_type=Uint16;
     prepared_index_buffer=native_indices;prepared_index_offset=0L;
     prepared_index_count=3L}in
  expect_metal Metal.Invalid_argument
    (Metal.Render_encoder.Private.prepare_indexed_draws
       (Device.Private.metal device)
       [|{prepared_draw with prepared_bindings=[|binding;binding|]}|]);
  expect_metal Metal.Invalid_argument
    (Metal.Render_encoder.Private.prepare_indexed_draws
       (Device.Private.metal device)
       [|{prepared_draw with prepared_index_offset=2L}|]);
  let fragment_binding={binding with prepared_stage=Fragment;
    prepared_index=1}in
  let copied_bindings=[|binding;fragment_binding|]in
  let bound_draw={prepared_draw with prepared_bindings=copied_bindings}in
  let prepared=get_metal(Metal.Render_encoder.Private.prepare_indexed_draws
    (Device.Private.metal device)[|bound_draw;bound_draw|])in
  copied_bindings.(0)<-{binding with prepared_index=31};
  let stale_indices=get(Buffer.create device~memory:Buffer.Shared
    {label=Some"stale-indices";size=6L;usage=[Index;Copy_dst]})in
  get(Buffer.write_bytes device stale_indices~dst_offset:0L bytes);
  let stale_draw={prepared_draw with
    prepared_index_buffer=Buffer.Private.metal stale_indices}in
  let stale_batch=get_metal(Metal.Render_encoder.Private.prepare_indexed_draws
    (Device.Private.metal device)[|prepared_draw;stale_draw|])in
  let native_queue=get_metal(Metal.Command_queue.create(Device.Private.metal device))in
  let native_commands=get_metal(Metal.Command_buffer.create native_queue())in
  let native_encoder=get_metal(Metal.Render_encoder.create native_commands
    ~target:(Texture.Private.metal target)())in
  get(Buffer.destroy stale_indices);
  expect_metal Metal.Destroyed
    (Metal.Render_encoder.Private.execute_prepared_indexed_draws
       native_encoder stale_batch);
  get_metal(Metal.Render_encoder.Private.execute_prepared_indexed_draws
    native_encoder prepared);
  expect_metal Metal.Parent_has_dependents
    (Metal.Buffer.destroy native_indices);
  get_metal(Metal.Render_encoder.end_encoding native_encoder);
  get_metal(Metal.Command_buffer.commit native_commands);
  get_metal(Metal.Command_buffer.wait_until_completed native_commands);
  let prepared_pixels=get(Texture.read_bytes device target~mip_level:0
    ~bytes_per_row:16)in
  if byte prepared_pixels 0 0 0<>0||byte prepared_pixels 0 0 1<>255||
     byte prepared_pixels 0 0 3<>255 then
    failwith"prepared indexed draw pixel mismatch";
  get(Buffer.destroy indices);
  get_metal(Metal.Command_buffer.destroy native_commands);
  let unretained_commands,unretained_buffer=
    let native_indices=get_metal(Metal.Buffer.create_copy
      ~device:(Device.Private.metal device)~storage:Metal.Buffer.Shared bytes)in
    let weak=Weak.create 1 in
    Weak.set weak 0(Some native_indices);
    let draw={prepared_draw with prepared_index_buffer=native_indices}in
    let prepared=get_metal(Metal.Render_encoder.Private.prepare_indexed_draws
      (Device.Private.metal device)[|draw|])in
    let commands=get_metal(Metal.Command_buffer.create_with_descriptor
      native_queue~retained_references:false())in
    let encoder=get_metal(Metal.Render_encoder.create commands
      ~target:(Texture.Private.metal target)())in
    get_metal(Metal.Render_encoder.Private.execute_prepared_indexed_draws
      encoder prepared);
    get_metal(Metal.Render_encoder.end_encoding encoder);
    commands,weak in
  Gc.full_major();
  if Weak.get unretained_buffer 0=None then
    failwith"unretained prepared command dropped its resource roots";
  get_metal(Metal.Command_buffer.commit unretained_commands);
  expect_metal Metal.Invalid_state
    (Metal.Command_buffer.Private.release_committed_references
       unretained_commands);
  Gc.full_major();
  if Weak.get unretained_buffer 0=None then
    failwith"unretained committed command dropped its resource roots";
  get_metal(Metal.Command_buffer.wait_until_completed unretained_commands);
  (match Weak.get unretained_buffer 0 with
   |None->()|Some buffer->get_metal(Metal.Buffer.destroy buffer));
  get_metal(Metal.Command_buffer.destroy unretained_commands);
  get_metal(Metal.Command_queue.destroy native_queue);
  get(Texture.destroy target);Pipeline.clear_cache cache;get(Queue.destroy queue);get(Device.destroy device);ignore(get_metal(Metal.Release_queue.drain()));let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"render-pass live-handle delta";
  print_endline"ogpu_metal render pass: list/strip, MSAA resolve frames1/2/60/600, prepared indexed/ICB/depth teardown, atomicity/unretained roots, zero live-handle delta"
