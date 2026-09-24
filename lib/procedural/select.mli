(** Typed, immutable selection expressions. They compile to PDK bitsets once
    per SOP cook; no group-string parsing occurs in element hot loops. *)

type point
type vertex
type primitive
type 'owner t

val all_points : point t
val point_indices : int array -> point t
val points_in_bounds : min:Prismel.Vec3.t -> max:Prismel.Vec3.t -> point t
val all_vertices : vertex t
val vertex_indices : int array -> vertex t
val all_primitives : primitive t
val primitive_indices : int array -> primitive t

val union : 'owner t -> 'owner t -> 'owner t
val intersection : 'owner t -> 'owner t -> 'owner t
val difference : 'owner t -> 'owner t -> 'owner t
val complement : 'owner t -> 'owner t

val fingerprint : 'owner t -> string
val evaluate : name:string -> 'owner t -> Pdk.Geometry.t -> (Pdk.Group.t, string) result
