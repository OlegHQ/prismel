open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "%a" pp_error e)|Ok _->failwith"expected rejection"
let source={|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
using M = mesh<V, void, 3, 1, topology::triangle>;
[[mesh]] void mesh93(M out,uint tid [[thread_index_in_threadgroup]]) { if(tid==0)out.set_primitive_count(0); }
fragment float4 fragment93(){return float4(1);}
|}
let ()=match Device.system_default()with Error _->print_endline"RenderPipeline93 mesh graph: skipped"|Ok device->
  let library=get(Library.compile_source~device source)in
  let mesh=get(Function.find~library "mesh93")and fragment=get(Function.find~library "fragment93")in
  let open Render_pipeline.Mesh_tile in let three={width=3L;height=1L;depth=1L}and zero={width=0L;height=0L;depth=0L}in
  let descriptor=get(mesh_descriptor~fragment_function:fragment~mesh_function:mesh~depth_format:Texture.Depth32_float~stencil_format:Texture.Stencil8~required_mesh_threads:three~required_object_threads:zero())in
  if get(mesh_mesh_function descriptor)!=mesh then failwith"mesh function identity";
  (match get(mesh_fragment_function descriptor)with Some value when value==fragment->()|_->failwith"fragment function identity");
  (match get(mesh_object_function descriptor)with None->()|Some _->failwith"object function default");
  (match get(mesh_binary_archives descriptor)with []->()|_->failwith"archive graph default");
  get(set_mesh_binary_archives descriptor[]);get(set_mesh_mesh_function descriptor mesh);get(set_mesh_fragment_function descriptor None);get(set_mesh_object_function descriptor None);
  expect Parent_has_dependents(Function.destroy mesh);
  get(destroy_mesh descriptor);get(Function.destroy mesh);get(Function.destroy fragment);get(Library.destroy library);get(Device.destroy device);
  print_endline"RenderPipeline93 mesh graph: exact12 ownership/identity passed"
