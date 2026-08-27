open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V scene_vertex(uint i [[vertex_id]]) { constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}}; V v;v.position=float4(p[i],0.,1.);return v; }
fragment float4 scene_fragment(){return float4(1.,0.,0.5,1.);}
|}
let ()=match Device.system_default()with Error _->print_endline"scene execution Metal: skipped (no M1 device)"|Ok native_device->
  let before=metal(Metal.Release_queue.stats())in
  let layer=metal(Metal.Metal_layer.create(Device.Private.metal native_device)(Metal.Metal_layer.default~width:4~height:4))in
  let driver,control=Backend.create~device:native_device~layer()in
  let shader=get(Ogpu.Shader.create{backend="metal";label=Some"scene-execution-metal";bytes=Bytes.of_string source;entry_points=[{name="scene_vertex";stage=Vertex};{name="scene_fragment";stage=Fragment}];bindings=[]})in
  let cache=get(Pipeline.create_cache~capacity:6)in
  let configuration:Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Bgra8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create_with_pipeline_variants driver configuration(fun device blend->let empty=get(Ogpu.Binding.create_layout[])in let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)[0,empty])in let descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"scene-execution-metal";layout;vertex=shader;vertex_entry="scene_vertex";fragment=Some shader;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in let native=get(Pipeline.create_render_runtime_msl~blend cache native_device descriptor)in Backend.register_pipeline control native;Ok(Pipeline.Private.portable native)))in
  let indices=Bytes.make 12 '\000'in Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;let mesh:Scene_execution.mesh={key="fullscreen";vertices=Bytes.make 48 '\000';vertex_count=3;indices;index_count=3}and state:Scene_execution.state={viewport=(0,0,4,4);scissor=(0,0,4,4)}in
  ignore(get(Scene_execution.render renderer[{mesh;state};{mesh;state}]));let pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
  let r=Char.code(Bytes.get pixels 0)and g=Char.code(Bytes.get pixels 1)and b=Char.code(Bytes.get pixels 2)in if r<>255||g<>0||b<>128 then failwith(Printf.sprintf"scene execution Metal pixel mismatch %d,%d,%d"r g b);
  List.iter(fun(blend,expected)->List.iter(fun _frame->
    ignore(get(Scene_execution.render_blended renderer[blend,{mesh;state}]));
    let bytes=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
    let actual=Char.code(Bytes.get bytes 0),Char.code(Bytes.get bytes 1),Char.code(Bytes.get bytes 2)in
    if actual<>expected then failwith"scene execution Metal blend pixel") [1;2;60;600])
    [Ogpu.Pipeline.Replace,(255,0,128);Alpha,(255,0,128);Add,(255,0,128);
     Multiply,(0,0,0);Screen,(255,0,128);Subtract,(0,0,0)];
  get(Scene_execution.resize renderer{configuration with physical_width=8;physical_height=8});ignore(get(Scene_execution.render renderer[{mesh;state={viewport=(0,0,8,8);scissor=(0,0,8,8)}}]));
  metal(Metal.Metal_layer.destroy layer);get(Scene_execution.destroy renderer);ignore(metal(Metal.Release_queue.drain()));let after=metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"scene execution Metal live delta";print_endline"scene execution Metal: SDL-free draw/resize, exact pixel, zero delta"
