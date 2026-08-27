open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"wrong render-pass rejection"
let source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V pass_vertex(uint i [[vertex_id]]) {
  constexpr float2 p[4]={{-1.,-1.},{3.,-1.},{-1.,3.},{1.,1.}};
  V v; v.position=float4(p[i],0.,1.); return v;
}
fragment float4 pass_fragment() { return float4(0.,1.,0.,1.); }
|}
let shader ()=get(Ogpu.Shader.create{backend="metal";label=Some"render-pass";bytes=Bytes.of_string source;entry_points=[{name="pass_vertex";stage=Vertex};{name="pass_fragment";stage=Fragment}];bindings=[]})
let layout device=let group=get(Ogpu.Binding.create_layout[])in get(Ogpu.Binding.create_pipeline_layout~device:(Device.Private.handle device)~capabilities:(Device.capabilities device)[0,group])
let portable_pass device target ~clear =
  let texture=get(Render_pass.attachment device target~usage:Ogpu.Render_pass.Render_target)in
  let color : Ogpu.Render_pass.color={texture;resolve=None;load=Clear;store=Store;clear}in
  let descriptor : Ogpu.Render_pass.descriptor={colors=[|Some color|];depth=None;stencil=None;viewport={x=0;y=0;width=4;height=4};scissor={x=2;y=0;width=2;height=4}}in
  get(Ogpu.Render_pass.create(Device.Private.handle device)descriptor)
let byte pixels x y channel=Char.code(Bytes.get pixels(y*16+x*4+channel))
let verify pixels =for y=0 to 3 do for x=0 to 3 do let expected=if x<2 then(255,0)else(0,255)in if byte pixels x y 0<>fst expected||byte pixels x y 1<>snd expected||byte pixels x y 3<>255 then failwith"render-pass viewport/scissor pixel mismatch"done done
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal render pass: skipped (no device)"|Ok device->
  let before=get_metal(Metal.Release_queue.stats())in
  let cache=get(Pipeline.create_cache~capacity:2)in let shader=shader()in
  let descriptor : Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"typed-pass";layout=layout device;vertex=shader;vertex_entry="pass_vertex";fragment=Some shader;fragment_entry=Some"pass_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in
  let pipeline=get(Pipeline.create_render cache device descriptor)in
  let texture_descriptor : Ogpu.Types.texture_descriptor={label=Some"target";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}in
  let target=get(Texture.create device~memory:Texture.Shared~format:Texture.Rgba8_unorm texture_descriptor)in
  let queue=get(Queue.create device)in
  let draw primitive index={Render_pass.pipeline;buffers=[];textures=[];primitive;vertex_start=0;vertex_count=3;index}in
  let run primitive index=let pass=portable_pass device target~clear:(1.,0.,0.,1.)in let encoded=get(Render_pass.create device pass~attachments:[target](draw primitive index))in let receipt=get(Queue.submit_render_pass queue encoded)in get(Queue.wait_through queue receipt.epoch);verify(get(Texture.read_bytes device target~mip_level:0~bytes_per_row:16))in
  run Render_pass.Triangle_list None;
  let indices=get(Buffer.create device~memory:Buffer.Shared{label=Some"indices";size=6L;usage=[Index;Copy_dst]})in let bytes=Bytes.make 6 '\000'in Bytes.set_int16_le bytes 0 0;Bytes.set_int16_le bytes 2 1;Bytes.set_int16_le bytes 4 2;get(Buffer.write_bytes device indices~dst_offset:0L bytes);
  for _=1 to 3 do run Triangle_strip(Some(Uint16,indices,0L,3))done;
  let bad=portable_pass device target~clear:(1.,0.,0.,1.)in expect Ogpu.Error.Invalid_argument(Render_pass.create device bad~attachments:[](draw Triangle_list None));
  get(Buffer.destroy indices);get(Texture.destroy target);Pipeline.clear_cache cache;get(Queue.destroy queue);get(Device.destroy device);ignore(get_metal(Metal.Release_queue.drain()));let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"render-pass live-handle delta";
  print_endline"ogpu_metal render pass: list/strip, scissor, atomic rejection, zero live-handle delta"
