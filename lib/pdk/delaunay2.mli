(** Packed deterministic unconstrained Delaunay triangulation in two dimensions.

    This is the shared low-level seed triangulation for public planar/CDT
    operations. Combinatorial decisions use exact binary64 predicates; no
    epsilon participates in topology. *)

type t

val build :
  ?cancel:Cancel.t -> ?seed:int64 ->
  x:float array -> y:float array -> unit -> (t, string) result
(** Exact-coordinate duplicates are represented once, by their lowest source
    point number. Output triangles are counter-clockwise and lexicographically
    canonicalized by source point number. *)

val source_count : t -> int
val unique_count : t -> int
val triangle_count : t -> int
val unique_source : t -> int -> int
val source_unique : t -> int -> int
val triangle_point : t -> int -> int -> int

module Private : sig
  type view = {
    unique_x : float array;
    unique_y : float array;
    unique_source : int array;
    source_unique : int array;
    triangle_points : int array;
  }

  val view : t -> view
end
