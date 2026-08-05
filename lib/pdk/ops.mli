(** Eager target-independent geometry operations. Known-cardinality generators
    allocate packed output once; modifiers preserve immutable snapshots. *)

type sort_owner = Points | Primitives
type sort_key =
  | X | Y | Z
  | Distance_to of Prismel.Vec3.t
  | Along_vector of Prismel.Vec3.t
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

type deform_selection =
  | Selected_points of Group.t
  | Selected_vertices of Group.t
  | Selected_primitives of Group.t
  | Selected_edges of Edge_group.t
(** Typed component selection. Deformations convert vertex and primitive
    membership to referenced points and edges to their endpoints. Operators
    that act on primitives, including Facet, promote points/vertices/edges to
    their incident primitives as documented at that operation. *)

type transform_order =
  | Transform_srt | Transform_str | Transform_rst
  | Transform_rts | Transform_tsr | Transform_trs
(** Application order for scale/shear ([s]), Euler rotation ([r]), and
    translation ([t]). For example, [Transform_srt] applies scale/shear,
    then rotation, then translation to column-vector points. *)

type transform_rotation_order =
  | Transform_xyz | Transform_xzy | Transform_yxz
  | Transform_yzx | Transform_zxy | Transform_zyx
(** Application order for Euler rotations, in radians. *)

type soft_transform_metric =
  | Soft_radius
  | Soft_edge
  | Soft_attribute of { attribute : string; apply_rolloff : bool }
(** Soft Transform distance source. Radius uses straight-line distance to the
    selected points; Edge uses shortest geometric edge-path distance.
    Attribute mode reads a point float field. With rolloff enabled it is a raw
    distance; otherwise it is the direct transform weight. *)

type soft_transform_falloff = Soft_linear | Soft_quadratic | Soft_cubic

type distance_along_radius =
  | Distance_fixed of float
  | Distance_maximum
(** Mask-normalization policy shared by distance-field operations. *)

type distance_from_geometry_reference =
  | Distance_reference_points
  | Distance_reference_primitives
(** Reference feature family for {!distance_from_geometry}. *)

type distance_from_target_projection =
  | Distance_target_spherical
  | Distance_target_cylindrical
  | Distance_target_planar
(** Analytic target used by {!distance_from_target}: a point, infinite axis,
    or infinite plane. *)

type distance_from_target_metric =
  | Distance_target_absolute
  | Distance_target_signed
(** Planar distance policy. Signed distance is positive in the supplied normal
    direction and is rejected for non-planar targets. *)

type normal_weighting =
  | Vertex_angle
  | Each_vertex
  | Face_area
(** Contribution policy for computed normals. [Vertex_angle] is resistant to
    triangulation changes, [Each_vertex] is the fastest equal-corner average,
    and [Face_area] gives larger polygons proportionally more influence. *)

type curvature_boundary =
  | Curvature_boundary_zero
  | Curvature_boundary_one_sided

type curvature_outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}

val default_curvature_outputs : curvature_outputs

type polyframe_style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string
(** Coordinate-frame construction. The first four styles emit point fields;
    [Texture_uv_gradient] and [Attribute_gradient] emit
    discontinuity-preserving vertex fields. *)

type smooth_boundary =
  | Smooth_free
  | Smooth_unshared
  | Smooth_group_boundary

type ray_method = Ray_minimum_distance | Ray_project
type ray_direction =
  | Ray_vector of Prismel.Vec3.t
  | Ray_normal
  | Ray_attribute of string
type ray_direction_mode =
  | Ray_forward
  | Ray_reverse
  | Ray_bidirectional_closest
  | Ray_bidirectional_farthest
type ray_surface_hit = Ray_first_surface | Ray_last_surface
type ray_combine =
  | Ray_average
  | Ray_median
  | Ray_shortest
  | Ray_longest

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
  origin:Prismel.Vec3.t -> direction:Prismel.Vec3.t -> length:float -> unit ->
  (Geometry.t, Error.t) result
(** Generate evenly spaced positions from [origin] in normalized [direction]
    through [length]. [Line_curve] creates one open polygon curve and requires
    at least two points; [Line_points] creates free points and requires at
    least one. Expected O(points) time/output with exact packed allocation and
    disjoint parallel fills. *)

val polyline :
  ?closed:bool -> (float * float * float) array -> (Geometry.t, Error.t) result

type circle_arc =
  | Circle_closed
  | Circle_open_arc of { start_angle : float; end_angle : float }
  | Circle_closed_arc of { start_angle : float; end_angle : float }
  | Circle_sliced_arc of { start_angle : float; end_angle : float }

type circle_orientation =
  | Circle_xy
  | Circle_xz
  | Circle_yz
  | Circle_axes of {
      horizontal : Prismel.Vec3.t;
      vertical : Prismel.Vec3.t;
    }

val circle :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?arc:circle_arc ->
  ?orientation:circle_orientation ->
  ?reverse:bool ->
  ?center:Prismel.Vec3.t ->
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

type grid_counts = Grid_divisions | Grid_point_counts

type grid_orientation =
  | Grid_xy
  | Grid_xz
  | Grid_yz
  | Grid_axes of {
      horizontal : Prismel.Vec3.t;
      vertical : Prismel.Vec3.t;
    }

type grid_connectivity =
  | Grid_points
  | Grid_rows
  | Grid_columns
  | Grid_rows_and_columns
  | Grid_quads
  | Grid_triangles
  | Grid_alternating_triangles
  | Grid_reverse_triangles

type revolve_type = Revolve_closed | Revolve_open_arc

type sweep_tangent =
  | Sweep_average_edges
  | Sweep_central_difference
  | Sweep_previous_edge
  | Sweep_next_edge
  | Sweep_z_axis

val grid :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?counts:grid_counts ->
  ?connectivity:grid_connectivity ->
  ?orientation:grid_orientation ->
  ?center:Prismel.Vec3.t ->
  ?width:float ->
  ?height:float ->
  ?rotation:float ->
  ?uv_attribute:string ->
  columns:int -> rows:int -> size:float -> unit ->
  (Geometry.t, Error.t) result
(** Create a packed planar point lattice. [Grid_divisions] preserves Prismel's
    compatibility convention: [columns] and [rows] count cells, so the point
    lattice is [(columns + 1) * (rows + 1)]. [Grid_point_counts] interprets
    them directly as Houdini-style hull-point counts.

    Connectivity may emit free points, one open polyline per row/column, both
    line families, quads, or consistently wound regular/reverse/checkerboard
    triangles. [Grid_xz] is the compatibility default with +Y normals;
    [Grid_xy] and [Grid_yz] use +Z and +X normals. [Grid_axes] robustly
    orthonormalizes its horizontal/vertical frame and uses [vertical ×
    horizontal] as the polygon normal. [rotation] is radians within that plane.
    [width] and [height] independently override the square [size]. An optional
    point float2 attribute stores normalized lattice coordinates.

    Cardinalities are checked before allocation. Positions, optional UVs,
    corner indices, primitive offsets, and primitive kinds use exact packed
    planes and deterministic disjoint ranges. Work and output are O(points +
    vertices + primitives); auxiliary storage is O(parallel ranges).
    Invalid axes, dimensions, topology counts, non-finite output, and
    cancellation fail atomically. *)

val revolve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?revolve_type:revolve_type ->
  ?connectivity:grid_connectivity ->
  ?start_angle:float ->
  ?end_angle:float ->
  ?reverse_cross_sections:bool ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string option ->
  divisions:int ->
  origin:Prismel.Vec3.t ->
  axis:Prismel.Vec3.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Revolve selected polygon curves around an arbitrary axis. Full revolutions
    use [divisions] wrapped angular edges; open arcs use [divisions + 1]
    angular samples including both endpoints. Connectivity matches {!grid}:
    points, angular rows, profile columns, both curve families, quads, and the
    three deterministic triangle splits.

    Profile points exactly on the axis share one pole point instead of
    producing coincident rings. Adjacent surface cells consequently become
    triangles, and axis-to-axis cells are omitted. Optional caps close the
    non-axis ends of open profiles for full polygon-surface revolutions.
    Generated UVs use normalized profile arc length and angular position;
    polygon surfaces use seam-safe vertex storage, while point output uses
    point storage. Source point/vertex/primitive/detail attributes and groups
    retain stable ancestry; stale point/vertex [N] is removed, and source
    native-edge groups are replicated along generated profile edges.

    Cardinalities are preflighted before allocation. Position and topology
    fills write disjoint packed ranges and are exact across domain counts.
    Time and output are O(selected curve vertices * divisions); auxiliary
    storage is O(selected curve vertices + output primitives). *)

type box_connectivity =
  | Box_triangles
  | Box_quads
  | Box_surface_points
  | Box_lattice_points

type box_normals = Box_no_normals | Box_point_normals | Box_vertex_normals

type box_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:box_rotation_order ->
  ?uniform_scale:float ->
  ?x_divisions:int ->
  ?y_divisions:int ->
  ?z_divisions:int ->
  ?uv_attribute:string ->
  ?face_groups:string ->
  size:Prismel.Vec3.t ->
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

type sphere_connectivity =
  | Sphere_triangles
  | Sphere_alternating_triangles
  | Sphere_quads
  | Sphere_rows
  | Sphere_columns
  | Sphere_rows_and_columns
  | Sphere_points

type sphere_normals =
  | Sphere_no_normals
  | Sphere_point_normals
  | Sphere_vertex_normals

type sphere_orientation =
  | Sphere_x
  | Sphere_y
  | Sphere_z
  | Sphere_axis of Prismel.Vec3.t

type sphere_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
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

type torus_connectivity =
  | Torus_triangles
  | Torus_alternating_triangles
  | Torus_quads
  | Torus_rows
  | Torus_columns
  | Torus_rows_and_columns
  | Torus_points

type torus_normals =
  | Torus_no_normals
  | Torus_point_normals
  | Torus_vertex_normals

type torus_orientation =
  | Torus_x
  | Torus_y
  | Torus_z
  | Torus_axis of Prismel.Vec3.t

type torus_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
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

type tube_connectivity =
  | Tube_triangles
  | Tube_alternating_triangles
  | Tube_quads
  | Tube_rows
  | Tube_columns
  | Tube_rows_and_columns
  | Tube_points

type tube_normals =
  | Tube_no_normals
  | Tube_point_normals
  | Tube_vertex_normals

type tube_orientation =
  | Tube_x
  | Tube_y
  | Tube_z
  | Tube_axis of Prismel.Vec3.t

type tube_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
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

type platonic_kind =
  | Platonic_tetrahedron
  | Platonic_cube
  | Platonic_octahedron
  | Platonic_icosahedron
  | Platonic_dodecahedron
  | Platonic_soccer_ball

type platonic_normals =
  | Platonic_no_normals
  | Platonic_point_normals
  | Platonic_vertex_normals

type platonic_orientation =
  | Platonic_x
  | Platonic_y
  | Platonic_z
  | Platonic_axis of Prismel.Vec3.t

type platonic_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
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

type spiral_extent =
  | Spiral_turns of { turns : float; height : float }
  | Spiral_height_pitch of { height : float; pitch : float }

type spiral_radius =
  | Spiral_archimedean_change of {
      start_radius : float; increase_per_turn : float;
    }
  | Spiral_archimedean_end of { start_radius : float; end_radius : float }
  | Spiral_logarithmic_change of {
      start_radius : float; scale_per_turn : float;
    }
  | Spiral_logarithmic_end of { start_radius : float; end_radius : float }

type spiral_direction = Spiral_counterclockwise | Spiral_clockwise

type spiral_divisions =
  | Spiral_divisions_per_curve of int
  | Spiral_divisions_per_turn of int

type spiral_orientation =
  | Spiral_x
  | Spiral_y
  | Spiral_z
  | Spiral_axis of Prismel.Vec3.t

type spiral_rotation_order =
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
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
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

type fuse_position =
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
type fuse_attributes = Keep_first | Average_numeric
type fuse_attribute_method =
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
type fuse_attribute_rule = {
  pattern : string;
  method_ : fuse_attribute_method;
  weight_attribute : string option;
}
type fuse_group_method =
  | Group_least_point
  | Group_greatest_point
  | Group_union
  | Group_intersection
  | Group_most_common
type fuse_group_rule = {
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
type fuse_metric = Euclidean | Componentwise
type fuse_using =
  | Least_target_point
  | Closest_target_point
type fuse_match_condition =
  | Equal_attribute_values
  | Unequal_attribute_values
type fuse_targeting =
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

type poly_bevel_shape =
  | Bevel_chamfer
  | Bevel_round of { convexity : float }

val poly_bevel :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?shape:poly_bevel_shape ->
  ?divisions:int ->
  ?point_scale_attribute:string ->
  ?ignore_flat_angle:float ->
  ?clamp_overlap:bool ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  ?recompute_point_normals:bool ->
  distance:float ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Insert fillet strips along selected consistently oriented two-sided polygon
    edges and fill arbitrary connected junctions. Chamfer and rational-circular
    rounded profiles support one or more deterministic divisions; round
    [convexity] lies in [-1, 1]. A scalar point attribute may scale cutback
    distance. Face-local slide distances are clamped before adjacent offset
    fronts cross, and [ignore_flat_angle] excludes smaller dihedral angles.

    Existing polygon and curve primitives are retained, selected polygon faces
    are cut back within their first ring, and generated edge/corner faces plus
    offset boundaries may be named. Numeric vertex payload interpolates across
    fillet rows; discrete vertex payload uses stable nearest-side ancestry.
    Point, primitive, detail, ordinary-group, ordered-group, and native-edge
    ancestry remain deterministic. Point/vertex normals are invalidated and an
    existing point normal is recomputed by default.

    Requested boundary, non-manifold, self, non-polygon, inconsistently wound,
    and excluded-flat edges do not contribute. Planning and auxiliary storage
    are O(points + vertices + primitives + edges), output cardinality is
    computed before allocation, and packed independent fills use the reusable
    domain pool with byte-identical ordering across domain counts. *)

val point_split :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?attributes:string ->
  ?tolerance:float ->
  ?promote_attributes:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Split shared points for selected point, vertex, or primitive corners.
    With a blank [attributes] pattern, every selected corner becomes unique;
    otherwise matching vertex/primitive attributes and named vertex/primitive
    groups define value clusters, with floating components compared using the
    inclusive [tolerance]. Glob terms use the shared ordered include/exclude
    pattern language. Group membership is a Boolean seam component.

    Existing point payload and groups duplicate by source-point ancestry;
    vertex, primitive, and detail payload remains structurally shared.
    Native edge groups replicate to every split incidence. When
    [promote_attributes] is true, matched attributes move to point ownership
    using each cluster's stable representative, replacing same-name point
    fields. Groups participate only in splitting and are not promoted. Free
    points receive the storage kind's zero/empty value.

    Planning preserves all original point numbers, appends only required
    clusters, allocates output cardinality once, and leaves already compatible
    points unchanged. Point-local clustering and every output-sized fill use
    deterministic disjoint ranges; ordered output is byte-identical across
    domain counts. Native-edge selections are rejected because Point Split's
    selection contract is point/vertex/primitive based. *)

type poly_loft_minimize = Two_point_distance | Three_point_distance

val poly_loft :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?rest:Geometry.t ->
  ?connect_closest_ends:bool ->
  ?minimize:poly_loft_minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Triangulate between consecutive selected polygon curves or polygon faces
    using their existing points. Unequal section cardinalities use a stable
    two- or three-distance zipper. [connect_closest_ends] aligns open endpoints
    and closed seams/orientation from geometry or an equal-point-count [rest]
    snapshot. [u_wrap] closes open sections and [v_wrap] connects the final
    section back to the first.

    Selected source sections are removed unless [keep_primitives] is true;
    unrelated primitives pass through in source order. New corners inherit
    exact section-corner ancestry, new faces inherit the preceding section,
    and [output_group] records only generated triangles. Point/detail storage
    is shared. Stale normals are removed and an existing point or vertex [N]
    can be regenerated.

    A zero [collinearity_tolerance] preserves every triangle with three
    distinct point numbers, making topology independent of metric roundoff.
    A positive dimensionless sine threshold explicitly enables approximate
    collinearity filtering.

    Pair planning is O(output triangles) after closest-seam search. Small seam
    searches are quadratic; large closed sections use a packed spatial index.
    Independent section pairs, topology copies, payload remaps, and normal
    fills use deterministic disjoint domain ranges. *)

val skin :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?rest:Geometry.t ->
  ?connect_closest_ends:bool ->
  ?minimize:poly_loft_minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Build a polygon skin between consecutive selected polygon curves or faces.
    Equal-cardinality section pairs produce stable quads; unequal pairs use the
    same deterministic triangle zipper and alignment policy as [poly_loft].
    This is the linear polygon-surface subset of a Skin operation; it does not
    synthesize spline surfaces or bilinear U/V boundary patches.

    Source retention, selection, rest alignment, U/V wrapping, payload
    ancestry, normal policy, cancellation, and parallel determinism match
    [poly_loft]. Time and auxiliary storage are linear in generated corners
    after optional closest-seam search. *)

type poly_bridge_pairing = Bridge_by_order | Bridge_by_centroid

type poly_reduce_target =
  | Reduce_ratio of float
  | Reduce_primitive_count of int

val poly_bridge :
  ?cancel:Cancel.t ->
  ?grain:int ->
  source:Edge_group.t ->
  destination:Edge_group.t ->
  ?pairing:poly_bridge_pairing ->
  ?connect_closest_ends:bool ->
  ?minimize:poly_loft_minimize ->
  ?reverse_source:bool ->
  ?reverse_destination:bool ->
  ?pairing_shift:int ->
  ?divisions:int ->
  ?keep_input:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Bridge paired simple source and destination edge paths or loops without
    duplicating their boundary points. Connected components pair in stable
    authored order or by deterministic lexicographic centroid rank. Equal
    component cardinalities produce quads; unequal components use the shared
    PolyLoft zipper. Reverse controls and a closed-loop destination pairing
    shift override automatic endpoint/seam alignment. [divisions] adds
    uniformly spaced straight rows for equal-cardinality pairs, linearly
    interpolating numeric point/vertex payload and using nearest endpoint
    policy for discrete payload and ordinary groups.

    Input topology is retained by default and generated faces append in pair
    order. New corners and faces retain exact boundary ancestry, including
    packed vertex/primitive payload and topology-affine edge groups;
    [output_group] identifies generated polygons. Selected edge graphs must be
    non-branching, source/destination components must have matching counts and
    closure, and their edge selections must not overlap.

    Path extraction, fixed-arity planning, and topology materialization are
    O(vertices + edges + output corners). Centroid-rank pairing is O(k log k)
    in the number of components; independent bridge plans and packed output
    ranges use deterministic disjoint domain work. Divided bridges add
    O((divisions - 1) * boundary points) packed point storage. *)

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

val edge_cusp :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?update_point_normals:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Split polygon point fans along the interior vertices of selected edge
    paths. Path endpoints—points incident to only one selected edge—remain
    shared, so a single selected edge is an identity and two connected edges
    split only their common point. An omitted edge group is an intentional
    no-op.

    New points duplicate every point attribute and ordinary/ordered point-group
    membership. Vertex, primitive, and detail payload retains its existing
    slots, while native edge groups follow exact source-corner ancestry.
    Existing point normals are recomputed by default; as with [normals], this
    replaces conflicting [N] fields on other owners. No normal is invented when
    the source has no point [N]. Effective selected edges must have at most two
    polygon incidences.

    Fan construction and output planning are O(points + vertices + edges) time
    and storage. Packed position, point-payload, group, topology, and ancestry
    fills use deterministic disjoint ranges in the reusable domain pool. *)

val edge_straighten :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Orthogonally project the points of each connected selected-edge component
    onto its least-squares best-fit line. An omitted selection uses every
    topology edge. Components with at most two points and components already
    collinear to scale-aware floating-point precision preserve their positions
    exactly. [output_group] optionally records the selected topology edges.

    Topology and non-normal payload remain structurally shared. A changed
    result removes stale point and vertex [N]. Selected endpoints and projected
    results must be finite; arbitrary branches and cycles are supported by the
    component fit rather than assigned an undocumented path order.

    Component construction, packed member planning, fitting, and projection
    are O(points + edges) time and storage. Independent component fits and
    disjoint point projections use the reusable domain pool; stable member
    order makes one- and multi-domain results byte-identical. *)

val circle_from_edges :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?radius:float ->
  ?scale:Prismel.Vec3.t ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Fit each simple connected selected-edge path or loop to a least-squares
    plane and algebraic circle, then radially project its points onto the fitted
    or explicit positive radius. [scale] is a component-wise world-axis scale
    about each fitted center. An omitted edge group selects topology boundary
    edges; [output_group] records exactly the transformed edges.

    Topology, payload, and non-selected positions remain structurally stable;
    changed point and vertex [N] are removed. Branches, components with fewer
    than three points, collinear fits, stale edge affinity, non-finite inputs or
    parameters, unrepresentable output, and cancellation fail atomically.

    Stable union-find/component CSR planning is O(points + edges); independent
    normalized covariance/circle fits and disjoint point projection use the
    reusable domain pool. Auxiliary storage is O(points + edges + components),
    and one/multi-domain output ordering is identical. *)

type graph_color_connectivity =
  | Graph_primitives_by_point
  | Graph_points_by_primitive
  | Graph_primitives_by_edge

type graph_color_worksets = {
  begin_attribute : string;
  length_attribute : string;
}

val graph_color :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?connectivity:graph_color_connectivity ->
  ?color_attribute:string ->
  ?sort_output:bool ->
  ?worksets:graph_color_worksets ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Assign a non-negative integer color to each selected point or primitive so
    directly connected selected elements have different values. Primitive
    connectivity can use shared points or shared closed-polygon edges; point
    connectivity treats all points in one primitive as a clique. Unselected
    elements receive [-1]. Typed selections are promoted to the target owner.

    [sort_output] stably places unselected elements first and then ascending
    color blocks while remapping every payload/group through the shared Sort
    core. Optional detail integer-array workset begin/length fields require
    sorted output and describe those selected blocks.

    Stable union-find builds disconnected graph components in O(points +
    vertices + edges) storage. Components color independently in the reusable
    domain pool with deterministic ascending-element greedy order. Neighbor
    scans do not materialize a potentially quadratic clique adjacency; time is
    output-sensitive to primitive valence. One- and multi-domain colors and
    sorted topology are identical. *)

type edge_equalize_method =
  | Equalize_average
  | Equalize_longest
  | Equalize_shortest

val edge_equalize :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?method_:edge_equalize_method ->
  ?iterations:int ->
  ?tolerance:float ->
  ?output_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Move selected-edge endpoints until all selected edges have the initial
    average, longest, or shortest selected length. An omitted selection uses
    every topology edge. [iterations] defaults to 64 and [tolerance] to a
    relative [1e-6]. [output_group] records the exact transformed selection.

    Independent edges are solved exactly in one disjoint parallel pass.
    Connected selections use a deterministic, centroid-preserving Jacobi
    projection with stable incident-edge order. A positive target cannot give
    direction to a zero-length edge; non-finite positions, unrepresentable
    lengths, and failure to converge are reported atomically. Changed results
    discard stale point and vertex [N].

    Initial planning is O(points + edges); connected solving is
    O(iterations * (points + selected incidences)). Auxiliary storage is
    O(points + edges), independent of domain count. *)

type edge_relax_selection =
  | Relax_points of Group.t
  | Relax_primitives of Group.t

type edge_relax_target_mode =
  | Individual_lengths
  | Scale_independent_distribution

val edge_relax :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:edge_relax_selection ->
  ?pin_points:Group.t ->
  ?iterations:int ->
  ?step_size:float ->
  ?target_mode:edge_relax_target_mode ->
  ?only_shorten:bool ->
  ?tolerance:float ->
  reference:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Relax movable points toward reference edge lengths from an exactly
    matching polygon/curve topology. Point selection moves named points;
    primitive selection promotes incident points once. Unselected and pinned
    points remain fixed while incident edges constrain movable neighbors.

    Individual mode uses each reference length. Scale-independent mode scales
    the reference distribution to the source's selected mean length.
    [only_shorten] ignores satisfied and lengthening constraints. Iteration
    buffers are bounded, residual stopping is deterministic, and output after
    the requested ceiling is a valid best effort rather than an implicit
    mutable solver state. Changed output removes stale point and vertex [N].

    Planning is O(points + edges), and solving is
    O(iterations * (points + selected incidences)) with O(points + edges)
    auxiliary storage. Point updates write disjoint packed ranges through the
    reusable domain pool and are byte-identical across domain counts. *)

type edge_transport_roots =
  | Transport_first_point
  | Transport_last_point
  | Transport_root_group of Group.t

type edge_transport_operation =
  | Transport
  | Transport_from_root
  | Transport_total
  | Transport_maximum
  | Transport_minimum

type edge_transport_root_value =
  | Transport_root_zero
  | Transport_root_hold

type edge_transport_split = Transport_copy | Transport_split

type edge_transport_normalization =
  | Transport_no_normalization
  | Transport_normalize_components
  | Transport_normalize_global

type edge_transport_direction = Transport_forward | Transport_backward

type edge_transport_merge =
  | Transport_merge_add
  | Transport_merge_maximum
  | Transport_merge_minimum

type blend_shapes_mode = Blend_normalized | Blend_differencing
type blend_shapes_masking = Blend_no_mask | Blend_set_from_attribute
  | Blend_scale_from_attribute
type blend_shape_mask_source = Blend_mask_first_input | Blend_mask_shape
type blend_shape

val blend_shape :
  ?mask_attribute:string ->
  ?mask_source:blend_shape_mask_source ->
  weight:float ->
  Geometry.t ->
  blend_shape

val blend_shapes :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?mode:blend_shapes_mode ->
  ?masking:blend_shapes_masking ->
  ?mask_attribute:string ->
  ?point_id_attribute:string ->
  ?attributes:string ->
  shapes:blend_shape list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Blend the first input toward multiple point shapes while preserving its
    topology. Normalized mode uses the first input for residual weight and
    renormalizes positive target weights above one. Differencing mode adds
    weighted target-minus-source deltas and permits extrapolation.

    Optional integer/text point IDs match reordered or partial targets. A
    missing target ID contributes the source value. Set/Scale masking reads a
    finite scalar point attribute from the first input or each shape. [P] and
    matching point Float/Float2/Float3/Float4 attributes blend in deterministic
    stable target order; absent target attributes contribute the source value.
    Point selection preserves unselected payload exactly.

    Work is O(points * shapes * blended components), output storage is exact,
    and ID maps add O(source + target points) scratch. Disjoint point ranges
    use the reusable domain pool and commit positions/attributes atomically. *)

type attribute_composite_operation =
  | Composite_mean
  | Composite_maximum
  | Composite_minimum
  | Composite_over
  | Composite_under

type attribute_composite_input

val attribute_composite_input :
  weight:float -> Geometry.t -> attribute_composite_input
(** Bind an additional ordered geometry input to a finite global weight. *)

val attribute_composite :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?operation:attribute_composite_operation ->
  ?weight:float ->
  ?detail_attributes:string ->
  ?primitive_attributes:string ->
  ?point_attributes:string ->
  ?vertex_attributes:string ->
  ?allow_position:bool ->
  ?alpha_attribute:string ->
  inputs:attribute_composite_input list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Composite matching fixed-width floating attributes from ordered geometry
    inputs onto the first input's topology. Each owner has an independent
    Houdini-style name pattern; [P] is eligible only with [allow_position].

    Mean computes the alpha-distributed weighted average, with an exact zero
    when the effective denominator is zero. Maximum and minimum compare
    component-wise weighted values. Over and Under initialize from the weighted
    first input, then fold subsequent inputs in stable order using their alpha;
    a missing alpha attribute is exactly one. Missing selected attributes
    contribute zero. Every present alpha and selected floating component must
    be finite, and directly indexed owner cardinalities must agree.

    Work is O(elements * inputs * selected components), with one exact output
    plane per selected component and, only for spatially varying Mean alpha,
    one denominator plane per active owner. Input-major passes write disjoint
    element ranges through the reusable domain pool. Topology and untouched
    payloads remain structurally shared; changing [P] removes normals unless
    that normal owner was explicitly composited. *)

type attribute_mirror_owner = Mirror_point_attributes
  | Mirror_vertex_attributes
  | Mirror_primitive_attributes

type attribute_mirror_group_use = Mirror_group_as_source
  | Mirror_group_as_destination

type attribute_mirror_method =
  | Mirror_by_plane of {
      origin : Prismel.Vec3.t;
      normal : Prismel.Vec3.t;
      distance : float;
      tolerance : float;
    }
  | Mirror_by_mapping of {
      mapping_attribute : string;
      destination_group : Group.t;
    }

type attribute_mirror_transform =
  | Mirror_copy
  | Mirror_uv of {
      origin_u : float;
      origin_v : float;
      direction_u : float;
      direction_v : float;
    }
  | Mirror_vector
  | Mirror_point

val attribute_mirror :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?group:Group.t ->
  ?group_use:attribute_mirror_group_use ->
  ?attributes:string ->
  ?transform:attribute_mirror_transform ->
  ?string_replace:(string * string) ->
  ?output_mapping:string ->
  ?source_group:string ->
  ?destination_group:string ->
  owner:attribute_mirror_owner ->
  method_:attribute_mirror_method ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Copy selected same-owner attributes from the source side of mirror pairs
    to their destinations without changing topology. Plane correspondence
    supports point positions or primitive bounding-box centers and uses a
    deterministic nearest reflected-source search inside [tolerance]. Explicit
    mapping consumes an integer destination-to-source attribute plus a matching
    destination group and supports point, vertex, or primitive ownership.

    Float/Int/Text/Float2/Float3/Float4 and packed ragged fields are copied.
    Optional UV, plane-vector, or plane-point transformation changes only
    mirrored destinations; literal text replacement is also destination-only.
    Mapping/source/destination outputs are rebuilt atomically, with [-1] for
    unmatched mapping elements. Work is O(elements log source-elements) for
    plane correspondence and O(elements + payload) for explicit mapping.
    Fixed-width output is exact-sized and disjoint range copying uses the
    reusable domain pool. *)

val rewire_vertices :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?recursive:bool ->
  ?delete_target_attribute:bool ->
  ?keep_unused_points:bool ->
  ?original_point_attribute:string ->
  owner:Attribute.owner ->
  target_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Reassign selected primitive corners to point numbers read from a scalar
    integer point, vertex, or primitive attribute. The typed selection is
    first promoted to the target attribute's owner, then to affected corners;
    invalid target numbers leave the corresponding corners unchanged.

    Recursive mode follows point-owned target chains to their terminal point.
    Nodes in a cycle remain wired to themselves; tails entering a cycle end at
    its stable entry point. Optional original-point output records every source
    corner, target-field deletion is atomic, and default cleanup deletes only
    points that became unused because of this rewire while preserving points
    which were already free. Point/vertex normals are invalidated when topology
    changes. All attribute/group payload is preserved, and native edge groups
    follow corner-edge ancestry with union when rewired edges merge.

    Direct rewiring is O(points + vertices + primitives + payload). Recursive
    point chains and cleanup add O(points) time/storage. Target fills, point
    payload compaction, and edge-group materialization use deterministic
    disjoint ranges through the reusable domain pool. *)

val edge_transport :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?roots:edge_transport_roots ->
  ?operation:edge_transport_operation ->
  ?root_value:edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:edge_transport_split ->
  ?direction:edge_transport_direction ->
  ?merge:edge_transport_merge ->
  ?normalization:edge_transport_normalization ->
  attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transport a scalar float point attribute through a deterministic
    shortest-path forest over selected topology edges. First/last root policy
    seeds every selected component; an explicit root group leaves unreachable
    points unchanged. Stable distance/root/point ties define parentage.

    [Transport] propagates the chosen root value, [Transport_from_root] copies
    each forest root, [Transport_total] accumulates ancestors (optionally a
    constant and/or edge length), and minimum/maximum fold the root-to-point
    path. Copy or split controls forward branching. Backward traversal treats
    forest leaves as traversal roots and combines child branches by Add,
    Maximum, or Minimum. Reached values may be normalized globally or per
    selected component.

    Topology planning is O(points + edges), shortest-path construction is
    O((points + edges) log points), and storage is O(points + edges). First/last
    roots drain independent components through component-local heaps; explicit
    multi-source roots retain one global stable heap. Length validation and
    packed edge metrics use reusable-domain ranges, and independent backward
    trees evaluate in parallel. Output is deterministic and committed
    atomically. *)

val edge_transport_curves :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?owner:Attribute.owner ->
  ?direction:edge_transport_direction ->
  ?operation:edge_transport_operation ->
  ?root_value:edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?normalization:edge_transport_normalization ->
  attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transport a scalar point or vertex field independently along selected
    polygon/curve primitives. Open-curve forward traversal runs from the
    lower-numbered endpoint to the higher-numbered endpoint. Closed curves
    use their lowest-numbered point as a deterministic seam, with the lower
    adjacent point choosing forward orientation.

    Curves are processed through disjoint reusable-domain ranges. Point-owned
    output rejects repeated/shared selected points because concurrent writes
    would otherwise be undefined; vertex-owned output remains valid for shared
    points. Work is O(selected vertices), auxiliary storage is O(points) only
    for point-write validation, and results are exact across domain counts. *)

val edge_transport_parent :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?parent_attribute:string ->
  ?direction:edge_transport_direction ->
  ?operation:edge_transport_operation ->
  ?root_value:edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:edge_transport_split ->
  ?merge:edge_transport_merge ->
  ?normalization:edge_transport_normalization ->
  attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transport a scalar point field through an integer point-parent forest,
    without requiring topology edges. Invalid, self, and selected-to-unselected
    parent references are roots; parent cycles are deliberately unreachable
    and remain unchanged.

    Forward traversal applies Copy/Split from roots to children. Backward
    traversal treats leaves as traversal roots and combines child branches by
    Add, Maximum, or Minimum. Independent rooted trees evaluate in parallel;
    stable numeric roots and child order make output exact across domains.
    Planning, evaluation, and normalization are O(points), with O(points)
    packed auxiliary storage and atomic output commit. *)

type grid_rounding = Grid_nearest | Grid_down | Grid_up

val snap_to_grid :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:Group.t ->
  ?spacing:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
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

val triangulate :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Deterministically ear-clip selected simple polygon primitives after
    dominant-axis projection. With no selection every primitive is selected.
    Unselected polygons and curves retain their exact topology and payload;
    selecting a curve is an error. Point data is shared, while vertex and
    primitive attributes and ordinary/native edge groups are remapped exactly.
    Empty selections and already-triangular selections preserve geometry
    identity.

    Work is O(primitives + sum selected primitive_size^2 + output payload) and
    auxiliary/output storage is O(primitives + output vertices). Planning,
    independent polygon clipping, and fixed-width payload remapping use stable
    disjoint parallel ranges. *)

type triangulate_2d_projection =
  | Triangulate_2d_best_fit
  | Triangulate_2d_xy
  | Triangulate_2d_yz
  | Triangulate_2d_zx
  | Triangulate_2d_plane of {
      origin : Prismel.Vec3.t;
      normal : Prismel.Vec3.t;
    }
  | Triangulate_2d_point_attribute of string

val triangulate_2d :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?constraint_edges:Edge_group.t ->
  ?constraint_primitives:Group.t ->
  ?projection:triangulate_2d_projection ->
  ?seed:int64 ->
  ?split_crossing_constraints:bool ->
  ?flood_from_hull_boundary:bool ->
  ?remove_outside_constraint_polygons:bool ->
  ?silhouette_constraints:bool ->
  ?remove_outside_silhouette:bool ->
  ?ignore_non_constraint_points:bool ->
  ?remove_duplicate_points:bool ->
  ?refine:bool ->
  ?allow_constraint_splitting:bool ->
  ?minimum_angle:float ->
  ?maximum_area:float ->
  ?target_edge_length:float ->
  ?minimum_edge_length:float ->
  ?maximum_new_points:int ->
  ?regularization_steps:int ->
  ?allow_movement_of_interior_input_points:bool ->
  ?preserve_point_payload:bool ->
  ?restore_original_point_positions:bool ->
  ?keep_primitives:bool ->
  ?remove_unused_points:bool ->
  ?recompute_point_normals:bool ->
  ?split_point_group:string ->
  ?refinement_point_group:string ->
  ?triangle_group:string ->
  ?constraint_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Connect selected points with a deterministic exact-predicate Delaunay
    triangulation. Native edge and primitive groups provide constraint
    segments. [split_crossing_constraints] inserts one exact-deduplicated point
    at every proper projected crossing; when false, proper crossings are an
    error. Constraint endpoints on other constraints and collinear overlaps
    are atomized in either mode. [flood_from_hull_boundary] removes every
    triangle reachable from an unconstrained convex-hull edge without crossing
    a constraint. [remove_outside_constraint_polygons] retains the non-zero
    winding region of closed constraint primitives, supporting disjoint loops,
    overlaps, and oppositely oriented holes. [silhouette_constraints] derives
    exact projected boundaries from consistently directed polygon faces;
    [remove_outside_silhouette] also retains their non-zero projected coverage.
    [ignore_non_constraint_points] builds the seed only from exact constraint
    endpoints; other selected source points remain isolated in output payload.
    [remove_duplicate_points] deletes only non-representative selected points
    with exact duplicate projected coordinates, preserving unrelated unused or
    unselected points.
    [refine] enables bounded constrained-Delaunay quality refinement.
    [minimum_angle] is in radians; [maximum_area] and [target_edge_length]
    independently cap triangle size, [minimum_edge_length] prevents further
    work once a bad triangle's longest edge is shorter, and
    [maximum_new_points] bounds constraint and interior Steiner points.
    [allow_constraint_splitting] inserts exact midpoints for encroached
    constraints. [refinement_point_group] identifies only refinement points.
    [regularization_steps] relaxes generated interior points after refinement;
    [allow_movement_of_interior_input_points] additionally moves original
    projected interior points while constraint and hull points remain fixed.
    [restore_original_point_positions=false] places participating source and
    generated points on the selected world projection plane (or XY for a point
    attribute); unselected isolated source points retain their authored [P].
    [keep_primitives] retains every input primitive except members of
    [constraint_primitives], followed by the generated triangles. Retained
    vertex/primitive payload and groups keep exact ancestry; generated entries
    receive zero/empty defaults.
    [remove_unused_points] applies stable packed compaction after topology is
    finalized. [recompute_point_normals] rebuilds point [N] only when the input
    already had point [N].
    Projection supports a PCA best-fit plane, principal planes,
    an explicit origin/normal plane, or the first two finite components of a
    point float2/float3 coordinate attribute.
    Exact projected-coordinate duplicates use their lowest selected source
    point; original 3D positions are retained when restoration is enabled. New
    crossing positions and numeric point attributes interpolate along the
    deterministically lower indexed source constraint; integer, text, ragged,
    and point-group payload uses its nearest endpoint. [split_point_group]
    identifies generated points.

    The topology kernel uses packed triangle adjacency, walking point location,
    local Bowyer-Watson cavities, and an exact projective supertriangle at
    binary64 extremes. Point/detail payload and point groups are structurally
    shared by default. Vertex/primitive payload and edge groups are removed
    unless primitive retention requires their ancestry; stale normals are
    removed. Optional primitive and native-edge output groups record generated
    triangles and recovered constraints. Projection and materialization use
    deterministic disjoint ranges. Expected work is O(n log n), worst-case
    O(n^2), with O(n) live topology and work storage. *)

val remesh :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?iterations:int ->
  ?smoothing:float ->
  ?project:bool ->
  ?use_input_points_only:bool ->
  ?hard_points:Group.t ->
  ?hard_edges:Edge_group.t ->
  ?target_size_attribute:string ->
  ?preserve_uv_seams:bool ->
  ?uv_attribute:string ->
  ?output_hard_edges:string ->
  ?output_mesh_size:string ->
  ?output_quality:string ->
  ?recompute_point_normals:bool ->
  target_length:float ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Deterministically isotropically remesh a polygon surface toward nearly
    equilateral triangles. Each iteration splits edges longer than four
    thirds of their local target, contracts a manifold-safe independent set
    shorter than four fifths, flips a disjoint set when it strictly improves
    triangle valence, Laplacian-relaxes unconstrained points, and optionally
    projects them back to the immutable input surface.

    [target_size_attribute] supplies positive per-point absolute target sizes;
    otherwise [target_length] is uniform. [use_input_points_only] disables
    split and contraction while retaining triangulation, flips, relaxation,
    and projection. Boundary/non-manifold edges, explicit [hard_edges],
    [hard_points], and exact discontinuities of the named vertex UV attribute
    are protected. Feature and boundary points remain fixed during relaxation.
    Optional outputs record final protected/boundary edges, effective point
    mesh size, and the scale-invariant triangle quality
    [4 sqrt(3) area / sum(edge_length_squared)]. Existing point/vertex normals
    are invalidated; point normals are generated by default.

    The topology phases are serially ordered because each consumes the prior
    immutable snapshot, while edge metric scans, exact-size group creation,
    packed topology/payload remaps, relaxation, BVH projection, normal
    generation, and output diagnostics use deterministic disjoint domain
    ranges. Per iteration costs are O(points + primitives + edges log edges +
    payload) time and O(points + primitives + edges) orchestration storage,
    in addition to the immutable topology-operation outputs. Selected
    contractions satisfy the triangle link condition, preserve surviving
    orientation, and cannot share affected primitives. *)

val boolean_detect :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?source_primitives:Group.t ->
  ?collision_primitives:Group.t ->
  ?tolerance:float ->
  ?include_coplanar:bool ->
  ?intersecting_group:string option ->
  ?intersections_attribute:string ->
  ?count_attribute:string ->
  ?self_intersecting_group:string ->
  ?self_intersections_attribute:string ->
  ?self_count_attribute:string ->
  collision:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Detect source/collision polygon intersections without changing source
    topology or payload. Both inputs are deterministically triangulated only
    inside packed surface indexes. [source_primitives] and
    [collision_primitives] restrict their respective inputs. Touching and,
    by default, coplanar-overlapping triangles count as intersections within
    the non-negative world-space [tolerance].

    [intersecting_group] defaults to the source primitive group
    [boolean_intersections]; pass [None] to omit it. The optional packed
    integer-array [intersections_attribute] stores the sorted unique collision
    primitive numbers intersecting each source primitive, while
    [count_attribute] stores each row length. At least one output is required.
    Existing same-name metadata is replaced atomically.

    [self_intersecting_group], [self_intersections_attribute], and
    [self_count_attribute] request the corresponding AxA results on the source
    surface. Every unordered triangle pair is tested once, triangulation pairs
    from one source primitive are omitted, and ordinary contacts at shared
    vertices/edges are suppressed. Genuine overlap beyond a shared boundary
    and duplicate faces remain intersections. Self lists are symmetric: if
    primitive [a] names [b], [b] names [a].

    Surface construction costs O((A + B) log(A + B)); candidate traversal is
    expected O((A + B) log B + C), narrow-phase triangle testing is O(C), and output
    sorting is O(sum k log k) over source rows. Auxiliary storage is
    O(A + B + C + I), where [C] is the BVH candidate count and [I] the retained
    primitive-pair payload. Broad phase, narrow testing, row sorting, and packed group output
    use deterministic disjoint parallel ranges. *)

val intersection_analysis :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?source_primitives:Group.t ->
  ?collision_primitives:Group.t ->
  ?tolerance:float ->
  ?include_coplanar:bool ->
  ?input_attribute:string option ->
  ?primitive_attribute:string option ->
  ?primitive_uvw_attribute:string option ->
  ?point_attribute:string option ->
  ?collision:Geometry.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create point-only geometry at triangle and polygon-curve intersections. With one input the
    operation finds AxA self-intersections; [collision] selects AxB analysis.
    Inputs are not passed through. Selected polygon primitives must be
    triangles; open and closed polygon curves are analyzed segment by segment.

    The four optional point attributes default to [sourceinput], [sourceprim],
    [sourceprimuv], and [sourcepoint]. Passing [None] suppresses an attribute.
    Integer provenance is stored in aligned CSR rows. [sourceprimuv] stores
    three floats per incident primitive record. Triangle values are
    barycentric; curve values are [(u, 0, 0)] with [u] spanning the complete
    primitive. [sourcepoint] stores the corresponding existing input point or
    [-1]. *)

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

type reverse_operation =
  | Reverse_vertices
  | Shift_vertices of int

val reverse :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?operation:reverse_operation ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Reverse or cyclically shift selected polygon/curve primitive corners.
    [Reverse_vertices] is the default and invalidates point/vertex [N] when at
    least one primitive changes winding. [Shift_vertices offset] preserves
    shape, winding, and point attributes while remapping every vertex-owned
    field/group by the same signed, wrapping offset. Unselected primitives
    retain exact topology and payload order. Empty selections and shifts which
    are multiples of every selected primitive size preserve geometry identity.

    Work and output storage are O(vertices + vertex payload); topology and
    fixed-width vertex payload planes fill in deterministic disjoint ranges.
    Point, primitive, and detail payloads remain structurally shared. *)

val smooth :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?constrained_points:Group.t ->
  ?boundary:smooth_boundary ->
  ?iterations:int ->
  ?method_:Attribute_ops.blur_method ->
  ?mode:Attribute_ops.blur_mode ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?recompute_normals:bool ->
  ?original_blend:float ->
  ?smoothed_blend:float ->
  attributes:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Smooth canonical [P] and matching point-owned floating attributes over the
    shared topology graph. A primitive selection affects all referenced
    points. [Smooth_unshared] locks topology boundaries;
    [Smooth_group_boundary] additionally locks edges separating selected and
    unselected primitives. [constrained_points] always remain fixed.

    The numeric kernel is the same deterministic packed implementation used
    by {!Attribute_ops.blur_points}: uniform or inverse-original-edge-length
    weights, constant or alternating passes, optional receiver/neighbor
    controls, and explicit original/smoothed composition. If [P] changes and
    the input carried normals, [recompute_normals] replaces them with fresh
    point normals; otherwise stale point/vertex normals are removed.

    Work is O(points + vertices + iterations * attribute_components * edges),
    with O(points + edges + attribute_components * points) auxiliary storage.
    Selection and iteration fills use disjoint packed ranges and are exact
    across domain counts. *)

val ray :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?collision_primitives:Group.t ->
  ?method_:ray_method ->
  ?direction:ray_direction ->
  ?direction_mode:ray_direction_mode ->
  ?surface_hit:ray_surface_hit ->
  ?samples:int ->
  ?jitter_scale:float ->
  ?seed:int ->
  ?combine:ray_combine ->
  ?min_distance:float ->
  ?max_distance:float ->
  ?tolerance:float ->
  ?scale:float ->
  ?lift:float ->
  ?distance_attribute:string ->
  ?primitive_attribute:string ->
  ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string ->
  ?hit_group:string ->
  ?normal_attribute:string ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  source:Geometry.t ->
  collision:Geometry.t ->
  unit ->
  (Geometry.t, Error.t) result
(** Project selected source points to a collision polygon surface by closest
    distance or normalized rays. Directional projection supports constant,
    point-attribute, authored/computed-normal, reverse, bidirectional, first-
    surface, and last-surface policies. Two to 1,024 samples retain one exact
    unjittered ray and add deterministic per-point cone-disk jitter. Average,
    upper-median, shortest, and longest successful-ray combiners move along
    the unjittered chosen direction by the combined world-space distance.
    Average interpolation emits all successful barycentric drivers with
    normalized equal ray weights; scalar primitive output uses the hit nearest
    the mean. Averaged geometric normals retain their arithmetic length while
    normal lift uses their normalized direction. If a requested collision
    point field matches [normal_attribute], the imported field wins. Scale and normal lift transform hits;
    misses retain source positions. Optional outputs include distance,
    original collision primitive, exact source-vertex/weight CSR provenance,
    geometric hit normal, and hit membership. Source point/vertex/primitive/
    detail fields and ordinary groups can be imported through the shared
    Attribute Interpolate kernel.

    Collision construction is O(corners + triangles log triangles) expected
    time and O(triangles) storage. Ordinary closest/ray queries are expected
    O(log triangles) each, with O(source points + imported output +
    domains * samples) operation storage. Average imported provenance repeats
    the chosen traversal after prefix sizing, avoiding O(points * samples)
    temporary hit storage. Degenerate overlapping BVH bounds can force O(triangles) query
    time. Query and output ranges are disjoint and exact across domain counts. *)

val mirror :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?keep_original:bool ->
  origin:Prismel.Vec3.t ->
  normal:Prismel.Vec3.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Reflect geometry across an arbitrary plane. Polygon winding is corrected,
    vertex attributes/groups and native edge groups are remapped, and point/vertex [N] values
    are reflected. With [keep_original=true] (the default), the source is
    followed by the mirrored copy in stable order. O(payload) time/output;
    packed point, vertex, and primitive ranges are parallelized. *)

type clip_keep = Above | Below | All

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
  origin:Prismel.Vec3.t ->
  normal:Prismel.Vec3.t ->
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
  ?local_normal:Prismel.Vec3.t ->
  transform:Prismel.Mat4.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transform-orientation convenience for [clip]. The transformed local origin
    defines the plane origin and the transformed [local_normal] (default +Y)
    defines its direction. Translation, rotation, and scale therefore compose
    through one matrix while [distance] remains measured after normalization. *)

type subdivision_scheme = Catmull_clark | Loop | Bilinear
type subdivision_boundary_interpolation =
  | Subdivide_boundary_none
  | Subdivide_boundary_edge_only
  | Subdivide_boundary_edge_and_corner
type subdivision_face_varying_interpolation =
  | Subdivide_fvar_none
  | Subdivide_fvar_corners_only
  | Subdivide_fvar_corners_plus1
  | Subdivide_fvar_corners_plus2
  | Subdivide_fvar_boundaries
  | Subdivide_fvar_all
type subdivision_triangle_policy =
  | Subdivide_triangles_catmull_clark
  | Subdivide_triangles_smooth
type subdivision_creasing_method =
  | Subdivide_creasing_uniform
  | Subdivide_creasing_chaikin
type subdivision_crack_policy =
  | Subdivide_do_not_close
  | Subdivide_pull_no_edge_division
  | Subdivide_pull_divide_edges of float
  | Subdivide_pull_triangulate of float
  | Subdivide_stitch_no_edge_division
  | Subdivide_stitch_divide_edges
  | Subdivide_stitch_triangulate

type crease_operation = Crease_add | Crease_set | Crease_delete

val crease :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?operation:crease_operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Author a vertex [creaseweight] field over unique topology edges for direct
    consumption by {!subdivide}. An omitted edge group selects every edge.
    [Crease_add] (the default) adds [weight] to the maximum existing incident
    corner value, [Crease_set] replaces it, and [Crease_delete] clears it.
    Every incident corner receives the same result, including on non-manifold
    edges; unrelated corner values are preserved exactly. A completely cleared
    field is removed.

    [add_vertex_color] creates or updates vertex float4 [Cd], coloring both
    endpoints of every resulting positive crease red while preserving other
    vertex colors. Existing point float4 [Cd] is expanded as the uncreased
    default; otherwise the default is white.

    Work is O(vertices + edges) with O(vertices + edges) output/scratch in the
    add/visualization paths and O(vertices) otherwise. Validation, unique-edge
    reduction, and disjoint corner/color fills run in parallel with stable
    results. Crease values must be finite and non-negative; malformed storage,
    topology affinity, overflow, and cancellation fail atomically. *)

val attribute_fade :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?start_source:Geometry.t ->
  ?hold_source:Geometry.t ->
  ?fade_attribute:string ->
  ?start_attribute:string ->
  ?start_retime:(float * float) ->
  ?hold_scale_attribute:string ->
  frame:float ->
  ?frame_offset:float ->
  ?fade_in:float ->
  ?fade_hold:float ->
  ?fade_out:float ->
  ?fade_in_ramp:(float * float) list ->
  ?fade_out_ramp:(float * float) list ->
  ?visualize:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Scale a scalar point attribute through a frame-domain fade envelope. A
    missing fade field starts at one. [start_attribute] defaults to zero and
    [hold_scale_attribute] to one; each may be read by point number from its
    independently supplied equal-cardinality input. [start_retime=(offset,
    scale)] computes [offset + value * scale] before [frame_offset].

    The default timings and linear ramps match Houdini Attribute Fade: two
    frames in, no hold, and two frames out. Custom ramps are finite,
    endpoint-complete piecewise-linear functions over [[0,1]]. Selected points
    are modified while other fade values remain exact. [visualize] replaces
    point float4 [Cd] with grayscale faded values and alpha one.

    Work is O(points * log ramp-knots), with one output float plane and four
    additional planes only for visualization. Inputs are borrowed, unchanged
    topology and payload are structurally shared, and block-parallel fills are
    byte-identical across domain counts. Invalid storage, cardinality,
    non-finite values, negative durations/scales, overflow, and cancellation
    fail atomically. *)

type poly_cut_element = Poly_cut_points | Poly_cut_edges
type poly_cut_strategy = Poly_cut_remove | Poly_cut_cut
type poly_cut_detection =
  | Poly_cut_all
  | Poly_cut_crossing of { attribute : string; value : float }
  | Poly_cut_change of { attribute : string; threshold : float }

val poly_cut :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?cut_points:Group.t ->
  ?cut_edges:Edge_group.t ->
  ?element:poly_cut_element ->
  ?strategy:poly_cut_strategy ->
  ?detection:poly_cut_detection ->
  ?keep_closed:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Break selected polygon curves at point endpoints or directed topology-edge
    events. [Poly_cut_all] treats every selection-eligible edge as invalid.
    [Poly_cut_crossing] accepts a scalar point float/integer field and cuts at
    its exact linear threshold crossing. [Poly_cut_change] accepts every
    numeric point width, uses scalar absolute or tuple Euclidean change, and
    subdivides a cut edge into [ceil(change/threshold)] disconnected segments.

    Removing points drops marked endpoints and their adjacent curve segments;
    cutting points retains them as independently owned fragment endpoints.
    Removing edges drops the selected invalid segments; cutting edges inserts
    interpolated, disconnected endpoints. A point or native-edge restriction
    applies only to its corresponding [element] mode. Selected closed inputs
    optionally close every viable fragment with a new topology edge.

    Point and vertex numeric payload is linearly interpolated; discrete and
    ragged payload, as well as ordinary groups, use the nearest endpoint.
    Primitive payload follows exact ancestry, detail payload is shared, and
    native edge groups follow every retained/subdivided source edge while new
    closure edges remain ungrouped. Removed point-mode endpoints are compacted
    only when no retained corner uses them; pre-existing free points survive.

    Work and auxiliary memory are O(points + vertices + primitives + output),
    where output includes requested change subdivisions. Classification,
    fragment planning, interpolation, and payload fills use stable disjoint
    ranges. Cardinality, topology affinity, finite operated fields, threshold,
    interpolation, and cancellation failures are atomic. *)

type separate_pieces_mode =
  | Separate_pieces_separate
  | Separate_pieces_move_back

val separate_pieces :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?owner:Attribute.owner ->
  ?translation_attribute:string ->
  ?axis:Prismel.Vec3.t ->
  ?gap:float ->
  mode:separate_pieces_mode ->
  piece_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Pack integer- or text-identified pieces into non-overlapping projection
    intervals along [axis], in stable first-occurrence order. [gap] defaults
    to [0.001] and is the non-negative distance between adjacent intervals. Point-owned identities
    require every primitive to reference one piece; primitive-owned identities
    require shared points to agree. Disconnected components with the same key
    move together.

    Separate mode stores its rigid translation as a float3 attribute on the
    piece owner's domain. Move-back mode subtracts that field after unrelated
    nodes that preserve positions and the translation attribute. Floating-point
    roundoff may prevent bit-identical recovery. Topology, all other
    payload, groups, and normals are structurally shared.

    Work is O(points + vertices + primitives + pieces), with O(points + pieces)
    auxiliary storage. Piece discovery and stable CSR construction are
    sequential; ownership validation, projection, and position fills use
    deterministic disjoint parallel ranges. Malformed
    storage, mixed-piece primitives/shared points, non-finite data, overflow,
    and cancellation fail atomically. *)

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

val edge_divide :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?edges:Edge_group.t ->
  ?divisions:int ->
  ?share_points:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Split every selected polygon or polygon-curve edge into [divisions]
    equal segments. No edge selection is an identity operation, matching the
    Edge Divide empty-group contract. With [share_points=true], all incident
    uses of one topology edge share a single ordered sequence of inserted
    points. Otherwise every incident primitive edge receives private points.

    Positions and numeric point/vertex attributes interpolate linearly;
    integer, text, and ragged fields use the nearest stable endpoint.
    Primitive/detail payload remains exact. New ordinary point/vertex group
    members require both endpoints to be members, and every native source edge
    group propagates to all child segments.

    Work is O(points + vertices + primitives + edges + output payload), with
    exact output cardinality and O(points + vertices + edges) planning storage.
    Independent point, topology, payload, and edge-ancestry ranges use the
    reusable domain pool and are byte-identical across domain counts. *)

type delete_topology_policy =
  | Destroy_touched_primitives
  | Heal_primitives

type blast_attribute_owner = Blast_points | Blast_primitives

type blast_attribute_mode =
  | Blast_below of float
  | Blast_range of { minimum : float; maximum : float }
  | Blast_width of { center : float; width : float }

type blast_attribute_output = Blast_delete | Blast_group of string

type poly_extrude_divide =
  | Extrude_individual
  | Extrude_connected_components

type poly_fill_mode =
  | Fill_single_polygon
  | Fill_triangles
  | Fill_triangle_fan

type clean_overlap_policy =
  | Keep_first_overlap
  | Delete_overlap_pairs

val delete :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selected:bool ->
  ?compact_points:bool ->
  ?policy:delete_topology_policy ->
  Group.t -> Geometry.t -> (Geometry.t, Error.t) result
(** Delete selected elements, or non-selected elements when [selected=false].
    Primitive selections remove whole primitives. Point/vertex selections use
    [Destroy_touched_primitives] by default; [Heal_primitives] removes selected
    corners and reconnects retained polygon/curve order, dropping results below
    their valid minimum cardinality. Point selections always remove selected
    point records. [compact_points] additionally removes every point unused by
    retained topology.

    Positions, every ordinary attribute owner, every ordinary group owner, and
    native edge groups are
    remapped in stable source order. Healing removes point/vertex [N] because
    the surface changed; whole-primitive deletion preserves valid normals.
    O(points + vertices + primitives + payload) time and linear
    auxiliary/output storage; independent packed payload copies are
    parallelized. *)

val blast_by_attribute :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?base:Group.t ->
  ?invert:bool ->
  ?remove_unused_points:bool ->
  owner:blast_attribute_owner ->
  attribute:string ->
  mode:blast_attribute_mode ->
  output:blast_attribute_output ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select points or primitives from a scalar float/integer attribute, either
    deleting the result or replacing one same-owner output group. [Blast_below]
    is strict; range and width endpoints are inclusive. [invert] complements
    the condition only inside [base]. Primitive deletion can compact all
    unused points; point deletion destroys every touched primitive through the
    shared Delete planner.

    Classification is O(elements) time with one packed bit per element and is
    parallel across independent bytes. Deletion retains Delete's stable
    O(points + vertices + primitives + payload) remapping. Float parameters
    and operated attribute values must be finite; malformed input and
    cancellation publish no partial geometry. *)

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

val convex_hull :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?preserve_point_payload:bool ->
  ?source_point_attribute:string ->
  ?hull_group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Construct the convex hull of every point referenced by an optional typed
    selection. Exact predicates determine duplicates, affine dimension,
    visibility, and horizon topology. One point remains free, collinear input
    becomes an endpoint polyline, coplanar input becomes one convex polygon,
    and full-dimensional input becomes an outward closed triangular surface.

    Point and detail payload is preserved by exact source-point ancestry by
    default; stale [N], corner/primitive payload, and topology-affine edge
    groups are removed. [source_point_attribute] records that ancestry and
    [hull_group] selects all generated primitives.

    Expected Quickhull time is O(n log n), with the usual O(n^2) worst case;
    auxiliary storage is O(n + f), where [f] includes live and retired work
    faces. Initial conflict classification, reclassification, payload remap,
    and materialization use deterministic disjoint domain ranges. *)

type centroid_piece_owner =
  | Centroid_piece_points
  | Centroid_piece_primitives

type centroid_run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of {
      owner : centroid_piece_owner;
      attribute : string;
    }

type centroid_method =
  | Centroid_point_mass
  | Centroid_bounding_box
  | Centroid_convex_hull

val extract_centroid :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?run_over:centroid_run_over ->
  ?method_:centroid_method ->
  ?source_primitive_attribute:string ->
  ?piece_output_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Emit one free point for the whole detail, each primitive, or every stable
    first-occurrence integer/text piece. Point-owned pieces contain their
    classified points; primitive-owned pieces contain each referenced point
    once, even across several primitives.

    [Centroid_point_mass] treats every included point as equal mass,
    [Centroid_bounding_box] returns the scale-safe AABB center, and
    [Centroid_convex_hull] invokes the exact shared hull kernel before taking
    its length-, area-, or signed-volume center. The primitive mode can record
    source primitive numbers; piece mode retains its identifier as a point
    attribute under the source name or [piece_output_attribute]. Detail
    attributes are structurally shared, while topology-affine payload is
    intentionally absent from the point-only result.

    Classification and stable radix-CSR construction are O(points + vertices
    + primitives + machine-word-bits * incidence); point-mass and bounds
    reductions are linear.
    Convex-hull mode adds each piece's expected O(n log n), worst O(n^2), hull
    cost. Independent non-hull centers use deterministic disjoint parallel
    ranges. Empty pieces, malformed identity fields, non-finite coordinates,
    cardinality overflow, and cancellation fail atomically. *)

type extract_curve_cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

val extract_point_from_curve :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?cut:extract_curve_cut ->
  ?point_attributes:string ->
  ?copy_primitive_attributes:bool ->
  ?primitive_attributes:string ->
  ?curve_u_attribute:string ->
  ?number_cuts_attribute:string ->
  ?curve_number_attribute:string ->
  distance_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Emit disconnected points wherever the named scalar point distance field
    equals a constant or per-primitive scalar cut value on selected polygon
    curves. Every exact matching source vertex is emitted once per curve;
    strict linear crossings add one interpolated point. A matching plateau
    therefore emits each authored plateau vertex, while a closed seam emits
    its first vertex only once.

    Canonical output [P] is always scale-safe linearly interpolated. Compiled
    point-attribute patterns add numeric interpolation and stable nearest-side
    discrete/ragged transfer. Optional primitive patterns copy curve fields to
    point ownership. Curve U is normalized uniform-edge parameter, number of
    cuts is constant per source curve, curve number is the original primitive
    index, and detail attributes remain structurally shared. Name collisions
    are rejected rather than silently overwritten.

    Classification, exact-cardinality materialization, payload interpolation,
    and diagnostics use deterministic disjoint ranges. Ordinary curves schedule
    by primitive; curves whose average size exceeds [grain] use stable
    primitive-major edge blocks so one long curve remains parallel. Time is
    O(vertices + output payload), auxiliary storage is O(primitives +
    vertices/grain + output), and ordering is primitive-major then increasing
    edge parameter. Polygon faces, malformed selections/patterns/fields/names,
    non-finite values or positions, overflow, and cancellation fail atomically.
    *)

type bound_shape =
  | Bound_box of { divisions : int * int * int }
  | Bound_sphere of { segments : int; rings : int; minimum_radius : float }

val bound :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?shape:bound_shape ->
  ?lower_padding:Prismel.Vec3.t ->
  ?upper_padding:Prismel.Vec3.t ->
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
  ?cancel:Cancel.t -> ?grain:int -> ?padding:Prismel.Vec3.t -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Create a hard-normal triangle box around point bounds. Empty geometry,
    invalid/negative padding, and zero-thickness output are rejected; use
    positive padding on collapsed axes for planar or linear input. *)

type match_size_fit =
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
  ?grain:int -> from:Prismel.Vec3.t -> into:Prismel.Vec3.t -> Geometry.t ->
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
  ?justify:Prismel.Vec3.t ->
  ?target_justify:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
  ?scale:float ->
  ?target_center:Prismel.Vec3.t ->
  ?target_size:Prismel.Vec3.t ->
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

type copy_target_owner = Copy_target_points | Copy_target_vertices
  | Copy_target_primitives
type copy_target_operation = Copy_target_nothing | Copy_target_copy
  | Copy_target_add | Copy_target_subtract | Copy_target_multiply
type copy_target_attribute_rule = {
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
  transforms:Prismel.Mat4.t array ->
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
  ?transform:Prismel.Mat4.t -> ?primitives:Group.t ->
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
  ?translate:Prismel.Vec3.t ->
  ?rotate:Prismel.Vec3.t ->
  ?scale:Prismel.Vec3.t ->
  ?shear:Prismel.Vec3.t ->
  ?uniform_scale:float ->
  ?pivot:Prismel.Vec3.t ->
  ?pivot_rotation:Prismel.Vec3.t ->
  ?invert:bool ->
  unit ->
  (Prismel.Mat4.t, Error.t) result
(** Compose one finite affine transform. Rotation values are radians. Shear
    components are X-on-XY, X-on-XZ, and Y-on-YZ. The pivot translates and
    rotates the local transform frame. [invert] rejects singular output. *)

val transform_selected :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:deform_selection ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Prismel.Mat4.t ->
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
  Prismel.Mat4.t ->
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
  ?origin:Prismel.Vec3.t ->
  ?direction:Prismel.Vec3.t ->
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

val transform : ?grain:int -> Prismel.Mat4.t -> Geometry.t -> Geometry.t
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
  ?origin:Prismel.Vec3.t ->
  ?direction:Prismel.Vec3.t ->
  ?up:Prismel.Vec3.t ->
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
  ?frequency:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
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
  seed:Prismel.Rand.t ->
  scale:float ->
  ?axis_scales:Prismel.Vec3.t ->
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

type point_generate_mode =
  | Generate_total of int
  | Generate_per_point of {
      points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string }

val point_generate :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?keep_input:bool ->
  ?seed:Prismel.Rand.t ->
  ?generated_group:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  mode:point_generate_mode ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Generate free points at the origin, deterministically replicate selected
    source points, or Bernoulli-sample selected source points from a point
    float probability attribute. Fractional per-point counts use deterministic
    stochastic rounding keyed by source point number and [seed].

    Original geometry may remain as a stable prefix. Generated point positions
    and matching point attributes follow source ancestry; unmatched generated
    fields receive typed zero/empty defaults. Detail fields use an independent
    pattern. [source_point_attribute] and per-source [source_index_attribute]
    integer provenance are emitted under configurable distinct names, and an
    optional point group marks exactly the generated suffix.

    Cardinality is planned before allocation. Position, fixed/ragged payload,
    provenance, and group fills use disjoint reusable-pool ranges. Keeping input
    structurally shares topology planes and rebinds unchanged native-edge bits;
    auxiliary storage is O(input points + output points), with exact ordering
    across domain counts. *)

type point_replicate_shape =
  | Replicate_point
  | Replicate_box
  | Replicate_sphere
  | Replicate_disk
  | Replicate_line
  | Replicate_custom

type point_replicate_velocity_stretch =
  | Replicate_no_velocity_stretch
  | Replicate_scaled_velocity
  | Replicate_velocity_only

val point_replicate :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?keep_input:bool ->
  ?seed:Prismel.Rand.t ->
  ?id_attribute:string ->
  ?generated_group:string ->
  ?copy_point_attributes:string ->
  ?keep_source_attributes:bool ->
  ?transform_attributes:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  ?shape:point_replicate_shape ->
  ?custom_shape:Geometry.t ->
  ?center:Prismel.Vec3.t ->
  ?size:Prismel.Vec3.t ->
  ?orientation:Prismel.Vec3.t ->
  ?uniform_scale:float ->
  ?quasi_stratified:bool ->
  ?velocity_stretch:point_replicate_velocity_stretch ->
  ?velocity_scale:float ->
  ?inherit_velocity:float ->
  ?radial_velocity:float ->
  ?noise_amplitude:Prismel.Vec3.t ->
  ?noise_frequency:Prismel.Vec3.t ->
  ?noise_offset:Prismel.Vec3.t ->
  ?noise_roughness:float ->
  ?noise_attenuation:float ->
  ?noise_turbulence:int ->
  ?noise_seed:int ->
  points_per_point:float ->
  ?scale_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Generate a deterministic local cloud around each selected input point.
    Point, box, volume-uniform sphere, area-uniform disk, line, and custom point-cloud
    shapes are normalized in local +Z space, then transformed through the same
    [pscale]/[scale]/[orient]/[N]/[up]/[v]/[rot]/[pivot]/[trans]/[transform]
    contract as {!copy_to_points}. Custom clouds emit [shapeptnum].
    Matching point float3 [transform_attributes] are additionally transformed
    as vectors; [N] uses the scale-safe inverse transpose and is removed when
    any selected source frame that emits points is singular. [P] is always
    handled exactly once.

    Counts, point/detail ancestry, input retention, generated grouping, and
    optional source metadata reuse Point Generate. Existing integer [id]
    values stabilize random clouds across point renumbering. Quasi-stratified
    sampling uses deterministic source-local low-discrepancy coordinates.
    Velocity may be inherited and augmented radially; velocity stretching can
    compose with or replace source geometric scale. Optional allocation-free
    vector fBm perturbs local coordinates and uses point [rest], when present,
    to keep noise stable while source positions move.

    Cardinality is exact before shape allocation. Source frames are evaluated
    once and generated point ranges are disjoint and byte-identical across
    domain counts. *)

val color_by_height :
  ?cancel:Cancel.t -> ?grain:int -> low:Prismel.Color.t -> high:Prismel.Color.t -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Create or replace point [Cd] by normalized Y extent. *)

val clean :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?epsilon:float ->
  ?remove_degenerate:bool ->
  ?consolidate_distance:float ->
  ?overlaps:clean_overlap_policy ->
  ?reverse_winding:bool ->
  ?remove_nan_points:bool ->
  ?remove_unused_points:bool ->
  ?delete_unused_groups:bool ->
  ?point_attributes:string ->
  ?vertex_attributes:string ->
  ?primitive_attributes:string ->
  ?detail_attributes:string ->
  ?point_groups:string ->
  ?vertex_groups:string ->
  ?primitive_groups:string ->
  ?edge_groups:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Run a stable polygon/curve cleanup pipeline. Optional exact/tolerance point
    consolidation precedes degeneracy removal. Polygon area is compared with
    [epsilon] squared, while curve length is compared directly. Overlap repair
    recognizes cyclic rotations and reversed winding of polygons which share
    the same point vertices, retaining the first polygon or deleting every
    member of an overlap class. Optional winding reversal, NaN-point removal,
    point compaction, empty-group deletion, and owner-specific attribute/group
    patterns complete the pipeline. Canonical [P] cannot be deleted.

    Primitive classification and canonical overlap preparation fill disjoint
    packed ranges in parallel; stable deletion/compaction preserves all
    surviving attribute and group ancestry. Expected time is linear in input
    and output payload for bounded primitive degree; general canonicalization
    is O(vertices), with O(points + primitives + output) temporary storage. *)

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

val poly_extrude :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?split_edges:Edge_group.t ->
  ?divide:poly_extrude_divide ->
  ?divisions:int ->
  ?output_front:bool ->
  ?output_back:bool ->
  ?output_side:bool ->
  ?front_group:string ->
  ?back_group:string ->
  ?side_group:string ->
  ?front_boundary_group:string ->
  ?back_boundary_group:string ->
  distance:float -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Extrude selected polygon faces as independent elements or stable
    shared-edge connected components. Connected fronts share new points,
    displace along selected-face averaged point normals, omit internal sides,
    honor topology-affine split edges, and emit [divisions] straight side rows.
    Unselected polygons and curves pass through. Front/back/side geometry and
    primitive groups are independently controlled; front/back boundary outputs
    are native edge groups. Attributes and ordinary/native edge groups remap
    by stable ancestry and point/vertex normals are invalidated.

    The compatibility default retains the original allocation-tight
    individual-face kernel and exact ordering. The connected planner is
    O(points + vertices + primitives + edges + output payload) expected time,
    uses O(selected topology + output) auxiliary memory, fills independent
    ranges in parallel, and is exact across domain counts. Connected selection
    touching a non-manifold edge fails atomically because radial side ordering
    is not represented by polygon topology. *)

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

val convert_line :
  ?cancel:Cancel.t -> ?grain:int -> ?edges:Edge_group.t ->
  ?connect_path:bool -> ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  ?remove_unused_points:bool -> ?length_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Replace every selected unique, non-degenerate topology edge with one open
    two-point polygon curve. Output uses canonical point-number order and does
    not duplicate points. Point/detail attributes, point groups, and native
    edge groups are preserved; new primitives intentionally discard source
    vertex/primitive payloads. [length_attribute] creates a primitive float
    value and rejects non-finite or unrepresentable edge lengths.
    [connect_path] instead emits maximal paths from the selected edge graph,
    spatially welding compatible endpoints within [maximum_distance].
    [connect_only_to_other_end_points] restricts welding to degree-one pairs;
    [make_isolated_loops_closed] emits isolated cycles as polygons. In this
    mode [length_attribute] is the complete resulting path length.
    [remove_unused_points] performs stable packed compaction.

    Standard mode takes O(vertices + edges * radix_digits + point payload)
    time. Connect Path takes O(vertices + edges + output + payload) plus
    expected spatial-candidate work when distance welding is enabled. Both use
    O(edges + points + output) auxiliary/output storage. Topology indexing,
    radix planning, and graph tracing are deterministic; independent topology,
    length, bitset, and compaction fills run over disjoint parallel ranges. *)

type curve_end_mode = Open_curve | Close_curve | Unroll_curve

val curve_ends :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> curve_end_mode ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Open, close, or unroll selected polygon curves. Unroll converts a closed
    curve to an open curve with its first corner repeated at the end, retaining
    the closing segment. All payload owners and native edge groups remap
    exactly in O(vertices + payload) time. *)

type ends_mode =
  | Ends_open
  | Ends_close_straight
  | Ends_unroll_shared
  | Ends_unroll_new

val ends :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ends_mode ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Change the U closure of selected polygon faces and polygon curves.
    [Ends_open] removes the closing edge. [Ends_close_straight] turns an open
    curve into a polygon face, removing a repeated shared terminal corner when
    needed. Unroll modes remove the face while preserving its closing segment:
    the shared form repeats the first point reference, while the new-point form
    duplicates the first point and every point payload/group row.

    Vertex payload follows exact corner ancestry, primitive/detail payload is
    shared, and native edge membership follows only real source edges; a newly
    authored straight closing edge remains unselected. Planning is O(primitives)
    and construction is O(points + vertices + payload + edges), with exact-sized
    arrays and deterministic disjoint parallel fills. *)

type curve_join_end =
  | Join_curve_start
  | Join_curve_end

type curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

val join_curves :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?picked_ends:curve_join_pick array ->
  ?orient_closest:bool -> ?connect_closest_ends:bool ->
  ?only_connected:bool -> ?group_size:int -> ?keep_originals:bool ->
  ?tolerance:float -> ?wrap:bool -> Geometry.t -> (Geometry.t, Error.t) result
(** Join selected open polygon curves in stable primitive order, or in the
    explicit order of an ordered primitive group. The next curve
    may be reversed to connect its closest end; endpoints within [tolerance]
    weld by retaining the previous endpoint, while separated ends receive a
    straight bridge. [only_connected] starts a new chain instead of bridging.
    [picked_ends] is an alternative selection that reproduces viewport-authored
    endpoint order. The first pick in each fixed-size subgroup marks its
    outgoing end; every later pick marks the incoming end connected to the
    previous curve. Picked primitive indices must be unique and cannot be
    combined with [primitives] or [connect_closest_ends].
    [connect_closest_ends] instead greedily chooses the globally nearest
    unused endpoint after every curve, anchoring the first selected curve and
    using stable primitive/end ties. Its removable balanced endpoint k-d tree
    avoids a quadratic all-pairs scan for ordinary spatial distributions.
    [group_size] starts a new output chain after every positive number of
    selected curves. [keep_originals] retains all source primitives in stable
    input order and appends the joined chains while sharing the source point
    plane; otherwise selected primitives are replaced in place.
    Joined primitive attributes come from the first source and primitive groups
    use union membership. Original native edges retain membership; welded
    substitutions do not lose their source edge, while bridge/wrap edges remain
    unselected. Expected O(curves + vertices + payload) time, excluding the
    expected-linear reverse-topology indexes needed only when edge groups exist.
    Pick validation and orientation use O(curves) auxiliary storage; without
    [only_connected], independent picked pairs plan over deterministic parallel
    ranges, while connected-only partitioning retains its ordered dependency.
    Global closest-end planning adds expected O(curves log curves) time and
    O(curves) auxiliary storage; its greedy dependency is sequential, while
    endpoint preparation and output/payload fills use stable parallel ranges. *)

val poly_path :
  ?cancel:Cancel.t -> ?grain:int -> ?connect_end_points:bool ->
  ?maximum_distance:float -> ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool -> Geometry.t ->
  (Geometry.t, Error.t) result
(** Replace unique non-self topology edges with stable maximal polygon paths.
    Paths stop at points connected to other than two distinct neighbors.
    Optional endpoint connection transitively rewires spatially close
    components onto the lowest point number before duplicate reduction; it can
    be restricted to endpoint pairs. Isolated loops remain open curves with a
    repeated endpoint unless requested as closed polygon surfaces. Point/detail
    payloads retain identity, vertex payloads follow stable source corners,
    primitive attributes use the lowest contributing primitive, and
    primitive/native edge groups use union ancestry.

    Expected O(vertices + unique edges + payload) time and O(points + edges +
    output + payload) storage. Endpoint connection adds O(points + candidate
    proximity pairs) expected time and O(points) clustering storage; a dense
    threshold can expose quadratically many candidate pairs. Graph planning is
    deterministic and sequential;
    independent output and payload planes use disjoint parallel ranges. *)

type carve_keep = Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Attribute_replace | Attribute_scale

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

val sweep :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?backbones:Group.t ->
  ?cross_sections:Group.t ->
  ?connectivity:grid_connectivity ->
  ?tangent:sweep_tangent ->
  ?continuous_closed:bool ->
  ?transform_attributes:bool ->
  ?reverse_cross_sections:bool ->
  ?scale:float ->
  ?roll:float ->
  ?twist:float ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string option ->
  ?cross_section_prefix:string ->
  backbone:Geometry.t ->
  cross_section:Geometry.t ->
  unit ->
  (Geometry.t, Error.t) result
(** Sweep every selected polygon cross-section curve along every selected
    polygon backbone curve. Cross-sections use local XY with +Y up and local
    +Z along the backbone; full XYZ profiles are accepted. Output ordering is
    stable backbone-major Cartesian order. Connectivity supports points,
    cross-section rows, backbone columns, both curve families, quads, and the
    three triangle splits shared with {!grid}.

    Tangents may average normalized adjacent edges, use central differences,
    use the previous/next edge, or remain world +Z. Parallel-transport frames
    use world +Y when no explicit transform attributes exist and optionally
    distribute closed-curve holonomy. With [transform_attributes], point
    [orient] takes frame precedence, point [N] replaces the tangent, point
    [up] fixes the projected up direction, and scalar [pscale] plus float3
    [scale] scale profile coordinates. [roll] is a constant radian rotation;
    [twist] is distributed by backbone arc length.

    Open backbones with closed profiles may receive oppositely wound polygon
    caps. Optional UVs are arc-length parameterized and seam-safe on polygon
    surfaces. Backbone payload retains its names; cross-section attributes,
    ordinary groups, and native edge groups receive [cross_section_prefix]
    (default ["cross_section_"]) so both input ancestries remain available.
    Point [N] is omitted because an input tangent is not an output surface
    normal.

    Cardinalities are preflighted and packed planes are allocated exactly.
    Ordered frame work is O(backbone vertices); generated points, topology,
    payload, and edge-group classification use deterministic disjoint parallel
    ranges. Total work and output are O(sum over selected curve pairs of
    backbone vertices times profile vertices); auxiliary storage is linear in
    selected input and output cardinality. Failure and cancellation are
    atomic. *)

type uv_projection =
  | Planar of {
      origin : Prismel.Vec3.t;
      u_axis : Prismel.Vec3.t;
      v_axis : Prismel.Vec3.t;
    }
  | Cylindrical of {
      origin : Prismel.Vec3.t;
      axis : Prismel.Vec3.t;
      seam : Prismel.Vec3.t;
      height : float;
    }
  | Spherical of {
      origin : Prismel.Vec3.t;
      axis : Prismel.Vec3.t;
      seam : Prismel.Vec3.t;
    }

type uv_unitize_mode = Per_face | Islands
type edge_incidence =
  | Any_edge
  | Boundary_edge
  | Manifold_edge
  | Non_manifold_edge

type edge_angle_basis =
  | Primitive_dihedral
  | Incident_edges

type group_owner =
  | Group_points
  | Group_vertices
  | Group_primitives
  | Group_edges

type group_promote_mode =
  | Include_any
  | Include_all
  | Include_shared_edge

type group_boundary_attribute = {
  boundary_attribute_owner : Attribute.owner;
  boundary_attribute_pattern : string;
}

type group_promote_boundary_options = {
  promote_boundary_attributes : group_boundary_attribute list;
  promote_boundary_tolerance : float;
  promote_include_unshared_edges : bool;
  promote_include_all_unshared_curve_edges : bool;
  promote_include_all_primitives_sharing_boundary_points : bool;
}

type group_promote_operation =
  | Promote_elements of group_promote_mode
  | Promote_boundary of group_promote_boundary_options

type group_promotion_rule = {
  promotion_source : group_owner;
  promotion_destination : group_owner;
  promotion_pattern : string;
  promotion_new_name : string option;
  promotion_keep_original : bool;
  promotion_output_as_attribute : bool;
  promotion_operation : group_promote_operation;
}

type primitive_group_connectivity =
  | Primitive_share_points
  | Primitive_share_edges

type group_expand_normal_attribute = {
  expand_normal_owner : Attribute.owner;
  expand_normal_name : string;
}

type group_expand_collision = {
  expand_collision_owner : group_owner;
  expand_collision_group : string;
  expand_collision_contain : bool;
  expand_collision_allow_boundary : bool;
}

type group_boolean_operation =
  | Group_replace
  | Group_union
  | Group_intersection
  | Group_subtract
  | Group_xor

type group_operand = { pattern : string; inverted : bool }
type group_combine_step = {
  operation : group_boolean_operation;
  operand : group_operand;
}

type group_range =
  | Range_start_end of { start : int; end_ : int }
  | Range_from_ends of { start : int; end_offset : int }
  | Range_start_length of { start : int; length : int }
  | Range_partition of { partition : int; partitions : int }

type group_range_filter = { select : int; of_ : int; offset : int }

type group_range_collision = {
  collision_owner : group_owner;
  collision_pattern : string;
  keep_boundary : bool;
}
(** A name-pattern-selected group whose topological boundary cuts connected
    regions. The collision owner is independent of the output owner. Boundary
    elements are excluded from local indexing unless [keep_boundary] is true. *)

type group_range_connectivity =
  | Range_disconnected of { region : int option }
  | Range_connected of {
      connectivity_attributes : string option;
      connectivity_tolerance : float;
      collision : group_range_collision option;
      region : int option;
      remove_other_regions : bool;
    }
(** Apply the range independently to topologically disconnected point or
    primitive components. [Range_disconnected] preserves the original strict
    one-region behavior. [Range_connected] additionally splits adjacency at
    discontinuities in one or more same-owner attributes selected with
    {!Attribute_pattern}, using [connectivity_tolerance] for floating storage,
    and at an independently owned collision-group boundary. [region = Some id]
    restricts the pattern to the stable component ID whose smallest included
    element is encountered first. When [remove_other_regions] is false, base
    members outside that component pass through unchanged. *)

type group_range_rule = {
  range_owner : group_owner;
  range_name : string;
  range_base : string option;
  range_invert : bool;
  range_filter : group_range_filter option;
  range_connectivity : group_range_connectivity option;
  range_merge : group_boolean_operation;
  range_specification : group_range;
}

val group_range_rule :
  ?base:string ->
  ?invert:bool ->
  ?filter:group_range_filter ->
  ?connectivity:group_range_connectivity ->
  ?merge:group_boolean_operation ->
  owner:group_owner ->
  name:string ->
  group_range ->
  group_range_rule
(** Construct one rule for {!group_ranges}. *)

type group_rename_conflict =
  | Rename_skip
  | Rename_error
  | Rename_overwrite
  | Rename_union

type group_rename_rule = {
  rename_owner : group_owner option;
  rename_pattern : string;
  rename_replacement : string;
  rename_conflict : group_rename_conflict;
}

type group_delete_rule = {
  delete_owner : group_owner option;
  delete_pattern : string;
}

type group_copy_conflict = Copy_skip | Copy_overwrite | Copy_add_suffix

type group_copy_rule = {
  copy_owner : group_owner;
  copy_pattern : string;
  copy_prefix : string;
  match_attribute : string option;
}

type group_transfer_rule = {
  transfer_owner : group_owner;
  transfer_pattern : string;
  transfer_prefix : string;
}

type group_name_conflict = Name_replace | Name_union
type invalid_group_name_policy = Ignore_invalid | Force_valid
type group_name_overlap = First_group | Last_group | Error_on_overlap
type group_bounds =
  | Bounds_box of { minimum : Prismel.Vec3.t; maximum : Prismel.Vec3.t }
  | Bounds_sphere of { center : Prismel.Vec3.t; radius : float }
type group_containment = Fully_contained | Partially_contained

type group_path_mode = Through_each | Start_end_pairs
type group_path_ending = Stop_at_end | Close_path

val uv_project :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?u_range:float * float ->
  ?v_range:float * float ->
  ?fix_seams:bool ->
  ?fix_poles:bool ->
  uv_projection ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create or replace a vertex float2 UV attribute using planar,
    cylindrical, or spherical projection. Existing values outside an optional
    primitive selection are preserved. Cylindrical and spherical modes can
    unwrap per-primitive boundary crossings and derive pole U from neighboring
    corners. O(vertices) time, exact 16-byte output per corner, and O(chunks)
    temporary storage. *)

val uv_transform :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?selection:Group.t ->
  owner:Attribute.owner ->
  ?translate:Prismel.Vec2.t ->
  ?scale:Prismel.Vec2.t ->
  ?angle:float ->
  ?pivot:Prismel.Vec2.t ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Transform a point- or vertex-owned float2 UV attribute. A selection, when
    supplied, must own the same element class. O(owner count) time and exact
    16-byte output per element. *)

val uv_auto_seam :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?angle:float ->
  ?include_boundaries:bool ->
  ?include_non_manifold:bool ->
  ?partition_attribute:string ->
  ?existing_uv:string ->
  ?uv_tolerance:float ->
  ?island_attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Mark UV seams in a native topology-affine edge group and a compatibility
    vertex group whose corners represent their outgoing edge. Cuts may come
    from dihedral angle, selection boundaries,
    non-manifold incidence, a primitive integer partition, or discontinuous
    existing UVs. Optional island IDs are stable in primitive order.
    O(points + vertices + primitives) time and linear auxiliary storage;
    normal and edge classification passes are parallel. *)

val group_edges :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?incidence:edge_incidence ->
  ?min_length:float ->
  ?max_length:float ->
  ?angle_basis:edge_angle_basis ->
  ?min_angle:float ->
  ?max_angle:float ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create a topology-affine native edge group. Active incidence, length,
    angle, and primitive-selection filters are conjunctive. The default
    [Primitive_dihedral] basis applies angles to two-sided polygon faces.
    [Incident_edges] compares each undirected edge with every other selected
    edge sharing either endpoint and accepts it when any pair is in the
    inclusive range. Angles are radians.

    Primitive-dihedral classification is O(edges + selected polygon corners).
    Incident-edge classification is O(edges + sum(point degree squared)), the
    required pairwise topology work. Both use packed bitsets and deterministic
    disjoint parallel output; incident comparison uses O(1) per-edge scratch. *)

val group_from_attribute_boundary :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?attributes:group_boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  owner:group_owner ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create a point, primitive, or native-edge group from discontinuities in
    selected point, vertex, or primitive attributes. Attribute patterns use
    {!Attribute_pattern}; point pattern [P] selects canonical positions.
    Numeric tuples differ when any component exceeds the finite non-negative
    [tolerance], while integer and text values compare exactly. Vertex values
    compare corresponding endpoints across each shared topology edge.

    [include_unshared_edges] adds polygon and closed-curve boundary edges. For
    open curves it adds only the first and last edges unless
    [include_all_unshared_curve_edges] is true. Primitive output normally
    includes incident faces; its point-sharing option also includes every face
    incident to a boundary endpoint. Vertex output is rejected.

    With [a] selected attribute planes, classification is O(attribute payload
    + a * sum(edge incidence)) time. Auxiliary storage is one packed edge
    bitset plus the shared O(points + vertices + edges) topology index. Numeric
    validation, edge classification, and output fills use deterministic
    disjoint parallel ranges. *)

val groups_from_name :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?prefix:string ->
  ?conflict:group_name_conflict ->
  ?invalid_names:invalid_group_name_policy ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  owner:Attribute.owner ->
  attribute:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create one unordered point or primitive group for each distinct non-empty
    value of a text attribute. Output groups follow first-value occurrence;
    values that normalize to the same forced-valid name are unioned.
    [Name_replace] replaces a same-owner group and [Name_union] includes its
    previous membership. Invalid names are either ignored or made ASCII-safe
    by replacing unsupported bytes and protecting a leading digit.

    The retained dense membership cost is exactly
    [distinct_groups * ceil(owner_count / 8)] bytes and is rejected before
    allocation when it exceeds [max_payload_bytes] (256 MiB by default) or
    [max_groups] (4096 by default). Classification is O(owner count) expected
    time with O(owner count) index storage; packed materialization is O(the
    retained payload), uses disjoint parallel byte ranges, and commits group
    metadata once. Reversible encoded names are intentionally not approximated
    by this API. *)

val name_from_groups :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?attribute:string ->
  ?pattern:string ->
  ?default:string ->
  ?overlap:group_name_overlap ->
  ?delete_groups:bool ->
  owner:Attribute.owner ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create or replace a point, vertex, or primitive text attribute from
    same-owner group names selected by a compiled pattern. Elements outside
    selected groups preserve an existing text value or receive [default].
    Overlaps resolve by stable geometry group order or fail atomically;
    selected source groups may be removed in one metadata commit.

    Group discovery is O(group count). Assignment is O(selected packed group
    bytes + selected cardinality), uses one integer plane, and is serial so
    overlap order is exact. Text output fills independent element ranges in
    parallel. *)

val group_random :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?seed:Prismel.Rand.t ->
  ?seed_attribute:string ->
  ?base:string ->
  ?merge:group_boolean_operation ->
  probability:float ->
  owner:group_owner ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select point, vertex, primitive, or native-edge elements by stateless
    deterministic probability. An optional exact-name base group restricts
    candidates. Point and primitive seeds use their element number or an
    owner-matched integer attribute; vertex seeds use the referenced point;
    native-edge seeds symmetrically combine endpoint point numbers or point
    integer values, matching Houdini's owner semantics.

    Classification is O(owner count), retains exactly one packed group plane,
    and fills disjoint bytes in parallel through the reusable domain pool.
    Fixed inputs are exact across domain counts. *)

val group_bounds :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?containment:group_containment ->
  ?merge:group_boolean_operation ->
  group_bounds ->
  owner:group_owner ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select point, vertex, primitive, or native-edge elements inside an
    inclusive axis-aligned box or sphere. Full primitive containment requires
    every referenced point; partial primitive containment requires any point,
    matching Group Create. Full edge containment requires both endpoints;
    partial edge containment includes robust segment/box or segment/sphere
    intersections even when both endpoints are outside.

    Classification is O(points + selected owner incidence), retains one exact
    packed group plane, and fills disjoint bytes in parallel. Segment tests
    normalize finite coordinates to avoid overflow at extreme magnitudes. *)

val group_normal :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?normal_attribute:string ->
  ?use_existing_normal:bool ->
  ?base:string ->
  ?include_opposite:bool ->
  ?merge:group_boolean_operation ->
  direction:Prismel.Vec3.t ->
  spread_angle:float ->
  owner:group_owner ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select points, primitives, or native edges whose normals lie within the
    inclusive angular spread around [direction]. Geometric primitive normals
    follow polygon winding; geometric point normals are deterministic
    angle-weighted incident-face averages; native edges use the normalized
    mean of their endpoint point normals. Vertex groups are rejected, matching
    Group Create. [include_opposite] unions the antipodal angular cap.

    By default, point and edge owners use an existing point float3 [N] plane
    and fall back to geometric normals when it is absent; primitive owners use
    implicit geometric normals. [normal_attribute] selects another
    owner-matched float3 plane instead. [use_existing_normal:false] forces the
    geometric path when no explicit attribute is named.
    Classification is O(points + vertices + primitives + selected edges), uses
    packed output and disjoint parallel ranges, and is exact across domain
    counts. Temporary geometric normals use packed structure-of-arrays storage
    and are released after the operation. *)

val group_non_planar :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?merge:group_boolean_operation ->
  tolerance:float ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select polygon primitives whose points deviate from a stable supporting
    plane by more than the absolute world-space [tolerance]. The supporting
    plane uses the farthest anchor pair and maximum-area third point, avoiding
    fragile first-three-point tests. Collinear polygons and curve primitives
    are not selected.

    Classification is O(vertices), uses O(1) scratch per primitive and one
    exact packed group plane, normalizes coordinates to remain finite near
    [max_float], and fills disjoint primitive ranges in parallel. Use
    [Group_union] to reproduce Group Create's additive non-planar criterion. *)

val group_backface :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?merge:group_boolean_operation ->
  viewpoint:Prismel.Vec3.t ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select non-degenerate polygon primitives whose winding-derived normal
    faces away from [viewpoint]. Edge-on polygons, curves, and degenerate
    polygons are not selected. Replace merge creates a backface group;
    subtracting into an existing same-name group reproduces Group Create's
    documented backface-removal behavior.

    Classification is O(vertices), uses O(1) scratch per primitive and one
    exact packed output plane, normalizes finite coordinates/viewpoint before
    subtraction and products, and fills disjoint primitive ranges in parallel. *)

val group_edge_depth :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?merge:group_boolean_operation ->
  depth:int ->
  point_group:string ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select points whose shortest topology-edge distance from [point_group] is
    at most the non-negative [depth]. Seeds are included at depth zero and
    disconnected components remain excluded. The complete merge algebra uses
    the existing same-name point group, with an absent destination treated as
    empty.

    The bounded multi-source BFS is O(points + visited edge incidence) time in
    the worst case and retains one packed point bitset plus a geometrically
    growing integer queue bounded by the visited cardinality. *)

val group_unshared :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?merge:group_boolean_operation ->
  owner:group_owner ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select points, primitives, or native edges incident to a topology edge
    owned by exactly one primitive. For curves, every segment is unshared.
    Vertex output is rejected, matching Group Create. Classification is
    O(points + vertices + edges), retains one packed edge plane plus the final
    packed owner plane, and fills independent output bytes in parallel. *)

val group_boundary_components :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?prefix:string ->
  ?conflict:group_name_conflict ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create one point group per connected polygon-surface boundary component,
    named [[prefix]__0], [[prefix]__1], and so on in stable smallest-point
    order. Curves and non-manifold edges are excluded. Output count and packed
    payload are preflighted before allocation. Classification and packed fills
    are parallel; deterministic integer union-find is near-linear. *)

val group_promote :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?mode:group_promote_mode ->
  source:group_owner ->
  destination:group_owner ->
  group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Convert a named point, vertex, primitive, or topology-affine edge group to
    another owner. [Include_any] uses incident membership,
    [Include_all] requires complete containment where the destination supports
    it, and [Include_shared_edge] restricts primitive output to primitives with
    a fully selected edge. [output_attribute] emits an owner-matched 0/1 integer
    attribute instead of the destination group; native edges reject it. The
    original is removed by default. Expected
    O(points + vertices + edges) index construction on a cold topology and
    O(output incidence) classification; output bits are filled in deterministic
    disjoint parallel byte ranges. *)

val group_promote_rule :
  ?new_name:string ->
  ?keep_original:bool ->
  ?output_as_attribute:bool ->
  ?mode:group_promote_mode ->
  source:group_owner ->
  destination:group_owner ->
  pattern:string ->
  unit ->
  group_promotion_rule
(** Construct an ordinary wildcard promotion rule. Blank [pattern] is a
    disabled slot. [new_name] uses the capture-preserving multi-term rewrite
    grammar of {!Attribute_pattern.compile_rewrite_set}; blank keeps each
    source name. *)

val group_promote_boundary_rule :
  ?new_name:string ->
  ?keep_original:bool ->
  ?output_as_attribute:bool ->
  ?attributes:group_boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  source:group_owner ->
  destination:group_owner ->
  pattern:string ->
  unit ->
  group_promotion_rule
(** Construct a wildcard convert-then-boundary rule with the same boundary
    controls as {!group_promote_boundary}. *)

val group_promotions :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?max_outputs:int ->
  ?max_payload_bytes:int ->
  rules:group_promotion_rule list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Apply ordered wildcard group promotions. Each rule snapshots all matching
    source groups before publishing that rule, so name collisions cannot alter
    another match's source payload. Later rules observe earlier outputs and may
    re-promote them. [output_as_attribute] emits an owner-matched integer mask
    under each rewritten output name. Empty/unmatched rules are no-ops; failure
    and cancellation publish no intermediate immutable geometry.

    [max_outputs] and [max_payload_bytes] preflight generated persistent or
    temporary payload before each match (defaults 4096 and 256 MiB). For [m]
    matches, time is O(group metadata + sum of destination incidence), and
    generated storage is the exact packed-group or integer-plane payload.
    Rule order is serial by contract; every independent topology/output pass
    retains deterministic disjoint parallel fills. *)

val group_promote_boundary :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?attributes:group_boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  source:group_owner ->
  destination:group_owner ->
  group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Convert a named group and retain only converted elements incident to its
    topology boundary. Point, vertex, and primitive sources expose their packed
    membership as a borrowed virtual integer plane; discontinuities across
    unique edges are unioned
    with optional typed attribute boundaries and requested polygon/curve
    unshared edges. Native-edge sources are already explicit boundary
    elements. Boundary edges are promoted to the destination and intersected
    with the ordinary converted selection, preventing elements on the opposite
    side from leaking into the result. Primitive output can additionally admit
    every selected primitive sharing a boundary point. Optional integer output
    follows {!group_promote}. The passes are linear in owner incidence plus
    selected attribute payload and use deterministic parallel packed fills. *)

val group_expand :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?steps:int ->
  ?flood:bool ->
  ?step_attribute:string ->
  ?primitive_connectivity:primitive_group_connectivity ->
  ?normal_spread:float ->
  ?normal_attribute:group_expand_normal_attribute ->
  ?connectivity_attributes:group_boundary_attribute list ->
  ?connectivity_tolerance:float ->
  ?collision:group_expand_collision ->
  owner:group_owner ->
  group:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Grow a group for positive [steps] and erode it for negative [steps]. Point
    adjacency follows topology edges; vertices follow primitive neighbors and
    coincident corners; edges share endpoints; primitives share points or,
    when requested, full edges. [flood] performs a linear multi-source graph
    traversal to the complete connected component and rejects shrinking. An
    optional owner-matched integer [step_attribute] records zero for the base
    selection/unreached elements and the first positive iteration at which an
    element is added or removed; native edges reject attributes.

    Point and edge-connected primitive growth can be constrained by adjacent
    normal spread, typed attribute discontinuities, and an independently owned
    collision group. Normals are geometric by default; a point, vertex, or
    primitive float3 attribute may be mapped to the target owner by normalized
    incident-corner averaging. Zero mapped normals reject a normal-constrained
    transition. Connectivity float comparisons use
    [connectivity_tolerance], while discrete storage compares exactly.
    Collision membership may contain growth and its boundary may be included
    or excluded. Attribute and collision seams prevent crossing and are also
    first-step erosion boundaries; normal spread affects growth only.
    Constrained vertex/edge targets and shared-point primitive seam semantics
    are deliberately rejected rather than approximated.

    Fixed-step passes use two packed bitsets and deterministic parallel byte
    ranges. Constraint compilation is O(elements + incidence + selected
    attribute payload) and uses packed seam/selection bits plus, when enabled,
    three target-sized float planes. Fixed-step time is
    O(abs(steps) * incidence); flood fill is O(elements + incidence) with an
    O(elements) stable queue. The resulting group itself is O(elements / 8),
    and all paths reuse the shared topology index. *)

val group_combine :
  ?cancel:Cancel.t ->
  ?grain:int ->
  owner:group_owner ->
  name:string ->
  base:group_operand ->
  steps:group_combine_step list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Create or replace one named group using ordered boolean operations over
    Houdini-style include/exclude name patterns. Operands may be complemented;
    unmatched patterns denote the empty set. All four owners, including native
    topology-affine edges, use the same semantics. Packed boolean passes are
    O(group bytes) and deterministic across domain counts. *)

val group_range :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?base:string ->
  ?invert:bool ->
  ?filter:group_range_filter ->
  ?connectivity:group_range_connectivity ->
  ?merge:group_boolean_operation ->
  owner:group_owner ->
  name:string ->
  group_range ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Select an inclusive absolute range, offsets from both ends, a start/length,
    or one balanced equal partition. An optional base name pattern masks the
    result; [filter] selects [select] consecutive indices per [of_] period with
    its offset measured from the range start. [connectivity] applies both the
    range and filter to stable local indices inside each disconnected point or
    primitive component, optionally splitting topology at same-owner attribute
    discontinuities and independently owned collision-group boundaries. A
    non-empty boundary switches primitive connectivity to shared non-seam
    edges. [keep_boundary = false] excludes output elements incident to a
    collision boundary from both local indexing and output. One-region mode
    either removes other components or passes their base members through.

    Merge operations combine with an existing output. Global classification is
    O(elements). Connected classification is O(points + vertices + primitives
    + selected attribute payload + boundary incidence), retaining component
    and local-index planes, two component-bound planes, and packed seam/include
    masks when configured. Attribute validation, boundary classification, and
    output bytes use deterministic disjoint parallel ranges; union-find and
    stable component numbering remain serial. Results are byte-identical across
    domain counts. *)

val group_ranges :
  ?cancel:Cancel.t ->
  ?grain:int ->
  rules:group_range_rule list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Apply an ordered collection of Group Range rules as one functional
    operation. Blank output names are disabled slots, matching Houdini's
    Number of Ranges multiparm. Later rules observe groups published by earlier
    rules, so they may use them as bases or collision groups. A failure or
    cancellation returns no intermediate geometry to the caller; an empty or
    all-disabled rule list preserves physical geometry identity.

    For [r] rules, time and temporary memory are the sum of the individual
    rule costs; output payload is one packed bitset per distinct published
    group. Rules intentionally execute in order because dependencies on earlier
    group names make unconstrained rule-level parallelism incorrect. Each
    individual boundary and output pass retains its deterministic internal
    parallelism. *)

val group_invert :
  ?conflict:group_rename_conflict ->
  ?owner:group_owner ->
  pattern:string ->
  ?new_name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Complement every matching ordinary or native-edge group. [new_name] uses
    the same wildcard-capture rewrite grammar as {!Attribute_pattern}; when
    omitted, groups are replaced in place. *)

val group_delete :
  rules:group_delete_rule list ->
  ?delete_unused:bool ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Delete named groups, not geometry elements. Rules use compiled
    include/exclude glob patterns and may target one owner or all owners.
    [delete_unused] additionally removes empty groups. Metadata is rebuilt once
    regardless of rule count. *)

val group_rename :
  rules:group_rename_rule list ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Apply wildcard-capture rename rules in order. Earlier results can match
    later rules. Conflicts can skip, error, overwrite, or union packed
    membership. *)

val group_copy :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?rules:group_copy_rule list ->
  ?conflict:group_copy_conflict ->
  ?copy_empty:bool ->
  source:Geometry.t ->
  target:Geometry.t ->
  unit ->
  (Geometry.t, Error.t) result
(** Copy selected point, primitive, vertex, and native-edge groups from
    [source] onto [target]. Points/primitives/edges match by stable element
    index; vertices match by primitive number and local corner index. Ordinary
    owners may instead match the first source element with an equal integer or
    text attribute. Each rule computes its target-to-source map once and fills
    all selected groups in deterministic packed parallel passes. Empty pattern
    strings select all source groups, matching Houdini Group Copy. *)

val group_transfer :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?rules:group_transfer_rule list ->
  ?conflict:group_copy_conflict ->
  ?create_empty:bool ->
  ?distance:float ->
  source:Geometry.t ->
  target:Geometry.t ->
  unit ->
  (Geometry.t, Error.t) result
(** Transfer selected point, primitive, and native-edge groups by closest
    same-owner geometric proximity. Point queries use the packed point index;
    polygon/curve primitive and unique-edge queries use exact triangle/segment
    feature distances through a median-split AABB hierarchy. Equal-distance
    ties choose the lower source element. Blank patterns mean [*]; conflicts
    skip, overwrite, or add a numeric suffix beginning at 2.

    Index construction is expected O(f log f), where [f] is source feature
    count. Queries are expected O(q log f), degrade to O(q*f) for fully
    overlapping bounds, and write disjoint target ranges in parallel. Packed
    feature/index/mapping/group storage is O(source + target features and
    elements). Ordered ordinary source groups produce destination order by
    source sequence, exact proximity, then target index. *)

val group_find_path :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?mode:group_path_mode ->
  ?ending:group_path_ending ->
  ?avoid_self_intersection:bool ->
  ?collision:Group.t ->
  ?contain:bool ->
  base:Group.t ->
  name:string ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Construct an ordered point or primitive group by joining the explicitly
    ordered [base] elements. Point paths follow topology edges; primitive paths
    follow the manifold shared-edge dual graph and reject non-manifold input.
    [Through_each] joins contiguous base elements; [Start_end_pairs] solves
    independent ordered pairs. Paths minimize relation count first, then finite
    edge length or primitive-centroid distance, with stable element ties.
    [Close_path] finds a second route that shares no primary interior element
    or relation. An optional same-owner collision group is excluded, or becomes
    the allowed region with [contain=true]. Vertex paths are not supported.

    Relation weights are prepared once in O(points + vertices + primitives +
    edges) time with disjoint parallel fills. Each route is O(elements +
    incident relations) time and O(elements) scratch. Routes without
    intersection coupling execute independently through the reusable domain
    pool; avoidance is deterministic in base order. *)

val uv_unitize :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?name:string ->
  ?primitives:Group.t ->
  ?seams:Group.t ->
  ?edge_seams:Edge_group.t ->
  ?tolerance:float ->
  ?uniform:bool ->
  uv_unitize_mode ->
  Geometry.t ->
  (Geometry.t, Error.t) result
(** Fit each selected polygon face or continuous UV island into the unit
    square. [uniform] preserves aspect ratio and centers the result; seam
    edges or compatibility seam corners force island cuts. O(vertices +
    primitives) expected time and
    linear auxiliary storage. Bounds and output fills are parallel. *)

val uv_flatten :
  ?cancel:Cancel.t -> ?grain:int -> ?name:string -> ?seams:Group.t ->
  ?edge_seams:Edge_group.t -> ?iterations:int -> ?tolerance:float ->
  Geometry.t -> (Geometry.t, Error.t) result
(** Flatten seam-delimited manifold triangle disk islands with positive
    mean-value harmonic coordinates. Boundaries are arc-length mapped and
    packed into the unit square; interior Jacobi passes are deterministic and
    parallel. O(vertices + triangles) auxiliary storage. *)

val uv_relax :
  ?cancel:Cancel.t -> ?grain:int -> ?name:string -> ?seams:Group.t ->
  ?edge_seams:Edge_group.t -> ?uv_tolerance:float -> ?iterations:int ->
  ?tolerance:float -> Geometry.t -> (Geometry.t, Error.t) result
(** Relax interiors with the same positive harmonic solver while preserving
    existing island boundaries and seam-separated placement. *)
