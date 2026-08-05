(** Persistent sparse voxel occupancy and surface extraction. *)

open Prismel

type cell = int * int * int
type t

val create : origin:Vec3.t -> dimensions:int * int * int -> voxel_size:float -> t
val of_cells :
  origin:Vec3.t ->
  dimensions:int * int * int ->
  voxel_size:float ->
  cell list ->
  (t, string) result
val init :
  origin:Vec3.t ->
  dimensions:int * int * int ->
  voxel_size:float ->
  occupied:(cell -> bool) ->
  t
(** Deterministically evaluate a dense occupancy predicate in page-sized
    parallel partitions. The callback must be pure. *)

module Builder : sig
  type voxel := t
  type t
  val create :
    origin:Vec3.t -> dimensions:int * int * int -> voxel_size:float -> t
  val set : cell -> t -> (unit, string) result
  val freeze : t -> voxel
end
(* Mutable bulk construction boundary. A builder is single-domain owned;
   [freeze] returns an immutable paged voxel value. *)
val origin : t -> Vec3.t
val dimensions : t -> int * int * int
val voxel_size : t -> float
val bounds : t -> Bounds3.t
val count : t -> int
val is_empty : t -> bool
val contains : cell -> t -> bool
val set : cell -> t -> (t, string) result
val unset : cell -> t -> t
val toggle : cell -> t -> (t, string) result
val cells : t -> cell list
val fold : ('a -> cell -> 'a) -> 'a -> t -> 'a
val filter : (cell -> bool) -> t -> t
val world_to_cell : Vec3.t -> t -> cell option
val cell_center : cell -> t -> Vec3.t
val set_world : Vec3.t -> t -> (t, string) result
val fill_bounds : Bounds3.t -> t -> t
val neighbors6 : cell -> cell list
val neighbors26 : cell -> cell list
val boundary : t -> cell list
val thicken : ?diagonal:bool -> layers:int -> t -> t
val to_octree : ?capacity:int -> t -> cell Octree.t

val surface_mesh : ?color:(cell -> Color.t) -> t -> (Mesh.t, string) result
(** Emit quads only for faces adjacent to empty/out-of-bounds cells. *)

val isosurface : ?smooth:bool -> t -> (Mesh.t, string) result
(** Extract a marching-tetrahedra surface at half occupancy. *)
