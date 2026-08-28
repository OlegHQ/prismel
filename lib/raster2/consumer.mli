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

module Workspace : sig
  type t
  (* Bounded, resize-on-demand transaction storage. A workspace must not be
      used by overlapping [execute] calls. *)
  val create : unit -> t
end

val execute :
  ?depth:depth ->
  ?workspace:Workspace.t ->
  lookup:(int -> resource option) ->
  target:Surface.t ->
  Render_ir.t ->
  (unit, error) result
module Private : sig
  val execute_swap : ?depth:depth -> workspace:Workspace.t ->
    lookup:(int -> resource option) -> target:Surface.t -> Render_ir.t ->
    (Surface.t,error) result
  val replace_workspace_color : Workspace.t -> bytes -> unit
end
