open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let source={|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V async9_vertex(uint id [[vertex_id]]) {
  float2 p[3]={float2(-1),float2(3,-1),float2(-1,3)};
  return {float4(p[id],0,1)};
}
kernel void async9_kernel(device uint *out [[buffer(0)]]) { out[0]=9; }
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
  List.iter(fun p->get(Compute_pipeline.destroy p))[p0;p1;p2];
  List.iter(fun p->get(Render_pipeline.destroy p))[r0;r1];
  get(Pipeline_descriptor.Compute.destroy cd);get(Pipeline_descriptor.Render.destroy rd);
  get(Function.destroy kernel);get(Function.destroy vertex);get(Library.destroy library);
  get(Device.destroy device);print_endline"metal device async9: core6 ok; stitched/mesh/tile capability fixtures separate"
