open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let source={|#include <metal_stdlib>
using namespace metal;
struct O{float4 position[[position]];};
struct A{texture2d<float,access::sample> image[[id(0)]];sampler sampling[[id(1)]];};
vertex O scene_vertex(uint i[[vertex_id]]){O o;o.position=float4(float(i==1),float(i==2),0.,1.);return o;}
fragment float4 scene_fragment(O o[[stage_in]],constant A&args[[buffer(1)]]){return args.image.sample(args.sampling,float2(.5));}
|}
let ()=match Device.system_default()with Error _->print_endline"pipeline argument buffer: skipped (no device)"|Ok device->
  let before=metal(Metal.Release_queue.stats())in
  let cache=get(Pipeline.create_cache~capacity:2)in
  let artifact bindings=get(Ogpu.Shader.create{backend="metal";label=Some"argument-pipeline";bytes=Bytes.of_string source;entry_points=[{name="scene_vertex";stage=Vertex};{name="scene_fragment";stage=Fragment}];bindings})in
  let vertex=artifact[]and fragment=artifact[{group=0;binding=1;kind=Storage_buffer;visibility=[Fragment]}]in
  let layout_entry=get(Ogpu.Binding.create_layout[{binding=1;kind=Buffer;visibility=[Fragment]}])in
  let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Device.Private.handle device)~capabilities:(Device.capabilities device)[0,layout_entry])in
  let descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"argument-pipeline";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in
  let rejected={descriptor with fragment_entry=None}in let native_before=metal(Metal.Release_queue.stats())and cache_before=Pipeline.cache_length cache in(match Pipeline.create_render_argument_buffer cache device rejected with Error e when e.Ogpu.Error.kind=Invalid_argument->()|_->failwith"missing fragment entry accepted");let native_after=metal(Metal.Release_queue.stats())in if Pipeline.cache_length cache<>cache_before||native_after.live_handles<>native_before.live_handles||native_after.total_created<>native_before.total_created then failwith"invalid argument pipeline allocated or cached";
  let direct=get(Pipeline.create_render_runtime_msl cache device descriptor)in
  let pipeline=get(Pipeline.create_render_argument_buffer cache device descriptor)in
  if Pipeline.key direct=Pipeline.key pipeline||Pipeline.cache_length cache<>2 then failwith"direct/argument pipeline cache collision";
  (match Pipeline.Private.native pipeline with Render native when metal(Metal.Render_pipeline.supports_indirect_command_buffers native)->()|_->failwith"argument pipeline lacks indirect support");
  let encoder=get(Pipeline.Private.argument_encoder pipeline~buffer_index:1L)in
  if Metal.Shader_argument_encoder.encoded_length encoder<=0L then failwith"empty argument encoder";
  (match Pipeline.Private.argument_encoder pipeline~buffer_index:(-1L)with Error e when e.Ogpu.Error.kind=Invalid_argument->()|_->failwith"negative argument index accepted");
  metal(Metal.Shader_argument_encoder.destroy encoder);get(Pipeline.destroy pipeline);get(Pipeline.destroy direct);Pipeline.clear_cache cache;get(Device.destroy device);ignore(metal(Metal.Release_queue.drain()));let after=metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"argument pipeline handle delta"else();
  print_endline"pipeline argument buffer: retained fragment/reflection/lifetime"
