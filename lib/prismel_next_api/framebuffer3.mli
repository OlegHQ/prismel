(** Immutable color, depth, and stencil attachments from offscreen 3D
    rendering. *)

type t

val render :
  width:int ->
  height:int ->
  camera:Camera.t ->
  Scene3.t ->
  t
(** Run the same deterministic rasterizer used by [Scene.view3d] without
    compositing it into the active SDL renderer. *)

val width : t -> int
val height : t -> int
val size : t -> int * int

val color : t -> Texture.t
(** Borrow the immutable color attachment as a mesh/shader texture. *)

val color_pixel : t -> x:int -> y:int -> Color.t option
val depth : t -> x:int -> y:int -> float option
val stencil : t -> x:int -> y:int -> int option
val depths : t -> float array
val stencils : t -> int array
(* Attachment arrays are returned as row-major copies. *)

val shadow :
  ?bias:float ->
  ?normal_bias:float ->
  ?filter:Shadow3.filter ->
  ?strength:float ->
  light:Light.t ->
  camera:Camera.t ->
  t ->
  Shadow3.t

val to_canvas : t -> (Canvas.t, string) result
val to_image : t -> (Image.t, string) result
(** Upload a color snapshot for 2D scene composition. The caller owns an image
    returned by [to_image] and must destroy it. *)
