type glyph_atlas = {
  width : int;
  height : int;
  pitch : int;
  bytes : bytes;
  cell_width : int;
  cell_height : int;
}

type resource = Image of Surface.t | Glyph_atlas of glyph_atlas
type depth = { attachment:Depth_stencil.t; state:Depth_stencil.state; value:float; clear:float; clear_stencil:int }

type error =
  | Missing_resource of int
  | Wrong_resource_kind of int
  | Invalid_resource of int
  | Surface_error
  | Scratch_limit

val execute :
  ?depth:depth ->
  lookup:(int -> resource option) ->
  target:Surface.t ->
  Render_ir.t ->
  (unit, error) result
