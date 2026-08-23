open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let ()=
  let open Render_pipeline.Mesh_tile in
  let buffer=get(buffer_descriptor ~mutability:Mutable())in
  if buffer_mutability buffer<>Mutable then fail "buffer mutability drift";
  get(set_buffer_mutability buffer Immutable);
  if buffer_mutability buffer<>Immutable then fail "buffer mutability setter drift";
  let color=get(create_color_attachment Texture.Bgra8_unorm)in
  if color_attachment_format color<>Texture.Bgra8_unorm then fail "color format drift";
  get(destroy_color color);get(destroy_buffer buffer)
