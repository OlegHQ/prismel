open Ogpu_metal

let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let metal=function Ok value->value|Error error->failwith(Format.asprintf"%a"Metal.pp_error error)

let source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V sample_vertex(uint i [[vertex_id]]) {
  constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}};
  V v; v.position=float4(p[i],0.,1.); return v;
}
fragment float4 sample_clamp(texture2d<float> t [[texture(0)]], sampler s [[sampler(1)]]) { return t.sample(s,float2(-0.25,0.25)); }
fragment float4 sample_repeat(texture2d<float> t [[texture(0)]], sampler s [[sampler(1)]]) { return t.sample(s,float2(-0.25,0.25)); }
fragment float4 sample_mirror(texture2d<float> t [[texture(0)]], sampler s [[sampler(1)]]) { return t.sample(s,float2(1.75,0.25)); }
fragment float4 sample_linear(texture2d<float> t [[texture(0)]], sampler s [[sampler(1)]]) { return t.sample(s,float2(0.5,0.5)); }
fragment float4 sample_mip(texture2d<float> t [[texture(0)]], sampler s [[sampler(1)]]) { return t.sample(s,float2(0.5),level(1.0)); }
|}

let shader entries bindings=get(Ogpu.Shader.create{backend="metal";label=Some"sampler-pixels";bytes=Bytes.of_string source;entry_points=entries;bindings})
let rgba bytes=Char.code(Bytes.get bytes 0),Char.code(Bytes.get bytes 1),Char.code(Bytes.get bytes 2),Char.code(Bytes.get bytes 3)
let close expected actual=List.for_all2(fun a b->abs(a-b)<=1)expected actual

let ()=match Device.system_default()with Error _->print_endline"ogpu_metal sampler pixels: skipped (no device)"|Ok native_device->
  let before=metal(Metal.Release_queue.stats())in
  let driver,control=Backend.create~device:native_device()in
  let device=get(Ogpu.Backend.create_device driver)and cache=get(Pipeline.create_cache~capacity:8)in
  let vertex=shader[{name="sample_vertex";stage=Ogpu.Shader.Vertex}][]and fragment name=shader[{name;stage=Ogpu.Shader.Fragment}][{group=0;binding=0;kind=Sampled_texture;visibility=[Fragment]};{group=0;binding=1;kind=Sampler;visibility=[Fragment]}]in
  let texture_layout=get(Ogpu.Binding.create_layout[{binding=0;kind=Ogpu.Binding.Texture;visibility=[Ogpu.Binding.Fragment]};{binding=1;kind=Ogpu.Binding.Sampler;visibility=[Ogpu.Binding.Fragment]}])in
  let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)[0,texture_layout])in
  let make_pipeline entry=let fragment=fragment entry in let descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some entry;layout;vertex;vertex_entry="sample_vertex";fragment=Some fragment;fragment_entry=Some entry;color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in let native=get(Pipeline.create_render_runtime_msl cache native_device descriptor)in Backend.register_pipeline control native;native,get(Ogpu.Backend.adopt_pipeline device(Pipeline.Private.portable native))in
  let pipelines=List.map make_pipeline["sample_clamp";"sample_repeat";"sample_mirror";"sample_linear";"sample_mip"]in
  let sampled_descriptor:Ogpu.Types.texture_descriptor={label=Some"sampled";width=2;height=2;depth=1;mip_levels=2;sample_count=1;usage=[Texture_binding;Texture_copy_dst]}and target_descriptor:Ogpu.Types.texture_descriptor={label=Some"target";width=1;height=1;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}in
  let sampled=get(Ogpu.Backend.create_texture device sampled_descriptor)and target=get(Ogpu.Backend.create_texture device target_descriptor)and upload=get(Ogpu.Backend.create_buffer device{label=None;size=768L;usage=[Copy_src;Copy_dst]})and queue=get(Ogpu.Backend.create_queue device)in
  let bytes=Bytes.make 768 '\000'in Bytes.blit(Bytes.of_string"\xff\x00\x00\xff\x00\xff\x00\xff")0 bytes 0 8;Bytes.blit(Bytes.of_string"\x00\x00\xff\xff\xff\xff\xff\xff")0 bytes 256 8;Bytes.blit(Bytes.of_string"\xff\xff\x00\xff")0 bytes 512 4;get(Ogpu.Backend.write_buffer upload~offset:0L bytes);
  let transfer=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)and zero:Ogpu.Transfer_pass.origin={x=0;y=0;z=0}in
  get(Ogpu.Transfer_pass.buffer_to_texture transfer~src:(Ogpu.Backend.transfer_buffer upload)~offset:0L~bytes_per_row:256L~bytes_per_image:512L~dst:(Ogpu.Backend.transfer_texture sampled)~mip:0~origin:zero~extent:{width=2;height=2;depth=1});
  get(Ogpu.Transfer_pass.buffer_to_texture transfer~src:(Ogpu.Backend.transfer_buffer upload)~offset:512L~bytes_per_row:256L~bytes_per_image:256L~dst:(Ogpu.Backend.transfer_texture sampled)~mip:1~origin:zero~extent:{width=1;height=1;depth=1});
  let receipt=get(Ogpu.Backend.submit queue(get(Ogpu.Backend.transfer transfer))~resources:[`Buffer upload;`Texture sampled]~pipelines:[])in get(Ogpu.Backend.complete_through queue receipt.epoch);
  let attachment=Ogpu.Backend.render_texture target~format:Ogpu.Render_pass.Rgba8~usage:Render_target in let pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device){colors=[|Some{texture=attachment;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}|];depth=None;stencil=None;viewport={x=0;y=0;width=1;height=1};scissor={x=0;y=0;width=1;height=1}})in
  let base:Ogpu.Types.sampler_descriptor={label=None;min_filter=Ogpu.Types.Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=2.;max_anisotropy=1}in
  let cases=["sample_clamp",[255;0;0;255],base;"sample_repeat",[0;255;0;255],{base with address_u=Repeat};"sample_mirror",[255;0;0;255],{base with address_u=Mirror_repeat};"sample_linear",[128;128;128;255],{base with min_filter=Linear;mag_filter=Linear};"sample_mip",[255;255;0;255],{base with mip_filter=Nearest_mip;lod_min=1.}]in
  let sampled_id=(Ogpu.Backend.render_texture sampled~format:Ogpu.Render_pass.Rgba8~usage:Render_target).id in
  let bad_native,bad_pipeline=List.hd pipelines in let missing:Ogpu.Render_pass.draw={pipeline_key=Pipeline.key bad_native;buffers=[];textures=[{stage=Ogpu.Command.Fragment;index=0;texture_id=sampled_id}];samplers=[];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in let unchanged=get(Ogpu.Backend.read_texture target~bytes_per_row:4)in(match Ogpu.Backend.render pass[missing]with Error error when error.Ogpu.Error.kind=Invalid_argument->()|_->failwith"missing sampler was accepted");if get(Ogpu.Backend.read_texture target~bytes_per_row:4)<>unchanged then failwith"missing sampler mutated target";ignore bad_pipeline;
  List.iter(fun(entry,expected,sampler)->let native,pipeline=List.find(fun(native,_)->Pipeline.label native=Some entry)pipelines in let draw:Ogpu.Render_pass.draw={pipeline_key=Pipeline.key native;buffers=[];textures=[{stage=Ogpu.Command.Fragment;index=0;texture_id=sampled_id}];samplers=[{stage=Ogpu.Command.Fragment;index=1;sampler}];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in let command=get(Ogpu.Backend.render pass[draw])in let receipt=get(Ogpu.Backend.submit queue command~resources:[`Texture target;`Texture sampled]~pipelines:[pipeline])in get(Ogpu.Backend.complete_through queue receipt.epoch);let r,g,b,a=rgba(get(Ogpu.Backend.read_texture target~bytes_per_row:4))in if not(close expected[r;g;b;a])then failwith(Printf.sprintf"%s pixel mismatch: %d,%d,%d,%d"entry r g b a))cases;
  get(Ogpu.Backend.destroy_queue queue);get(Ogpu.Backend.destroy_buffer upload);get(Ogpu.Backend.destroy_texture sampled);get(Ogpu.Backend.destroy_texture target);List.iter(fun(_,pipeline)->get(Ogpu.Backend.destroy_pipeline pipeline))pipelines;get(Ogpu.Backend.destroy_device device);ignore(metal(Metal.Release_queue.drain()));let after=metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"sampler pixel live-handle delta";print_endline"ogpu_metal sampler pixels: nearest/linear clamp/repeat/mirror/mip exact, zero delta"
