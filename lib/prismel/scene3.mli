(** Pure descriptions of a depth-tested 3D scene. *)

type render_mode = Faces | Wireframe | Vertices
type cull = Cull_none | Cull_back | Cull_front
type shading = Smooth | Flat
type comparison =
  | Never
  | Less
  | Equal
  | Less_equal
  | Greater
  | Not_equal
  | Greater_equal
  | Always
type depth_state = private {
  comparison : comparison;
  write : bool;
}
type stencil_operation =
  | Keep
  | Zero
  | Replace
  | Increment
  | Decrement
  | Increment_wrap
  | Decrement_wrap
  | Invert
type stencil_state = private {
  comparison : comparison;
  reference : int;
  read_mask : int;
  write_mask : int;
  on_stencil_fail : stencil_operation;
  on_depth_fail : stencil_operation;
  on_pass : stencil_operation;
}
type raster_state = private {
  line_width : float;
  point_size : float;
}
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
type texture = private {
  value : Texture.t;
  filter : Texture.filter;
  wrap_u : Texture.wrap;
  wrap_v : Texture.wrap;
}
type node
type t

val empty : t
(* [samples] is [1], [4], [9], or [16] coverage samples per pixel. *)
val create :
  ?lights:Light.t list ->
  ?shadows:Shadow3.t list ->
  ?ambient:Color.t ->
  ?separate_specular:bool ->
  ?fog:Fog3.t ->
  ?depth_clear:float ->
  ?stencil_clear:int ->
  ?samples:int ->
  node list ->
  t

val depth_state :
  ?comparison:comparison -> ?write:bool -> unit -> depth_state
val default_depth : depth_state
val stencil_state :
  ?comparison:comparison ->
  ?reference:int ->
  ?read_mask:int ->
  ?write_mask:int ->
  ?on_stencil_fail:stencil_operation ->
  ?on_depth_fail:stencil_operation ->
  ?on_pass:stencil_operation ->
  unit ->
  stencil_state
val default_stencil : stencil_state
val raster_state :
  ?line_width:float -> ?point_size:float -> unit -> raster_state
val default_raster : raster_state

val textured :
  ?filter:Texture.filter ->
  ?wrap_u:Texture.wrap ->
  ?wrap_v:Texture.wrap ->
  Texture.t ->
  texture

val mesh :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  Mesh.t ->
  node

(* Draw immutable geometry at many independent transforms. *)
val instances :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  Mesh.t ->
  Mat4.t list ->
  node

val instances_array :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  Mesh.t ->
  Mat4.t array ->
  node
(** Array-native instance submission. The array is copied once; meshes remain
    shared and instance transforms stream through rendering without first
    materializing a drawing list. *)

val group : node list -> node
val transform : Mat4.t -> node list -> node
val translate : Vec3.t -> node list -> node
val rotate : axis:Vec3.t -> float -> node list -> node
val scale : Vec3.t -> node list -> node
val at_node : Node3.t -> node list -> node
val with_depth : depth_state -> node list -> node
val with_stencil : stencil_state -> node list -> node
val with_raster : raster_state -> node list -> node
val with_blend : blend -> node list -> node

val box :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  width:float ->
  height:float ->
  depth:float ->
  unit ->
  node
val plane :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  width:float ->
  height:float ->
  unit ->
  node
val sphere :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  radius:float ->
  unit ->
  node
val icosphere :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  radius:float ->
  unit ->
  node
val cylinder :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  radius:float ->
  height:float ->
  unit ->
  node
val cone :
  ?material:Material.t ->
  ?texture:texture ->
  ?shader:Shader3.t ->
  ?mode:render_mode ->
  ?cull:cull ->
  ?shading:shading ->
  radius:float ->
  height:float ->
  unit ->
  node

module Private : sig
  type drawing = {
    mesh : Mesh.t;
    material : Material.t;
    texture : texture option;
    shader : Shader3.t option;
    mode : render_mode;
    cull : cull;
    shading : shading;
    depth : depth_state;
    stencil : stencil_state;
    raster : raster_state;
    blend : blend;
    transform : Mat4.t;
  }

  val drawings : t -> drawing list
  val cacheable : t -> bool
  val iter_drawings : (drawing -> unit) -> t -> unit
  (* Iterate one descriptor per mesh node. [Some transforms] is a borrowed
     instance batch composed after the descriptor's parent transform. *)
  val iter_batches : (drawing -> Mat4.t array option -> unit) -> t -> unit
  val lights : t -> Light.t list
  val shadows : t -> Shadow3.t list
  val ambient : t -> Color.t
  val separate_specular : t -> bool
  val fog : t -> Fog3.t option
  val depth_clear : t -> float
  val stencil_clear : t -> int
  val samples : t -> int
end
(** Internal renderer boundary. *)
