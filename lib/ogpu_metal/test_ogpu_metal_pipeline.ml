open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"wrong rejection"
let layout device entries=let group=get(Ogpu.Binding.create_layout entries)in get(Ogpu.Binding.create_pipeline_layout~device:(Device.Private.handle device)~capabilities:(Device.capabilities device)[0,group])
let shader~label~bytes~entries~bindings=get(Ogpu.Shader.create{backend="metal";label=Some label;bytes=Bytes.of_string bytes;entry_points=entries;bindings})
let compute_source={|#include <metal_stdlib>
using namespace metal;
kernel void mapped_compute(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] = values[i] * 2 + 3; }
|}
let render_source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V mapped_vertex(uint i [[vertex_id]]) { constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}}; V v; v.position=float4(p[i],0.,1.); return v; }
fragment float4 mapped_fragment() { return float4(0.125,0.5,0.875,1.); }
|}
let ended f=let command=Command.create()in get(f command);get(Command.end_ command);command
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal pipeline: skipped (no device)"|Ok device->
  let other=get(Device.system_default())in let before=get_metal(Metal.Release_queue.stats())in let cache=get(Pipeline.create_cache~capacity:2)in
  let compute_binding : Ogpu.Shader.binding={group=0;binding=0;kind=Storage_buffer;visibility=[Compute]}in
  let compute_shader=shader~label:"mapped-compute"~bytes:compute_source~entries:[{name="mapped_compute";stage=Compute}]~bindings:[compute_binding]in
  let compute_layout=layout device[{binding=0;kind=Ogpu.Binding.Buffer;visibility=[Ogpu.Binding.Compute]}]in
  let compute_descriptor : Ogpu.Pipeline.compute_descriptor={backend="metal";label=Some"mapped-compute";layout=compute_layout;shader=compute_shader;entry="mapped_compute"}in
  let compute=get(Pipeline.create_compute_runtime_msl cache device compute_descriptor)in if get(Pipeline.create_compute_runtime_msl cache device compute_descriptor)!=compute||Pipeline.cache_length cache<>1 then failwith"pipeline cache miss on canonical hit";
  expect Ogpu.Error.Cross_device(Pipeline.validate other compute);
  let buffer_descriptor : Ogpu.Types.buffer_descriptor={label=None;size=16L;usage=[Storage;Copy_src;Copy_dst]}in let buffer=get(Buffer.create device~memory:Buffer.Shared buffer_descriptor)in
  let input=Bytes.make 16 '\000'in for i=0 to 3 do Bytes.set_int32_le input(i*4)(Int32.of_int i)done;get(Buffer.write_bytes device buffer~dst_offset:0L input);
  let queue=get(Queue.create device)in let command=ended(fun c->Command.dispatch c~pipeline:compute~buffer~threads:4)in let receipt=get(Queue.submit queue command)in get(Queue.wait_through queue receipt.epoch);
  let output=get(Buffer.read_bytes device buffer~offset:0L~length:16)in for i=0 to 3 do if Bytes.get_int32_le output(i*4)<>Int32.of_int(i*2+3)then failwith"mapped compute output mismatch"done;
  let render_shader=shader~label:"mapped-render"~bytes:render_source~entries:[{name="mapped_vertex";stage=Vertex};{name="mapped_fragment";stage=Fragment}]~bindings:[]in
  let render_layout=layout device[]in let render_descriptor : Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"mapped-render";layout=render_layout;vertex=render_shader;vertex_entry="mapped_vertex";fragment=Some render_shader;fragment_entry=Some"mapped_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in
  let render=get(Pipeline.create_render_runtime_msl cache device render_descriptor)in
  let target_descriptor : Ogpu.Types.texture_descriptor={label=None;width=2;height=2;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}in let target=get(Texture.create device~memory:Texture.Shared~format:Texture.Rgba8_unorm target_descriptor)in
  let draw=ended(fun c->Command.draw_triangle c~pipeline:render~target)in let drawn=get(Queue.submit queue draw)in get(Queue.wait_through queue drawn.epoch);
  let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:8)in if Char.code(Bytes.get pixels 0)<>32||Char.code(Bytes.get pixels 1)<>128||Char.code(Bytes.get pixels 2)<>223||Char.code(Bytes.get pixels 3)<>255 then failwith"mapped render output mismatch";
  let blend_cache=get(Pipeline.create_cache~capacity:6)in
  let expected=[
    Ogpu.Pipeline.Replace,(Metal.Render_pipeline.Blend_disabled,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_zero,Metal.Render_pipeline.Blend_add);
    Alpha,(Metal.Render_pipeline.Blend_enabled,Metal.Render_pipeline.Blend_source_alpha,Metal.Render_pipeline.Blend_one_minus_source_alpha,Metal.Render_pipeline.Blend_add);
    Add,(Metal.Render_pipeline.Blend_enabled,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_add);
    Multiply,(Metal.Render_pipeline.Blend_enabled,Metal.Render_pipeline.Blend_destination_color,Metal.Render_pipeline.Blend_zero,Metal.Render_pipeline.Blend_add);
    Screen,(Metal.Render_pipeline.Blend_enabled,Metal.Render_pipeline.Blend_one_minus_destination_color,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_add);
    Subtract,(Metal.Render_pipeline.Blend_enabled,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_one,Metal.Render_pipeline.Blend_reverse_subtract)]in
  List.iter(fun(blend,(enabled,source,destination,operation))->
    let value=get(Pipeline.create_render_runtime_msl~blend blend_cache device render_descriptor)in
    match Pipeline.Private.native value with
    | Pipeline.Private.Render native->begin match Metal.Render_pipeline.color_attachments native with
      | [{blending;source_rgb;destination_rgb;rgb_operation;_}]
        when blending=enabled&&source_rgb=source&&destination_rgb=destination&&rgb_operation=operation->()
      | _->failwith"native render blend attachment mismatch"end
    | Pipeline.Private.Compute _->failwith"render blend compiled as compute")expected;
  if Pipeline.cache_length blend_cache<>6 then failwith"blend pipeline cache-key collision";
  Pipeline.clear_cache blend_cache;
  let mismatch_shader=shader~label:"mismatch"~bytes:compute_source~entries:[{name="mapped_compute";stage=Compute}]~bindings:[{compute_binding with kind=Sampled_texture}]in let mismatch_layout=layout device[{binding=0;kind=Ogpu.Binding.Texture;visibility=[Ogpu.Binding.Compute]}]in
  expect Ogpu.Error.Invalid_argument(Pipeline.create_compute cache device{compute_descriptor with label=Some"mismatch";layout=mismatch_layout;shader=mismatch_shader});
  let invalid_shader=shader~label:"invalid-msl"~bytes:"this is not Metal"~entries:[{name="bad";stage=Compute}]~bindings:[]in let empty_layout=layout device[]in expect Ogpu.Error.Device_lost(Pipeline.create_compute cache device{compute_descriptor with label=Some"invalid";layout=empty_layout;shader=invalid_shader;entry="bad"});
  let alternate_shader=shader~label:"alternate"~bytes:(compute_source^"\n")~entries:[{name="mapped_compute";stage=Compute}]~bindings:[compute_binding]in let alternate=get(Pipeline.create_compute cache device{compute_descriptor with label=Some"alternate";shader=alternate_shader})in
  if Pipeline.cache_length cache<>2||not(Pipeline.destroyed compute)then failwith"bounded cache eviction failed";expect Ogpu.Error.Stale_handle(Pipeline.validate device compute);
  Pipeline.clear_cache cache;if not(Pipeline.destroyed render&&Pipeline.destroyed alternate)then failwith"cache clear did not destroy pipelines";
  get(Texture.destroy target);get(Buffer.destroy buffer);get(Queue.destroy queue);get(Device.destroy device);get(Device.destroy other);ignore(get_metal(Metal.Release_queue.drain()));let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-2 then failwith"pipeline live-handle delta";
  print_endline"ogpu_metal pipeline: reflected compute/render, bounded cache, zero live-handle delta"
