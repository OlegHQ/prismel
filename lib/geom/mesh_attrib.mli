(** Functional mesh attribute and UV generators. *)

open Prismel

type uv_generator = face:int -> vertex:int -> point:Vec3.t -> Vec2.t

val face_uvs : Vec2.t list list -> uv_generator
val constant_uv : Vec2.t -> uv_generator
val uv_rect : ?x:float -> ?y:float -> ?u_width:float -> ?v_height:float -> width:float -> height:float -> unit -> Vec2.t list
val uv_cube_map_horizontal : ?power_of_two:bool -> face_size:int -> unit -> Vec2.t list list
val uv_cube_map_vertical : ?power_of_two:bool -> face_size:int -> unit -> Vec2.t list list
val uv_tube : u:float -> v:float -> du:float -> dv:float -> Vec2.t list
val uv_flat_disc : theta:float -> delta:float -> radius:float -> Vec2.t list
val uv_polygon_disc : vertices:int -> Vec2.t list

val with_generated_uvs : uv_generator -> Mesh.t -> (Mesh.t, string) result
(** Expand triangle faces as needed so face-local UV seams remain representable.
    Existing colors are copied and normals are regenerated. *)
