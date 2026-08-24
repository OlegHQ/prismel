open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let source={|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
using M = mesh<V, void, 3, 1, topology::triangle>;
[[mesh]] void mesh_tile105_mesh(M out, uint tid [[thread_index_in_threadgroup]]) {
  constexpr float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
  if (tid < 3) { V v; v.position=float4(p[tid],0,1); out.set_vertex(tid,v); out.set_index(tid,tid); }
  if (tid == 0) out.set_primitive_count(1);
}
kernel void mesh_tile105_tile(ushort2 p [[thread_position_in_threadgroup]]) { (void)p; }
|}
let ()=
  let open Render_pipeline.Mesh_tile in
  let buffer=get(buffer_descriptor ~mutability:Mutable())in
  if buffer_mutability buffer<>Mutable then fail "buffer mutability drift";
  get(set_buffer_mutability buffer Immutable);
  if buffer_mutability buffer<>Immutable then fail "buffer mutability setter drift";
  let color=get(create_color_attachment Texture.Bgra8_unorm)in
  if color_attachment_format color<>Texture.Bgra8_unorm then fail "color format drift";
  get(destroy_color color);get(destroy_buffer buffer);
  match Device.system_default() with
  | Error _->print_endline "metal mesh/tile safe: skipped (no device)"
  | Ok device->
      let library=get(Library.compile_source~device source)in
      let mesh=get(Function.find~library "mesh_tile105_mesh")in
      let tile=get(Function.find~library "mesh_tile105_tile")in
      let one={width=1L;height=1L;depth=1L}in
      let zero={width=0L;height=0L;depth=0L}in
      let three={width=3L;height=1L;depth=1L}in
      let mesh_descriptor=get(mesh_descriptor~mesh_function:mesh
        ~depth_format:Texture.Depth32_float~stencil_format:Texture.Stencil8
        ~required_mesh_threads:three~required_object_threads:zero())in
      let tile_descriptor=get(tile_descriptor~tile_function:tile
        ~required_threads:one())in
      (match compile_mesh~reflection:true mesh_descriptor with
       | Error {kind=Unsupported;_}->()
       | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
       | Ok pipeline->
           if Render_pipeline.kind pipeline<>Render_pipeline.Mesh then fail "mesh pipeline kind drift";
           let mesh_threads=get(Render_pipeline.mesh_threads_per_threadgroup pipeline)in
           if mesh_threads.width<>3L||mesh_threads.height<>1L||mesh_threads.depth<>1L then
             fail "mesh required threadgroup size drift";
           let object_threads=get(Render_pipeline.object_threads_per_threadgroup pipeline)in
           if object_threads.width<>0L||object_threads.height<>0L||object_threads.depth<>0L then
             fail "nil-object required threadgroup size drift";
           get(Render_pipeline.destroy pipeline));
      (match compile_tile~reflection:true tile_descriptor with
       | Error {kind=Unsupported;_}->()
       | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
       | Ok pipeline->
           if Render_pipeline.kind pipeline<>Render_pipeline.Tile then fail "tile pipeline kind drift";
           get(Render_pipeline.destroy pipeline));
      get(destroy_mesh mesh_descriptor);get(destroy_tile tile_descriptor);
      get(Function.destroy mesh);get(Function.destroy tile);
      get(Library.destroy library);get(Device.destroy device);
      print_endline "metal mesh/tile safe: ok"
