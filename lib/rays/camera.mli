(** Immutable perspective and orthographic cameras. *)

type projection =
  | Perspective of {
      fov_y : float;
      near : float;
      far : float;
    }
  | Orthographic of {
      height : float;
      near : float;
      far : float;
    }

(** Thin-lens depth of field for renderers that model it (the path tracer):
    [aperture] is the lens radius in scene units (0, the default, is a
    pinhole); [focus_distance] is the sharp distance along the view direction,
    or [None] to focus on [target]. Raster views ignore the lens. *)
type lens = { aperture : float; focus_distance : float option }

val pinhole : lens

type t

val perspective :
  ?fov_y:float ->
  ?near:float ->
  ?far:float ->
  at:Vec3.t ->
  target:Vec3.t ->
  unit ->
  t
(** [fov_y] is a vertical angle in radians. *)

val orthographic :
  height:float ->
  at:Vec3.t ->
  target:Vec3.t ->
  unit ->
  t

val position : t -> Vec3.t
val target : t -> Vec3.t
val up : t -> Vec3.t
val projection : t -> projection
val lens : t -> lens

val focus_distance : t -> float
(** The lens's focus distance, or the distance to [target]. *)

val with_position : Vec3.t -> t -> t
val with_up : Vec3.t -> t -> t

val with_lens : lens -> t -> t
(** Raises [Invalid_argument] for a negative or non-finite aperture or a
    non-positive focus distance. *)

(* Translate both position and target. *)

val view_projection_matrix :
  viewport:int * int * int * int -> t -> Mat4.t

(* Return logical screen x/y and normalized depth in [0, 1]. *)
val world_to_screen :
  viewport:int * int * int * int -> t -> Vec3.t -> Vec3.t option

val world_to_camera : t -> Vec3.t -> Vec3.t

(* Return a world-space ray origin and normalized direction. *)
val screen_ray :
  viewport:int * int * int * int ->
  t ->
  at:float * float ->
  (Vec3.t * Vec3.t) option
