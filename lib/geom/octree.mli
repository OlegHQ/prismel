(** Persistent point octree. *)

open Prismel

type 'a entry = { point : Vec3.t; value : 'a }
type 'a t

val create : ?capacity:int -> ?max_depth:int -> Bounds3.t -> 'a t
(* Bulk-build using a transient mutable tree, then freeze it as a persistent
   value. This avoids copying the root-to-leaf path for every input entry. *)
val of_list : ?capacity:int -> ?max_depth:int -> Bounds3.t -> (Vec3.t * 'a) list -> ('a t, string) result
val bounds : 'a t -> Bounds3.t
val size : 'a t -> int
val is_empty : 'a t -> bool
val insert : Vec3.t -> 'a -> 'a t -> ('a t, string) result
val insert_exn : Vec3.t -> 'a -> 'a t -> 'a t
val entries : 'a t -> 'a entry list
val fold : ('b -> 'a entry -> 'b) -> 'b -> 'a t -> 'b
val query_bounds : Bounds3.t -> 'a t -> 'a entry list
val query_sphere : center:Vec3.t -> radius:float -> 'a t -> 'a entry list
val nearest : ?max_distance:float -> Vec3.t -> 'a t -> 'a entry option
val remove_if : ('a entry -> bool) -> 'a t -> 'a t
val filter : ('a entry -> bool) -> 'a t -> 'a t
val map : ('a -> 'b) -> 'a t -> 'b t
