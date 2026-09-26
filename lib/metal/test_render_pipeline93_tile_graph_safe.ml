open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "%a" pp_error e)|Ok _->failwith"expected rejection"
let source={|
#include <metal_stdlib>
using namespace metal;
kernel void tile93(ushort2 p [[thread_position_in_threadgroup]]){(void)p;}
|}
let run () =match Device.system_default()with Error _->print_endline"RenderPipeline93 tile graph: skipped"|Ok device->
  let library=get(Library.compile_source~device source)in let tile=get(Function.find~library "tile93")in
  let open Render_pipeline.Mesh_tile in let one={width=1L;height=1L;depth=1L}in
  let descriptor=get(tile_descriptor~tile_function:tile~required_threads:one())in
  expect Parent_has_dependents(Function.destroy tile);get(destroy_tile descriptor);get(Function.destroy tile);get(Library.destroy library);get(Device.destroy device);
  print_endline"RenderPipeline93 tile graph: exact9 ownership/identity passed"
