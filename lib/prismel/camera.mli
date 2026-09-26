(** Immutable perspective and orthographic cameras. *)

type projection =
  | Perspective of {
      fov_y : float;
      near : float;
      far : float;
      lens_offset : Vec2.t;
    }
  | Orthographic of {
      height : float;
      near : float;
      far : float;
    }
  | Frustum of {
      left : float;
      right : float;
      bottom : float;
      top : float;
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
  ?lens_offset:Vec2.t ->
  ?v_flip:bool ->
  at:Vec3.t ->
  target:Vec3.t ->
  unit ->
  t
(** [fov_y] is a vertical angle in radians. *)

val orthographic :
  ?near:float ->
  ?far:float ->
  ?v_flip:bool ->
  height:float ->
  at:Vec3.t ->
  target:Vec3.t ->
  unit ->
  t

val frustum :
  left:float ->
  right:float ->
  bottom:float ->
  top:float ->
  near:float ->
  far:float ->
  ?v_flip:bool ->
  at:Vec3.t ->
  target:Vec3.t ->
  unit ->
  t

val off_axis_portal :
  ?near:float ->
  ?far:float ->
  ?v_flip:bool ->
  eye:Vec3.t ->
  top_left:Vec3.t ->
  bottom_left:Vec3.t ->
  bottom_right:Vec3.t ->
  unit ->
  t

val position : t -> Vec3.t
val target : t -> Vec3.t
val up : t -> Vec3.t
val projection : t -> projection
val v_flip : t -> bool
val forced_aspect : t -> float option
val lens : t -> lens

val focus_distance : t -> float
(** The lens's focus distance, or the distance to [target]. *)

val with_position : Vec3.t -> t -> t
val with_target : Vec3.t -> t -> t
val with_up : Vec3.t -> t -> t
val look_at : Vec3.t -> t -> t
val with_projection : projection -> t -> t
val with_v_flip : bool -> t -> t
val with_forced_aspect : float option -> t -> t

val with_lens : lens -> t -> t
(** Raises [Invalid_argument] for a negative or non-finite aperture or a
    non-positive focus distance. *)

val move : Vec3.t -> t -> t
(* Translate both position and target. *)

val view_matrix : t -> Mat4.t
val projection_matrix : viewport:int * int * int * int -> t -> Mat4.t
val aspect_ratio : viewport:int * int * int * int -> t -> float
val image_plane_distance :
  viewport:int * int * int * int -> t -> float option
val view_projection_matrix :
  viewport:int * int * int * int -> t -> Mat4.t

(* Return logical screen x/y and normalized depth in [0, 1]. *)
val world_to_screen :
  viewport:int * int * int * int -> t -> Vec3.t -> Vec3.t option

val screen_to_world :
  viewport:int * int * int * int -> t -> Vec3.t -> Vec3.t option
val world_to_camera : t -> Vec3.t -> Vec3.t
val camera_to_world : t -> Vec3.t -> Vec3.t option

(* Return a world-space ray origin and normalized direction. *)
val screen_ray :
  viewport:int * int * int * int ->
  t ->
  at:float * float ->
  (Vec3.t * Vec3.t) option

val frustum_mesh : viewport:int * int * int * int -> t -> Mesh.t
