(** Immutable indexed 3D geometry. *)

type mode =
  | Points
  | Lines
  | Line_strip
  | Line_loop
  | Triangles
  | Triangle_strip
  | Triangle_fan

type t
type face = {
  vertex_indices : int * int * int;
  points : Vec3.t * Vec3.t * Vec3.t;
  vertex_normals : (Vec3.t * Vec3.t * Vec3.t) option;
  vertex_colors : (Color.t * Color.t * Color.t) option;
  vertex_tex_coords : (Vec2.t * Vec2.t * Vec2.t) option;
  face_normal : Vec3.t;
}

val create :
  ?mode:mode ->
  ?indices:int list ->
  ?normals:Vec3.t list ->
  ?colors:Color.t list ->
  ?tex_coords:Vec2.t list ->
  Vec3.t list ->
  (t, string) result
val create_exn :
  ?mode:mode ->
  ?indices:int list ->
  ?normals:Vec3.t list ->
  ?colors:Color.t list ->
  ?tex_coords:Vec2.t list ->
  Vec3.t list ->
  t

val mode : t -> mode
val vertices : t -> Vec3.t list
val indices : t -> int list
val normals : t -> Vec3.t list
val colors : t -> Color.t list
val tex_coords : t -> Vec2.t list
val vertex_count : t -> int
val index_count : t -> int
val centroid : t -> Vec3.t option
val has_normals : t -> bool
val has_colors : t -> bool
val has_tex_coords : t -> bool

val vertex : int -> t -> Vec3.t option
val index : int -> t -> int option
val normal : int -> t -> Vec3.t option
val color : int -> t -> Color.t option
val tex_coord : int -> t -> Vec2.t option

val with_mode : mode -> t -> t
val with_vertex : int -> Vec3.t -> t -> (t, string) result
val with_index : int -> int -> t -> (t, string) result
val with_normal : int -> Vec3.t -> t -> (t, string) result
val with_color : int -> Color.t -> t -> (t, string) result
val with_tex_coord : int -> Vec2.t -> t -> (t, string) result
val with_indices : int list -> t -> (t, string) result
val with_normals : Vec3.t list -> t -> (t, string) result
val with_colors : Color.t list -> t -> (t, string) result
val with_tex_coords : Vec2.t list -> t -> (t, string) result
(* [remove_vertex] preserves valid indexing and therefore returns an error
   while the vertex is still referenced. *)
val remove_vertex : int -> t -> (t, string) result
val without_normals : t -> t
val without_colors : t -> t
val without_tex_coords : t -> t
val auto_indices : t -> t
val clear : t -> t
val transformed : Mat4.t -> t -> t
val recalculate_normals : t -> t
(* Duplicate triangle vertices so every face has one constant normal. *)
val flat_shaded : t -> t
val append : t -> t -> (t, string) result

(* Expand triangle, strip, and fan modes to indexed triangles. *)
val triangles : t -> (int * int * int) list
val faces : t -> face list
val face : int -> t -> face option
val face_normals : t -> Vec3.t list

val plane : ?columns:int -> ?rows:int -> width:float -> height:float -> unit -> t
val box :
  ?x_segments:int ->
  ?y_segments:int ->
  ?z_segments:int ->
  width:float ->
  height:float ->
  depth:float ->
  unit ->
  t
val sphere : ?segments:int -> ?rings:int -> radius:float -> unit -> t
val icosphere : ?subdivisions:int -> radius:float -> unit -> t
val cylinder :
  ?segments:int ->
  ?height_segments:int ->
  ?cap_segments:int ->
  ?capped:bool ->
  radius:float ->
  height:float ->
  unit ->
  t
val cone :
  ?segments:int ->
  ?height_segments:int ->
  ?cap_segments:int ->
  ?capped:bool ->
  radius:float ->
  height:float ->
  unit ->
  t

module Private : sig
  type vec3_view = {
    x : float array;
    y : float array;
    z : float array;
  }

  type view = {
    mode : mode;
    vertices : Vec3.t array;
    indices : int array;
    normals : Vec3.t array option;
    colors : Color.t array option;
    tex_coords : Vec2.t array option;
  }

  val view : t -> view

  type packed_view = {
    mode : mode;
    vertices : vec3_view;
    indices : int array;
    normals : vec3_view option;
    colors : Color.t array option;
    tex_coords : Vec2.t array option;
  }

  val packed_view : t -> packed_view
  val create_owned :
    ?mode:mode ->
    ?indices:int array ->
    ?normals:Vec3.t array ->
    ?colors:Color.t array ->
    ?tex_coords:Vec2.t array ->
    Vec3.t array ->
    (t, string) result
  (** Ownership-transfer construction for sibling-library generators.
      Position and normal records are packed into retained coordinate planes;
      the other supplied arrays become owned by the returned immutable mesh. *)

  val create_packed_owned :
    ?mode:mode ->
    ?indices:int array ->
    ?normals:vec3_view ->
    ?colors:Color.t array ->
    ?tex_coords:Vec2.t array ->
    vec3_view ->
    (t, string) result
  (** Zero-copy construction from packed coordinate planes. Every supplied
      array becomes owned by the returned immutable mesh and must never be
      mutated or aliased afterward. *)

  val create_packed_shared :
    ?mode:mode ->
    ?indices:int array ->
    ?normals:vec3_view ->
    ?colors:Color.t array ->
    ?tex_coords:Vec2.t array ->
    vec3_view ->
    (t, string) result
  (** Zero-copy construction from already-published immutable packed storage.
      The returned mesh retains the supplied arrays and may share them with
      another immutable value. No holder may mutate the arrays afterward. *)

  val triangle_count : t -> int
end
(** [packed_view] is the borrowed zero-copy renderer boundary. [view]
    materializes boxed vectors for compatibility with sibling algorithms.
    Callers must not mutate arrays returned by either view. *)
