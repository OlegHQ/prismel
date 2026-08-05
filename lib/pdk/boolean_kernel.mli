(** Internal exact-construction boundary for PDK Boolean stages.

    This module is exposed only so focused black-box regressions can exercise
    the same compiled implementation. It is not a stable modeling API. *)

module Private : sig
  type source

  type t

  type projection = XY | YZ | ZX

  type construction =
    | Explicit of int
    | Rounded of { x : float; y : float; z : float }
    | Line_plane of {
        line_start : int;
        line_end : int;
        plane_a : int;
        plane_b : int;
        plane_c : int;
      }
    | Line_line of {
        projection : projection;
        first_start : int;
        first_end : int;
        second_start : int;
        second_end : int;
      }
      | Triple_plane of {
        first_a : int; first_b : int; first_c : int;
        second_a : int; second_b : int; second_c : int;
        third_a : int; third_b : int; third_c : int;
      }
    | Midpoint of { first : t; second : t }
    | Centroid3 of { first : t; second : t; third : t }
    | Circumcenter2_xy of { first : t; second : t; third : t }

  type error =
    | Coordinate_plane_size_mismatch
    | Non_finite_coordinate of int
    | Index_out_of_bounds of int
    | Parallel_line_and_plane
    | Parallel_lines
    | Dependent_planes
    | Point_source_mismatch
    | Degenerate_triangle
    | Non_finite_approximation

  val source : x:float array -> y:float array -> z:float array ->
    (source, error) result
  val source_triangle_projection : source -> int -> int -> int -> projection
  val source_segment_contains :
    source -> projection:projection -> first:int -> second:int -> t -> bool
  val barycentric_source_triangle :
    source -> a:int -> b:int -> c:int -> t -> float * float * float
  val barycentric_source_triangle_reference :
    source -> a:int -> b:int -> c:int -> t -> float * float * float
  val construction : t -> construction
  val explicit : source -> int -> (t, error) result
  val rounded : reference:t -> x:float -> y:float -> z:float -> (t, error) result
  val line_plane : source ->
    line_start:int -> line_end:int ->
    plane_a:int -> plane_b:int -> plane_c:int ->
    (t, error) result
  val line_line : source -> projection:projection ->
    first_start:int -> first_end:int ->
    second_start:int -> second_end:int ->
    (t, error) result
  val triple_plane : source ->
    first_a:int -> first_b:int -> first_c:int ->
    second_a:int -> second_b:int -> second_c:int ->
    third_a:int -> third_b:int -> third_c:int ->
    (t, error) result
  val centroid3 : t -> t -> t -> (t, error) result
  val midpoint : t -> t -> (t, error) result
  val circumcenter2_xy : t -> t -> t -> (t, error) result
  val diametral_dot_xy : first:t -> second:t -> t -> Predicates.sign
  val approximate : t -> float * float * float
  val bounds : t -> (float * float) * (float * float) * (float * float)
  val equal : t -> t -> bool
  val compare_x : t -> t -> int
  val compare_y : t -> t -> int
  val compare_z : t -> t -> int
  val compare_arena_x : t -> t -> int
  val compare_arena_y : t -> t -> int
  val compare_arena_z : t -> t -> int
  val compare_reference_x : t -> t -> int
  val compare_reference_y : t -> t -> int
  val compare_reference_z : t -> t -> int
  val orient2d_xy : t -> t -> t -> Predicates.sign
  val orient2d_yz : t -> t -> t -> Predicates.sign
  val orient2d_zx : t -> t -> t -> Predicates.sign
  val orient3d : t -> t -> t -> t -> Predicates.sign
  val orient2d_arena_xy : t -> t -> t -> Predicates.sign
  val orient2d_arena_yz : t -> t -> t -> Predicates.sign
  val orient2d_arena_zx : t -> t -> t -> Predicates.sign
  val orient2d_reference_xy : t -> t -> t -> Predicates.sign
  val orient2d_reference_yz : t -> t -> t -> Predicates.sign
  val orient2d_reference_zx : t -> t -> t -> Predicates.sign
  val orient3d_arena_exact : t -> t -> t -> t -> Predicates.sign
  val orient3d_reference : t -> t -> t -> t -> Predicates.sign
  val radial_dot : t -> t -> t -> t -> Predicates.sign
  val radial_dot_arena_exact : t -> t -> t -> t -> Predicates.sign
  val radial_dot_reference : t -> t -> t -> t -> Predicates.sign
  val ray_edge :
    query:t -> first:t -> second:t -> dx:float -> dy:float -> dz:float ->
    Predicates.sign
  val ray_edge_reference :
    query:t -> first:t -> second:t -> dx:float -> dy:float -> dz:float ->
    Predicates.sign
  val ray_edge_symbolic :
    query:t -> first:t -> second:t -> Predicates.sign
  val ray_edge_symbolic_reference :
    query:t -> first:t -> second:t -> Predicates.sign
  val normal_dot_direction :
    t -> t -> t -> dx:float -> dy:float -> dz:float -> Predicates.sign
  val normal_dot_direction_reference :
    t -> t -> t -> dx:float -> dy:float -> dz:float -> Predicates.sign
  val normal_dot_symbolic : t -> t -> t -> Predicates.sign
  val normal_dot_symbolic_reference : t -> t -> t -> Predicates.sign
  type symbolic_ray_triangle =
    | Symbolic_miss
    | Symbolic_hit of Predicates.sign
    | Symbolic_origin_boundary
    | Symbolic_degenerate
  type axis_ray_triangle =
    | Axis_miss
    | Axis_hit of Predicates.sign
    | Axis_boundary
    | Axis_parallel
  val symbolic_ray_triangle :
    query:t -> first:t -> second:t -> third:t -> symbolic_ray_triangle
  val symbolic_ray_source_triangle :
    source -> a:int -> b:int -> c:int -> t -> symbolic_ray_triangle
  val axis_ray_source_triangle :
    source -> a:int -> b:int -> c:int -> axis:int -> positive:bool -> t ->
    axis_ray_triangle
  val barycentric : t -> t -> t -> t -> float * float * float
  val incircle_xy : t -> t -> t -> t -> Predicates.sign
  val incircle_yz : t -> t -> t -> t -> Predicates.sign
  val incircle_zx : t -> t -> t -> t -> Predicates.sign
  val incircle_reference_xy : t -> t -> t -> t -> Predicates.sign
  val incircle_reference_yz : t -> t -> t -> t -> Predicates.sign
  val incircle_reference_zx : t -> t -> t -> t -> Predicates.sign
end

module Constraints : sig
  type constraint_kind = Point | Segment
  type side = Left | Right
  type t
  val build :
    ?cancel:Cancel.t ->
    ?resolve_left_self_intersections:bool ->
    ?resolve_right_self_intersections:bool ->
    grain:int -> left:Geometry.t -> right:Geometry.t ->
    unit -> (t, Error.t) result
  val point_count : t -> int
  val approximate_point : t -> int -> float * float * float
  val constraint_count : t -> int
  val constraint_kind : t -> int -> constraint_kind
  val constraint_first : t -> int -> int
  val constraint_second : t -> int -> int
  val constraint_first_side : t -> int -> side
  val constraint_second_side : t -> int -> side
  val constraint_first_triangle : t -> int -> int
  val constraint_second_triangle : t -> int -> int
  val constraint_left_triangle : t -> int -> int
  val constraint_right_triangle : t -> int -> int
  val left_triangle_count : t -> int
  val right_triangle_count : t -> int
  val left_constraint_range : t -> int -> int * int
  val right_constraint_range : t -> int -> int * int
  val left_constraint : t -> int -> int
  val right_constraint : t -> int -> int
  val coplanar_pair_count : t -> int
  val coplanar_first_side : t -> int -> side
  val coplanar_second_side : t -> int -> side
  val coplanar_first_triangle : t -> int -> int
  val coplanar_second_triangle : t -> int -> int
  val coplanar_left_triangle : t -> int -> int
  val coplanar_right_triangle : t -> int -> int
  val degenerate_pair_count : t -> int
end

module Coplanar : sig
  type overlap_kind = Empty | Point | Segment | Polygon
  type t
  val build :
    ?cancel:Cancel.t -> grain:int -> Constraints.t -> (t, Error.t) result
  val pair_count : t -> int
  val first_side : t -> int -> Constraints.side
  val second_side : t -> int -> Constraints.side
  val first_triangle : t -> int -> int
  val second_triangle : t -> int -> int
  val left_triangle : t -> int -> int
  val right_triangle : t -> int -> int
  val kind : t -> int -> overlap_kind
  val point_count : t -> int -> int
  val approximate_point : t -> int -> int -> float * float * float
  val boundary_count : t -> int -> int
  val boundary_first : t -> int -> int -> int
  val boundary_second : t -> int -> int -> int
end

module Arrangement : sig
  type side = Left | Right
  type broad_phase = Sweep | Stable_bvh | Exact_oracle
  type t
  val build :
    ?cancel:Cancel.t -> ?coplanar:Coplanar.t ->
    ?broad_phase:broad_phase ->
    Constraints.t -> side:side -> triangle:int ->
    (t, Error.t) result
  val point_count : t -> int
  val approximate_point : t -> int -> float * float * float
  val segment_count : t -> int
  val segment_first : t -> int -> int
  val segment_second : t -> int -> int
end

module Triangulation : sig
  type t
  type point_location = Walk | Exact_scan
  type constraint_recovery = Trace | Edge_scan
  val build :
    ?cancel:Cancel.t -> ?point_location:point_location ->
    ?constraint_recovery:constraint_recovery ->
    Constraints.t -> Arrangement.t ->
    side:Arrangement.side -> triangle:int -> (t, Error.t) result
  val point_count : t -> int
  val approximate_point : t -> int -> float * float * float
  val triangle_count : t -> int
  val triangle_point : t -> int -> int -> int
  val constraint_count : t -> int
  val constraint_first : t -> int -> int
  val constraint_second : t -> int -> int
end

module Refinement : sig
  type t
  val build :
    ?cancel:Cancel.t -> ?coplanar:Coplanar.t ->
    grain:int -> Constraints.t -> (t, Error.t) result
  val left_face_count : t -> int
  val right_face_count : t -> int
  val left_face : t -> int -> Triangulation.t option
  val right_face : t -> int -> Triangulation.t option
  val refined_left_count : t -> int
  val refined_right_count : t -> int
end

module Coincident : sig
  type side = Left | Right
  type t
  val build :
    ?cancel:Cancel.t -> Constraints.t -> Coplanar.t -> Refinement.t ->
    (t, Error.t) result
  val group_count : t -> int
  val member_range : t -> int -> int * int
  val member_side : t -> int -> side
  val member_face : t -> int -> int
  val member_triangle : t -> int -> int
  val member_winding : t -> int -> int
end

module Complex : sig
  type side = Left | Right
  type t
  val build :
    ?cancel:Cancel.t -> Constraints.t -> Refinement.t -> (t, Error.t) result
  val vertex_count : t -> int
  val approximate_vertex : t -> int -> float * float * float
  val facet_count : t -> int
  val facet_vertex : t -> int -> int -> int
  val facet_member_range : t -> int -> int * int
  val member_side : t -> int -> side
  val member_face : t -> int -> int
  val member_triangle : t -> int -> int
  val member_winding : t -> int -> int
  val edge_count : t -> int
  val edge_first : t -> int -> int
  val edge_second : t -> int -> int
  val edge_incident_range : t -> int -> int * int
  val edge_incident_facet : t -> int -> int
  val edge_incident_local : t -> int -> int
end

module Radial : sig
  type t
  val build : ?cancel:Cancel.t -> Complex.t -> (t, Error.t) result
  val edge_count : t -> int
  val incident_range : t -> int -> int * int
  val incident_facet : t -> int -> int
  val incident_local : t -> int -> int
end

module Weiler : sig
  type side = Negative | Positive
  type t
  val build :
    ?cancel:Cancel.t -> Complex.t -> Radial.t -> (t, Error.t) result
  val half_facet_count : t -> int
  val half_facet : int -> side -> int
  val half_facet_facet : int -> int
  val half_facet_side : int -> side
  val neighbor : t -> half_facet:int -> local_edge:int -> int
  val shell_count : t -> int
  val half_facet_shell : t -> int -> int
  val facet_left_winding : t -> int -> int
  val facet_right_winding : t -> int -> int
end

module Cells : sig
  type t
  val build :
    ?cancel:Cancel.t -> ?axis_fast_path:bool -> ?component_index:bool ->
    ?track_left:bool -> ?track_right:bool ->
    Complex.t -> Weiler.t -> (t, Error.t) result
  val shell_count : t -> int
  val left_winding : t -> int -> int
  val right_winding : t -> int -> int
  val symbolic_seed_count : t -> int
end

module Extract : sig
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
  val primitive_side : ancestry -> int -> Complex.side
  val primitive_face : ancestry -> int -> int
  val primitive_triangle : ancestry -> int -> int
  val primitive_refined_triangle : ancestry -> int -> int
  val primitive_winding : ancestry -> int -> int
  val primitive_source_point : ancestry -> int -> int -> int
  val primitive_source_vertex : ancestry -> int -> int -> int
  val corner_barycentric : ancestry -> int -> int -> float * float * float
  val build_with_ancestry :
    ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
    expression:expression ->
    Complex.t -> Weiler.t -> Cells.t -> (ancestry, Error.t) result
  val build :
    ?cancel:Cancel.t -> ?require_closed:bool -> expression:expression ->
    Complex.t -> Weiler.t -> Cells.t -> (Geometry.t, Error.t) result
  module Private : sig
    val complex : ancestry -> Complex.t
    val point_complex_vertex : ancestry -> int -> int
    val primitive_complex_facet : ancestry -> int -> int
    val left_geometry : ancestry -> Geometry.t
    val right_geometry : ancestry -> Geometry.t
    val validate_positions :
      x:float array -> y:float array -> z:float array ->
      (unit, Error.t) result
    val validate_materialized :
      ?allow_degenerate:bool ->
      x:float array -> y:float array -> z:float array ->
      vertex_points:int array -> unit -> (unit, Error.t) result
    val coalesce_positions :
      complex_vertices:int array ->
      x:float array -> y:float array -> z:float array ->
      float array * float array * float array * int array * int array
    val validate_closed_topology : Topology.t -> (unit, Error.t) result
    val build_selected_with_ancestry :
      ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
      selection:bytes ->
      side:Complex.side -> Complex.t -> Weiler.t -> Cells.t ->
      (ancestry, Error.t) result
    val concatenate_ancestries :
      ?cancel:Cancel.t -> ancestry array -> (ancestry, Error.t) result
  end
end

module Seam : sig
  type kind = Left_self | Between | Right_self
  type t
  val build :
    ?cancel:Cancel.t -> ?grain:int -> ?parallel_cutoff:int ->
    Complex.t -> (t, Error.t) result
  val curves : t -> Geometry.t
  val coincident : t -> Geometry.t
  val curve_kind : t -> int -> kind
  val curve_edge_range : t -> int -> int * int
  val curve_edge : t -> int -> int
  module Private : sig
    val complex : t -> Complex.t
    val is_seam_edge : t -> int -> bool
    val verify_curves :
      ?cancel:Cancel.t -> grain:int -> Geometry.t -> (unit, Error.t) result
  end
end

module Materialization : sig
  (* Select extracted surface edges incident to an exact complex facet that
      touches a Boolean seam and whose once-rounded binary64 length does not
      exceed the explicit metric threshold. *)
  val tiny_seam_edges :
    ?cancel:Cancel.t -> grain:int -> threshold:float ->
    Extract.ancestry -> Seam.t -> (Edge_group.t, Error.t) result
  val surface_seam_edges :
    ?cancel:Cancel.t -> grain:int -> Extract.ancestry -> Seam.t ->
    (Edge_group.t, Error.t) result
  val safe_independent_edges :
    ?cancel:Cancel.t -> grain:int -> ?keep_greatest:bool ->
    Edge_group.t -> Geometry.t ->
    (Edge_group.t, Error.t) result
  (* Verify once-rounded triangles, optional closed incidence, and exact
      non-adjacent self-contact. *)
  val verify_surface :
    ?cancel:Cancel.t -> grain:int -> require_closed:bool ->
    ?allow_opposite_duplicates:bool -> Geometry.t ->
    (unit, Error.t) result
  type cleanup
  val cleanup_geometry : cleanup -> Geometry.t
  val cleanup_candidate_count : cleanup -> int
  val cleanup_collapsed_count : cleanup -> int
  val cleanup_batch_count : cleanup -> int
  val cleanup_remaining_candidate_count : cleanup -> int
  val cleanup_rounding_repaired_count : cleanup -> int
  val cleanup_point_source : cleanup -> int -> int
  val cleanup_vertex_source : cleanup -> int -> int
  val cleanup_primitive_source : cleanup -> int -> int
  val cleanup_seam_edges : cleanup -> Edge_group.t
  val collapse_tiny_seam_batch :
    ?cancel:Cancel.t -> grain:int -> threshold:float -> require_closed:bool ->
    ?allow_opposite_duplicates:bool ->
    Extract.ancestry -> Seam.t -> Geometry.t -> (cleanup, Error.t) result
  val collapse_tiny_seams :
    ?cancel:Cancel.t -> grain:int -> threshold:float -> require_closed:bool ->
    ?allow_opposite_duplicates:bool -> ?max_batches:int -> ?strict:bool ->
    Extract.ancestry -> Seam.t -> Geometry.t -> (cleanup, Error.t) result
  val split_seam_points :
    ?cancel:Cancel.t -> grain:int -> cleanup -> (cleanup, Error.t) result
  type detriangulation = All_polygons | Unchanged_polygons
  val detriangulate :
    ?cancel:Cancel.t -> grain:int -> assume_flat:bool ->
    mode:detriangulation -> Extract.ancestry -> cleanup ->
    (cleanup, Error.t) result
end

module Solid : sig
  type t
  type treatment = Solid | Surface
  type operation = Union | Intersection | Difference | Reverse_difference | Xor
  val prepare :
    ?cancel:Cancel.t ->
    ?resolve_left_self_intersections:bool ->
    ?resolve_right_self_intersections:bool ->
    ?left_treatment:treatment -> ?right_treatment:treatment ->
    grain:int -> left:Geometry.t -> right:Geometry.t ->
    unit -> (t, Error.t) result
  val extract :
    ?cancel:Cancel.t -> ?require_closed:bool ->
    expression:Extract.expression -> t -> (Geometry.t, Error.t) result
  val extract_with_ancestry :
    ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
    expression:Extract.expression -> t -> (Extract.ancestry, Error.t) result
  val extract_product :
    ?cancel:Cancel.t -> ?require_closed:bool -> operation:operation -> t ->
    (Geometry.t, Error.t) result
  val extract_product_with_ancestry :
    ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool ->
    operation:operation -> t ->
    (Extract.ancestry, Error.t) result
  val seams :
    ?cancel:Cancel.t -> ?grain:int -> ?parallel_cutoff:int ->
    t -> (Seam.t, Error.t) result
  val shatter_with_ancestry :
    ?cancel:Cancel.t -> ?require_closed:bool -> ?defer_rounded_slivers:bool -> t ->
    (Extract.ancestry array, Error.t) result
  val vertex_count : t -> int
  val facet_count : t -> int
  val shell_count : t -> int
end

module Payload : sig
  val copy_primitives :
    ?cancel:Cancel.t -> grain:int -> Extract.ancestry ->
    (Geometry.t, Error.t) result
  type point_conflict = Reject | Promote_to_vertex
  val copy_points_and_vertices :
    ?cancel:Cancel.t -> grain:int -> point_conflict:point_conflict ->
    point_tolerance:float ->
    Extract.ancestry -> Geometry.t -> (Geometry.t, Error.t) result
  (** Complete private Point/Vertex attribute and group transfer. Numeric point
      agreement uses the explicit finite non-negative metric tolerance;
      discrete values and group membership remain exact. Native edge groups
      use multi-member exact directed-edge ancestry. *)
end
