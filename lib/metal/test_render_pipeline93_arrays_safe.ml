open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "%a" pp_error e)|Ok _->failwith"expected rejection"
let all predicate array=Array.for_all predicate array
let ()=
  let open Render_pipeline.Mesh_tile in
  let render=get(descriptor Render_descriptor)and mesh=get(descriptor Mesh_descriptor)and tile=get(descriptor Tile_descriptor)in
  if not(all Option.is_none(get(descriptor_color_formats render)))then failwith"render color defaults";
  if not(all((=)Default)(get(descriptor_buffer_mutabilities render Vertex_buffers)))then failwith"vertex buffer defaults";
  if not(all((=)Default)(get(descriptor_buffer_mutabilities render Fragment_buffers)))then failwith"fragment buffer defaults";
  if not(all Option.is_none(get(descriptor_color_formats mesh)))then failwith"mesh color defaults";
  List.iter(fun stage->if not(all((=)Default)(get(descriptor_buffer_mutabilities mesh stage)))then failwith"mesh buffer defaults")[Object_buffers;Mesh_buffers;Fragment_buffers];
  if not(all Option.is_none(get(descriptor_color_formats tile)))then failwith"tile color defaults";
  if not(all((=)Default)(get(descriptor_buffer_mutabilities tile Tile_buffers)))then failwith"tile buffer defaults";
  expect Invalid_argument(descriptor_buffer_mutabilities tile Vertex_buffers);
  get(destroy_descriptor render);get(destroy_descriptor mesh);get(destroy_descriptor tile);
  print_endline"RenderPipeline93 arrays: exact18 immutable typed snapshots passed"
