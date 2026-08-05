(** Packed reverse topology derived from {!Topology.t}.

    The source topology stores forward primitive-to-corner and corner-to-point
    relations. This index adds point-to-corner CSR incidence and an undirected
    edge table. Polygon and closed-polyline corners own a cyclic outgoing edge;
    the final corner of an open polyline has no outgoing edge.

    Construction is O(vertices + edges) expected time and uses O(vertices +
    edges + points) auxiliary storage. The open-addressed edge table uses
    integer keys and does not allocate tuples in the insertion hot loop. *)

type t

val create : ?cancel:Cancel.t -> Topology.t -> t
(** Return the process-shared index for this immutable topology. The weak,
    thread-safe cache retains no topology after its source becomes unreachable. *)

val create_uncached : ?cancel:Cancel.t -> Topology.t -> t
(** Build without consulting or populating the weak cache. Intended for cold
    benchmarks and specialized one-shot ownership. *)

val topology_data_id : t -> int
(* Data identity of the topology from which this index was derived. *)
val point_count : t -> int
val vertex_count : t -> int
val primitive_count : t -> int
val edge_count : t -> int

val primitive_of_vertex : t -> int -> int
val next_vertex : t -> int -> int
val previous_vertex : t -> int -> int
(** Primitive-local neighboring corners. Open-polyline endpoints return [-1]
    where no neighbor exists. *)

val edge_of_vertex : t -> int -> int
(** The outgoing undirected edge of a corner, or [-1] for the last corner of
    an open polyline. *)

val opposite_vertex : t -> int -> int
(** Opposite directed corner for a two-sided manifold edge, or [-1] for a
    boundary/non-manifold/no-edge corner. *)

val edge_points : t -> int -> int * int
val find_edge_index : t -> a:int -> b:int -> int
(* Allocation-free endpoint lookup. Returns [-1] when the edge is absent or
    either endpoint is outside the topology. *)
val find_edge : t -> a:int -> b:int -> int option
val edge_incidence_count : t -> int -> int
val edge_vertex : t -> edge:int -> local:int -> int
val point_incidence_count : t -> int -> int
val point_vertex : t -> point:int -> local:int -> int
val point_edge_count : t -> int -> int
val point_edge : t -> point:int -> local:int -> int
val boundary_edge_count : t -> int
val non_manifold_edge_count : t -> int

module Private : sig
  type view = {
    primitive_of_vertex : int array;
    next_vertex : int array;
    previous_vertex : int array;
    edge_of_vertex : int array;
    opposite_vertex : int array;
    edge_a : int array;
    edge_b : int array;
    edge_offsets : int array;
    edge_vertices : int array;
    point_offsets : int array;
    point_vertices : int array;
    point_edge_offsets : int array;
    point_edges : int array;
  }

  val view : t -> view
  (** Borrowed immutable planes for audited PDK kernels. *)

  val polygon_manifold_boundary_points :
    ?cancel:Cancel.t -> topology:Topology.t -> t -> (bytes, string) result
  (** Validate a consistently wound polygon-only 2-manifold, including
      repeated corners, edge incidence, boundary fan cardinality, and
      disconnected point fans. The returned byte plane marks boundary points.
      This shared topology predicate deliberately performs no metric checks. *)
end
