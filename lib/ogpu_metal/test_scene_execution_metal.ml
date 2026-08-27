open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let source={|#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V scene_vertex(uint i [[vertex_id]]) { constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}}; V v;v.position=float4(p[i],0.,1.);return v; }
fragment float4 scene_fragment(){return float4(1.,0.,0.5,1.);}
|}
let source3={|#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]]; };
inline float scene_double(const device uchar *p){uint lo=*reinterpret_cast<const device uint*>(p);uint hi=*reinterpret_cast<const device uint*>(p+4);ulong bits=(ulong(hi)<<32)|ulong(lo);float sign=(hi>>31)==0?1.:-1.;int exponent=int((bits>>52)&0x7fful);ulong fraction=bits&0xffffffffffffful;if(exponent==0)return sign*ldexp(float(fraction)/4503599627370496.,-1022);return sign*ldexp(1.+float(fraction)/4503599627370496.,exponent-1023);}
vertex Out scene_vertex(uint i [[vertex_id]],const device uchar *input [[buffer(0)]]){const device uchar*p=input+i*68;Out v;v.position=float4(scene_double(p),scene_double(p+8),scene_double(p+16),1.);return v;}
fragment float4 scene_fragment(){return float4(1.,0.,0.5,1.);}
|}
let source3_textured={|#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]]; float2 uv; };
inline float scene_double(const device uchar *p){uint lo=*reinterpret_cast<const device uint*>(p);uint hi=*reinterpret_cast<const device uint*>(p+4);ulong bits=(ulong(hi)<<32)|ulong(lo);float sign=(hi>>31)==0?1.:-1.;int exponent=int((bits>>52)&0x7fful);ulong fraction=bits&0xffffffffffffful;if(exponent==0)return sign*ldexp(float(fraction)/4503599627370496.,-1022);return sign*ldexp(1.+float(fraction)/4503599627370496.,exponent-1023);}
vertex Out scene_vertex(uint i [[vertex_id]],const device uchar *input [[buffer(0)]]){const device uchar*p=input+i*68;Out v;v.position=float4(scene_double(p),scene_double(p+8),scene_double(p+16),1.);v.uv=float2(scene_double(p+52),scene_double(p+60));return v;}
fragment float4 scene_fragment(Out value [[stage_in]],texture2d<float> image [[texture(0)]],sampler sampling [[sampler(0)]]){return image.sample(sampling,value.uv);}
|}
let ()=match Device.system_default()with Error _->print_endline"scene execution Metal: skipped (no M1 device)"|Ok native_device->
  let before=metal(Metal.Release_queue.stats())in
  let layer=metal(Metal.Metal_layer.create(Device.Private.metal native_device)(Metal.Metal_layer.default~width:4~height:4))in
  let driver,control=Backend.create~device:native_device~layer()in
  let cache=get(Pipeline.create_cache~capacity:18)in
  let configuration:Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Bgra8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create_with_pipeline_variants driver configuration(fun device family blend->let bytes,vertex_bindings,fragment_bindings,groups=match family with
    |Scene_execution.Scene2->source,[],[],[]
    |Scene3->source3,[{Ogpu.Shader.group=0;binding=0;kind=Storage_buffer;visibility=[Vertex]}],[],[0,[{Ogpu.Binding.binding=0;kind=Buffer;visibility=[Vertex]}]]
    |Scene3_textured->source3_textured,[{Ogpu.Shader.group=0;binding=0;kind=Storage_buffer;visibility=[Vertex]}],[{Ogpu.Shader.group=1;binding=0;kind=Sampled_texture;visibility=[Fragment]};{group=1;binding=1;kind=Sampler;visibility=[Fragment]}],[0,[{Ogpu.Binding.binding=0;kind=Buffer;visibility=[Vertex]}];1,[{Ogpu.Binding.binding=0;kind=Texture;visibility=[Fragment]};{binding=1;kind=Sampler;visibility=[Fragment]}]]in
    let vertex=get(Ogpu.Shader.create{backend="metal";label=Some"scene-execution-metal-vertex";bytes=Bytes.of_string bytes;entry_points=[{name="scene_vertex";stage=Vertex}];bindings=vertex_bindings})and fragment=get(Ogpu.Shader.create{backend="metal";label=Some"scene-execution-metal-fragment";bytes=Bytes.of_string bytes;entry_points=[{name="scene_fragment";stage=Fragment}];bindings=fragment_bindings})in
    let layouts=List.map(fun(group,entries)->group,get(Ogpu.Binding.create_layout entries))groups in let layout=get(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities:(Ogpu.Backend.capabilities device)layouts)in let descriptor:Ogpu.Pipeline.render_descriptor={backend="metal";label=Some"scene-execution-metal";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1}in let native=get(Pipeline.create_render_runtime_msl~blend cache native_device descriptor)in Backend.register_pipeline control native;Ok(Pipeline.Private.portable native)))in
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
  let vertices3=Bytes.make(68*3)'\000'in
  List.iteri(fun index(x,y)->let offset=index*68 in Bytes.set_int64_le vertices3 offset(Int64.bits_of_float x);Bytes.set_int64_le vertices3(offset+8)(Int64.bits_of_float y);Bytes.set_int64_le vertices3(offset+16)(Int64.bits_of_float 0.))[-1.,-1.;3.,-1.;-1.,3.];
  let mesh3:Scene_execution.mesh={key="fullscreen-scene3-double68";vertices=vertices3;vertex_count=3;indices;index_count=3}in
  List.iter(fun _frame->ignore(get(Scene_execution.render_family renderer[Scene_execution.Scene3,Ogpu.Pipeline.Replace,{mesh=mesh3;state}]));let bytes=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in if Char.code(Bytes.get bytes 0)<>255||Char.code(Bytes.get bytes 2)<>128 then failwith"scene execution Metal Scene3 double68 pixel")[1;2;60;600];
  let mesh_uv u v=let bytes=Bytes.copy vertices3 in for index=0 to 2 do let offset=index*68 in Bytes.set_int64_le bytes(offset+52)(Int64.bits_of_float u);Bytes.set_int64_le bytes(offset+60)(Int64.bits_of_float v)done;{mesh3 with Scene_execution.key=Printf.sprintf"textured-%g-%g"u v;vertices=bytes}in
  let levels=[|{Scene_execution.width=2;height=2;bytes=Bytes.of_string"\255\000\000\255\000\255\000\255\000\000\255\255\255\255\255\255"};{width=1;height=1;bytes=Bytes.of_string"\255\255\000\255"}|]in
  let sampler ?(min_filter=Ogpu.Types.Nearest)?(mag_filter=Ogpu.Types.Nearest)?(mip_filter=Ogpu.Types.No_mip)?(address_u=Ogpu.Types.Clamp_to_edge)?(address_v=Ogpu.Types.Clamp_to_edge)?(lod_min=0.)?(lod_max=1.)() : Ogpu.Types.sampler_descriptor={label=Some"scene-texture-test";min_filter;mag_filter;mip_filter;address_u;address_v;lod_min;lod_max;max_anisotropy=1}in
  let cases=[mesh_uv 0.1 0.1,sampler(),(255,0,0);mesh_uv 0.5 0.5,sampler~min_filter:Linear~mag_filter:Linear(),(128,128,128);mesh_uv 1.1 0.1,sampler~address_u:Repeat(),(255,0,0);mesh_uv 1.9 0.1,sampler~address_u:Mirror_repeat(),(255,0,0);mesh_uv 0.1 0.1,sampler~mip_filter:Nearest_mip~lod_min:1.~lod_max:1.(),(255,255,0)]in
  List.iteri(fun index(mesh,sampler,expected)->let texture:Scene_execution.sampled_texture={key="native-mip-chain";levels;sampler}and stable=ref None in List.iter(fun _frame->ignore(get(Scene_execution.render_textured renderer[Scene_execution.Scene3_textured,Ogpu.Pipeline.Replace,Some texture,{mesh;state}]));let bytes=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in let actual=Char.code(Bytes.get bytes 0),Char.code(Bytes.get bytes 1),Char.code(Bytes.get bytes 2)in begin if actual<>expected then let r,g,b=actual in failwith(Printf.sprintf"scene execution Metal texture case %d: %d,%d,%d"index r g b)end;let uploaded=Scene_execution.upload_bytes renderer in match !stable with None->stable:=Some uploaded|Some value when value=uploaded->()|Some _->failwith"stable native mip chain reuploaded")[1;2;60;600])cases;
  let replacement=[|{Scene_execution.width=2;height=2;bytes=Bytes.make 16 '\255'};{width=1;height=1;bytes=Bytes.of_string"\000\000\255\255"}|]in let replaced:Scene_execution.sampled_texture={key="native-mip-chain";levels=replacement;sampler=sampler()}in let before_reload=Scene_execution.upload_bytes renderer in ignore(get(Scene_execution.render_textured renderer[Scene_execution.Scene3_textured,Ogpu.Pipeline.Replace,Some replaced,{mesh=mesh_uv 0.1 0.1;state}]));if Scene_execution.upload_bytes renderer<=before_reload then failwith"texture generation replacement was not uploaded";
  let malformed={replaced with Scene_execution.key="malformed";levels=[|{Scene_execution.width=2;height=2;bytes=Bytes.make 15 '\000'}|]}and before_reject=Scene_execution.upload_bytes renderer in begin match Scene_execution.render_textured renderer[Scene_execution.Scene3_textured,Ogpu.Pipeline.Replace,Some malformed,{mesh=mesh_uv 0.1 0.1;state}]with Error _ when Scene_execution.upload_bytes renderer=before_reject->()|_->failwith"malformed texture was not rejected atomically"end;
  get(Scene_execution.resize renderer{configuration with physical_width=8;physical_height=8});ignore(get(Scene_execution.render renderer[{mesh;state={viewport=(0,0,8,8);scissor=(0,0,8,8)}}]));
  metal(Metal.Metal_layer.destroy layer);get(Scene_execution.destroy renderer);ignore(metal(Metal.Release_queue.drain()));let after=metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"scene execution Metal live delta";print_endline"scene execution Metal: SDL-free draw/resize, exact pixel, zero delta"
