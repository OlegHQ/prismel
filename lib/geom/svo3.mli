(** Persistent sparse voxel octree with explicit depth addressing. *)

open Prismel

type cell = int * int * int
type t

val create : origin:Vec3.t -> size:float -> precision:float -> t
val origin : t -> Vec3.t
val size : t -> float
val precision : t -> float
val max_depth : t -> int
val size_at_depth : t -> int -> float
val dimensions_at_depth : t -> int -> int

val set_at : Vec3.t -> t -> (t, string) result
val delete_at : Vec3.t -> t -> t
val contains : Vec3.t -> t -> bool
val depth_at : ?max_depth:int -> Vec3.t -> t -> int option
(** Deepest occupied branch along the point's path. *)

val select_cells : depth:int -> t -> cell list
val select : depth:int -> t -> Vec3.t list
(** Centers of occupied cells at the requested (clamped) depth. *)

val fold_points : ('a -> Vec3.t -> 'a) -> 'a -> t -> 'a
val of_points : origin:Vec3.t -> size:float -> precision:float -> Vec3.t list -> (t, string) result
val to_voxel3 : depth:int -> t -> Voxel3.t
