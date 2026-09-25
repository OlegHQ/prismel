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
  | Torus_axis of Prismel_math.Vec3.t

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
  (Geometry.t, string) result
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
  | Tube_axis of Prismel_math.Vec3.t

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
  (Geometry.t, string) result
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
  | Platonic_axis of Prismel_math.Vec3.t

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
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:platonic_rotation_order ->
  ?face_groups:string ->
  radius:float ->
  unit ->
  (Geometry.t, string) result
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


val torus_checked :
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

val tube_checked :
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

val platonic_checked :
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
