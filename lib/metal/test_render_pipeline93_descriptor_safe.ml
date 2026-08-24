open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)
let expect kind = function Error error when error.kind=kind -> () | Error error -> failwith (Format.asprintf "%a" pp_error error) | Ok _ -> failwith "expected rejection"

let () =
  let open Render_pipeline.Mesh_tile in
  let render=get(descriptor ~label:"render93" Render_descriptor) in
  let mesh=get(descriptor Mesh_descriptor) in
  let tile=get(descriptor Tile_descriptor) in
  if descriptor_kind render<>Render_descriptor||get(descriptor_label render)<>Some"render93" then failwith"descriptor identity";
  get(set_descriptor_label render(Some"copied"));
  let color=get(create_color_attachment Texture.Rgba8_unorm) in
  get(set_descriptor_color render~index:0(Some color));
  (match get(descriptor_color render~index:0)with Some returned when returned==color->()|_->failwith"color identity");
  expect Parent_has_dependents(destroy_color color);
  expect Invalid_argument(set_descriptor_color mesh~index:0(Some color));
  let vertex=Vertex_descriptor.create
    ~attributes:[Vertex_descriptor.attribute~index:0~format:Vertex_descriptor.Float2~offset:0~buffer_index:0]
    ~layouts:[Vertex_descriptor.layout~buffer_index:0~stride:(Vertex_descriptor.Static 8)()]|>get in
  get(set_descriptor_vertex render(Some vertex));
  (match get(descriptor_vertex render)with Some returned when returned==vertex->()|_->failwith"vertex descriptor copy drift");
  expect Invalid_argument(set_descriptor_vertex mesh(Some vertex));
  get(reset_descriptor render);
  if get(descriptor_label render)<>None||get(descriptor_color render~index:0)<>None||get(descriptor_vertex render)<>None then failwith"reset defaults";
  get(reset_descriptor mesh);get(reset_descriptor tile);
  get(destroy_color color);get(destroy_descriptor render);get(destroy_descriptor mesh);get(destroy_descriptor tile);
  print_endline"RenderPipeline93 descriptor safe: classes/reset/label/color/vertex ownership passed"
