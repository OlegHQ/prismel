(** Eager target-independent geometry operations. Known-cardinality generators
    allocate packed output once; modifiers preserve immutable snapshots. *)

type sort_owner = Points | Primitives
type sort_key =
  | X | Y | Z
  | Distance_to of Prismel_math.Vec3.t
  | Along_vector of Prismel_math.Vec3.t
  | Attribute_component of { name : string; component : int }
  | By_vertex_order
  | By_primitive_index
  | Spatial_locality
  | Random of int64
  | Index_attribute of string
  | Reverse
  | Shift of int

type line_kind = Line_curve | Line_points

type scatter_density = {
  density_owner : Attribute.owner;
  density_attribute : string;
}

val scatter_density : owner:Attribute.owner -> string -> scatter_density
(** Select one scalar float density field with explicit ownership. Negative
    values have zero probability. *)

type deform_selection = Transform_ops.deform_selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t
(** Typed component selection. Deformations convert vertex and primitive
    membership to referenced points and edges to their endpoints. Operators
    that act on primitives, including Facet, promote points/vertices/edges to
    their incident primitives as documented at that operation. *)

type transform_order = Transform_ops.transform_order =
  | Transform_srt | Transform_str | Transform_rst
  | Transform_rts | Transform_tsr | Transform_trs
(** Application order for scale/shear ([s]), Euler rotation ([r]), and
    translation ([t]). For example, [Transform_srt] applies scale/shear,
    then rotation, then translation to column-vector points. *)

type transform_rotation_order = Transform_ops.transform_rotation_order =
  | Transform_xyz | Transform_xzy | Transform_yxz
  | Transform_yzx | Transform_zxy | Transform_zyx
(** Application order for Euler rotations, in radians. *)

type soft_transform_metric = Transform_ops.soft_transform_metric =
  | Soft_radius
  | Soft_edge
  | Soft_attribute of { attribute : string; apply_rolloff : bool }
(** Soft Transform distance source. Radius uses straight-line distance to the
    selected points; Edge uses shortest geometric edge-path distance.
    Attribute mode reads a point float field. With rolloff enabled it is a raw
    distance; otherwise it is the direct transform weight. *)

type soft_transform_falloff = Transform_ops.soft_transform_falloff =
  Soft_linear | Soft_quadratic | Soft_cubic

type distance_along_radius = Transform_ops.distance_along_radius =
  | Distance_fixed of float
  | Distance_maximum
(** Mask-normalization policy shared by distance-field operations. *)

type distance_from_geometry_reference = Transform_ops.distance_from_geometry_reference =
  | Distance_reference_points
  | Distance_reference_primitives
(** Reference feature family for {!distance_from_geometry}. *)

type distance_from_target_projection = Transform_ops.distance_from_target_projection =
  | Distance_target_spherical
  | Distance_target_cylindrical
  | Distance_target_planar
(** Analytic target used by {!distance_from_target}: a point, infinite axis,
    or infinite plane. *)

type distance_from_target_metric = Transform_ops.distance_from_target_metric =
  | Distance_target_absolute
  | Distance_target_signed
(** Planar distance policy. Signed distance is positive in the supplied normal
    direction and is rejected for non-planar targets. *)

type normal_weighting = Normal_ops.weighting =
  | Vertex_angle
  | Each_vertex
  | Face_area
(** Contribution policy for computed normals. [Vertex_angle] is resistant to
    triangulation changes, [Each_vertex] is the fastest equal-corner average,
    and [Face_area] gives larger polygons proportionally more influence. *)

type curvature_boundary = Analysis_ops.curvature_boundary =
  | Curvature_boundary_zero
  | Curvature_boundary_one_sided

type curvature_outputs = Analysis_ops.curvature_outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}

val default_curvature_outputs : curvature_outputs

type laplacian_weighting = Analysis_ops.laplacian_weighting =
  | Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform

type polyframe_style = Analysis_ops.polyframe_style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string
(** Coordinate-frame construction. The first four styles emit point fields;
    [Texture_uv_gradient] and [Attribute_gradient] emit
    discontinuity-preserving vertex fields. *)

val sort :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Group.t -> ?descending:bool ->
  ?output_indices:string -> ?combine_indices:bool ->
  owner:sort_owner -> key:sort_key -> Geometry.t -> (Geometry.t, Error.t) result
(** Stable point or primitive reorder. Restricted sorting permutes only the
    selected index slots. Point sorting remaps topology references and all
    point payloads/groups; primitive sorting remaps CSR spans and all vertex/
    primitive payloads/groups. Key preparation and output fills are parallel;
    stable comparison sorting is deterministic sequential work. [Random] uses
    an immutable seed and an allocation-free O(n) Fisher-Yates pass and rejects
    group restriction, matching the documented Sort limitation.

    [By_vertex_order] and [By_primitive_index] are point-only topology keys and
    place unconnected points first. [Spatial_locality] orders point positions or
    primitive centroids by stable scale-normalized 63-bit Morton code.

    [Index_attribute] applies a validated integer permutation. With
    [output_indices], geometry is not reordered; instead each source element
    receives its destination rank. [combine_indices] uses that pre-existing
    rank permutation as the stable input order for chained indirect sorts. *)

val points : (float * float * float) array -> Geometry.t

val line :
  ?cancel:Cancel.t -> ?grain:int -> ?kind:line_kind -> ?points:int ->
  origin:Prismel_math.Vec3.t -> direction:Prismel_math.Vec3.t -> length:float -> unit ->
  (Geometry.t, Error.t) result
(** Generate evenly spaced positions from [origin] in normalized [direction]
    through [length]. [Line_curve] creates one open polygon curve and requires
    at least two points; [Line_points] creates free points and requires at
    least one. Expected O(points) time/output with exact packed allocation and
    disjoint parallel fills. *)

val polyline :
  ?closed:bool -> (float * float * float) array -> (Geometry.t, Error.t) result

type circle_arc = Plane_generators.circle_arc =
  | Circle_closed
  | Circle_open_arc of { start_angle : float; end_angle : float }
  | Circle_closed_arc of { start_angle : float; end_angle : float }
  | Circle_sliced_arc of { start_angle : float; end_angle : float }

type circle_orientation = Plane_generators.circle_orientation =
  | Circle_xy
  | Circle_xz
  | Circle_yz
  | Circle_axes of {
      horizontal : Prismel_math.Vec3.t;
      vertical : Prismel_math.Vec3.t;
    }

val circle :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?arc:circle_arc ->
  ?orientation:circle_orientation ->
  ?reverse:bool ->
  ?center:Prismel_math.Vec3.t ->
  ?radius_x:float ->
  ?radius_y:float ->
  ?rotation:float ->
  ?uniform_scale:float ->
  ?segments:int -> radius:float -> unit -> (Geometry.t, Error.t) result
(** Generate an allocation-once polygon circle, ellipse, or arc. The compatible
    default is a closed XZ circle. Arc angles and [rotation] are radians.
    [Circle_open_arc] emits an open polygon curve; [Circle_closed_arc] adds the
    endpoint chord through closed topology; [Circle_sliced_arc] additionally
    appends the center to form a pie-slice boundary. PDK closed primitives do
    not repeat their first point.

    Standard or robust custom plane axes, center, independent radii, uniform
    scale, and traversal reversal are supported. Work and output storage are
    O(points); fixed point ranges fill disjoint packed planes exactly across
    domain counts. *)

type grid_counts = Plane_generators.grid_counts = Grid_divisions | Grid_point_counts

type grid_orientation = Plane_generators.grid_orientation =
  | Grid_xy
  | Grid_xz
  | Grid_yz
  | Grid_axes of {
      horizontal : Prismel_math.Vec3.t;
      vertical : Prismel_math.Vec3.t;
    }

type grid_connectivity = Plane_generators.grid_connectivity =
  | Grid_points
  | Grid_rows
  | Grid_columns
  | Grid_rows_and_columns
  | Grid_quads
  | Grid_triangles
  | Grid_alternating_triangles
  | Grid_reverse_triangles
type box_connectivity = Box_generator.box_connectivity =
  | Box_triangles
  | Box_quads
  | Box_surface_points
  | Box_lattice_points

type box_normals = Box_generator.box_normals = Box_no_normals | Box_point_normals | Box_vertex_normals

type box_rotation_order = Box_generator.box_rotation_order =
  | Box_xyz
  | Box_xzy
  | Box_yxz
  | Box_yzx
  | Box_zxy
  | Box_zyx

val box :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?connectivity:box_connectivity ->
  ?consolidate_points:bool ->
  ?normals:box_normals ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:box_rotation_order ->
  ?uniform_scale:float ->
  ?x_divisions:int ->
  ?y_divisions:int ->
  ?z_divisions:int ->
  ?uv_attribute:string ->
  ?face_groups:string ->
  size:Prismel_math.Vec3.t ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate an axis-divided box as triangles, quads, surface points, or a
    complete volume lattice. The compatibility default is the exact 24-point,
    12-triangle hard-normal box. [consolidate_points] welds every coincident
    surface boundary point. Unconsolidated point normals are face-hard; welded
    point normals are smooth corner/edge averages, while [Box_vertex_normals]
    remains face-hard for welded polygon output.

    Rotation components are radians and [box_rotation_order] names the order
    in which axis rotations are applied. Optional vertex UVs are normalized
    independently on each face. [face_groups] prefixes six primitive groups:
    [right], [left], [top], [bottom], [front], and [back].

    Cardinalities are preflighted. Exact position, normal, UV, index, and
    offset planes use disjoint stable ranges. Work/output are O(points +
    vertices + primitives); auxiliary error storage is O(parallel ranges). *)

type sphere_connectivity = Uv_sphere.sphere_connectivity =
  | Sphere_triangles
  | Sphere_alternating_triangles
  | Sphere_quads
  | Sphere_rows
  | Sphere_columns
  | Sphere_rows_and_columns
  | Sphere_points

type sphere_normals = Uv_sphere.sphere_normals =
  | Sphere_no_normals
  | Sphere_point_normals
  | Sphere_vertex_normals

type sphere_orientation = Uv_sphere.sphere_orientation =
  | Sphere_x
  | Sphere_y
  | Sphere_z
  | Sphere_axis of Prismel_math.Vec3.t

type sphere_rotation_order = Uv_sphere.sphere_rotation_order =
  | Sphere_xyz
  | Sphere_xzy
  | Sphere_yxz
  | Sphere_yzx
  | Sphere_zxy
  | Sphere_zyx

val uv_sphere :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?connectivity:sphere_connectivity ->
  ?unique_points_per_pole:bool ->
  ?triangular_poles:bool ->
  ?normals:sphere_normals ->
  ?orientation:sphere_orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:sphere_rotation_order ->
  ?uniform_scale:float ->
  ?radius_x:float ->
  ?radius_y:float ->
  ?radius_z:float ->
  ?uv_attribute:string ->
  ?segments:int ->
  ?rings:int ->
  radius:float ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate a latitude/longitude sphere or ellipsoid as regular/alternating
    triangles, quads, open row/column curves, combined curves, or points. The
    compatible default retains shared poles, triangles, +Y pole orientation,
    and smooth point normals. Quad poles may be triangles or logically
    degenerate quads; [unique_points_per_pole] gives every meridian its own
    coincident endpoint.

    Radius overrides name the local radial-X, pole-Y, and radial-Z axes before
    pole orientation and Euler rotation. [Sphere_axis] uses a deterministic
    scale-safe orthonormal frame. Rotation components are radians and the
    rotation-order constructor names their application order. Optional UVs
    are vertex-owned for topology and point-owned for point output, with a
    non-crossing surface seam.

    Cardinalities are checked before allocation. Positions, normals, UVs,
    topology, offsets, and kinds use exact packed planes and deterministic
    disjoint fills. Work/output are O(segments * rings); auxiliary storage is
    O(segments + rings + parallel ranges). *)

type torus_connectivity = Parametric_generators.torus_connectivity =
  | Torus_triangles
  | Torus_alternating_triangles
  | Torus_quads
  | Torus_rows
  | Torus_columns
  | Torus_rows_and_columns
  | Torus_points

type torus_normals = Parametric_generators.torus_normals =
  | Torus_no_normals
  | Torus_point_normals
  | Torus_vertex_normals

type torus_orientation = Parametric_generators.torus_orientation =
  | Torus_x
  | Torus_y
  | Torus_z
  | Torus_axis of Prismel_math.Vec3.t

type torus_rotation_order = Parametric_generators.torus_rotation_order =
  | Torus_xyz
  | Torus_xzy
  | Torus_yxz
  | Torus_yzx
  | Torus_zxy
  | Torus_zyx

val torus :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?connectivity:torus_connectivity ->
  ?normals:torus_normals ->
  ?orientation:torus_orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:torus_rotation_order ->
  ?uniform_scale:float ->
  ?u_start:float ->
  ?u_end:float ->
  ?v_start:float ->
  ?v_end:float ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?u_end_caps:bool ->
  ?v_end_cap:bool ->
  ?uv_attribute:string ->
  ?rows:int ->
  ?columns:int ->
  major_radius:float ->
  minor_radius:float ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate a polygon torus or partial toroidal patch. [rows] samples the
    major U sweep and [columns] samples the cross-section V sweep. Each axis
    can wrap independently; an open axis includes both requested angle
    endpoints. Connectivity can emit regular/checkerboard triangles, quads,
    U rows, V columns, both curve families, or free points.

    U end caps close the two cross-section boundaries of an open U sweep. A V
    end cap closes an open cross-section with a strip along the U sweep. Caps
    are available for polygon output and follow its triangle/quad policy,
    except each U cap is one polygon. Point normals remain the smooth toroidal
    field; vertex normals make caps hard. Optional UVs are seam-safe and
    vertex-owned for topology, or point-owned for free-point output.

    The compatible frame has its hole axis along +Y. Arbitrary scale-safe hole
    axes, center, positive uniform scale, and all six Euler orders are
    supported. Work/output are O(rows * columns); auxiliary storage is
    O(rows + columns + parallel ranges). Cardinality and all generated values
    are checked before publishing the immutable result. *)

type tube_connectivity = Parametric_generators.tube_connectivity =
  | Tube_triangles
  | Tube_alternating_triangles
  | Tube_quads
  | Tube_rows
  | Tube_columns
  | Tube_rows_and_columns
  | Tube_points

type tube_normals = Parametric_generators.tube_normals =
  | Tube_no_normals
  | Tube_point_normals
  | Tube_vertex_normals

type tube_orientation = Parametric_generators.tube_orientation =
  | Tube_x
  | Tube_y
  | Tube_z
  | Tube_axis of Prismel_math.Vec3.t

type tube_rotation_order = Parametric_generators.tube_rotation_order =
  | Tube_xyz
  | Tube_xzy
  | Tube_yxz
  | Tube_yzx
  | Tube_zxy
  | Tube_zyx

val tube :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?connectivity:tube_connectivity ->
  ?end_caps:bool ->
  ?consolidate_cap_points:bool ->
  ?normals:tube_normals ->
  ?orientation:tube_orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:tube_rotation_order ->
  ?radius_scale:float ->
  ?uv_attribute:string ->
  ?cap_group:string ->
  ?rows:int ->
  ?columns:int ->
  top_radius:float ->
  bottom_radius:float ->
  height:float ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate a cylinder, frustum, cone, or pyramid. [rows] counts samples
    along the primary axis and [columns] counts radial samples. A zero top or
    bottom radius creates one shared apex and side triangles without emitting
    degenerate faces. Connectivity supports regular/checkerboard triangles,
    quads with triangular apex bands, longitudinal rows, non-degenerate radial
    columns, both curve families, or free points.

    Polygon output may add non-zero end-cap polygons. Consolidated caps share
    side boundary points; unconsolidated caps own duplicate corner points.
    Smooth point normals retain side normals at consolidated rims, while
    vertex normals make caps hard. Optional topology UVs are vertex-owned and
    seam-safe; point output receives point UVs. [cap_group] selects every
    generated cap primitive.

    The compatible frame uses +Y as the primary axis. X/Y/Z or arbitrary
    scale-safe axes, center, three-axis Euler rotation, independent non-negative
    radii, positive radius scale, and positive height are supported. Work and
    output are O(rows * columns); auxiliary storage is O(rows + columns +
    parallel ranges). Cardinality, finite values, cancellation, and generated
    output are validated atomically. *)

type platonic_kind = Parametric_generators.platonic_kind =
  | Platonic_tetrahedron
  | Platonic_cube
  | Platonic_octahedron
  | Platonic_icosahedron
  | Platonic_dodecahedron
  | Platonic_soccer_ball

type platonic_normals = Parametric_generators.platonic_normals =
  | Platonic_no_normals
  | Platonic_point_normals
  | Platonic_vertex_normals

type platonic_orientation = Parametric_generators.platonic_orientation =
  | Platonic_x
  | Platonic_y
  | Platonic_z
  | Platonic_axis of Prismel_math.Vec3.t

type platonic_rotation_order = Parametric_generators.platonic_rotation_order =
  | Platonic_xyz
  | Platonic_xzy
  | Platonic_yxz
  | Platonic_yzx
  | Platonic_zxy
  | Platonic_zyx

val platonic :
  ?cancel:Cancel.t ->
  ?kind:platonic_kind ->
  ?normals:platonic_normals ->
  ?orientation:platonic_orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:platonic_rotation_order ->
  ?face_groups:string ->
  radius:float ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate a regular tetrahedron, cube, octahedron, icosahedron,
    dodecahedron, or truncated-icosahedron soccer ball. [radius] is the
    circumsphere radius. Every polygon retains its natural face arity; the
    soccer ball contains twelve pentagons followed by twenty hexagons and a
    primitive [Cd] field with black pentagons and white hexagons.

    Point normals are radial and vertex normals are hard per face. Optional
    face groups use the supplied prefix with [_triangles], [_quads],
    [_pentagons], or [_hexagons] for each arity present. The compatible frame
    uses +Y as its up axis; X/Y/Z or arbitrary scale-safe up axes, center, and
    every Euler rotation order are supported.

    All shapes have fixed bounded cardinality, so deliberately stay on the
    lower-overhead sequential path rather than dispatching domain work. Time,
    output, and auxiliary storage are O(1); cancellation and every generated
    value are validated before the immutable geometry is published. *)

type spiral_extent = Spiral.extent =
  | Spiral_turns of { turns : float; height : float }
  | Spiral_height_pitch of { height : float; pitch : float }

type spiral_radius = Spiral.radius =
  | Spiral_archimedean_change of {
      start_radius : float; increase_per_turn : float;
    }
  | Spiral_archimedean_end of { start_radius : float; end_radius : float }
  | Spiral_logarithmic_change of {
      start_radius : float; scale_per_turn : float;
    }
  | Spiral_logarithmic_end of { start_radius : float; end_radius : float }

type spiral_direction = Spiral.direction = Spiral_counterclockwise | Spiral_clockwise

type spiral_divisions = Spiral.divisions =
  | Spiral_divisions_per_curve of int
  | Spiral_divisions_per_turn of int

type spiral_orientation = Spiral.orientation =
  | Spiral_x
  | Spiral_y
  | Spiral_z
  | Spiral_axis of Prismel_math.Vec3.t

type spiral_rotation_order = Spiral.rotation_order =
  | Spiral_xyz
  | Spiral_xzy
  | Spiral_yxz
  | Spiral_yzx
  | Spiral_zxy
  | Spiral_zyx

val spiral :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?extent:spiral_extent ->
  ?radius:spiral_radius ->
  ?height_ramp:(float * float) list ->
  ?radius_scale:float ->
  ?radius_ramp:(float * float) list ->
  ?direction:spiral_direction ->
  ?start_angle:float ->
  ?divisions:spiral_divisions ->
  ?uniform_angle:bool ->
  ?spiral_count:int ->
  ?orientation:spiral_orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:spiral_rotation_order ->
  ?uniform_scale:float ->
  ?angle_attribute:string ->
  ?x_axis_attribute:string ->
  ?y_axis_attribute:string ->
  ?tangent_attribute:string ->
  ?orient_attribute:string ->
  ?distance_attribute:string ->
  unit ->
  (Geometry.t, Error.t) result
(** Generate one or more polygon spirals/helices. Extent is specified by
    explicit positive turns plus signed height, or signed height/pitch with a
    positive quotient. Radius is Archimedean (linear change) or logarithmic
    (geometric change), using either a per-turn control or explicit end radius.
    Piecewise-linear ramps scale height from the origin and radial distance.

    Divisions count curve segments: per-curve output has [divisions + 1]
    points, while per-turn mode rounds up fractional-turn coverage and includes
    the exact endpoint. [uniform_angle] uses equal angular increments; disabling
    it performs deterministic Gauss-integrated equal-arc-length placement.
    Multiple spirals are phase-distributed around one turn.

    Optional point attributes expose unwrapped angle, an orthonormal X/Y/
    tangent frame, its float4 quaternion orientation, and cumulative polygon
    distance. The compatible frame uses +Y as the central axis and supports
    scale-safe arbitrary axes plus all Euler orders.

    The angular path is O(points + output), with O(points + divisions)
    auxiliary/output storage. Equal-arc placement is O(points * log divisions)
    with O(divisions) scratch. Dense independent fills use stable disjoint
    ranges; cumulative distances use fixed blocks so one- and multi-domain
    results are byte-identical. *)

val merge : ?cancel:Cancel.t -> ?grain:int -> Geometry.t list ->
  (Geometry.t, Error.t) result
(** Concatenate geometry in input order. Attribute, ordinary-group, and native
    edge-group schemas must
    match exactly. Detail attributes are rejected because their merge policy
    would otherwise be ambiguous. O(total payload). *)

type fuse_position = Fuse_reduce.position =
  | First_position
  | Least_point_position
  | Greatest_point_position
  | Average_position
  | Minimum_position
  | Maximum_position
  | Mode_position
  | Median_position
  | Sum_position
  | Sum_squares_position
  | Root_mean_square_position
  | Weighted_average_position
  | Weighted_sum_position
  | Minimum_weight_position
  | Maximum_weight_position
type fuse_attributes = Fuse_reduce.attributes = Keep_first | Average_numeric
type fuse_attribute_method = Fuse_reduce.attribute_method =
  | Attribute_average
  | Attribute_least_point
  | Attribute_greatest_point
  | Attribute_maximum
  | Attribute_minimum
  | Attribute_mode
  | Attribute_median
  | Attribute_sum
  | Attribute_sum_squares
  | Attribute_root_mean_square
  | Attribute_concatenate
  | Attribute_weighted_average
  | Attribute_weighted_sum
  | Attribute_minimum_weight
  | Attribute_maximum_weight
  | Attribute_concatenate_weight_order
type fuse_attribute_rule = Fuse_reduce.attribute_rule = {
  pattern : string;
  method_ : fuse_attribute_method;
  weight_attribute : string option;
}
type fuse_group_method = Fuse_reduce.group_method =
  | Group_least_point
  | Group_greatest_point
  | Group_union
  | Group_intersection
  | Group_most_common
type fuse_group_rule = Fuse_reduce.group_rule = {
  group_pattern : string;
  group_method : fuse_group_method;
}
(* One Houdini-style point-attribute pattern and reduction. Later matching
    rules override earlier rules. Weighted methods require a finite scalar
    point float/integer weight field. *)
val fuse_attribute_rule :
  ?weight_attribute:string -> pattern:string -> fuse_attribute_method ->
  fuse_attribute_rule

(* One point-group name pattern and propagation policy. Later matching rules
    override earlier rules. *)
val fuse_group_rule : pattern:string -> fuse_group_method -> fuse_group_rule
type fuse_metric = Fuse_grid.fuse_metric = Euclidean | Componentwise
type fuse_using = Fuse_grid.fuse_using =
  | Least_target_point
  | Closest_target_point
type fuse_match_condition = Fuse_grid.fuse_match_condition =
  | Equal_attribute_values
  | Unequal_attribute_values
type fuse_targeting = Fuse_grid.fuse_targeting =
  | Near_points
  | Specified_points of string

val fuse :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Group.t ->
  ?target_selection:Group.t ->
  ?targeting:fuse_targeting ->
  ?using:fuse_using ->
  ?tolerance:float ->
  ?position:fuse_position ->
  ?weight_attribute:string ->
  ?attributes:fuse_attributes ->
  ?metric:fuse_metric ->
  ?inclusive:bool ->
  ?attribute_rules:fuse_attribute_rule list ->
  ?group_rules:fuse_group_rule list ->
  ?match_attributes:bool ->
  ?radius_attribute:string ->
  ?match_attribute:string ->
  ?match_condition:fuse_match_condition ->
  ?match_tolerance:float ->
  ?modify_target:bool ->
  ?fuse_points:bool ->
  ?keep_fused_points:bool ->
  ?snapped_group:string ->
  ?snapped_destination_attribute:string ->
  ?remove_degenerate_primitives:bool ->
  ?remove_unused_points_from_degenerate_primitives:bool ->
  ?remove_all_unused_points:bool ->
  ?target:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Consolidate selected points whose distance is at most [tolerance] into
    deterministic earliest-representative clusters; unselected points are
    preserved and cannot become implicit targets. Zero selects exact position
    matching. The earliest
    source index names each cluster. Topology
    point references are remapped without changing corner/primitive order.
    [First_position] and [Least_point_position] retain the lowest member;
    [Greatest_point_position] retains the highest. Average, component-wise
    minimum/maximum/mode/upper-median/sum/sum-of-squares/RMS, weighted
    average/sum, and minimum/maximum-weight selection are also available.
    Weighted modes require a finite scalar point float/integer
    [weight_attribute]; a zero weighted-average denominator and every
    non-finite result are errors. Mode ties retain the value whose first source
    point is lowest. Point groups use union semantics; integer/text attributes
    retain the first value, while float tuple attributes may be averaged
    explicitly. Set
    [match_attributes] to prevent consolidation across point-attribute seams.
    [metric] and [inclusive] make distance-boundary policy explicit.

    [attribute_rules] override the legacy coarse [attributes] policy for
    matching point fields. Rules are evaluated in order and the last matching
    pattern wins. A weight name on an unweighted method is ignored; weighted
    methods require and validate it. Scalar and float2/3/4 numerical fields support the
    documented numeric/statistical/weighted methods; scalar integer results
    retain integer storage with checked arithmetic. Text supports stable
    least/greatest, lexical min/max/mode/upper-median, and concatenation.
    Scalar numeric concatenation becomes packed CSR array storage, and existing
    integer/float array rows concatenate without intermediate lists. Tuple
    concatenation is rejected until PDK has a width-preserving tuple-array
    representation. [group_rules] implement least/greatest, union,
    intersection, and strict-majority membership. Ordered group ancestry is
    stable.

    Supplying [target], [target_selection], or an advanced targeting/output
    option enables fixed-target snapping. Query and target point groups are
    independent; an omitted same-geometry target group reuses [selection].
    Near-point targeting chooses either the lowest eligible target number or
    the closest target with lowest-number ties. Optional non-negative point
    radii expand the threshold on both inputs, while a scalar float/integer/
    text match attribute accepts equal or unequal values (float equality uses
    [match_tolerance]). [Specified_points] reads a query point integer target
    number and ignores invalid or excluded destinations.

    With fixed targets, matching point payload is copied from the selected
    target before optional consolidation; target-only matching groups are
    created on the query output. Weighted rules resolve their weight on target
    geometry. With one input and no explicit target group, behavior is Modify
    Target as in Fuse 2.0. Generated snapped metadata is committed after rule
    evaluation and cannot be captured accidentally by wildcard rules.

    [modify_target] is available only with the same geometry on both sides and
    reduces positions and point payload over each deterministic query/target
    link component. Advanced mode can retain topology with
    [fuse_points=false], emit a point
    group for every mapped query, and emit the chosen target point number or
    [-1]. When fusing, mapped queries that share an output position are
    consolidated; same-geometry destination points participate as fixed
    targets. [keep_fused_points] rewires topology exactly as normal fusion but
    retains every point record, assigning every component member its reduced
    position and point payload. Position changes invalidate point/vertex [N].

    [remove_degenerate_primitives] removes consecutive repeated point
    references (including the closed seam), then deletes polygons and closed
    curves below three vertices and open curves below two. The associated
    unused-point option removes only points that became unused by that pass,
    preserving points that were already unused; [remove_all_unused_points]
    compacts every topology-unused point. Vertex/primitive attributes, ordered
    groups, and native edge groups follow stable source ancestry.

    Expected O(query points + target points + candidates + payload) time and
    O(query points + target points) auxiliary storage; the worst case is
    quadratic when all eligible targets occupy neighboring cells. Stable
    candidate reduction and cluster-member order make one- and multi-domain
    results byte-identical. Position/group reductions and cleanup are linear
    in input plus output payload except exact mode/median reductions, which are
    O(points log points) time within clusters. *)

val edge_collapse :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?connectivity_attribute:string ->
  ?position:fuse_position ->
  ?remove_degenerate_primitives:bool ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Collapse each connected component of selected topology edges. The default
    uses its arithmetic center; [position] selects another Fuse reduction.
    An omitted edge group selects all
    edges. [connectivity_attribute] names a point field whose exact value
    boundaries prevent selected edges from joining collapse components.

    Point payload and groups retain the stable lowest-numbered component
    member, while vertex, primitive, detail, ordered-group, and native-edge
    ancestry use the shared Fuse rewiring and cleanup kernel. Degenerate
    polygons and curves are removed by default, along with points newly
    orphaned by that cleanup. Existing point normals are recomputed by default;
    no point-normal field is invented when the input has none.

    Component planning is O(points + edges) time/storage. Packed point
    reduction, topology/payload remapping, cleanup, and optional normals are
    linear in the affected geometry and use deterministic disjoint ranges in
    the reusable domain pool. *)

type dissolve_operation = Dissolve_selected | Dissolve_non_selected
type dissolve_bridge_policy =
  | Create_bridged_polygons
  | Create_disjoint_polygons
  | Delete_bridge_polygons

val dissolve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?operation:dissolve_operation ->
  ?bridge_policy:dissolve_bridge_policy ->
  ?remove_inline_points:bool ->
  ?collinearity_tolerance:float ->
  ?remove_unused_points:bool ->
  ?create_boundary_curves:bool ->
  ?recompute_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Remove selected polygon edges and merge their consistently wound incident
    faces. An omitted group with [Dissolve_selected] is an identity; with
    [Dissolve_non_selected] it selects every polygon edge. Curve edges are
    ignored, and selected non-manifold edges fail atomically.

    A disk-like component emits one polygon. Multiple closed boundary loops
    may be emitted independently, deleted, or reconnected by a selected source
    bridge edge. Selecting a surface-boundary edge deletes its incident merged
    component unless [create_boundary_curves] is enabled, in which case each
    remaining boundary run becomes a polygon curve. Optional inline cleanup
    removes only selected-edge points within a radian angular tolerance;
    unused point compaction and existing-normal recomputation are explicit.

    Point/detail payload is structurally shared until optional compaction.
    Vertex/primitive payload and every ordinary/native-edge group follow exact
    stable source ancestry. Planning is O(points + vertices + primitives +
    edges + output); bridge-loop reconnection is linear per selected-edge scan
    for the uncommon multi-loop case. Packed payload remaps and normal fills
    use stable disjoint parallel ranges. *)

type poly_reduce_target = Poly_reduce.target =
  | Reduce_ratio of float
  | Reduce_primitive_count of int

val edge_flip :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?cycles:int ->
  ?cycle_vertex_attributes:bool ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Rotate each selected manifold polygon edge around the joined boundary.
    One cycle advances the first endpoint by one boundary point while
    preserving both incident polygon cardinalities. An omitted edge group is
    an intentional no-op. Selected effective edges must have two oppositely
    oriented polygon incidences and may not share an incident primitive;
    sequence dependent edits belong in separate calls.

    Vertex attributes and vertex groups rotate with their incident polygon by
    default; set [cycle_vertex_attributes] to [false] to keep payload in its
    original vertex slots. Native edge groups preserve source point-pair
    ancestry, with the replacement diagonal inheriting the selected edge's
    membership. Point and vertex normals are invalidated; an existing point
    normal is rebuilt only when [recompute_point_normals] is true.

    Planning and validation are O(edges + selected boundary vertices); packed
    topology and payload remapping are linear in geometry size. Disjoint
    selected pairs fill deterministic output ranges through the reusable
    domain pool. *)

 type grid_rounding = Fuse_grid.grid_rounding = Grid_nearest | Grid_down | Grid_up

val snap_to_grid :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Group.t ->
  ?spacing:Prismel_math.Vec3.t ->
  ?offset:Prismel_math.Vec3.t ->
  ?rounding:grid_rounding ->
  ?max_distance:float ->
  ?fuse_points:bool ->
  ?position:fuse_position ->
  ?weight_attribute:string ->
  ?attributes:fuse_attributes ->
  ?attribute_rules:fuse_attribute_rule list ->
  ?group_rules:fuse_group_rule list ->
  ?snapped_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Snap selected point positions to an axis-aligned grid. [spacing] is a
    strictly positive per-axis world spacing and [offset] is a finite
    per-axis fraction of that spacing. An optional [max_distance] rejects a
    move by its Euclidean world distance. [fuse_points] consolidates selected
    points that land at the same grid position through the shared Fuse kernel;
    weighted position policies use the scalar point [weight_attribute].
    unrelated points never become implicit targets. Position changes remove
    stale point/vertex normals, and [snapped_group] records moved output points.

    Work is O(points + payload) expected and auxiliary storage is O(points)
    only when fusion is requested; snap-only output owns three exact position
    planes plus one packed transient change bit per point. Point ranges are
    disjoint and byte-identical across domain counts. *)

val poly_reduce :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?target:poly_reduce_target ->
  ?primitives:Group.t ->
  ?hard_points:Group.t ->
  ?hard_edges:Edge_group.t ->
  ?preserve_boundary:bool ->
  ?only_original_positions:bool ->
  ?equalize_lengths:float ->
  ?max_normal_deviation:float ->
  ?output_group:string ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Adaptively reduce polygon surfaces through deterministic batches of
    one-ring-independent quadric-error edge contractions. Non-triangle
    polygons are robustly triangulated first. [Reduce_ratio] targets a
    fraction of that working polygon count; [Reduce_primitive_count] supplies
    an absolute output target. Constraints may stop above the requested count.

    Primitive selection locks its interface to unselected geometry. Hard
    points and hard-edge endpoints never move; [preserve_boundary] likewise
    locks all unshared-edge points. Every contraction satisfies the manifold
    link condition, rejects collapsed or flipped surviving triangles, and may
    additionally limit normal deviation. [only_original_positions] contracts
    to the lower-numbered endpoint; otherwise it uses the midpoint. Existing
    payload and groups follow the shared Fuse ancestry kernel, and
    [output_group] marks surviving operated polygons.

    Each round is O(points + primitives + edges log edges + payload) time and
    O(points + edges) auxiliary storage. Quadric construction, edge scoring,
    packed contraction/remapping, and optional normal generation use stable
    disjoint ranges; cost ordering and independent-set selection are
    deterministic across domain counts. *)

type clip_keep = Plane_clip.keep = Above | Below | All

val clip :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?keep:clip_keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:deform_selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  origin:Prismel_math.Vec3.t ->
  normal:Prismel_math.Vec3.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Clip polygons and polygon curves against an arbitrary plane. [clip_attribute]
    defaults to canonical [P]; scalar and fixed-width numeric point attributes
    use their first three components and zero-fill missing components. [distance]
    translates the plane along its normalized normal. [All] emits
    both sides in stable above/below order; optional split connectivity gives
    each side distinct plane points. Numeric point/vertex attributes are
    interpolated, integer/text values use the nearest endpoint, existing
    ordinary/native edge groups are remapped, and optional clipped-edge and
    primitive output groups are materialized. A clipped edge has both endpoints
    on the effective clipping plane after tolerance snapping.

    [selection] promotes point, vertex, primitive, or native-edge membership to
    incident primitives. Unselected primitives pass through in source order;
    shared selected/unselected points receive isolated tokens so snapping and
    connectivity splitting cannot mutate the unselected topology. Selected
    standalone points are clipped only for a point-owned selection.

    Output groups replace same-owner groups by default. With
    [replace_existing_groups=false], generated membership is unioned into each
    existing same-named primitive or native-edge group.

    [fill] traces manifold intersection loops, shares their boundary points to
    keep the result watertight, and emits hard vertex normals at cap seams.
    Concave polygon intersections are reconstructed from ordered plane spans
    and may emit multiple independent fragments with exact payload ancestry.
    Directed, oppositely wound nested contours become holes; same-winding
    nested solids remain independent caps, and alternating nesting preserves
    interior islands. Hole caps are deterministically visibility-bridged and
    emitted as triangles because one PDK polygon has no implicit hole contour.
    Open, non-manifold, inconsistently wound, intersecting, or unbridgeable cap
    boundaries return structured errors instead of invalid topology.

    The variable output uses geometric-growth buffers. Expected ordinary work
    is O(points + vertices + payload + cap validation); a polygon with [k]
    clipping intersections uses O(k log k) time and O(k) scratch only when it
    has multiple retained boundary runs. Cap-contour intersection validation
    uses an X-interval sweep in O(c log c + i) expected time for [i] active
    bounding-box candidates, with O(c^2) worst case. For [c] total vertices and
    [h] holes in one nested contour component, deterministic visibility
    bridging and ear clipping use O(h*c^2 + (c + 2h)^2) worst-case time and
    O(c + h) scratch. Two or more sufficiently large independent nested
    components triangulate into disjoint result slots through the shared domain
    pool; topology-dependent work within one component remains sequential.
    Polygon-only unfilled cooks use an exact-sized parallel count/prefix/fill
    plan; curves, caps, repeated-corner polygons, and disconnected concave
    fragments use the general geometric-growth builder. *)

val clip_transform :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?keep:clip_keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:deform_selection ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  ?local_normal:Prismel_math.Vec3.t ->
  transform:Prismel_math.Mat4.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transform-orientation convenience for [clip]. The transformed local origin
    defines the plane origin and the transformed [local_normal] (default +Y)
    defines its direction. Translation, rotation, and scale therefore compose
    through one matrix while [distance] remains measured after normalization. *)

type subdivision_scheme = Subdivision_ops.scheme = Catmull_clark | Loop | Bilinear
type subdivision_boundary_interpolation = Subdivision_ops.boundary_interpolation =
  | Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type subdivision_face_varying_interpolation = Subdivision_ops.face_varying_interpolation =
  | Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type subdivision_triangle_policy = Subdivision_ops.triangle_policy =
  | Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type subdivision_creasing_method = Subdivision_ops.creasing_method =
  | Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type subdivision_crack_policy = Subdivision_ops.crack_policy =
  | Subdivide_do_not_close
  | Subdivide_pull_no_edge_division
  | Subdivide_pull_divide_edges of float
  | Subdivide_pull_triangulate of float
  | Subdivide_stitch_no_edge_division
  | Subdivide_stitch_divide_edges
  | Subdivide_stitch_triangulate

 val subdivide :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?scheme:subdivision_scheme ->
  ?iterations:int ->
  ?primitives:Group.t ->
  ?cracks:subdivision_crack_policy ->
  ?consistent_topology:bool ->
  ?creases:Geometry.t ->
  ?crease_primitives:Group.t ->
  ?crease_weight:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group:string ->
  ?hole_primitives:Group.t ->
  ?remove_holes:bool ->
  ?boundary_interpolation:subdivision_boundary_interpolation ->
  ?face_varying_interpolation:subdivision_face_varying_interpolation ->
  ?triangle_policy:subdivision_triangle_policy ->
  ?creasing_method:subdivision_creasing_method ->
  ?treat_curves_as_independent:bool ->
  ?recompute_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Refine polygon surfaces and open/closed polygon curves with Catmull-Clark
    (the default) or bilinear subdivision; Loop accepts triangle surfaces
    only. Catmull-Clark and bilinear surface refinement emit native quads and
    share edge points.

    Numeric point attributes follow the position stencils. Vertex attributes
    are refined face-varying so discontinuous UV/color seams remain
    discontinuous. Primitive attributes/groups propagate to every child;
    point and vertex groups retain original members and include a new edge or
    face value only when all of its local parents are members. Integer/text
    values use stable representatives. Point [N] follows the same numeric
    stencil as [P] by default, without implicit normalization; vertex [N]
    follows the selected face-varying policy. With
    [recompute_point_normals=true], an existing input point [N] is instead
    replaced after the complete cook by normalized area-weighted point
    normals, and any vertex [N] is removed. The option does not create [N]
    when the input had no point-owned [N].

    One iteration is O(points + edges + vertices + attribute payload) time and
    auxiliary/output storage. Stable packed payload ranges are parallelized;
    topology planning remains deterministic and sequential.

    Polygon curves retain their primitive kind and insert one midpoint per
    segment. Bilinear leaves old points fixed. Catmull-Clark pins open
    endpoints and shared-graph points whose unique-edge degree is not two;
    degree-two points use the cubic [1/8, 3/4, 1/8] neighbor stencil. Numeric
    point fields use the same rule, vertex fields are linearly interpolated,
    discrete fields use stable representatives, and source native edges map to
    both children. By default, curves sharing point identities also share old
    points and edge midpoints. [treat_curves_as_independent=true] implements
    Houdini's option by treating every curve corner as its own point, including
    coincident/shared source corners; this also pins each open-curve endpoint.
    Curve topology and stencil planes are cardinality-exact, recursive, and
    filled in deterministic disjoint ranges. Mixed polygon/curve inputs are
    partitioned by primitive family, refined through these two packed planners,
    and restored to stable source-primitive order. Local curve selection splits
    point identity only across the selected/unselected boundary. Free points
    survive exactly once.

    [primitives] locally refines a primitive subset. The selected region is
    compacted and evaluated with its own adjacency, unselected polygons and
    free points pass through, and only points shared across the selection
    boundary are duplicated. [Subdivide_do_not_close] leaves refined and coarse
    boundary edges unwelded. [Subdivide_pull_no_edge_division] projects every
    refined interface point onto its exact original coarse edge, or their
    shared endpoint at corners, without splitting or welding the surrounding
    polygon. [Subdivide_pull_divide_edges bias] splits the surrounding edge
    into the exact descendant count, explicitly welds corresponding points,
    and places the joined chain between the coarse and refined positions;
    [bias] must be finite and in [[0, 1]].
    [Subdivide_pull_triangulate bias] applies the same split, weld, and bias,
    then triangulates every surrounding polygon incident to the interface.
    [Subdivide_stitch_no_edge_division] inserts a deterministic triangle strip
    between every refined chain and its unsplit coarse edge, sharing both
    sides' existing points. [Subdivide_stitch_divide_edges] splits the coarse
    edge and inserts a conforming two-triangle strip per descendant edge.
    [Subdivide_stitch_triangulate] additionally triangulates every surrounding
    polygon incident to the interface.
    [consistent_topology] defaults to [false]. When enabled, crack closing
    ignores geometric coincidence/collinearity when choosing topology:
    Stitch retains every topology-prescribed strip triangle and Triangulate
    uses a stable source-corner fan. This keeps point/vertex/primitive counts
    and connectivity invariant under position-only deformation; transition
    triangles may consequently be zero-area at coincident chains.

    [creases] is a second topology input. Its selected polygon/polyline edges
    match source edges solely by point number; its positions are ignored.
    [crease_primitives] restricts that input with a primitive group.
    With a second input, [crease_weight] explicitly overrides every matching
    edge. Without a second input, it overrides every edge in the subdivided
    surface, including only the selected compact surface during local
    refinement. Without an override, vertex and primitive [creaseweight]
    fields on [creases] are combined by maximum; attribute-driven inputs must
    have topology identical to the source. Override values replace, rather
    than add to, existing source edge weights. Unmatched subset edges are
    ignored. The no-input scalar enters the first packed crease plan directly;
    it does not synthesize a per-corner attribute.
    [generate_resulting_creases] defaults to [true] and emits positive
    per-level residual [creaseweight]/[cornerweight] fields. An optional
    [resulting_crease_group] names a native edge group containing exactly the
    residual crease edges; it requires result generation.
    [hole_primitives], or the source primitive group named
    [subdivision_hole] when omitted, marks faces which participate in every
    point/edge/face stencil but whose descendants are omitted from the final
    topology when [remove_holes] is [true] (the default). Recursive refinement
    retains the hole faces internally until its final level.
    [boundary_interpolation] defaults to [Subdivide_boundary_edge_only], the
    historical Prismel boundary curve. [Subdivide_boundary_edge_and_corner]
    additionally pins boundary vertices with exactly one incident face.
    [Subdivide_boundary_none] follows OpenSubdiv by marking every face incident
    to an unsharpened topology boundary as a hole; because PDK sharpness is
    finite, every topology boundary qualifies. Bilinear refinement is
    unaffected, matching OpenSubdiv's zero-neighborhood scheme behavior.
    [face_varying_interpolation] defaults to [Subdivide_fvar_all], preserving
    Prismel's historical bilinear face-local vertex-attribute interpolation.
    The other five OpenSubdiv modes progressively smooth continuous floating
    vertex attributes while preserving exact-value seams: None smooths every
    smooth region; Corners Only pins one-face regions; Corners Plus 1 also pins
    junctions of three or more regions; Corners Plus 2 additionally pins darts
    and both sides of concave corners; Boundaries linearly constrains every
    region boundary. Geometry boundary and semi-sharp crease rules take
    precedence. Bilinear subdivision remains linear for every mode.
    [triangle_policy] defaults to [Subdivide_triangles_catmull_clark]. Smooth
    Triangles applies OpenSubdiv's alternate Catmull-Clark edge mask when one
    or both incident faces are triangles. It affects Catmull-Clark point and
    smoothly interpolated face-varying fields; Loop, bilinear, boundary, and
    fully sharp edge rules are unchanged.
    [creasing_method] defaults to [Subdivide_creasing_uniform], which subtracts
    one from both child edges. Chaikin computes each endpoint child's value as
    three quarters of its parent sharpness plus one quarter of the mean of the
    other finite positive crease edges incident to that endpoint, then
    subtracts one. Smooth edges do not enter the mean. Corner sharpness still
    uses uniform per-level decay.
    Houdini/OpenSubdiv detail controls on the source override the corresponding
    explicit arguments once per complete cook. [osd_scheme] accepts integer
    [0]/[1]/[2] or text ["catmull-clark"]/["loop"]/["bilinear"]. Integer
    [osd_vtxboundaryinterpolation] maps [0..2] to None/Edge Only/Edge and
    Corner; [osd_fvarlinearinterpolation] maps [0..5] in constructor order;
    [osd_creasingmethod] maps [0]/[1] to Uniform/Chaikin; and
    [osd_trianglesubdiv] maps [0]/[1] to Catmull-Clark/Smooth. Controls remain
    ordinary propagated detail attributes. Wrong storage, unknown tokens, and
    out-of-range values fail atomically instead of falling back silently.
    Generated bridge spokes are excluded from native edge groups. Empty
    selection and zero iterations preserve object identity;
    full selection uses the whole-mesh path byte-for-byte. *)

type poly_fill_mode =
  | Fill_single_polygon
  | Fill_triangles
  | Fill_triangle_fan

val normals :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?owner:Attribute.owner ->
  ?weighting:normal_weighting ->
  ?cusp_angle:float ->
  ?keep_original_zero:bool ->
  ?reverse:bool ->
  ?attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Compute unit normals without changing topology. [owner] defaults to
    points and may also be vertex, primitive, or detail. [weighting] defaults
    to the compatibility [Face_area] policy; [cusp_angle] is in radians and is
    used for vertex normals. Typed point, vertex, primitive, or native-edge
    selections are promoted to the output owner. When an output field exists,
    unselected values remain exact. When it does not exist, point/primitive/
    detail computation follows Houdini by computing all relevant elements;
    vertex computation initializes a completely smooth field before replacing
    the selected vertices with the requested cusp result.

    [keep_original_zero] retains an existing selected value when geometry can
    only produce zero; [reverse] negates computed selected values. [attribute]
    defaults to [N] and replaces same-named fields on other owners to keep one
    unambiguous normal source. Curves, degenerate faces, and isolated points
    contribute zero. Non-finite surface geometry fails atomically.

    Point, primitive, detail, and fully smooth vertex modes are O(points +
    vertices + primitives). Cusped vertex mode is O(vertices + sum point
    incidence squared). Packed face/output planes are linear; face and output
    ranges run in deterministic disjoint parallel blocks. *)

val measure_curvature :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?boundary:curvature_boundary ->
  ?smoothing_iterations:int ->
  ?smoothing_strength:float ->
  ?outputs:curvature_outputs ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Estimate point surface curvature with the mixed Voronoi-area and cotangent
    operators of Meyer et al. Mean curvature is signed by the consistently
    wound area-weighted point normal; Gaussian curvature uses angle defect.
    Principal minimum/maximum values, curvedness, and shape index derive from
    the requested mean/Gaussian field pair. Output names are independently
    optional through [curvature_outputs]; [default_curvature_outputs] writes
    signed mean curvature to [curvature]. Existing point-float values outside
    [points] remain exact.

    [Curvature_boundary_zero] pins open-surface boundary values to zero.
    [Curvature_boundary_one_sided] uses the one-sided [pi - angle_sum] defect.
    Optional synchronous uniform-neighbor smoothing applies to the fundamental
    mean and Gaussian fields before derived values and remains deterministic
    across domain counts.

    Input must be a finite, consistently wound polygon-only 2-manifold with
    representable non-degenerate triangulation. Repeated corners, non-manifold
    edges or points, disconnected point fans, inconsistent winding, malformed
    selections/outputs, and non-finite results fail atomically. Polygon faces
    are triangulated in stable concave-safe order without changing topology.

    Time is O(points + vertices + primitives + triangles + smoothing_steps *
    edges + output_fields * points); auxiliary storage is O(points + triangles
    + triangle incidences). Polygon triangulation, triangle metrics, point
    reductions, smoothing, and output fills use deterministic disjoint ranges.
    Stable point-to-triangle CSR reduction order makes one- and multi-domain
    results bit-identical. *)

val attribute_laplacian :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?weighting:laplacian_weighting ->
  ?normalize:bool ->
  source:string ->
  ?output:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Apply a discrete surface Laplacian to a point-owned scalar, integer,
    float2, float3, or float4 field. Canonical [P] is also accepted as a
    read-only float3 source. The default output is [<source>_laplacian], or
    [laplacian] for [P]. Existing compatible output values outside [points]
    remain bit-identical.

    [Laplacian_cotan] uses signed cotangent weights and is the default.
    [Laplacian_positive_cotan] clamps negative per-triangle contributions to
    enforce non-negative neighbor influence at the cost of linear precision.
    [Laplacian_uniform] uses the topology-edge graph. With [normalize=true],
    cotangent output is divided by Meyer mixed area in world units and uniform
    output is divided by valence; with [false], both return their integrated
    weighted sums. The sign convention is neighbor minus center, suitable for
    adding a small positive multiple to smooth a field.

    The input must be a consistently wound polygon-only 2-manifold. Cotangent
    modes additionally require finite positions and representable non-degenerate
    stable polygon triangulation. Time and auxiliary storage are linear in
    points, corners, primitives, internal triangles, source width, and topology
    edges. Metric preparation and point/component output use deterministic
    disjoint ranges; stable incidence order makes domain count irrelevant. *)

val polyframe :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:deform_selection ->
  ?orthogonal:bool -> ?left_handed:bool -> ?normal_attribute:string ->
  ?tangent_attribute:string option -> ?bitangent_attribute:string option ->
  polyframe_style -> Geometry.t -> (Geometry.t, Error.t) result
(** Generate normalized normal/tangent/bitangent coordinate fields without
    changing topology. First-edge, two-edge, centroid, and texture-UV styles
    create point fields; texture-UV-gradient and attribute-gradient styles
    create vertex fields and retain seams. Empty texture names resolve to
    [uv]. Existing output fields are preserved outside [selection].
    [orthogonal] Gram-Schmidt projects tangents and enforces the requested
    right- or [left_handed] frame. Work and auxiliary/output storage are
    linear in topology. *)

val delete_primitives :
  ?cancel:Cancel.t -> ?grain:int -> ?selected:bool -> ?compact_points:bool ->
  Group.t -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Delete selected primitives (or keep only them when [selected=false]),
    preserving point storage and remapping vertex/primitive attributes and
    groups in stable input order. [compact_points] additionally removes points
    that no retained vertex references. O(points + vertices + primitives +
    attributes). *)

val compact_points :
  ?cancel:Cancel.t -> ?grain:int -> Geometry.t -> (Geometry.t, Error.t) result
(** Remove every point not referenced by topology, preserving retained point
    order and remapping point attributes/groups, native edge groups, and vertex point indices.
    O(points + vertices + point payload) time and O(points + output) storage. *)

type bound_shape = Bound.bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

val bound :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?shape:bound_shape ->
  ?lower_padding:Prismel_math.Vec3.t ->
  ?upper_padding:Prismel_math.Vec3.t ->
  ?bounds_group:string ->
  ?center_attribute:string ->
  ?radii_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create bounds around all points referenced by an optional typed component
    selection. Boxes have independently divided hard-normal faces; spheres are
    UV polygon ovoids enclosing the selected AABB before asymmetric padding.
    Optional output metadata is a primitive bounds group plus detail float3
    center and radii attributes.

    Selected bounds are reduced through stable disjoint point ranges in
    O(points + selected incidence) time. Box output is O(surface divisions),
    sphere output O(segments * rings), and all output storage is allocated to
    its exact cardinality. Empty selections, non-finite selected positions,
    invalid dimensions, and overflowing output cardinalities fail atomically. *)

val bounding_box :
  ?cancel:Cancel.t -> ?grain:int -> ?padding:Prismel_math.Vec3.t -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Create a hard-normal triangle box around point bounds. Empty geometry,
    invalid/negative padding, and zero-thickness output are rejected; use
    positive padding on collapsed axes for planar or linear input. *)

type match_size_fit = Match_size.match_size_fit =
  | Translate_only
  | Stretch
  | Contain
  | Cover
  | Match_x
  | Match_y
  | Match_z
  | Match_perimeter
  | Match_area
  | Match_volume

val match_axis :
  ?grain:int -> from:Prismel_math.Vec3.t -> into:Prismel_math.Vec3.t -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Rotate the complete geometry about the origin so [from] aligns with [into].
    Parallel and antiparallel inputs use deterministic identity/half-turn
    paths. Position and normal handling delegates to the packed transform. *)

val match_size :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?source_selection:deform_selection ->
  ?target_selection:deform_selection ->
  ?fit:match_size_fit ->
  ?translate_axes:(bool * bool * bool) ->
  ?scale_axes:(bool * bool * bool) ->
  ?justify:Prismel_math.Vec3.t ->
  ?target_justify:Prismel_math.Vec3.t ->
  ?offset:Prismel_math.Vec3.t ->
  ?scale:float ->
  ?target_center:Prismel_math.Vec3.t ->
  ?target_size:Prismel_math.Vec3.t ->
  ?target:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Translate and optionally scale source geometry into reference bounds.
    [selection] controls moved points, while [source_selection] and
    [target_selection] independently determine alignment bounds. Vertex,
    primitive, and native-edge selections use their referenced points.

    A supplied [target] provides the reference geometry. Otherwise the
    reference is an axis-aligned box at [target_center] (default origin) with
    [target_size] (default unit size). [justify] and [target_justify]
    components range from [-1] (minimum) through [0] (center) to [1]
    (maximum); translation axes may be disabled independently and [offset] is
    applied after alignment.

    [Stretch] uses independent enabled-axis ratios. [Match_x], [Match_y], and
    [Match_z] preserve aspect ratio using one named axis; [Contain] and [Cover]
    use the minimum and maximum non-degenerate bounds ratio. Perimeter, area,
    and volume fits derive a uniform linear scale from selected primitive
    measures on both geometry inputs and therefore require [target]. [scale]
    multiplies an enabled fit scale. Transformed point/vertex normals use the
    inverse-transpose diagonal and are normalized.

    Bounds work is O(points + selected incidence). Metric fits add O(vertices)
    perimeter work or deterministic polygon triangulation; output work is
    O(points + matching normal payload) with exact-sized planes and disjoint
    deterministic ranges. Invalid, empty, non-finite, or measureless inputs
    and cancellation fail atomically. *)

val scatter_surface :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?density:scatter_density ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?source_primitive_attribute:string ->
  ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string ->
  count:int -> seed:int -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Deterministically scatter exactly [count] points over selected polygon
    area. Optional point/vertex density is integrated and sampled as a linear
    field; primitive/detail density is constant per face. Negative density is
    clamped to zero. Polygon curves are ignored. [N] is interpolated with a
    geometric fallback, [Cd] is interpolated when present, and stable point
    [id] values are generated.

    Owner-specific attribute patterns transfer numeric fields by barycentric
    weights, discrete fields by the strongest corner, and primitive/detail
    fields by source incidence. [match_groups] transfers matching ordinary
    groups as point groups. Optional source primitive and paired vertex-number/
    weight CSR outputs preserve exact source provenance for later Attribute
    Interpolate cooks, including concave N-gons.

    Planning deterministically ear-clips selected simple polygons into exact
    packed triangle arrays; an allocation-linear alias table then samples each
    point in O(1). Total work is O(points + polygon ear clipping), output and
    auxiliary storage are O(points + emitted triangles), and point fills are
    exact across domain counts. *)

type copy_target_owner = Instance_copy.copy_target_owner =
  | Copy_target_points | Copy_target_vertices
  | Copy_target_primitives
type copy_target_operation = Instance_copy.copy_target_operation =
  | Copy_target_nothing | Copy_target_copy
  | Copy_target_add | Copy_target_subtract | Copy_target_multiply
type copy_target_attribute_rule = Instance_copy.copy_target_attribute_rule = {
  copy_target_pattern : string;
  copy_target_owner : copy_target_owner;
  copy_target_operation : copy_target_operation;
}
(** Ordered target-point attribute and group broadcast. Patterns use
    {!Attribute_pattern}; the last matching rule selects one destination owner
    and operation for each retained target field. [Copy_target_nothing]
    suppresses an earlier match. Copy replaces storage. Numeric
    add/subtract/multiply requires matching storage; when absent, add/multiply
    copy and subtract negates the target. Text always copies. Fixed tuples and
    packed integer/float arrays are supported. Target point groups use
    copy/intersection/union/subtraction respectively; absent multiply/add
    destinations copy the target group, while absent subtraction creates an
    empty group. *)

val copy_to_points :
  ?cancel:Cancel.t -> ?grain:int -> ?source_primitives:Group.t ->
  ?target_points:Group.t -> ?piece_attribute:string ->
  ?target_attributes:copy_target_attribute_rule list ->
  source:Geometry.t -> targets:Geometry.t -> unit ->
  (Geometry.t, Error.t) result
(** Expand one source copy at each target point. Target [pscale], [scale], and
    quaternion [orient] attributes control transforms. Without [orient], point
    [N], or [v] when [N] is absent, aligns source +Z; a finite nonzero [up]
    additionally aligns source +Y, while absent, zero, or parallel [up] uses
    deterministic shortest-arc alignment. Quaternion [rot] is applied after
    that orientation, [pivot] translates source-local points before scaling,
    and [trans] augments target [P]. A point float-array [transform] containing
    fixed-width row-major affine 3x3 or 4x4 matrices overrides orientation,
    rotation, and scale; 4x4 translation remains additive with [P] and [trans].
    [source_primitives] keeps only matching source primitives and compacts their
    points once before expansion. [target_points] keeps matching target points
    in stable numeric order, including free points. Source attributes and
    ordinary/native edge groups repeat in stable target order. Point/vertex
    normals use inverse-scale rotation or the matrix inverse transpose; if any
    matrix is singular, copied normals are omitted atomically. Ordered
    [target_attributes] rules then broadcast target point attributes and groups
    onto copied point, vertex, or primitive owners. [piece_attribute] matches an
    integer or text target point field to the same source primitive field, or
    then to a source point field. Primitive pieces compact their referenced
    points; point pieces preserve matching free points and omit mixed-value
    primitives. With no source field, an integer target value selects one
    source primitive by numeric index. Unmatched targets emit no geometry.
    O(source
    preparation + targets + copies * selected source payload) time/output. *)

val materialize_instances :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?apply_transform:bool ->
  transforms:Prismel_math.Mat4.t array ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Materialize one exact copy of the input for every transform in stable
    transform-major order. By default positions use the complete homogeneous transform;
    point/vertex normals use normalized inverse-transpose transforms and are
    removed when any transform is singular. Attributes and ordinary/native
    edge groups retain exact copy ancestry. An empty transform array produces
    valid empty topology while retaining detail attributes. With
    [apply_transform=false], transforms provide only the instance count and
    every materialized copy retains the prototype coordinates and normals. A
    single instance structurally shares unchanged topology and metadata; one
    identity instance returns the input snapshot itself.

    O(instances * source payload) time and exact output-sized storage plus one
    copied transform-reference array. Position, topology, attribute, group,
    and normal fills use deterministic disjoint parallel ranges. *)

val duplicate :
  ?cancel:Cancel.t -> ?grain:int -> ?copies:int -> ?cumulative:bool ->
  ?transform:Prismel_math.Mat4.t -> ?primitives:Group.t ->
  ?copy_group_prefix:string -> ?preserve_groups:bool -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Append [copies] transformed materialized copies after the original.
    Cumulative mode applies transform powers 0..copies; otherwise every added
    copy uses the same transform. [primitives] restricts copied topology while
    retaining the complete input as an exact prefix; only points referenced by
    selected primitives are copied. All fixed/ragged attributes and
    ordinary/native edge groups retain exact ancestry in copy-major order,
    while point/vertex normals use normalized inverse-transpose matrices.
    [copy_group_prefix] creates one primitive group per appended copy, named by
    the prefix plus a one-based copy number. Colliding group membership is
    replaced unless [preserve_groups] is true. Generated groups are bounded to
    4096 groups and 256 MiB of packed payload.

    Unrestricted duplication is O((copies + 1) * payload) time with exact
    output storage and retains its direct exact-copy fast path. Restricted
    duplication is O(input topology + copied selected payload); cardinalities
    are planned once and disjoint point, topology, attribute, group, normal,
    and edge-bitset ranges are filled in parallel. *)

val compose_transform :
  ?order:transform_order ->
  ?rotation_order:transform_rotation_order ->
  ?translate:Prismel_math.Vec3.t ->
  ?rotate:Prismel_math.Vec3.t ->
  ?scale:Prismel_math.Vec3.t ->
  ?shear:Prismel_math.Vec3.t ->
  ?uniform_scale:float ->
  ?pivot:Prismel_math.Vec3.t ->
  ?pivot_rotation:Prismel_math.Vec3.t ->
  ?invert:bool ->
  unit ->
  (Prismel_math.Mat4.t, Error.t) result
(** Compose one finite affine transform. Rotation values are radians. Shear
    components are X-on-XY, X-on-XZ, and Y-on-YZ. The pivot translates and
    rotates the local transform frame. [invert] rejects singular output. *)

val transform_selected :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Prismel_math.Mat4.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transform positions referenced by an optional point, vertex, primitive,
    or native-edge selection. Point and vertex [N] values attached to moved
    points use the inverse-transpose matrix; they are normalized unless
    [preserve_normal_length] is set. Singular transforms invalidate [N].
    [recompute_normals] instead rebuilds every pre-existing point/vertex [N]
    plane from the resulting polygon geometry. Execution uses disjoint packed
    point/normal ranges and is exact across domain counts. *)

val soft_transform :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?metric:soft_transform_metric ->
  ?falloff:soft_transform_falloff ->
  ?radius:float ->
  ?falloff_attribute:string ->
  ?recompute_normals:bool ->
  Prismel_math.Mat4.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Blend every affected point from its original position toward the supplied
    transformed position. Radius mode uses the closest selected source point;
    edge mode uses exact multi-source shortest geometric edge-path distance.
    Attribute mode treats [selection] as the affected point set and either
    rolls raw point-float distances through [radius] or uses the field directly
    as an extrapolating transform weight. Linear, quadratic, and smooth cubic
    falloffs map distance zero to one and the radius to zero.

    [falloff_attribute] stores the exact point weights. Existing normals are
    recomputed by default; disabling recomputation removes stale point/vertex
    [N]. Radius queries use the packed parallel point index; output fills are
    parallel and allocation-free per point. Edge distance is a stable bounded
    Dijkstra traversal. *)

val distance_along_geometry :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?affected:deform_selection ->
  ?falloff:soft_transform_falloff ->
  ?radius:distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  start:deform_selection ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Compute exact multi-source shortest geometric edge-path distance from
    [start]. An optional affected selection restricts which point values are
    replaced; pre-existing values outside it are preserved. The default raw
    [distance] output stores [-1] for unreachable points. Pass
    [~distance_attribute:None] to omit it. A mask maps distance zero to one and
    the chosen fixed or maximum reachable affected distance to zero through
    the requested falloff; unreachable points map to zero.

    The stable indexed Dijkstra kernel uses O(points + edges) memory and
    O((points + edges) log points) worst-case time. Packed output fills run in
    disjoint parallel ranges and are byte-identical across domain counts. *)

val distance_from_geometry :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?affected:deform_selection ->
  ?reference_selection:deform_selection ->
  ?reference_kind:distance_from_geometry_reference ->
  ?falloff:soft_transform_falloff ->
  ?radius:distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  reference:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Measure each affected source point to the closest selected reference point
    or polygon-surface feature. Raw distance defaults to [distance] and uses
    [-1] when the reference is empty or a bounded query misses. Pass
    [~distance_attribute:None] to request only a fixed-radius mask. Existing
    values outside the affected selection survive exactly.

    Point queries use the packed median-split point index; primitive queries
    use the triangulated polygon BVH. Both fill only one squared-distance plane
    in parallel, then materialize enabled immutable outputs atomically. *)

val distance_from_target :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?affected:deform_selection ->
  ?projection:distance_from_target_projection ->
  ?origin:Prismel_math.Vec3.t ->
  ?direction:Prismel_math.Vec3.t ->
  ?metric:distance_from_target_metric ->
  ?falloff:soft_transform_falloff ->
  ?radius:distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Measure affected points from an analytic spherical, cylindrical, or planar
    target. Cylindrical and planar directions are normalized once. Planar raw
    distance may be signed; masks always use its magnitude. Existing values
    outside the affected selection survive exactly.

    Work is O(points), auxiliary storage is O(points) only when a maximum-radius
    mask is requested without a raw output, and disjoint fills are exact across
    domain counts. *)

val transform : ?grain:int -> Prismel_math.Mat4.t -> Geometry.t -> Geometry.t
(** Compatibility whole-geometry matrix transform. New code that needs
    selection, cancellation, or explicit normal policy should use
    {!transform_selected}. *)

val noise_displace :
  ?cancel:Cancel.t -> ?grain:int -> amplitude:float -> frequency:float -> seed:int ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Add deterministic coherent displacement to point Y. Existing point and
    vertex normals are removed because displacement invalidates them. *)

val peak :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?direction_attribute:string ->
  ?normalize_direction:bool ->
  ?mask_attribute:string ->
  distance:float ->
  ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Move affected points by [distance] along point [N], averaged vertex [N],
    or area-weighted geometric normals, in that priority order. A custom point
    float3 [direction_attribute] replaces that source. The optional point
    float mask linearly scales displacement without clamping. Zero directions
    do not move. Changed positions remove point/vertex normals unless
    [recompute_normals] installs fresh area-weighted point normals.

    Work is O(points + referenced topology), output is exactly three point
    planes, and point fills are deterministic disjoint parallel ranges. *)

val bend :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?mask_attribute:string ->
  ?origin:Prismel_math.Vec3.t ->
  ?direction:Prismel_math.Vec3.t ->
  ?up:Prismel_math.Vec3.t ->
  length:float ->
  ?bend_angle:float ->
  ?twist_angle:float ->
  ?limit:bool ->
  ?both_directions:bool ->
  ?continuous_twist:bool ->
  ?capture_attribute:string ->
  ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Bend and/or twist selected points in an arbitrary orthonormal capture
    frame. Angles are radians distributed over [length]. Bend preserves spine
    arc length; twist rotates around the capture direction. With [limit=true],
    the active interval is [[0,length]] or [[-length,length]] in bidirectional
    mode. Without a limit, one-direction mode still excludes the negative
    half-space. [continuous_twist=false] mirrors the twist parameter across a
    bidirectional origin. A point float mask is clamped to [[0,1]].

    [capture_attribute] records effective deformation influence. Changed
    positions invalidate normals unless recomputation is requested. Work is
    O(points + selected topology incidence), auxiliary/output storage is three
    exact point planes plus optional influence, and point fills are
    deterministic disjoint parallel ranges. *)

val mountain :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?direction_attribute:string ->
  ?normalize_direction:bool ->
  ?mask_attribute:string ->
  ?seed:int ->
  height:float ->
  ?frequency:Prismel_math.Vec3.t ->
  ?offset:Prismel_math.Vec3.t ->
  ?octaves:int ->
  ?lacunarity:float ->
  ?roughness:float ->
  ?height_attribute:string ->
  ?recompute_normals:bool ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Displace points along resolved normals/directions with deterministic 3D
    Perlin fBm. [roughness] is the octave gain from zero through one;
    [lacunarity] is positive and [octaves] is from one through 64. An optional point float
    [height_attribute] records signed displacement while preserving unselected
    existing values. O(points * octaves + referenced topology) time and exact
    position/output storage; every selected point is independent and exact
    across domain counts. *)

val point_jitter :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?use_point_scale:bool ->
  seed:Prismel_math.Rand.t ->
  scale:float ->
  ?axis_scales:Prismel_math.Vec3.t ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Jitter selected points independently by uniform XYZ samples from -0.5
    inclusive to 0.5 exclusive, times [scale] and the corresponding [axis_scales]
    component. A point-float mask linearly scales displacement without
    clamping. [id_attribute] uses point integers as stable random identities;
    a missing named ID falls back to point number. [use_point_scale] multiplies
    by point-float [pscale] when present and by one when absent. Any changed
    positions invalidate point/vertex [N].

    Work is O(points), output storage is three exact point planes, and range
    scratch is O(ceil(points / grain)). Indexed immutable random streams and
    disjoint fills make results byte-identical across domain counts. *)

 val facet :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?primitives:Group.t ->
  ?pre_compute_normals:bool ->
  ?make_normals_unit_length:bool ->
  ?unique_points:bool ->
  ?consolidate_distance:float ->
  ?consolidate_normals_distance:float ->
  ?remove_inline_points:bool ->
  ?inline_distance:float ->
  ?orient_polygons:bool ->
  ?cusp_angle:float ->
  ?remove_degenerate:bool ->
  ?make_planar:bool ->
  ?post_compute_normals:bool ->
  ?reverse_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Run the implemented Facet stages in SideFX pipeline order, optionally on
    a typed point, vertex, primitive, or native-edge [selection]. A point
    selects every incident primitive, a vertex its owning primitive, and an
    edge every incident primitive. The legacy resolved [primitives] entry point
    remains available; supplying both restrictions is invalid. Stages include
    optional
    pre-normal computation and normalization; full point uniquing with exact
    point-field/group duplication and native-edge ancestry; deterministic
    mutually exclusive point or point/vertex-normal consolidation;
    inline-point removal; manifold polygon orientation; dihedral-angle polygon
    cusping; degenerate cleanup; conflict-safe per-polygon planar projection;
    post-normal computation; and final normal
    reversal. Selection is re-established after every topology-changing stage.
    Shared point fields are affected when any selected primitive references the
    point; unselected primitive corners, primitive payload, and winding remain
    exact. All topology-changing stages preserve every current packed storage
    kind and stable ordinary-group order. Time and
    auxiliary/output storage are linear except tolerance consolidation's
    documented spatial-hash worst case. Normal consolidation leaves positions
    and topology unchanged, applies stable arithmetic averages to point and/or
    incident vertex [N], and preserves non-normal payload by identity. Make
    Planar uses scale-normalized centroid-plane projection and duplicates only
    shared corners whose independent primitive projections conflict. It is
    O(points + vertices + primitives + output payload) time and storage, with
    deterministic disjoint projection fills. *)

val poly_fill :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?boundary:Edge_group.t ->
  ?mode:poly_fill_mode ->
  ?reverse_patches:bool ->
  ?unique_points:bool ->
  ?update_point_normals:bool ->
  ?patch_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Fill complete manifold polygon boundary loops. With no [boundary], every
    valid polygon hole is filled; a supplied native edge group selects every
    complete loop touched by at least one member. [Fill_single_polygon]
    appends one N-gon, [Fill_triangles] deterministically ear-clips the loop,
    and [Fill_triangle_fan] appends one averaged center point and a triangle
    per boundary edge. Patches share boundary points unless [unique_points]
    is enabled. Default winding opposes every source boundary half-edge;
    [reverse_patches] deliberately reverses it.

    Existing geometry remains a stable prefix. New boundary points/corners
    inherit their exact point/vertex ancestry, numeric center fields use a
    stable arithmetic mean, discrete center fields use the first boundary
    value, and generated primitives inherit the adjacent boundary primitive's
    attributes but no pre-existing primitive groups. Source native edge groups
    remain attached only to source edges; [patch_group] marks all generated
    primitives. If requested and point [N] exists, point normals are recomputed
    after the atomic topology commit.

    Boundary planning and output storage are O(points + vertices + primitives
    + edges + output payload). Triangle fans and N-gons are linear; concave-safe
    ear clipping is O(sum boundary_size squared). Auxiliary storage is linear.
    Validation, triangulation, packed copies, interpolation, and topology fills
    use deterministic disjoint ranges where profitable. Branched boundaries,
    inconsistent winding, non-boundary selections, non-finite loop positions,
    and non-simple/degenerate projected loops fail without partial output. *)

val resample_curves :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?segments:int ->
  ?maximum_segment_length:float -> ?segment_length_attribute:string ->
  ?segments_attribute:string -> ?even_last_segment:bool ->
  ?curve_u_attribute:string -> ?curve_number_attribute:string ->
  ?distance_attribute:string -> ?tangent_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Arc-length resample every open or closed polygon curve. [segments] sets an
    exact edge count when used alone and acts as a per-curve ceiling when
    combined with [maximum_segment_length]. [primitives] restricts cooking
    while retaining unselected curves in primitive order. Optional primitive
    float [segment_length_attribute] and primitive integer
    [segments_attribute] override their corresponding controls; non-positive
    values disable that control and preserve a curve when both are disabled.
    Length-driven sampling emits equal
    edges when [even_last_segment] is true; otherwise it preserves the maximum
    step and leaves a shorter final edge. Closed outputs retain at least three
    edges. Optional point attributes expose input polygon-curve U, source curve
    number, half adjacent output-edge distance, and normalized output tangent.
    Numeric payloads are linearly interpolated, integer/text payloads and
    ordinary groups use the nearest endpoint, native edge groups require every
    traversed source interval, and primitive/detail data is preserved.
    Packed cumulative lengths and output planes use stable parallel ranges,
    including chunks of one long curve. Expected O(input vertices + output
    samples + payload) time and O(input vertices + output + payload) storage. *)

type carve_keep = Curve_modeling.carve_keep =
  | Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Curve_modeling.carve_attribute_mode =
  | Attribute_replace | Attribute_scale

val carve_curves :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?relative_arc_length:bool ->
  ?first:float -> ?last:float -> ?first_attribute:string ->
  ?last_attribute:string -> ?attribute_mode:carve_attribute_mode ->
  ?only_at_breakpoints:bool -> ?cut_at_all_internal_breakpoints:bool ->
  ?keep:carve_keep ->
  ?extract_points:bool -> ?divisions:int ->
  ?keep_original:bool -> Geometry.t -> (Geometry.t, Error.t) result
(** Retain the normalized parameter interval [[first,last]] of selected polygon
    curves as open curves. Unselected primitives of every supported topology
    kind retain their original point references, topology, and payload.
    Relative arc length is the default; uniform edge parameterization is
    available explicitly. Primitive float [first_attribute] and
    [last_attribute] values replace their corresponding constants by default,
    or multiply them in [Attribute_scale] mode. Endpoint payloads interpolate,
    discrete/group values choose the nearest endpoint, and native edge groups
    require every traversed source interval. [Keep_outside] retains the
    complement as two ordered open pieces for open curves and one seam-crossing
    open path for closed curves; [Keep_inside_and_outside] emits every resulting
    piece. [only_at_breakpoints] moves the interval inward to polygon vertices.
    [cut_at_all_internal_breakpoints] then splits retained paths at every vertex;
    in extraction mode it emits every vertex in the snapped interval. Outside
    breakpoint mode, Cut splits the retained inside interval into [divisions]
    equal ordered open-curve pieces; one division preserves the unsplit result.
    Extraction emits [divisions] evenly parameterized free points from [first]
    through [last], with one division sampling [first]. Selected primitives are
    removed unless [keep_original] is true. Expected O(vertices + divisions *
    log vertices-per-curve + output + payload) time and exact linear
    output/auxiliary storage. *)

val sweep_circle :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?sides:int ->
  ?divisions_attribute:string -> ?segments:int -> ?segments_attribute:string ->
  ?segment_scales:(float * float) -> ?segment_scales_attribute:string ->
  ?prevent_joint_buckling:bool -> ?maximum_joint_scale:float ->
  ?maximum_joint_scale_attribute:string ->
  ?smooth_point:bool -> ?smooth_attribute:string -> ?max_valence:int ->
  ?scale_attribute:string ->
  ?seam_offset:int -> ?seam_attribute:string -> ?segment_seam_attribute:string ->
  ?v_attribute:string ->
  ?generate_uv:bool -> ?u_range:(float * float) -> ?v_range:(float * float) ->
  ?uv_range_attribute:string -> ?up_attribute:string -> ?caps:bool ->
  ?cap_group:string -> radius:float -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Sweep a circular cross-section along every curve using parallel-transport
    frames. [primitives] restricts conversion and leaves other primitives
    unchanged. [divisions_attribute] is an optional point integer ring-side
    override; differing adjacent rings are joined by a deterministic minimal
    triangle/quad zipper. [segments] subdivides every longitudinal edge and a
    point integer [segments_attribute] overrides it with the rounded mean of
    the two endpoint values. [segment_scales] places the first/last interior
    ring in normalized source-edge coordinates; an outgoing-corner float2
    [segment_scales_attribute] overrides it per edge.
    [prevent_joint_buckling] emits a radial miter at each non-end source joint:
    every ring point is enlarged until it reaches both incident tube surfaces,
    capped by [maximum_joint_scale] or an overriding point float
    [maximum_joint_scale_attribute]. Limits must be finite and at least one.
    [smooth_point] controls whether source joints connect; a point float
    [smooth_attribute] below [0.5] disconnects that point, while [max_valence]
    disconnects points incident to more selected topology edges than its
    positive limit. Disconnection emits independent coincident rings with no
    transition face, restarts tangent/frame transport, and leaves those new
    ends uncapped. Closed curves rotate stably to the first break.
    An optional point float
    [scale_attribute] multiplies the base
    radius per ring. [seam_offset] rotates the snapped polygon seam by an
    integer number of sides; an optional point integer [seam_attribute] adds a
    per-ring offset without integer overflow. An outgoing-corner integer
    [segment_seam_attribute] additionally cycles the physical ring-to-face
    correspondence uniformly over each complete source edge, so subdivided
    segments retain one seam. A point float [v_attribute]
    overrides normalized arc-length side UV coordinates. A point float3
    [up_attribute] projects an explicit joint-up direction into each tangent
    plane; parallel vectors fail atomically instead of producing an invalid
    frame. [generate_uv] controls generated vertex UVs. Optional [u_range] and
    [v_range] apply per source edge; an outgoing-corner float4
    [uv_range_attribute] overrides them as [(u0,u1,v0,v1)]. Point
    [v_attribute] remains the highest-precedence V source. [caps] adds
    oppositely wound N-gons to open spines,
    hard vertex normals, planar cap UVs, and an optional primitive [cap_group].
    Emits polygon quads, point [N], and seam-safe vertex [uv], while remapping
    source attributes and ordinary/native edge groups.
    Ordered frame transport is per curve; packed ring and transition planes use
    disjoint global parallel ranges, including for one long spine, and each
    distinct cross-section cardinality is precomputed once. With [r] sampled
    rings, division counts [d_i], and adjacent counts [a_e,b_e], time is
    O(source + sum d_i + sum (a_e + b_e - gcd(a_e,b_e)) + payload), with exact
    linear output and O(source + rings + transitions + output ancestry)
    auxiliary storage. Division values are bounded to [3,4096] and segment
    values to [1,1048576] before cardinality planning. *)
