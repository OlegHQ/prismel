(** Private typed expression extraction from classified Weiler cells. *)

type expression =
  | Left
  | Right
  | Not of expression
  | And of expression * expression
  | Or of expression * expression
  | Xor of expression * expression

val union : expression
val intersection : expression
val difference : expression
val reverse_difference : expression
val xor : expression

type ancestry

val geometry : ancestry -> Geometry.t
val primitive_side : ancestry -> int -> Boolean_complex.side
val primitive_face : ancestry -> int -> int
val primitive_triangle : ancestry -> int -> int
val primitive_refined_triangle : ancestry -> int -> int
val primitive_winding : ancestry -> int -> int
val primitive_source_point : ancestry -> int -> int -> int
val primitive_source_vertex : ancestry -> int -> int -> int
val corner_barycentric : ancestry -> int -> int -> float * float * float
(** Source ownership selected deterministically for every output triangle.
    [primitive_winding] is the output orientation relative to that member's
    source orientation and is always [-1] or [1]. [primitive_face] is the
    original polygon primitive, [primitive_triangle] is its stable internal
    triangulation member, and [primitive_refined_triangle] is [-1] for an
    untouched triangle or the per-face refinement child. Source points and
    exact-construction-derived barycentrics are relative to that internal
    source triangle; source point and source vertex identities are both
    retained because vertex attributes follow corner ownership. Corner indices
    are 0, 1, or 2. Private directed-edge CSR additionally retains every
    coincident member whose exact source-native edge contains an output edge;
    it is intentionally multi-source rather than derived from the preferred
    primitive member. *)

val build_with_ancestry :
  ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
  expression:expression ->
  Boolean_complex.t -> Boolean_weiler.t -> Boolean_cells.t ->
  (ancestry, Error.t) result

val build :
  ?cancel:Cancel.t -> ?require_closed:bool -> expression:expression ->
  Boolean_complex.t -> Boolean_weiler.t -> Boolean_cells.t ->
  (Geometry.t, Error.t) result
(** Extract a triangle boundary. Exact combinatorics choose facets and
    orientation; coordinates round to binary64 once while materializing the
    packed PDK geometry. *)

module Private : sig
  type ancestry_view = {
    point_complex_vertices : int array;
    primitive_complex_facets : int array;
    primitive_sides : bytes;
    primitive_source_points : int array;
    primitive_source_vertices : int array;
    barycentric_a : float array;
    barycentric_b : float array;
    barycentric_c : float array;
    edge_source_offsets : int array;
    edge_source_sides : bytes;
    edge_source_edges : int array;
  }
  val ancestry_view : ancestry -> ancestry_view
  val complex : ancestry -> Boolean_complex.t
  val point_complex_vertex : ancestry -> int -> int
  (* Output point for a selected exact-complex vertex, or [-1]. Distinct exact
     vertices that round to bit-identical binary64 positions may map to the
     same output point after certified coalescing. *)
  val complex_output_point : ancestry -> int -> int
  val primitive_complex_facet : ancestry -> int -> int
  val left_geometry : ancestry -> Geometry.t
  val right_geometry : ancestry -> Geometry.t
  val validate_positions :
    x:float array -> y:float array -> z:float array -> (unit, Error.t) result
  val validate_materialized :
    ?allow_degenerate:bool ->
    x:float array -> y:float array -> z:float array ->
    vertex_points:int array -> unit -> (unit, Error.t) result
  val coalesce_positions :
    complex_vertices:int array -> x:float array -> y:float array -> z:float array ->
    float array * float array * float array * int array * int array
  val validate_closed_topology : Topology.t -> (unit, Error.t) result
  (* Materialize the exact facets selected by packed orientation bytes:
      zero omits, one keeps canonical orientation, and two reverses it. The
      requested side supplies deterministic payload ancestry. *)
  val build_selected_with_ancestry :
    ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
    selection:bytes ->
    side:Boolean_complex.side -> Boolean_complex.t -> Boolean_weiler.t ->
    Boolean_cells.t -> (ancestry, Error.t) result
  (* Concatenate products from one exact complex while sharing equal exact
      complex vertices and preserving every packed ancestry plane. *)
  val concatenate_ancestries :
    ?cancel:Cancel.t -> ancestry array -> (ancestry, Error.t) result
end
