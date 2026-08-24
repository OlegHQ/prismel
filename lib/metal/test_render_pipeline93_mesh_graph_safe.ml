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
kernel void tile93(ushort2 p [[thread_position_in_threadgroup]]) { (void)p; }
|}
let ()=match Device.system_default()with Error _->print_endline"RenderPipeline93 mesh graph: skipped"|Ok device->
  let library=get(Library.compile_source~device source)in
  let mesh=get(Function.find~library "mesh93")and fragment=get(Function.find~library "fragment93")and tile=get(Function.find~library "tile93")in
  let additional=get(Render_pipeline.Functions_descriptor.create())in
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Vertex[mesh]);
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Fragment[fragment]);
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Tile[tile]);
  (match get(Render_pipeline.Functions_descriptor.functions additional Render_pipeline.Functions_descriptor.Vertex)with[value]when value==mesh->()|_->failwith"additional vertex functions drift");
  expect Parent_has_dependents(Function.destroy mesh);
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Vertex[]);
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Fragment[]);
  get(Render_pipeline.Functions_descriptor.set_functions additional Render_pipeline.Functions_descriptor.Tile[]);
  get(Render_pipeline.Functions_descriptor.destroy additional);
  let open Render_pipeline.Mesh_tile in let three={width=3L;height=1L;depth=1L}and zero={width=0L;height=0L;depth=0L}in
  let descriptor=get(mesh_descriptor~fragment_function:fragment~mesh_function:mesh~depth_format:Texture.Depth32_float~stencil_format:Texture.Stencil8~required_mesh_threads:three~required_object_threads:zero())in
  if get(mesh_mesh_function descriptor)!=mesh then failwith"mesh function identity";
  (match get(mesh_fragment_function descriptor)with Some value when value==fragment->()|_->failwith"fragment function identity");
  (match get(mesh_object_function descriptor)with None->()|Some _->failwith"object function default");
  (match get(mesh_binary_archives descriptor)with []->()|_->failwith"archive graph default");
  get(set_mesh_binary_archives descriptor[]);get(set_mesh_mesh_function descriptor mesh);get(set_mesh_fragment_function descriptor None);get(set_mesh_object_function descriptor None);
  let linked=get(Linked_functions.create device)in
  get(set_mesh_object_linked_functions descriptor(Some linked));
  get(set_mesh_mesh_linked_functions descriptor(Some linked));
  get(set_mesh_fragment_linked_functions descriptor(Some linked));
  let same_linked=function Some value when value==linked->true|_->false in
  if not(same_linked(get(mesh_object_linked_functions descriptor)))||not(same_linked(get(mesh_mesh_linked_functions descriptor)))||not(same_linked(get(mesh_fragment_linked_functions descriptor)))then failwith"mesh linked graph identity";
  expect Parent_has_dependents(Linked_functions.destroy linked);
  get(set_mesh_object_linked_functions descriptor None);get(set_mesh_mesh_linked_functions descriptor None);get(set_mesh_fragment_linked_functions descriptor None);
  let one={width=1L;height=1L;depth=1L}in
  let tile_descriptor=get(tile_descriptor~tile_function:tile~required_threads:one())in
  get(set_tile_linked_functions tile_descriptor(Some linked));
  if not(same_linked(get(tile_linked_functions tile_descriptor)))then failwith"tile linked graph identity";
  expect Parent_has_dependents(Linked_functions.destroy linked);
  get(set_tile_linked_functions tile_descriptor None);get(destroy_tile tile_descriptor);get(Linked_functions.destroy linked);
  (match compile_mesh descriptor with
   |Error{kind=Unsupported;_}->()
   |Error e->failwith(Format.asprintf "%a" pp_error e)
   |Ok pipeline->
      (match get(Render_pipeline.Function_lookup.function_ pipeline Render_pipeline.Function_lookup.Mesh mesh)with None->()|Some handle->get(Render_pipeline.Function_lookup.destroy handle));
      (match Render_pipeline.Function_lookup.named pipeline Render_pipeline.Function_lookup.Mesh "mesh93"with Ok(Some handle)->get(Render_pipeline.Function_lookup.destroy handle)|Ok None|Error{kind=Unsupported;_}->()|Error e->failwith(Format.asprintf "%a" pp_error e));
      (match Render_pipeline.Function_table.create Render_pipeline.Function_table.Visible~pipeline~stage:Render_pipeline.Function_lookup.Mesh~capacity:1 with Ok table->get(Render_pipeline.Function_table.destroy table)|Error{kind=Unsupported;_}->()|Error e->failwith(Format.asprintf "%a" pp_error e));
      (match Render_pipeline.Function_table.create Render_pipeline.Function_table.Intersection~pipeline~stage:Render_pipeline.Function_lookup.Mesh~capacity:1 with Ok table->get(Render_pipeline.Function_table.destroy table)|Error{kind=Unsupported;_}->()|Error e->failwith(Format.asprintf "%a" pp_error e));
      (match Render_pipeline.Specialization_descriptor.create pipeline with Ok descriptor->get(Render_pipeline.Specialization_descriptor.destroy descriptor)|Error{kind=Unsupported;_}->()|Error e->failwith(Format.asprintf "%a" pp_error e));
      get(Render_pipeline.destroy pipeline));
  expect Parent_has_dependents(Function.destroy mesh);
  get(destroy_mesh descriptor);get(Function.destroy mesh);get(Function.destroy fragment);get(Function.destroy tile);get(Library.destroy library);get(Device.destroy device);
  print_endline"RenderPipeline93 mesh graph: function12 + linked12 ownership/identity passed"
