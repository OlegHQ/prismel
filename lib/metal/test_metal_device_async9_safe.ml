open Metal
let fail error=failwith(Format.asprintf"%a"pp_error error)
let get=function Ok x->x|Error e->fail e
let source={|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V async9_vertex(uint id [[vertex_id]]) {
  float2 p[3]={float2(-1),float2(3,-1),float2(-1,3)};
  return {float4(p[id],0,1)};
}
kernel void async9_kernel(device uint *out [[buffer(0)]]) { out[0]=9; }
using M = mesh<V, void, 3, 1, topology::triangle>;
[[mesh]] void async9_mesh(M out, uint tid [[thread_index_in_threadgroup]]) {
  if(tid<3){V v;v.position=float4(0,0,0,1);out.set_vertex(tid,v);out.set_index(tid,tid);}
  if(tid==0)out.set_primitive_count(1);
}
kernel void async9_tile(ushort2 p [[thread_position_in_threadgroup]]) {(void)p;}
|}
let ()=match Device.system_default()with
|Error _->print_endline"metal device async9: skipped (no device)"
|Ok device->
  let library=get(Device_async.library_source device source)in
  let kernel=get(Function.find~library "async9_kernel")in
  let vertex=get(Function.find~library "async9_vertex")in
  let p0=get(Device_async.compute_function device kernel)in
  let p1=get(Device_async.compute_function~variant:Device_async.With_options device kernel)in
  let cd=get(Pipeline_descriptor.Compute.create kernel)in
  let p2=get(Device_async.compute_descriptor cd)in
  let rd=get(Pipeline_descriptor.Render.create vertex)in
  let r0=get(Device_async.render_descriptor rd)in
  let r1=get(Device_async.render_descriptor~variant:Device_async.With_options rd)in
  let stitched=get(Stitched_library_descriptor.create~functions:[]~graphs:[]())in
  (match Device_async.stitched_library device stitched with
   |Ok library->get(Library.destroy library)
   |Error {kind=(Unsupported|Native_error);_}->()
   |Error error->fail error);
  let mesh=get(Function.find~library "async9_mesh")in
  let tile=get(Function.find~library "async9_tile")in
  let open Render_pipeline.Mesh_tile in
  let mesh_d=get(mesh_descriptor~mesh_function:mesh
    ~depth_format:Texture.Depth32_float~stencil_format:Texture.Stencil8
    ~required_mesh_threads:{width=3L;height=1L;depth=1L}
    ~required_object_threads:{width=0L;height=0L;depth=0L}())in
  let tile_d=get(tile_descriptor~tile_function:tile
    ~required_threads:{width=1L;height=1L;depth=1L}())in
  (match Device_async.mesh mesh_d with Ok p->get(Render_pipeline.destroy p)
   |Error {kind=Unsupported;_}->()|Error error->fail error);
  (match Device_async.tile tile_d with Ok p->get(Render_pipeline.destroy p)
   |Error {kind=Unsupported;_}->()|Error error->fail error);
  List.iter(fun p->get(Compute_pipeline.destroy p))[p0;p1;p2];
  List.iter(fun p->get(Render_pipeline.destroy p))[r0;r1];
  get(Pipeline_descriptor.Compute.destroy cd);get(Pipeline_descriptor.Render.destroy rd);
  get(destroy_mesh mesh_d);get(destroy_tile tile_d);get(Stitched_library_descriptor.destroy stitched);
  get(Function.destroy mesh);get(Function.destroy tile);get(Function.destroy kernel);get(Function.destroy vertex);get(Library.destroy library);
  get(Device.destroy device);print_endline"metal device async9: exact9 ok"
