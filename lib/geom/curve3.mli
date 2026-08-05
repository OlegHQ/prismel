(** Immutable sampled three-dimensional curves. *)

open Prismel

type t

val create : ?closed:bool -> Vec3.t list -> (t, string) result
val create_exn : ?closed:bool -> Vec3.t list -> t
val points : t -> Vec3.t list
val point_count : t -> int
val closed : t -> bool
val segments : t -> Segment3.t list
val length : t -> float
val point_at : t -> float -> Vec3.t
val sample_uniform : ?include_last:bool -> distance:float -> t -> Vec3.t list
val map : (Vec3.t -> Vec3.t) -> t -> t
val transform : Mat4.t -> t -> t
val translate : Vec3.t -> t -> t
val centroid : t -> Vec3.t
val bounds : t -> Bounds3.t
val chaikin : ?iterations:int -> ?ratio:float -> t -> t
val cubic_subdivide : ?iterations:int -> t -> t
val quadratic_bezier : ?resolution:int -> from_:Vec3.t -> control:Vec3.t -> to_:Vec3.t -> unit -> t
val cubic_bezier : ?resolution:int -> from_:Vec3.t -> control1:Vec3.t -> control2:Vec3.t -> to_:Vec3.t -> unit -> t
val catmull_rom : ?closed:bool -> ?tension:float -> ?resolution:int -> Vec3.t list -> (t, string) result
