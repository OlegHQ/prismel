(** Persistent point quadtree. *)

open Prismel

type 'a entry = { point : Vec2.t; value : 'a }
type 'a t

val create : ?capacity:int -> ?max_depth:int -> Bounds2.t -> 'a t
(* Bulk-build using a transient mutable tree, then freeze it as a persistent
   value. This avoids copying the root-to-leaf path for every input entry. *)
val of_list : ?capacity:int -> ?max_depth:int -> Bounds2.t -> (Vec2.t * 'a) list -> ('a t, string) result
val bounds : 'a t -> Bounds2.t
val size : 'a t -> int
val is_empty : 'a t -> bool
val insert : Vec2.t -> 'a -> 'a t -> ('a t, string) result
val insert_exn : Vec2.t -> 'a -> 'a t -> 'a t
val entries : 'a t -> 'a entry list
val fold : ('b -> 'a entry -> 'b) -> 'b -> 'a t -> 'b
val query_bounds : Bounds2.t -> 'a t -> 'a entry list
val query_circle : center:Vec2.t -> radius:float -> 'a t -> 'a entry list
val nearest : ?max_distance:float -> Vec2.t -> 'a t -> 'a entry option
val remove_if : ('a entry -> bool) -> 'a t -> 'a t
val filter : ('a entry -> bool) -> 'a t -> 'a t
val map : ('a -> 'b) -> 'a t -> 'b t
