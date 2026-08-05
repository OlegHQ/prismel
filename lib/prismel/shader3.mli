(** Deterministic programmable vertex, geometry, and fragment stages for
    [Scene3].

    Shader functions run on the CPU in both desktop and headless rendering.
    They should be pure and must not access SDL resources. *)

type uniform =
  | Float of float
  | Int of int
  | Bool of bool
  | Vec2 of Vec2.t
  | Vec3 of Vec3.t
  | Vec4 of float * float * float * float
  | Color of Color.t
  | Mat4 of Mat4.t
  | Texture of Texture.t
  | Floats of float list
  | Ints of int list

type uniforms

val empty_uniforms : uniforms
val set_uniform : string -> uniform -> uniforms -> uniforms
val remove_uniform : string -> uniforms -> uniforms
val find_uniform : string -> uniforms -> uniform option
val float_uniform : string -> uniforms -> float option
val int_uniform : string -> uniforms -> int option
val bool_uniform : string -> uniforms -> bool option
val vec2_uniform : string -> uniforms -> Vec2.t option
val vec3_uniform : string -> uniforms -> Vec3.t option
val color_uniform : string -> uniforms -> Color.t option
val mat4_uniform : string -> uniforms -> Mat4.t option
val texture_uniform : string -> uniforms -> Texture.t option

type vertex_input = {
  vertex_index : int;
  position : Vec3.t;
  normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  model : Mat4.t;
  view : Mat4.t;
  projection : Mat4.t;
  model_view_projection : Mat4.t;
  normal_matrix : Mat4.t;
  uniforms : uniforms;
}

type vertex_output = {
  clip_position : float * float * float * float;
  world_position : Vec3.t;
  world_normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  varyings : float list;
}

type primitive =
  | Point of vertex_output
  | Line of vertex_output * vertex_output
  | Triangle of vertex_output * vertex_output * vertex_output

type geometry_input = {
  primitive_index : int;
  primitive : primitive;
  uniforms : uniforms;
}

type fragment_input = {
  screen_position : Vec2.t;
  depth : float;
  front_facing : bool;
  world_position : Vec3.t;
  world_normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  varyings : float list;
  uniforms : uniforms;
}

type fragment_output = {
  color : Color.t;
  depth : float option;
}

type t

val create :
  ?varying_count:int ->
  ?uniforms:uniforms ->
  ?geometry:(geometry_input -> primitive list) ->
  vertex:(vertex_input -> vertex_output) ->
  fragment:(fragment_input -> fragment_output option) ->
  unit ->
  t

val with_uniform : string -> uniform -> t -> t
val with_uniforms : uniforms -> t -> t
val uniforms : t -> uniforms
val varying_count : t -> int
val has_geometry : t -> bool

val default_vertex : vertex_input -> vertex_output
(* Preserve the interpolated fixed-pipeline color and depth. *)
val default_fragment : fragment_input -> fragment_output option
val output : ?depth:float -> Color.t -> fragment_output option
val discard : fragment_output option

module Private : sig
  val vertex : t -> vertex_input -> vertex_output
  val geometry : t -> (geometry_input -> primitive list) option
  val fragment : t -> fragment_input -> fragment_output option
end
