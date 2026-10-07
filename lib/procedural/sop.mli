(** Human-first SOP graph constructors. One-input modifiers take their input
    last so they compose with [(|>)]. *)

type element_owner = Element_point | Element_vertex | Element_primitive | Element_edge
type smoothing_mode = Laplacian | Custom

type element_group =
  | Point_group of string
  | Vertex_group of string
  | Primitive_group of string
  | Edge_group of string
(** Named topology component group. Each SOP documents whether it promotes the
    selection to referenced points or incident primitives. *)

val snapshot : ?label:string -> Rdk.Geometry.t -> Node.t
(** Use an immutable cooked geometry value as an explicit graph source. This
    is the feedback boundary for iterative [Sketch.run_state] applications;
    it does not create a cycle inside the SOP DAG. *)

val points : ?label:string -> (float * float * float) array -> Node.t

(* Generate an origin point cloud without an input. The generated point and
    local-index metadata default to [sourcepoint] (always [-1]) and
    [sourceindex] (the stable generated point number). *)
val point_generate_origin :
  ?label:string ->
  ?points:int ->
  ?generated_group:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  unit ->
  Node.t
val line :
  ?label:string ->
  ?kind:Rdk.Line_geometry.kind ->
  ?points:int ->
  ?origin:Rays_math.Vec3.t ->
  ?direction:Rays_math.Vec3.t ->
  ?length:float ->
  unit ->
  Node.t
val polyline :
  ?label:string -> ?closed:bool -> (float * float * float) array -> Node.t
type kernel_mode = Kernel_explicit | Kernel_auto
type axis_orientation = Axis_x | Axis_y | Axis_z | Axis_custom
type circle_arc = Circle_closed | Circle_open | Circle_chord | Circle_sliced
type plane_orientation = Plane_xy | Plane_xz | Plane_yz | Plane_axes
val circle :
  ?label:string ->
  ?arc:circle_arc ->
  ?start_angle:float ->
  ?end_angle:float ->
  ?orientation:plane_orientation ->
  ?horizontal:Rays_math.Vec3.t ->
  ?vertical:Rays_math.Vec3.t ->
  ?radius:float ->
  ?radius_x_mode:kernel_mode ->
  ?radius_y_mode:kernel_mode ->
  ?reverse:bool ->
  ?center:Rays_math.Vec3.t ->
  ?radius_x:float ->
  ?radius_y:float ->
  ?rotation:float ->
  ?uniform_scale:float ->
  ?segments:int ->
  unit ->
  Node.t
(* Immutable polygon circle, ellipse, open/chord-closed arc, or sliced arc.
    Plane, transform, dimensions, traversal, and arc parameters participate in
    cache identity; cooking uses the context's cancellation token and grain.
    Explicit radii default to one; Auto uses the base radius for that axis.
    The default segment count follows Lisp's 48. *)
(* Packed planar lattice with division- or point-count resolution and
    point/row/column/quad/triangle topology. Orientation, dimensions, center,
    in-plane rotation, and optional normalized point UVs are immutable cache
    parameters. Explicit dimensions default to one; Auto uses [size] for
    that dimension. Blank UV names are unset. *)
val grid :
  ?label:string ->
  ?counts:Rdk.Plane_generators.grid_counts ->
  ?connectivity:Rdk.Plane_generators.grid_connectivity ->
  ?orientation:plane_orientation ->
  ?horizontal:Rays_math.Vec3.t ->
  ?vertical:Rays_math.Vec3.t ->
  ?width_mode:kernel_mode ->
  ?height_mode:kernel_mode ->
  ?columns:int ->
  ?rows:int ->
  ?size:float ->
  ?width:float ->
  ?height:float ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:float ->
  ?uv_attribute:string ->
  unit ->
  Node.t
val box :
  ?label:string ->
  ?connectivity:Rdk.Box_generator.box_connectivity ->
  ?normals:Rdk.Box_generator.box_normals option ->
  ?size:Rays_math.Vec3.t ->
  ?x_divisions:int ->
  ?y_divisions:int ->
  ?z_divisions:int ->
  ?consolidate_points:bool ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Box_generator.box_rotation_order ->
  ?uniform_scale:float ->
  ?uv_attribute:string ->
  ?face_groups:string ->
  unit ->
  Node.t
(* Immutable divided triangle/quad Box or surface/volume point lattice. Every
   topology, sharing, normal, transform, UV, and face-group parameter is part
   of the node's stable cache identity. *)

val uv_sphere :
  ?label:string ->
  ?connectivity:Rdk.Uv_sphere.sphere_connectivity ->
  ?normals_mode:kernel_mode ->
  ?normals:Rdk.Uv_sphere.sphere_normals ->
  ?orientation:axis_orientation ->
  ?axis:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Uv_sphere.sphere_rotation_order ->
  ?base_radius:float ->
  ?radius_x_mode:kernel_mode ->
  ?radius_y_mode:kernel_mode ->
  ?radius_z_mode:kernel_mode ->
  ?unique_points_per_pole:bool ->
  ?triangular_poles:bool ->
  ?radius:Rays_math.Vec3.t ->
  ?uniform_scale:float ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?segments:int ->
  ?rings:int ->
  ?uv_attribute:string ->
  unit ->
  Node.t
(** Immutable latitude/longitude sphere/ellipsoid generator. Every topology,
    pole-sharing, normal, frame/transform, radii, and UV parameter contributes
    to the stable cache identity and cooks through the RDK packed kernel. *)

val torus :
  ?label:string ->
  ?connectivity:Rdk.Parametric_generators.torus_connectivity ->
  ?normals_mode:kernel_mode ->
  ?normals:Rdk.Parametric_generators.torus_normals ->
  ?orientation:axis_orientation ->
  ?axis:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Parametric_generators.torus_rotation_order ->
  ?major_radius:float ->
  ?minor_radius:float ->
  ?uniform_scale:float ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?u_start:float ->
  ?u_end:float ->
  ?v_start:float ->
  ?v_end:float ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?u_end_caps:bool ->
  ?v_end_cap:bool ->
  ?rows:int ->
  ?columns:int ->
  ?uv_attribute:string ->
  unit ->
  Node.t
(** Immutable full/partial torus generator. Connectivity, independent U/V
    angle and wrap policy, polygon caps, normals, frame/transform, resolution,
    radii, and UV parameters all participate in stable cache identity. *)

val tube :
  ?label:string ->
  ?connectivity:Rdk.Parametric_generators.tube_connectivity ->
  ?normals_mode:kernel_mode ->
  ?normals:Rdk.Parametric_generators.tube_normals ->
  ?orientation:axis_orientation ->
  ?axis:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Parametric_generators.tube_rotation_order ->
  ?top_radius:float ->
  ?bottom_radius:float ->
  ?height:float ->
  ?radius_scale:float ->
  ?end_caps:bool ->
  ?consolidate_cap_points:bool ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?rows:int ->
  ?columns:int ->
  ?uv_attribute:string ->
  ?cap_group:string ->
  unit ->
  Node.t
(** Immutable cylinder/frustum/cone/pyramid generator. Connectivity, cap
    sharing, normals, frame/transform, dual radii, resolution, UV, and cap
    group parameters all participate in stable cache identity. *)

val platonic :
  ?label:string ->
  ?kind:Rdk.Parametric_generators.platonic_kind ->
  ?normals:Rdk.Parametric_generators.platonic_normals ->
  ?radius:float ->
  ?orientation:axis_orientation ->
  ?axis:Rays_math.Vec3.t ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Parametric_generators.platonic_rotation_order ->
  ?face_groups:string ->
  unit ->
  Node.t
(** Immutable regular-polyhedron generator. Kind, normals, frame/transform,
    face-group prefix, and circumsphere radius all participate in stable cache
    identity. The soccer-ball kind also carries black/white primitive [Cd]. *)

type spiral_extent_mode = Spiral_turns_height | Spiral_height_pitch
type spiral_radius_mode = Spiral_archimedean_change | Spiral_archimedean_end | Spiral_logarithmic_change | Spiral_logarithmic_end
type spiral_divisions_mode = Spiral_per_curve | Spiral_per_turn
val spiral :
  ?label:string ->
  ?extent_mode:spiral_extent_mode ->
  ?turns:float ->
  ?height:float ->
  ?pitch:float ->
  ?radius_mode:spiral_radius_mode ->
  ?start_radius:float ->
  ?radius_change:float ->
  ?end_radius:float ->
  ?logarithmic_scale:float ->
  ?height_ramp:string ->
  ?radius_ramp:string ->
  ?radius_scale:float ->
  ?direction:Rdk.Spiral.direction ->
  ?start_angle:float ->
  ?divisions_mode:spiral_divisions_mode ->
  ?divisions:int ->
  ?uniform_angle:bool ->
  ?spiral_count:int ->
  ?orientation:axis_orientation ->
  ?axis:Rays_math.Vec3.t ->
  ?center:Rays_math.Vec3.t ->
  ?rotation:Rays_math.Vec3.t ->
  ?rotation_order:Rdk.Spiral.rotation_order ->
  ?uniform_scale:float ->
  ?angle_attribute:string ->
  ?x_axis_attribute:string ->
  ?y_axis_attribute:string ->
  ?tangent_attribute:string ->
  ?orient_attribute:string ->
  ?distance_attribute:string ->
  unit ->
  Node.t
(** Immutable polygon spiral/helix generator. Curve family, extent, ramps,
    sampling policy, phase count, transform, and optional frame/distance
    attributes all participate in stable cache identity. Ramps use comma-separated
    position:value knots; blank is unset, one knot is constant, and multiple
    knots span 0 through 1 in strictly increasing order. Cooking delegates to
    the deterministic packed RDK kernel using the context grain and
    cancellation token. *)

type transform_mode = Transform_trs | Transform_matrix
val transform : ?label:string ->
  ?mode:transform_mode ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?order:Rdk.Transform_ops.transform_order ->
  ?rotation_order:Rdk.Transform_ops.transform_rotation_order ->
  ?shear_xy:float ->
  ?shear_xz:float ->
  ?shear_yz:float ->
  ?pivot:Rays_math.Vec3.t ->
  ?pivot_rotation:Rays_math.Vec3.t ->
  ?invert:bool ->
  ?m00:float ->
  ?m01:float ->
  ?m02:float ->
  ?m03:float ->
  ?m10:float ->
  ?m11:float ->
  ?m12:float ->
  ?m13:float ->
  ?m20:float ->
  ?m21:float ->
  ?m22:float ->
  ?m23:float ->
  ?m30:float ->
  ?m31:float ->
  ?m32:float ->
  ?m33:float ->
  ?translate:Rays_math.Vec3.t ->
  ?rotate:Rays_math.Vec3.t ->
  ?scale:Rays_math.Vec3.t ->
  ?uniform_scale:float ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Apply TRS or a flat matrix to the selected elements. *)

val transform_trs : ?label:string ->
  ?mode:transform_mode ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?order:Rdk.Transform_ops.transform_order ->
  ?rotation_order:Rdk.Transform_ops.transform_rotation_order ->
  ?shear_xy:float ->
  ?shear_xz:float ->
  ?shear_yz:float ->
  ?pivot:Rays_math.Vec3.t ->
  ?pivot_rotation:Rays_math.Vec3.t ->
  ?invert:bool ->
  ?m00:float ->
  ?m01:float ->
  ?m02:float ->
  ?m03:float ->
  ?m10:float ->
  ?m11:float ->
  ?m12:float ->
  ?m13:float ->
  ?m20:float ->
  ?m21:float ->
  ?m22:float ->
  ?m23:float ->
  ?m30:float ->
  ?m31:float ->
  ?m32:float ->
  ?m33:float ->
  ?translate:Rays_math.Vec3.t ->
  ?rotate:Rays_math.Vec3.t ->
  ?scale:Rays_math.Vec3.t ->
  ?uniform_scale:float ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Alias of [transform], sharing its Lisp defaults and fields. *)

type soft_transform_metric = Soft_radius | Soft_edge | Soft_attribute
val soft_transform_trs :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?order:Rdk.Transform_ops.transform_order ->
  ?rotation_order:Rdk.Transform_ops.transform_rotation_order ->
  ?translate:Rays_math.Vec3.t ->
  ?rotate:Rays_math.Vec3.t ->
  ?scale:Rays_math.Vec3.t ->
  ?shear_xy:float ->
  ?shear_xz:float ->
  ?shear_yz:float ->
  ?uniform_scale:float ->
  ?pivot:Rays_math.Vec3.t ->
  ?pivot_rotation:Rays_math.Vec3.t ->
  ?invert:bool ->
  ?metric:soft_transform_metric ->
  ?metric_attribute:string ->
  ?apply_rolloff:bool ->
  ?falloff:Rdk.Transform_ops.soft_transform_falloff ->
  ?radius:float ->
  ?falloff_attribute:string ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Soft selection over a composed TRS/shear/pivot transform. *)

type distance_radius_mode = Radius_fixed | Radius_maximum
val distance_along_geometry :
  ?label:string ->
  ?start_owner:element_owner ->
  ?start_group:string ->
  ?affected_owner:element_owner ->
  ?affected_group:string ->
  ?falloff:Rdk.Transform_ops.soft_transform_falloff ->
  ?radius_mode:distance_radius_mode ->
  ?radius:float ->
  ?distance_attribute:string ->
  ?mask_attribute:string ->
  Node.t ->
  Node.t
(** Compute point distance along mesh edges from a required typed start group.
    The optional affected group limits writes. Raw distance defaults to the
    point-float [distance] plane; pass [~distance_attribute:""] to omit it.
    An optional mask uses fixed or maximum-distance normalization. *)

val distance_from_geometry :
  ?label:string ->
  ?affected_owner:element_owner ->
  ?affected_group:string ->
  ?reference_owner:element_owner ->
  ?reference_group:string ->
  ?reference_kind:Rdk.Transform_ops.distance_from_geometry_reference ->
  ?falloff:Rdk.Transform_ops.soft_transform_falloff ->
  ?radius_mode:distance_radius_mode ->
  ?radius:float ->
  ?distance_attribute:string ->
  ?mask_attribute:string ->
  Node.t ->
  Node.t ->
  Node.t
(** Measure source points to the closest selected reference point or polygon
    surface. Typed affected/reference groups are resolved against their own
    inputs. Raw distance and optional fixed/maximum-radius masks share the
    packed spatial query and preserve source values outside the affected set. *)

val distance_from_target :
  ?label:string ->
  ?affected_owner:element_owner ->
  ?affected_group:string ->
  ?projection:Rdk.Transform_ops.distance_from_target_projection ->
  ?origin:Rays_math.Vec3.t ->
  ?direction:Rays_math.Vec3.t ->
  ?metric:Rdk.Transform_ops.distance_from_target_metric ->
  ?falloff:Rdk.Transform_ops.soft_transform_falloff ->
  ?radius_mode:distance_radius_mode ->
  ?radius:float ->
  ?distance_attribute:string ->
  ?mask_attribute:string ->
  Node.t ->
  Node.t
(** Measure source points from an analytic point, axis, or plane. Typed affected
    groups are promoted once; planar distance may be signed, while masks use
    magnitude and fixed or maximum-distance normalization. *)

val merge : ?label:string ->
  ?source_attribute:string ->
  ?source_base:int ->
  Node.t list ->
  Node.t
(* At least one input is required. [source_attribute] names a primitive int
   attribute holding [source_base] plus each primitive's input index
   (see [Rdk.Mesh_merge.merge]); a blank name leaves source tagging disabled. *)
(* Deterministic packed Fuse 2.0 point snapping/consolidation. A second target
    remains immutable and supplies an independent named target group. Near
    targeting supports least-number or closest targets, radius expansion, and
    scalar match filters; specified targeting reads query point target numbers.
    Position reducers, same-input Modify Target, Keep Fused Points, and
    topology/unused-point cleanup correspond to Rdk.Fuse_grid.fuse. Snap-only mode
    preserves topology, while output metadata records mapped queries and
    destinations. *)
type fuse_targeting = Fuse_near_points | Fuse_specified_points
val fuse :
  ?label:string ->
  ?group:string ->
  ?target_group:string ->
  ?targeting:fuse_targeting ->
  ?target_attribute:string ->
  ?using:Rdk.Fuse_grid.fuse_using ->
  ?tolerance:float ->
  ?position:Rdk.Fuse_reduce.position ->
  ?weight_attribute:string ->
  ?attributes:Rdk.Fuse_reduce.attributes ->
  ?attribute_rules:string ->
  ?group_rules:string ->
  ?metric:Rdk.Fuse_grid.fuse_metric ->
  ?inclusive:bool ->
  ?match_attributes:bool ->
  ?radius_attribute:string ->
  ?match_attribute:string ->
  ?match_condition:Rdk.Fuse_grid.fuse_match_condition ->
  ?match_tolerance:float ->
  ?modify_target:bool ->
  ?fuse_points:bool ->
  ?keep_fused_points:bool ->
  ?snapped_group:string ->
  ?snapped_destination_attribute:string ->
  ?remove_degenerate_primitives:bool ->
  ?remove_unused_points_from_degenerate_primitives:bool ->
  ?remove_all_unused_points:bool ->
  Node.t ->
  Node.t option ->
  Node.t
val snap_to_grid :
  ?label:string ->
  ?group:string ->
  ?spacing:Rays_math.Vec3.t ->
  ?offset:Rays_math.Vec3.t ->
  ?rounding:Rdk.Fuse_grid.grid_rounding ->
  ?limit_distance:bool ->
  ?max_distance:float ->
  ?fuse_points:bool ->
  ?position:Rdk.Fuse_reduce.position ->
  ?weight_attribute:string ->
  ?attributes:Rdk.Fuse_reduce.attributes ->
  ?snapped_group:string ->
  ?attribute_rules:string ->
  ?group_rules:string ->
  Node.t ->
  Node.t
(* Snap a named point group, or every point, to a deterministic axis-aligned
    grid. Optional post-snap fusion uses the same group restriction and packed
    Fuse core, including weighted position reduction. Enable [limit_distance]
    to use [max_distance]. Spacing is positive and offset fractions are in
    [0, 1]. Blank names are unset.
    Rules use escaped tab-separated rows, separated by newlines; escape a
    literal tab/newline/backslash as backslash-t/backslash-n/double-backslash.
    Attribute rows contain pattern, method and optional weight name (keep the
    third column when blank). Methods: average, least, greatest, maximum,
    minimum, mode, median, sum, sum_squares, root_mean_square, concatenate,
    weighted_average, weighted_sum, minimum_weight, maximum_weight,
    concatenate_weight_order. The final five require a weight name.
    Group rows contain pattern and method: least, greatest, union,
    intersection or most_common. *)
(* Reflect across an arbitrary plane with corrected polygon winding. *)
val mirror :
  ?label:string ->
  ?keep_original:bool ->
  ?origin:Rays_math.Vec3.t ->
  ?normal:Rays_math.Vec3.t ->
  Node.t ->
  Node.t
val clip :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?keep:Rdk.Plane_clip.keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?distance:float ->
  ?origin:Rays_math.Vec3.t ->
  ?normal:Rays_math.Vec3.t ->
  ?clip_attribute:string ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  ?replace_existing_groups:bool ->
  Node.t ->
  Node.t
(* Plane clipping/creasing with a canonical or numeric point clip attribute,
    distance offset, typed interpolation, native clipped-edge output, and
    optional manifold caps. *)
val crease :
  ?label:string ->
  ?group:string ->
  ?operation:Rdk.Crease.operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Node.t ->
  Node.t
(** Add, set, or delete [creaseweight] on a named native edge group, or every
    topology edge when [group] is omitted. The immutable graph node delegates
    unique-edge reduction and packed corner/color fills to RDK; its result can
    feed [subdivide] directly. [weight] is ignored for delete. *)

val attribute_fade :
  ?label:string ->
  ?group:string ->
  ?fade_attribute:string ->
  ?start_attribute:string ->
  ?start_retime_offset:float ->
  ?start_retime_scale:float ->
  ?hold_scale_attribute:string ->
  ?frame_offset:float ->
  ?fade_in:float ->
  ?fade_hold:float ->
  ?fade_out:float ->
  ?fade_in_ramp:string ->
  ?fade_out_ramp:string ->
  ?visualize:bool ->
  Node.t ->
  Node.t option ->
  Node.t option ->
  Node.t
(** Frame-dependent scalar point-attribute fade. A missing fade field starts
    at one; optional start and hold-scale fields may come from independent
    equal-point-count graphs, passed as positional [Node.t option] inputs.
    Ramps are comma-separated position:value knots spanning 0 through 1;
    blank uses the linear fade-in or inverse linear fade-out default.
    The immutable node declares only the frame fact,
    so bounded sessions reuse a cook across irrelevant time/seed changes while
    invalidating exactly when the frame or any input snapshot changes. *)

type poly_cut_detection = Cut_all | Cut_crossing | Cut_change
val poly_cut :
  ?label:string ->
  ?group:string ->
  ?cut_group:string ->
  ?element:Rdk.Poly_cut.element ->
  ?strategy:Rdk.Poly_cut.strategy ->
  ?detection:poly_cut_detection ->
  ?attribute:string ->
  ?value:float ->
  ?threshold:float ->
  ?keep_closed:bool ->
  Node.t ->
  Node.t
(** Break polygon curves at selected point or native-edge attribute events.
    [group] restricts source primitives; [cut_group] resolves as a point group
    for [Poly_cut_points] and a native edge group for [Poly_cut_edges]. The
    immutable node delegates packed planning, interpolation, ancestry, and
    deterministic parallel fills to {!Rdk.Poly_cut.cut}. *)

val separate_pieces :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?piece_attribute:string ->
  ?translation_attribute:string ->
  ?axis:Rays_math.Vec3.t ->
  ?gap:float ->
  ?mode:Rdk.Separate_pieces.mode ->
  Node.t ->
  Node.t
(** Deterministically separate point- or primitive-identified pieces into
    disjoint intervals along an axis, or restore them from the stored float3
    translation. The immutable node delegates ownership validation, packed
    bounds, reversible position fills, and cancellation to
    {!Rdk.Separate_pieces.run}. *)

(* Packed Catmull-Clark or bilinear polygon-surface and polygon-curve
   refinement, plus triangle-only Loop refinement. [group] restricts
   refinement to a named primitive group. [treat_curves_as_independent]
   duplicates every selected curve corner's point identity, matching Houdini;
   otherwise shared curve points participate in one degree-aware cubic graph.
   [cracks] exposes every
   Pull/Stitch No Edge, Divide, and Triangulate policy; Pull variants carry
   their bias in the policy value. [consistent_topology] selects stable
   topology-only bridge and surrounding-face triangulation decisions.
   [creases] supplies a second topology whose [crease_group] edges match the
   source by point number. With that input, [crease_weight] overrides its
   attributes; without it, the value applies to every edge of the subdivided
   surface. Residual sharpness can be omitted or collected in a named native
   edge group.
   [hole_group], or [subdivision_hole] automatically, contributes to stencils
   while its descendant faces are optionally omitted at the final level.
   [boundary_interpolation] selects OpenSubdiv None, Edge Only, or Edge and
   Corner point-boundary behavior. [face_varying_interpolation] selects all
   six OpenSubdiv linear constraints for floating vertex attributes; its
   compatibility default is Linear All. [triangle_policy] selects standard
   Catmull-Clark or OpenSubdiv Smooth Triangles edge weights.
   [creasing_method] selects uniform or endpoint-dependent Chaikin residual
   edge sharpness. Source detail [osd_scheme],
   [osd_vtxboundaryinterpolation], [osd_fvarlinearinterpolation],
   [osd_creasingmethod], and [osd_trianglesubdiv] attributes use Houdini's
   integer/text contract and override the corresponding node parameters during
   cooking; invalid controls produce a traced structured diagnostic.
   Point [N] is interpolated with the point stencil unless
   [recompute_point_normals=true]. Recompute replaces an existing input point
   [N] with final normalized area-weighted normals; it does not create [N]
   when no point normal existed. *)
type subdivision_cracks = Cracks_do_not_close | Cracks_pull_no_division | Cracks_pull_divide | Cracks_pull_triangulate
  | Cracks_stitch_no_division | Cracks_stitch_divide | Cracks_stitch_triangulate
val subdivide :
  ?label:string ->
  ?group:string ->
  ?scheme:Rdk.Subdivide.scheme ->
  ?iterations:int ->
  ?cracks:subdivision_cracks ->
  ?crack_bias:float ->
  ?consistent_topology:bool ->
  ?crease_group:string ->
  ?crease_weight_mode:kernel_mode ->
  ?crease_weight:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group:string ->
  ?hole_group:string ->
  ?remove_holes:bool ->
  ?boundary_interpolation:Rdk.Subdivide.boundary_interpolation ->
  ?face_varying_interpolation:Rdk.Subdivide.face_varying_interpolation ->
  ?triangle_policy:Rdk.Subdivide.triangle_policy ->
  ?creasing_method:Rdk.Subdivide.creasing_method ->
  ?treat_curves_as_independent:bool ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t option ->
  Node.t
(* Split a named native edge group into equal segments. An omitted group is an
   intentional no-op, matching Houdini's empty Edge Divide group. Shared mode
   reuses one inserted point sequence across coincident primitive edges;
   unique mode gives every incident primitive edge private points. Numeric
   point/vertex payload interpolates and native edge groups follow every child
   segment. *)
val edge_divide :
  ?label:string ->
  ?group:string ->
  ?divisions:int ->
  ?share_points:bool ->
  Node.t ->
  Node.t
(* Collapse each connected component of a named native edge group to its
    arithmetic center. An omitted group selects all topology edges. Exact
    point [connectivity_attribute] boundaries partition the components.
    Degenerate cleanup and recomputation of an existing point [N] field are
    enabled by default. *)
val edge_collapse :
  ?label:string ->
  ?group:string ->
  ?connectivity_attribute:string ->
  ?position:Rdk.Fuse_reduce.position ->
  ?remove_degenerate_primitives:bool ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t
(* Remove a named set of polygon edges and merge consistently wound incident
   faces. Non-selected inversion, bridge-loop policy, boundary-to-curve
   output, selected-edge inline cleanup, point compaction, and normal
   recomputation map directly to the packed RDK Dissolve kernel. *)
val dissolve :
  ?label:string ->
  ?group:string ->
  ?operation:Rdk.Dissolve.operation ->
  ?bridge_policy:Rdk.Dissolve.bridge_policy ->
  ?remove_inline_points:bool ->
  ?collinearity_tolerance:float ->
  ?remove_unused_points:bool ->
  ?create_boundary_curves:bool ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(* Cut selected two-sided polygon edges back into their first face ring, emit
   connected fillet strips and close arbitrary manifold junctions. Chamfer or
   rational-circular round profiles, point-scale control, flat-edge exclusion,
   collision limiting, generated face/boundary groups, payload interpolation,
   and existing-normal regeneration map to the packed RDK PolyBevel kernel.
   An omitted group selects all eligible edges. *)
type poly_bevel_shape = Poly_chamfer | Poly_round
val poly_bevel :
  ?label:string ->
  ?group:string ->
  ?shape:poly_bevel_shape ->
  ?convexity:float ->
  ?distance:float ->
  ?divisions:int ->
  ?point_scale_attribute:string ->
  ?ignore_flat_angle:float ->
  ?clamp_overlap:bool ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t
(* Split selected shared points into unique or attribute-compatible clusters.
    [selection] accepts point, vertex, or primitive groups. A blank attribute
    pattern makes selected corners unique; otherwise the shared Houdini-style
    glob language selects vertex/primitive seam fields and named groups.
    Optional promotion moves matched attributes—not groups—to point ownership
    after topology is separated. *)
val point_split :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?attributes:string ->
  ?tolerance:float ->
  ?promote_attributes:bool ->
  Node.t ->
  Node.t
(* Emit points from selected source points in stable source/local order.
    Per-point mode supports deterministic fractional stochastic rounding and
    an optional point-float count scale; probability mode reads a point float
    in [[0,1]]. Matched point/detail payload, optional input retention,
    generated grouping, and source provenance map directly to the packed RDK
    kernel. Without an explicit seed, the node derives a stable stream from
    context seed and node identity. *)
type point_generation_mode = Point_generate_total | Point_generate_per_point | Point_generate_probability
val point_generate :
  ?label:string ->
  ?mode:point_generation_mode ->
  ?group:string ->
  ?keep_input:bool ->
  ?total:int ->
  ?points_per_point:float ->
  ?scale_attribute:string ->
  ?probability_attribute:string ->
  ?context_seed:bool ->
  ?seed:int ->
  ?generated_group:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  Node.t ->
  Node.t
(* Generate shaped deterministic point clouds around selected input points.
   Built-in and optional custom point-cloud shapes use the standard packed
   Copy-to-Points transform rules. Count scaling, stable ID seeding, source
   payload/provenance, generated grouping, quasi-stratification, velocity
   stretch, inherited velocity, and radial velocity remain immutable cache
   parameters. Matching copied Float3 vectors can follow the same frame through
   [transform_attributes], with inverse-transpose handling for [N].
   [custom_shape] is required exactly for [Replicate_custom]. *)
val point_replicate :
  ?label:string ->
  ?group:string ->
  ?keep_input:bool ->
  ?points_per_point:float ->
  ?scale_attribute:string ->
  ?context_seed:bool ->
  ?seed:int ->
  ?id_attribute:string ->
  ?shape:Rdk.Point_replication.shape ->
  ?center:Rays_math.Vec3.t ->
  ?size:Rays_math.Vec3.t ->
  ?orientation:Rays_math.Vec3.t ->
  ?uniform_scale:float ->
  ?quasi_stratified:bool ->
  ?velocity_stretch:Rdk.Point_replication.velocity_stretch ->
  ?velocity_scale:float ->
  ?inherit_velocity:float ->
  ?radial_velocity:float ->
  ?use_noise:bool ->
  ?noise_amplitude:Rays_math.Vec3.t ->
  ?noise_frequency:Rays_math.Vec3.t ->
  ?noise_offset:Rays_math.Vec3.t ->
  ?noise_roughness:float ->
  ?noise_attenuation:float ->
  ?noise_turbulence:int ->
  ?noise_context_seed:bool ->
  ?noise_seed:int ->
  ?generated_group:string ->
  ?copy_point_attributes:string ->
  ?keep_source_attributes:bool ->
  ?transform_attributes:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  Node.t ->
  Node.t option ->
  Node.t
(* Triangulate between consecutive selected polygon curves or faces. Unequal
   section cardinalities use a deterministic two- or three-distance zipper;
   closest-end alignment can use an equal-point-count rest snapshot. U/V wrap,
   source retention, generated-face grouping, collinearity policy, and existing
   normal regeneration map directly to the packed RDK PolyLoft kernel. *)
val poly_loft :
  ?label:string ->
  ?group:string ->
  ?connect_closest_ends:bool ->
  ?minimize:Rdk.Poly_loft.minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t option ->
  Node.t
(* Build a linear polygon skin between consecutive selected curves or faces.
   Equal-cardinality pairs retain quad topology; unequal pairs use the shared
   deterministic PolyLoft zipper. Selection, rest alignment, U/V wrapping,
   source retention, grouping, and normal policy map to the RDK Skin kernel. *)
val skin :
  ?label:string ->
  ?group:string ->
  ?connect_closest_ends:bool ->
  ?minimize:Rdk.Poly_loft.minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t option ->
  Node.t
(* Bridge paired simple source and destination edge paths/loops. Components
   pair in authored or centroid-sorted order; equal counts emit quads and
   unequal counts use the shared loft zipper. Reverse, closed-loop shift,
   input-retention, grouping, collinearity, and normal controls map directly
   to RDK. *)
val poly_bridge :
  ?label:string ->
  ?source_group:string ->
  ?destination_group:string ->
  ?pairing:Rdk.Poly_bridge.pairing ->
  ?connect_closest_ends:bool ->
  ?minimize:Rdk.Poly_loft.minimize ->
  ?reverse_source:bool ->
  ?reverse_destination:bool ->
  ?pairing_shift:int ->
  ?divisions:int ->
  ?keep_input:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(* Rotate each edge in a named native edge group through its joined polygon
   boundary while preserving both face cardinalities. An omitted group is an
   intentional no-op. Vertex payload cycles with the face by default; native
   edge-group membership follows source ancestry. Selected flips must be
   manifold, consistently oriented, geometrically valid, and pairwise
   primitive-disjoint. *)
val edge_flip :
  ?label:string ->
  ?group:string ->
  ?cycles:int ->
  ?cycle_vertex_attributes:bool ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t
(* Split polygon point fans along the interior vertices of a named native edge
   path. Path endpoints remain shared; an omitted group is a no-op. Point
   payload and groups duplicate exactly, native edge groups retain ancestry,
   and an existing point-normal field is rebuilt by default. *)
val edge_cusp :
  ?label:string ->
  ?group:string ->
  ?update_point_normals:bool ->
  Node.t ->
  Node.t
(* Project every connected component of a named native edge group onto its
   least-squares best-fit line. An omitted group uses all topology edges;
   [output_group] optionally records the transformed selection. *)
val edge_straighten :
  ?label:string ->
  ?group:string ->
  ?output_group:string ->
  Node.t ->
  Node.t
(* Fit each simple connected path or loop in a named native edge group to its
   least-squares plane and circle. An omitted group uses topology boundary
   edges; [radius] overrides the best-fit radius, [scale] transforms each
   circle about its fitted center, and [output_group] records the selection. *)
val circle_from_edges :
  ?label:string ->
  ?group:string ->
  ?use_radius:bool ->
  ?radius:float ->
  ?scale:Rays_math.Vec3.t ->
  ?output_group:string ->
  Node.t ->
  Node.t
(* Color a point/primitive adjacency graph through the single packed RDK core.
   Typed groups promote to the selected connectivity owner; unselected elements
   receive -1. Stable sorting and optional detail workset ranges use the shared
   Sort remapper and remain exact across domain counts. *)
val graph_color :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?connectivity:Rdk.Graph_color.connectivity ->
  ?color_attribute:string ->
  ?sort_output:bool ->
  ?output_worksets:bool ->
  ?workset_begin_attribute:string ->
  ?workset_length_attribute:string ->
  Node.t ->
  Node.t
(* Equalize the initial selected edge lengths to their average, longest, or
   shortest value. Connected selections use the deterministic RDK iterative
   projection; [iterations] and relative [tolerance] bound convergence. *)
val edge_equalize :
  ?label:string ->
  ?group:string ->
  ?method_:Rdk.Edge_ops.equalize_method ->
  ?iterations:int ->
  ?tolerance:float ->
  ?output_group:string ->
  Node.t ->
  Node.t
(* Match source edge lengths to an exactly topology-compatible reference.
   Point/primitive restriction and point pins are resolved on the source.
   Scale-independent mode preserves the source mean while adopting the
   reference length distribution. *)
val edge_relax :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?pin_group:string ->
  ?iterations:int ->
  ?step_size:float ->
  ?target_mode:Rdk.Edge_relax.target_mode ->
  ?only_shorten:bool ->
  ?tolerance:float ->
  Node.t ->
  Node.t ->
  Node.t
val blend_shapes :
  ?label:string ->
  ?group:string ->
  ?mode:Rdk.Blend_shapes.mode ->
  ?attributes:string ->
  ?weight1:float ->
  ?weight2:float ->
  ?weight3:float ->
  ?weight4:float ->
  ?masking:Rdk.Blend_shapes.masking ->
  ?mask_attribute:string ->
  ?mask_source:Rdk.Blend_shapes.mask_source ->
  ?point_id_attribute:string ->
  ?weights:string ->
  ?shape_masks:string ->
  Node.t ->
  Node.t option ->
  Node.t option ->
  Node.t option ->
  Node.t option ->
  Node.t list ->
  Node.t
(* Blend point shapes while retaining the first input's topology. Four fixed
   optional slots precede unlimited additional shapes. [weights] is an escaped
   one-column table of finite signed extra weights; missing rows use 0.
   [shape_masks] is an escaped three-column table: one-based shape slot, mask
   attribute and source (first/shape). Blank cells inherit global mask settings;
   fixed slots keep indices 1-4 and connected extras start at 5. Unused rows
   remain available for future connections. Integer/text point-ID matching,
   point group, floating attribute patterns and all fields share Lisp identity.
   An empty shape list retains the node's own schema and unchanged geometry. *)
val attribute_composite :
  ?label:string ->
  ?operation:Rdk.Attribute_composite.operation ->
  ?weight:float ->
  ?point_attributes:string ->
  ?allow_position:bool ->
  ?alpha_attribute:string ->
  ?vertex_attributes:string ->
  ?primitive_attributes:string ->
  ?detail_attributes:string ->
  ?weight1:float ->
  ?weight2:float ->
  ?weight3:float ->
  ?weight4:float ->
  ?weights:string ->
  Node.t ->
  Node.t option ->
  Node.t option ->
  Node.t option ->
  Node.t option ->
  Node.t list ->
  Node.t
(* Composite ordered inputs with independent owner patterns and Mean, Max,
   Min, Over, or Under semantics. Fixed optional layers retain their slot weights;
   the final list supports unlimited additional layers. [weights] is an escaped
   one-column table of their finite signed weights, in order; missing rows use 1.
   Unused rows remain available for later connections. Blank alpha disables masking.
   All fields and connected inputs participate in the shared schema/cache identity. *)
type mirror_method = Mirror_plane | Mirror_mapping
type mirror_transform = Mirror_copy | Mirror_uv | Mirror_vector | Mirror_point
(** Mirror named point, vertex, or primitive attributes from a source side to
    a destination side. Plane mode uses reflected nearest correspondence for
    points and primitive bounding-box centers; mapping mode resolves a named
    integer map and named destination group at cook time. All policies and
    output metadata participate in immutable cache identity. *)
val attribute_mirror :
  ?label:string ->
  ?owner:Rdk.Attribute_mirror.owner ->
  ?attributes:string ->
  ?group:string ->
  ?group_use:Rdk.Attribute_mirror.group_use ->
  ?method_:mirror_method ->
  ?origin:Rays_math.Vec3.t ->
  ?normal:Rays_math.Vec3.t ->
  ?distance:float ->
  ?tolerance:float ->
  ?mapping_attribute:string ->
  ?mapping_destination_group:string ->
  ?transform:mirror_transform ->
  ?uv_origin_u:float ->
  ?uv_origin_v:float ->
  ?uv_direction_u:float ->
  ?uv_direction_v:float ->
  ?replace_strings:bool ->
  ?string_search:string ->
  ?string_replacement:string ->
  ?output_mapping:string ->
  ?source_group:string ->
  ?destination_group:string ->
  Node.t ->
  Node.t

(** Reassign polygon/curve corners using a scalar integer point, vertex, or
    primitive attribute. Selection is typed and promoted to the target owner;
    recursive point chains, target deletion, newly-unused cleanup, and original
    corner-point provenance are immutable cache parameters. *)
val rewire_vertices :
  ?label:string ->
  ?selection_owner:element_owner ->
  ?selection:string ->
  ?owner:Rdk.Attribute.owner ->
  ?target_attribute:string ->
  ?recursive:bool ->
  ?delete_target_attribute:bool ->
  ?keep_unused_points:bool ->
  ?original_point_attribute:string ->
  Node.t ->
  Node.t
(* Transport a scalar point field over the deterministic RDK shortest-path
   edge forest. [root_group] selects explicit multi-source roots; otherwise
   [roots] chooses the first or last point of each selected component. *)
type transport_roots = Transport_first | Transport_last | Transport_group
val edge_transport :
  ?label:string ->
  ?attribute:string ->
  ?point_group:string ->
  ?roots:transport_roots ->
  ?root_group:string ->
  ?direction:Rdk.Edge_transport.direction ->
  ?operation:Rdk.Edge_transport.operation ->
  ?root_value:Rdk.Edge_transport.root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:Rdk.Edge_transport.split ->
  ?merge:Rdk.Edge_transport.merge ->
  ?normalization:Rdk.Edge_transport.normalization ->
  Node.t ->
  Node.t
(* Transport a scalar point or vertex field independently along selected
    polygon/curve primitives. Open curves orient from the lower-numbered
    endpoint; closed curves use a deterministic lowest-point seam. Independent
    curves cook in parallel, while shared point writes are rejected rather
    than made scheduling-dependent. *)
val edge_transport_curves :
  ?label:string ->
  ?attribute:string ->
  ?primitive_group:string ->
  ?owner:Rdk.Attribute.owner ->
  ?direction:Rdk.Edge_transport.direction ->
  ?operation:Rdk.Edge_transport.operation ->
  ?root_value:Rdk.Edge_transport.root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?normalization:Rdk.Edge_transport.normalization ->
  Node.t ->
  Node.t
(* Transport a scalar point field through an integer parent forest without
   requiring topology edges. Forward split and backward branch merge are
   explicit, and independent rooted trees cook in parallel. *)
val edge_transport_parent :
  ?label:string ->
  ?attribute:string ->
  ?point_group:string ->
  ?parent_attribute:string ->
  ?direction:Rdk.Edge_transport.direction ->
  ?operation:Rdk.Edge_transport.operation ->
  ?root_value:Rdk.Edge_transport.root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:Rdk.Edge_transport.split ->
  ?merge:Rdk.Edge_transport.merge ->
  ?normalization:Rdk.Edge_transport.normalization ->
  Node.t ->
  Node.t
(* Expands the source once per target point. Target [pscale], [scale], and
   quaternion [orient] point attributes are optional. Without [orient], [N]
   (or fallback [v]) aligns source +Z and a nonzero [up] aligns source +Y.
   Quaternion [rot] is applied afterward; [pivot] offsets source-local points,
   and [trans] augments target [P]. A point [transform] installed by
   [set_transform] overrides orientation and scale. Copies use stable
   target-point order. [source_group] names a primitive subset compacted once;
   [target_group] names a point subset retained in stable numeric order.
   [piece_attribute] matches integer or text target points to a same-named
   source primitive or point field; without a source field an integer value is
   a source primitive number. Unmatched targets emit no geometry, and expanded
   output remains in target-major order.
   Ordered [target_attributes] use last-match-wins patterns to broadcast
   matching target point attributes and groups onto copied point, vertex, or
   primitive owners. [Rdk.Instance_copy.Copy_target_nothing] cancels an earlier match;
   group arithmetic is intersection, union, and subtraction. *)
val copy_to_points :
  ?label:string ->
  ?source_group:string ->
  ?target_group:string ->
  ?piece_attribute:string ->
  ?pack:bool ->
  ?target_attributes:string ->
  Node.t ->
  Node.t ->
  Node.t
(** [pack] (default false) returns the source once with one instance
    transform per target ({!Session.output.instances}) instead of copies.
    Packed copies require an unset source group and piece attribute.
    Blank names are unset. Target-attribute rules use escaped tab-separated
    pattern, owner (points/vertices/primitives), operation
    (nothing/copy/add/subtract/multiply) rows separated by newlines. *)

val duplicate :
  ?label:string ->
  ?copies:int ->
  ?cumulative:bool ->
  ?m00:float ->
  ?m01:float ->
  ?m02:float ->
  ?m03:float ->
  ?m10:float ->
  ?m11:float ->
  ?m12:float ->
  ?m13:float ->
  ?m20:float ->
  ?m21:float ->
  ?m22:float ->
  ?m23:float ->
  ?m30:float ->
  ?m31:float ->
  ?m32:float ->
  ?m33:float ->
  ?group:string ->
  ?copy_group_prefix:string ->
  ?preserve_groups:bool ->
  Node.t ->
  Node.t
(* Append transformed materialized copies. [group] restricts the copied
    primitives while preserving the full input prefix. A copy-group prefix
    emits one one-based primitive group per appended copy. *)
val switch : ?label:string -> ?input:int -> Node.t -> Node.t -> Node.t list -> Node.t
(* Cook only the selected branch. [a] and [b] are branches 0 and 1; further
    branches follow in order. An [input] outside the connected branches is
    refused at construction. *)
val null : ?label:string ->
  Node.t ->
  Node.t
(* Deterministically ear-clip all polygon primitives or a named primitive
   group. Unselected polygons and curves pass through with exact payload. *)
val triangulate : ?label:string ->
  ?group:string ->
  Node.t ->
  Node.t
type triangulate_2d_projection = Triangulate_best_fit | Triangulate_xy | Triangulate_yz | Triangulate_zx | Triangulate_plane | Triangulate_attribute
val triangulate_2d :
  ?label:string ->
  ?point_group:string ->
  ?constraint_edge_group:string ->
  ?constraint_primitive_group:string ->
  ?projection:triangulate_2d_projection ->
  ?plane_origin:Rays_math.Vec3.t ->
  ?plane_normal:Rays_math.Vec3.t ->
  ?point_attribute:string ->
  ?seed:int ->
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
  ?use_maximum_area:bool ->
  ?maximum_area:float ->
  ?use_target_edge_length:bool ->
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
  Node.t ->
  Node.t
(* Delaunay-triangulate point geometry through the shared exact-predicate RDK
    kernel. The named point group is promoted nowhere: it selects exactly its
    members. Crossing-constraint splitting, bounded quality refinement,
    regularization, projection, original-position restoration, primitive
    retention, seed, payload policy, and output groups participate in immutable
    node identity. Angles are radians. *)
val remesh :
  ?label:string ->
  ?target_length:float ->
  ?iterations:int ->
  ?smoothing:float ->
  ?project:bool ->
  ?use_input_points_only:bool ->
  ?hard_point_group:string ->
  ?hard_edge_group:string ->
  ?target_size_attribute:string ->
  ?preserve_uv_seams:bool ->
  ?uv_attribute:string ->
  ?output_hard_edges:string ->
  ?output_mesh_size:string ->
  ?output_quality:string ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t
(* Isotropically remesh a complete polygon surface through the shared packed
    RDK split/collapse/flip/relax/project kernel. Named hard point and native
    edge groups, point target sizes, UV seams, diagnostic outputs, and input-
    points-only mode are part of the immutable node identity. *)
type boolean_closed_policy = Closed_default | Closed_required | Closed_not_required
val boolean :
  ?label:string ->
  ?operation:Rdk.Boolean.operation ->
  ?left_treatment:Rdk.Boolean.treatment ->
  ?right_treatment:Rdk.Boolean.treatment ->
  ?resolve_left_self_intersections:bool ->
  ?resolve_right_self_intersections:bool ->
  ?point_conflict:Rdk.Boolean.point_conflict ->
  ?point_tolerance:float ->
  ?tiny_seam_threshold:float ->
  ?cleanup_max_batches:int ->
  ?strict_cleanup:bool ->
  ?seam_points:Rdk.Boolean.seam_points ->
  ?detriangulation:Rdk.Boolean.detriangulation ->
  ?assume_flat:bool ->
  ?require_closed:boolean_closed_policy ->
  ?piece_attribute:string ->
  ?left_piece_group:string ->
  ?overlap_piece_group:string ->
  ?right_piece_group:string ->
  Node.t ->
  Node.t ->
  Node.t
(* Exact two-input polygon Boolean SOP. Operand treatment, product/shatter, payload
    conflict, seam-point, detriangulation, self-intersection, flatness, and
    closed-output policies are immutable cache identity. The node delegates
    all geometry work to {!Rdk.Boolean.run}; it does not own another kernel.
    [piece_attribute] names the optional primitive integer plane containing
    exact Boolean-cell identities. *)
val boolean_fracture :
  ?label:string ->
  ?point_conflict:Rdk.Boolean.point_conflict ->
  ?assume_flat:bool ->
  ?resolve_cutter_self_intersections:bool ->
  ?detriangulation:Rdk.Boolean.detriangulation ->
  ?require_closed:bool ->
  ?piece_attribute:string ->
  ?point_tolerance:float ->
  ?tiny_seam_threshold:float ->
  ?cleanup_max_batches:int ->
  ?strict_cleanup:bool ->
  Node.t ->
  Node.t ->
  Node.t
(* Fracture a solid with zero-volume cutting surfaces. Output remains welded
    at shared seams and receives one primitive integer identity per exact
    closed arrangement cell, suitable for packing and rigid transforms. *)
val boolean_seam :
  ?label:string ->
  ?output:Rdk.Boolean.seam_output ->
  ?left_treatment:Rdk.Boolean.treatment ->
  ?right_treatment:Rdk.Boolean.treatment ->
  ?resolve_left_self_intersections:bool ->
  ?resolve_right_self_intersections:bool ->
  ?left_self_group:string ->
  ?between_group:string ->
  ?right_self_group:string ->
  ?coincident_group:string ->
  Node.t ->
  Node.t ->
  Node.t
(* Exact two-input seam/coincident-area product from the same RDK arrangement
   core. Curve-kind and coincident group names are explicit cache identity. *)
(* Detect AxB intersections between source and optional collision polygon
    surfaces, plus AxA self-intersections on the source, while retaining source
    topology and payload. Named primitive groups restrict the inputs. The default
    [boolean_self_intersections] output is always enabled; a connected collision
    also enables [boolean_intersections]. Blank names disable outputs. Collision
    fields are ignored while that input is disconnected.

    The optional primitive integer-array [intersections_attribute] contains
    sorted unique collision primitive numbers for every source primitive, and
    [count_attribute] contains the AxB row lengths; the corresponding [self_*]
    controls emit symmetric AxA rows and counts. Ordinary shared-edge/vertex
    topology contacts are not self-intersections. At least one output is required.
    All controls and both graph inputs participate in immutable cache identity;
    the packed BVH and narrow phase are owned by [Rdk.Boolean_detect.run_checked]. *)
val boolean_detect :
  ?label:string ->
  ?source_group:string ->
  ?collision_group:string ->
  ?tolerance:float ->
  ?include_coplanar:bool ->
  ?intersecting_group:string ->
  ?intersections_attribute:string ->
  ?count_attribute:string ->
  ?self_intersecting_group:string ->
  ?self_intersections_attribute:string ->
  ?self_count_attribute:string ->
  Node.t ->
  Node.t option ->
  Node.t
(* Emit a point cloud at triangle and polygon-curve intersections rather than
    passing either input through. One input performs self-analysis and
    [collision] enables AxB analysis. Named primitive groups restrict each side. The aligned
    point-owned CSR provenance defaults to [sourceinput], [sourceprim],
    [sourceprimuv], and [sourcepoint]; pass [None] to suppress any field.
    [sourceprimuv] contains triangle barycentrics or curve [(u, 0, 0)] per
    incident primitive, while [sourcepoint] is the matching input point number
    or [-1]. *)
val intersection_analysis :
  ?label:string ->
  ?source_group:string ->
  ?collision_group:string ->
  ?tolerance:float ->
  ?include_coplanar:bool ->
  ?input_attribute:string ->
  ?primitive_attribute:string ->
  ?primitive_uvw_attribute:string ->
  ?point_attribute:string ->
  Node.t ->
  Node.t option ->
  Node.t
(* Deterministic adaptive quadric-error polygon reduction. Named hard point
   and native-edge groups are exact constraints; preserving unshared
   boundaries is enabled by default. A primitive group restricts reduction
   and locks its interface. Constraints may stop above the requested target. *)
type poly_reduce_target = Reduce_ratio | Reduce_primitive_count
val poly_reduce :
  ?label:string ->
  ?group:string ->
  ?hard_point_group:string ->
  ?hard_edge_group:string ->
  ?target_mode:poly_reduce_target ->
  ?ratio:float ->
  ?primitive_count:int ->
  ?preserve_boundary:bool ->
  ?only_original_positions:bool ->
  ?equalize_lengths:float ->
  ?limit_normal_deviation:bool ->
  ?max_normal_deviation:float ->
  ?output_group:string ->
  ?recompute_point_normals:bool ->
  Node.t ->
  Node.t
(* Reverse or cyclically shift corners of every primitive or of a named
    primitive group. Signed shift offsets wrap independently per primitive;
    all vertex fields/groups follow the corner permutation. *)
type reverse_operation = Reverse | Shift
val reverse :
  ?label:string ->
  ?group:string ->
  ?operation:reverse_operation ->
  ?shift:int ->
  Node.t ->
  Node.t
(* Compute point, vertex, primitive, or detail normals through the packed RDK
   kernel. Typed selections are promoted to the requested output owner;
   [cusp_angle] is in radians and only affects vertex normals. *)
val normals :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?owner:Rdk.Attribute.owner ->
  ?weighting:Rdk.Normal_ops.weighting ->
  ?cusp_angle:float ->
  ?keep_original_zero:bool ->
  ?reverse:bool ->
  ?attribute:string ->
  Node.t ->
  Node.t

val measure_curvature :
  ?label:string ->
  ?point_group:string ->
  ?boundary:Rdk.Curvature.boundary ->
  ?smoothing_iterations:int ->
  ?smoothing_strength:float ->
  ?mean:string ->
  ?gaussian:string ->
  ?minimum:string ->
  ?maximum:string ->
  ?curvedness:string ->
  ?shape_index:string ->
  Node.t ->
  Node.t
(* Estimate signed mean, Gaussian, principal, curvedness, and shape-index
   point fields through the shared packed RDK curvature kernel. The default
   writes signed mean curvature to [curvature]. A point group limits output
   replacement while metric estimation remains topology-complete. *)

val attribute_laplacian :
  ?label:string ->
  ?point_group:string ->
  ?weighting:Rdk.Laplacian.weighting ->
  ?normalize:bool ->
  ?source:string ->
  ?output:string ->
  Node.t ->
  Node.t
(* Apply the shared packed surface Laplacian to a point numeric field or [P].
   Cotangent, non-negative cotangent, and uniform graph weights are available;
   normalization selects pointwise versus integrated output. *)
type polyframe_style = Style_first_edge | Style_two_edges | Style_centroid
  | Style_texture_uv | Style_texture_uv_gradient | Style_attribute_gradient

val polyframe :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?style:polyframe_style ->
  ?style_attribute:string ->
  ?orthogonal:bool ->
  ?left_handed:bool ->
  ?normal_attribute:string ->
  ?tangent_attribute:string ->
  ?bitangent_attribute:string ->
  Node.t ->
  Node.t
(* Generate point or vertex coordinate-frame fields with deterministic packed
   RDK kernels. First-edge, two-edge, centroid, and texture-UV styles produce
   point fields; texture-UV-gradient and attribute-gradient produce
   seam-preserving vertex fields. Empty texture names resolve to [uv].
   A blank tangent or bitangent name disables that output. Orthogonal frames are
   right-handed unless [left_handed] is enabled. *)
(* Smooth point positions and matching point-owned floating attributes without
    changing topology. [group] is a primitive group; [constrained_points]
    names an additional point group to lock. Boundary policy, packed weighting,
    alternating low-pass steps, and normal handling delegate to the shared RDK
    Smooth/Attribute Blur kernel. *)
val smooth :
  ?label:string ->
  ?group:string ->
  ?constrained_points:string ->
  ?boundary:Rdk.Smooth.boundary ->
  ?iterations:int ->
  ?method_:Rdk.Attribute_ops.blur_method ->
  ?mode:smoothing_mode ->
  ?step:float ->
  ?odd_step:float ->
  ?even_step:float ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?attributes:string ->
  ?original_blend:float ->
  ?smoothed_blend:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
type ray_direction = Direction_vector | Direction_normal | Direction_attribute
val ray :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?collision_group:string ->
  ?method_:Rdk.Ray.method_ ->
  ?direction:ray_direction ->
  ?direction_vector:Rays_math.Vec3.t ->
  ?direction_attribute:string ->
  ?direction_mode:Rdk.Ray.direction_mode ->
  ?surface_hit:Rdk.Ray.surface_hit ->
  ?samples:int ->
  ?jitter_scale:float ->
  ?seed:int ->
  ?combine:Rdk.Ray.combine ->
  ?min_distance:float ->
  ?limit_max_distance:bool ->
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
  Node.t ->
  Node.t ->
  Node.t
(* Project source points onto collision polygons using closest-distance or
    directional BVH queries. Bounded deterministic multi-ray jitter and its
    average/median/shortest/longest combiner are part of immutable node
    identity. Source and collision inputs follow Lisp's positional order. *)
val peak :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?direction_attribute:string ->
  ?normalize_direction:bool ->
  ?mask_attribute:string ->
  ?distance:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Move selected point/vertex/primitive/edge components along resolved normals
    or a custom point direction. The group name is resolved at cook time and
    remains part of the inspectable cache identity. *)

val bend :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?mask_attribute:string ->
  ?origin:Rays_math.Vec3.t ->
  ?direction:Rays_math.Vec3.t ->
  ?up:Rays_math.Vec3.t ->
  ?length:float ->
  ?bend_angle:float ->
  ?twist_angle:float ->
  ?limit:bool ->
  ?both_directions:bool ->
  ?continuous_twist:bool ->
  ?capture_attribute:string ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Captured arc-length-preserving bend and axial twist in an arbitrary frame.
    Angles are radians. Typed point/vertex/primitive/edge selections resolve at
    cook time; an optional point float mask scales deformation in [[0,1]]. *)

val mountain :
  ?label:string ->
  ?group:string ->
  ?direction_attribute:string ->
  ?mask_attribute:string ->
  ?height_attribute:string ->
  ?seed_mode:kernel_mode ->
  ?normalize_direction:bool ->
  ?offset:Rays_math.Vec3.t ->
  ?seed:int ->
  ?height:float ->
  ?frequency:Rays_math.Vec3.t ->
  ?octaves:int ->
  ?lacunarity:float ->
  ?roughness:float ->
  ?recompute_normals:bool ->
  Node.t ->
  Node.t
(** Deterministic Perlin-fBm normal displacement. Without an explicit seed,
    the node derives a stable stream from context seed and node identity. *)


val exploded_view :
  ?label:string ->
  ?amount:float ->
  ?scale:Rays_math.Vec3.t ->
  ?piece_attribute:string ->
  ?noise_amount:float ->
  ?noise_frequency:float ->
  ?noise_seed:int ->
  Node.t ->
  Node.t
(** Terminal geometry passthrough carrying packed-piece view controls. *)

val point_jitter :
  ?label:string ->
  ?group:string ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?seed_mode:kernel_mode ->
  ?seed:int ->
  ?scale:float ->
  ?use_point_scale:bool ->
  ?axis:Rays_math.Vec3.t ->
  Node.t ->
  Node.t
(** Add deterministic component-wise uniform offsets to points. [group] limits
    the affected points, [mask_attribute] blends the displacement, and
    [id_attribute] supplies stable integer identities when point numbering may
    change. [use_point_scale] multiplies the offset by point float [pscale].
    The default is explicit seed 0. With [seed_mode:Kernel_auto], the node
    derives a stable stream from context seed and node identity. Blank
    optional names are unset; scale and axis scales are finite and nonnegative. *)

type clean_overlap = Clean_keep_first | Clean_delete_pairs | Clean_overlap_auto

val clean :
  ?label:string ->
  ?epsilon_mode:kernel_mode ->
  ?epsilon:float ->
  ?remove_degenerate:bool ->
  ?consolidate_mode:kernel_mode ->
  ?consolidate_distance:float ->
  ?overlaps:clean_overlap ->
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
  Node.t ->
  Node.t
type facet_consolidation = Consolidation_none | Consolidation_points | Consolidation_normals
val facet :
  ?label:string ->
  ?group:string ->
  ?group_owner:element_owner ->
  ?consolidation:facet_consolidation ->
  ?pre_compute_normals:bool ->
  ?make_normals_unit_length:bool ->
  ?unique_points:bool ->
  ?consolidate_distance:float ->
  ?consolidate_normals_distance:float ->
  ?remove_inline_points:bool ->
  ?inline_distance:float ->
  ?orient_polygons:bool ->
  ?cusp_mode:kernel_mode ->
  ?cusp_angle:float ->
  ?remove_degenerate:bool ->
  ?make_planar:bool ->
  ?post_compute_normals:bool ->
  ?reverse_normals:bool ->
  Node.t ->
  Node.t
(* Ordered Facet pipeline, optionally restricted to a typed named point,
    vertex, primitive, or native-edge selection through [group_owner] and [group]. Point/vertex/edge selections promote to every
    incident primitive before the pipeline. Covers normal preparation,
    topology-correct Unique Points, deterministic
    point/normal consolidation, inline-point removal, manifold polygon orientation,
    dihedral-angle cusping, degenerate cleanup, conflict-safe polygon
    planarization, post normals, and final normal
    reversal. Normal consolidation preserves positions/topology and supports
    simultaneous point and vertex [N]. *)
(* Extrude selected polygon faces individually or as shared-edge connected
   components. Split edges divide connected fronts; output geometry, role
   groups, native boundary groups, and straight side divisions are explicit. *)
val poly_extrude :
  ?label:string ->
  ?group:string ->
  ?split_edges:string ->
  ?distance:float ->
  ?divide:Rdk.Poly_extrude.divide ->
  ?divisions:int ->
  ?output_front:bool ->
  ?output_back:bool ->
  ?output_side:bool ->
  ?front_group:string ->
  ?back_group:string ->
  ?side_group:string ->
  ?front_boundary_group:string ->
  ?back_boundary_group:string ->
  Node.t ->
  Node.t
(* Fill all manifold polygon boundary loops, or auto-complete only loops
    touched by a named native edge group. Supports a single polygon,
    deterministic concave-safe triangles, or an averaged triangle fan;
    shared/unique boundary points, patch winding, point-normal refresh, and a
    generated primitive group are immutable cook parameters. *)
val poly_fill :
  ?label:string ->
  ?boundary_group:string ->
  ?mode:Rdk.Poly_fill.mode ->
  ?reverse_patches:bool ->
  ?unique_points:bool ->
  ?update_point_normals:bool ->
  ?patch_group:string ->
  Node.t ->
  Node.t
val resample :
  ?label:string ->
  ?group:string ->
  ?use_segments:bool ->
  ?segments:int ->
  ?use_maximum_segment_length:bool ->
  ?maximum_segment_length:float ->
  ?segment_length_attribute:string ->
  ?segments_attribute:string ->
  ?even_last_segment:bool ->
  ?curve_u_attribute:string ->
  ?curve_number_attribute:string ->
  ?distance_attribute:string ->
  ?tangent_attribute:string ->
  Node.t ->
  Node.t
(* Arc-length curve Resample. A segment count, maximum segment length, or both
    may be supplied. Optional generated point fields expose input polygon U,
    source curve number, output-point coverage distance, and curve tangent. *)
type extract_point_cut =
  | Extract_point_constant
  | Extract_point_primitive_attribute
  | Extract_point_current_time

(** Emit disconnected points at exact values and strict linear crossings of a
    scalar point field on selected polygon curves. Cuts may be constant,
    primitive-authored, or the current cook time; only the latter declares a
    time cache dependency. Point patterns interpolate payload, primitive
    patterns may be copied to point ownership, and optional diagnostics expose
    uniform-edge curve U, cut count, and original curve number. *)
val extract_point_from_curve :
  ?label:string ->
  ?group:string ->
  ?distance_attribute:string ->
  ?cut:extract_point_cut ->
  ?constant:float ->
  ?primitive_attribute:string ->
  ?point_attributes:string ->
  ?copy_primitive_attributes:bool ->
  ?primitive_attributes:string ->
  ?curve_u_attribute:string ->
  ?number_cuts_attribute:string ->
  ?curve_number_attribute:string ->
  Node.t ->
  Node.t
(* Convert unique topology edges to canonical two-point curves. [group]
   names an optional native edge group. [connect_path] emits maximal paths and
   enables the endpoint-distance and isolated-loop controls. *)
val convert_line :
  ?label:string ->
  ?group:string ->
  ?connect_path:bool ->
  ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  ?remove_unused_points:bool ->
  ?length_attribute:string ->
  Node.t ->
  Node.t
(* Carve selected polygon curves to a normalized interval. [group] names an
   optional primitive group; unselected primitives pass through exactly.
   Primitive float endpoint attributes replace or scale constants. Breakpoint
   mode snaps inward to source vertices and can split/extract every retained
   vertex boundary. Outside breakpoint mode, positive [divisions] splits a Cut
   interval into equal ordered pieces or controls the inclusive Extract sample
   count. *)
val carve :
  ?label:string ->
  ?group:string ->
  ?relative_arc_length:bool ->
  ?first:float ->
  ?last:float ->
  ?first_attribute:string ->
  ?last_attribute:string ->
  ?attribute_mode:Rdk.Curve_ops.parameter_attribute_mode ->
  ?only_at_breakpoints:bool ->
  ?cut_at_all_internal_breakpoints:bool ->
  ?keep:Rdk.Curve_ops.cut_mode ->
  ?extract_points:bool ->
  ?divisions:int ->
  ?keep_original:bool ->
  Node.t ->
  Node.t
val ends :
  ?label:string ->
  ?group:string ->
  ?mode:Rdk.Curve_topology.ends_mode ->
  Node.t ->
  Node.t
(* Open, close straight, or unroll selected polygon faces and polygon curves.
    Shared unroll repeats the first point reference; new-point unroll duplicates
    the complete seam point payload. *)
(* Join selected open polygon curves. An ordered primitive [group] controls
    authored traversal order. [picked_ends] is an alternative selection whose
    first pick in every fixed-size subgroup marks the outgoing endpoint and
    whose later picks mark incoming endpoints; it cannot be combined with
    [group] or [connect_closest_ends]. [connect_closest_ends] globally orders
    unused curve endpoints by proximity after the first selected curve.
    [group_size] starts fixed-size joined subgroups; [keep_originals] retains
    source primitives and appends joined chains over their shared points.
    Ordering, reversals, welds, and connected-only partitions are deterministic
    and participate in node identity. *)
val join_curves :
  ?label:string ->
  ?group:string ->
  ?picked_ends:string ->
  ?orient_closest:bool ->
  ?connect_closest_ends:bool ->
  ?only_connected:bool ->
  ?use_group_size:bool ->
  ?group_size:int ->
  ?keep_originals:bool ->
  ?tolerance:float ->
  ?wrap:bool ->
  Node.t ->
  Node.t
(** Picked ends are comma-separated primitive:start or primitive:end pairs
    in traversal order. Blank means unset; [] explicitly selects no curves.
    Picks exclude a primitive group and closest-end ordering. Enable
    [use_group_size] to limit the number of joined curves per output. *)
val poly_path :
  ?label:string ->
  ?connect_end_points:bool ->
  ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool ->
  Node.t ->
  Node.t
(* Clean unique topology edges into maximal polygon paths. Optional spatial
   endpoint rewiring and isolated-loop closing mirror Houdini PolyPath's
   topology controls. *)
val revolve :
  ?label:string ->
  ?group:string ->
  ?revolve_type:Rdk.Sweep_modeling.revolve_type ->
  ?connectivity:Rdk.Plane_generators.grid_connectivity ->
  ?start_angle:float ->
  ?end_angle:float ->
  ?reverse_cross_sections:bool ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string ->
  ?divisions:int ->
  ?origin:Rays_math.Vec3.t ->
  ?axis:Rays_math.Vec3.t ->
  Node.t ->
  Node.t
(* Cached polygon-curve Revolve node backed by [Rdk.Sweep_modeling.revolve]. *)
val sweep :
  ?label:string ->
  ?backbone_group:string ->
  ?cross_section_group:string ->
  ?connectivity:Rdk.Plane_generators.grid_connectivity ->
  ?tangent:Rdk.Sweep_modeling.sweep_tangent ->
  ?continuous_closed:bool ->
  ?transform_attributes:bool ->
  ?reverse_cross_sections:bool ->
  ?scale:float ->
  ?roll:float ->
  ?twist:float ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string ->
  ?cross_section_prefix:string ->
  Node.t ->
  Node.t ->
  Node.t
(* Cached two-input general-profile Sweep backed by [Rdk.Sweep_modeling.sweep]. Both
    optional group names select primitive curves on their corresponding input.
    Cross-section payload is namespaced by default so both input ancestries
    remain inspectable. *)
val sweep_circle : ?label:string -> ?group:string -> ?radius:float -> ?use_sides:bool -> ?sides:int -> ?divisions_attribute:string -> ?segments:int -> ?segments_attribute:string -> ?use_segment_scales:bool -> ?first_segment_scale:float -> ?last_segment_scale:float -> ?segment_scales_attribute:string -> ?prevent_joint_buckling:bool -> ?maximum_joint_scale:float -> ?maximum_joint_scale_attribute:string -> ?smooth_point:bool -> ?smooth_attribute:string -> ?use_max_valence:bool -> ?max_valence:int -> ?scale_attribute:string -> ?seam_offset:int -> ?seam_attribute:string -> ?segment_seam_attribute:string -> ?v_attribute:string -> ?up_attribute:string -> ?generate_uv:bool -> ?use_u_range:bool -> ?u_min:float -> ?u_max:float -> ?use_v_range:bool -> ?v_min:float -> ?v_max:float -> ?uv_range_attribute:string -> ?caps:bool -> ?cap_group:string -> Node.t -> Node.t
val polywire : ?label:string ->
  ?group:string ->
  ?radius:float ->
  ?use_sides:bool ->
  ?sides:int ->
  ?divisions_attribute:string ->
  ?segments:int ->
  ?segments_attribute:string ->
  ?use_segment_scales:bool ->
  ?first_segment_scale:float ->
  ?last_segment_scale:float ->
  ?segment_scales_attribute:string ->
  ?prevent_joint_buckling:bool ->
  ?maximum_joint_scale:float ->
  ?maximum_joint_scale_attribute:string ->
  ?smooth_point:bool ->
  ?smooth_attribute:string ->
  ?use_max_valence:bool ->
  ?max_valence:int ->
  ?scale_attribute:string ->
  ?seam_offset:int ->
  ?seam_attribute:string ->
  ?segment_seam_attribute:string ->
  ?v_attribute:string ->
  ?up_attribute:string ->
  ?generate_uv:bool ->
  ?use_u_range:bool ->
  ?u_min:float ->
  ?u_max:float ->
  ?use_v_range:bool ->
  ?v_min:float ->
  ?v_max:float ->
  ?uv_range_attribute:string ->
  ?caps:bool ->
  ?cap_group:string ->
  Node.t ->
  Node.t
(* Artist-facing circular PolyWire node backed by the same packed kernel as
   [sweep_circle], including primitive restriction, point-varying radial
   divisions, longitudinal segmentation, point-scaled radius, snapped seam
   offsets, explicit V coordinates, projected joint-up vectors, first/last
   interior segment placement, optional generated UVs, and per-edge U/V
   ranges. Optional radial joint miters prevent sharp bends from collapsing
   and use a constant or point-authored maximum enlargement. [smooth_point],
   [smooth_attribute], and [max_valence] turn non-smooth open-curve joints into
   real uncapped run boundaries without a connecting face. An outgoing-corner
   [segment_seam_attribute] keeps one snapped texture seam across every
   subdivided source edge. *)
type uv_projection = Planar | Cylindrical | Spherical

val uv_project :
  ?label:string ->
  ?projection:uv_projection ->
  ?name:string ->
  ?group:string ->
  ?origin:Rays_math.Vec3.t ->
  ?axis:Rays_math.Vec3.t ->
  ?seam:Rays_math.Vec3.t ->
  ?planar_u:Rays_math.Vec3.t ->
  ?planar_v:Rays_math.Vec3.t ->
  ?height:float ->
  ?u_min:float ->
  ?u_max:float ->
  ?v_min:float ->
  ?v_max:float ->
  ?fix_seams:bool ->
  ?fix_poles:bool ->
  Node.t ->
  Node.t
(* Project seam-safe vertex UVs. [group] names an optional primitive group. *)
val uv_transform :
  ?label:string ->
  ?name:string ->
  ?owner:Rdk.Attribute.owner ->
  ?group:string ->
  ?translate_u:float ->
  ?translate_v:float ->
  ?scale_u:float ->
  ?scale_v:float ->
  ?angle:float ->
  ?pivot_u:float ->
  ?pivot_v:float ->
  Node.t ->
  Node.t
(* Transform point- or vertex-owned UVs. [group], when supplied, must have
   the same owner. Angles are radians. *)
val uv_auto_seam :
  ?label:string ->
  ?name:string ->
  ?group:string ->
  ?angle:float ->
  ?include_boundaries:bool ->
  ?include_non_manifold:bool ->
  ?partition_attribute:string ->
  ?existing_uv:string ->
  ?uv_tolerance:float ->
  ?island_attribute:string ->
  Node.t ->
  Node.t
(* Detect angle, boundary, non-manifold, partition, and existing-UV cuts.
   [name] identifies the native edge output and compatibility outgoing-corner
   vertex group; [group] restricts selected primitives. *)
val group_edges :
  ?label:string ->
  ?name:string ->
  ?group:string ->
  ?incidence:Rdk.Group_mesh.incidence ->
  ?use_min_length:bool ->
  ?min_length:float ->
  ?use_max_length:bool ->
  ?max_length:float ->
  ?angle_basis:Rdk.Group_mesh.angle_basis ->
  ?use_min_angle:bool ->
  ?min_angle:float ->
  ?use_max_angle:bool ->
  ?max_angle:float ->
  Node.t ->
  Node.t
(* Create a native topology-affine edge group using conjunctive incidence,
   length, angle, and optional primitive-group filters. Angles use primitive
   dihedrals by default or pairwise incident-edge directions. *)
(* Create a point, primitive, or native-edge group from point, vertex, or
    primitive attribute discontinuities. Numeric values use [tolerance];
    integer and text values compare exactly. Optional unshared topology and
    point-sharing primitive expansion follow the RDK boundary contract. *)
val group_from_attribute_boundary :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?attributes:Rdk.Group_ops.boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  Node.t ->
  Node.t
(* Create bounded, stable point or primitive groups from distinct non-empty
    values of a text attribute. Dense output is rejected before allocation
    when either configured limit would be exceeded. *)
val groups_from_name :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?attribute:string ->
  ?prefix:string ->
  ?conflict:Rdk.Group_ops.name_conflict ->
  ?invalid_names:Rdk.Group_ops.invalid_name_policy ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  Node.t ->
  Node.t
(* Convert stable same-owner group names back to a point, vertex, or primitive
   text attribute. This is the memory-efficient inverse for partition-style
   workflows, especially with [delete_groups=true]. *)
val name_from_groups :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?attribute:string ->
  ?pattern:string ->
  ?default:string ->
  ?overlap:Rdk.Group_ops.name_overlap ->
  ?delete_groups:bool ->
  Node.t ->
  Node.t
val uv_unitize :
  ?label:string ->
  ?mode:Rdk.Uv_ops.unitize_mode ->
  ?name:string ->
  ?group:string ->
  ?seams:string ->
  ?tolerance:float ->
  ?uniform:bool ->
  Node.t ->
  Node.t
(* Fit each selected face or UV island into the unit square. [seams] names
   a native edge group; outgoing-edge vertex groups remain accepted for
   compatibility. *)
val uv_flatten :
  ?label:string ->
  ?name:string ->
  ?seams:string ->
  ?iterations:int ->
  ?tolerance:float ->
  Node.t ->
  Node.t
(* Flatten seam-delimited manifold triangle disk islands with deterministic
   positive mean-value harmonic coordinates. *)
val uv_relax :
  ?label:string ->
  ?name:string ->
  ?seams:string ->
  ?uv_tolerance:float ->
  ?iterations:int ->
  ?tolerance:float ->
  Node.t ->
  Node.t
(* Relax UV interiors while preserving existing island boundaries. *)
val measure :
  ?label:string ->
  ?kind:Rdk.Analysis.measure ->
  ?group:string ->
  ?accumulation:Rdk.Analysis.accumulation ->
  ?attribute:string ->
  ?total_attribute:string ->
  Node.t ->
  Node.t
(* Measure polygon area, polygon/curve perimeter, or oriented polygon volume
   contribution into primitive attributes, optionally restricted, accumulated
   throughout, and/or accompanied by one detail total. *)
type connectivity_output = Integer | Text

val connectivity :
  ?label:string ->
  ?owner:Rdk.Analysis.connectivity_owner ->
  ?primitive_group:string ->
  ?point_group:string ->
  ?seam_group:string ->
  ?uv_attribute:string ->
  ?name:string ->
  ?output:connectivity_output ->
  ?text_prefix:string ->
  Node.t ->
  Node.t
(* Add stable point or primitive connected-component IDs, [class] by default.
   Include groups exclude elements and topology outside their membership.
   Primitive connectivity may be cut by a native edge seam group or split at
   exact vertex float2/float3 UV discontinuities. Output may be integer IDs or
   prefixed text labels. *)
val set_float :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?value:float ->
  Node.t ->
  Node.t

(** Assign a material to an optional primitive group. *)
val material :
  ?label:string ->
  ?group:string ->
  ?material:string ->
  ?color:Rays_math.Vec3.t ->
  ?roughness:float ->
  ?emission:Rays_math.Vec3.t ->
  Node.t ->
  Node.t

val set_int :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?value:int ->
  Node.t ->
  Node.t
val set_vector :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?value:Rays_math.Vec3.t ->
  Node.t ->
  Node.t
val set_orient : ?label:string ->
  ?x:float ->
  ?y:float ->
  ?z:float ->
  ?w:float ->
  Node.t ->
  Node.t
(* Install a constant point [transform] matrix for Copy to Points. The matrix
   must be finite and affine. *)
val set_transform : ?label:string ->
  ?m00:float ->
  ?m01:float ->
  ?m02:float ->
  ?m03:float ->
  ?m10:float ->
  ?m11:float ->
  ?m12:float ->
  ?m13:float ->
  ?m20:float ->
  ?m21:float ->
  ?m22:float ->
  ?m23:float ->
  ?m30:float ->
  ?m31:float ->
  ?m32:float ->
  ?m33:float ->
  Node.t ->
  Node.t
val rest_position : ?label:string ->
  ?mode:Rdk.Motion.rest_mode ->
  ?rest_attribute:string ->
  ?normals:Rdk.Motion.rest_normals ->
  ?normal_attribute:string ->
  ?rest_normal_attribute:string ->
  Node.t ->
  Node.t option ->
  Node.t
val set_color :
  ?label:string ->
  ?group:string ->
  ?owner:Rdk.Attribute.owner ->
  ?color:Rays_math.Vec3.t ->
  ?alpha:float ->
  Node.t ->
  Node.t
val set_color_float :
  ?label:string ->
  ?group:string ->
  ?owner:Rdk.Attribute.owner ->
  ?color:Rays_math.Vec3.t ->
  ?alpha:float ->
  Node.t ->
  Node.t
(* Delete or keep ordinary attributes with owner-specific compiled patterns.
    Optional reference geometry prepends its attribute names to each owner
    selection, matching Attribute Delete SOP reference semantics. *)
val delete_attributes :
  ?label:string ->
  ?delete_non_selected:bool ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  Node.t ->
  Node.t option ->
  Node.t
(* Apply sequential capture-pattern attribute renames with explicit
    skip/error/overwrite conflict behavior. *)
val rename_attributes :
  ?label:string ->
  ?rules:Rdk.Attribute_ops.rename_rule list ->
  Node.t ->
  Node.t
(* Apply ordered owner-specific Attribute Swap rules. Copy, move, and swap
   preserve packed payload sharing; paired wildcard captures are supported.
   Canonical point [P] participates as float3, and moving [P] becomes Copy. *)
val swap_attributes :
  ?label:string ->
  ?rules:Rdk.Attribute_ops.swap_rule list ->
  Node.t ->
  Node.t

val promote_attributes :
  ?label:string ->
  ?source:Rdk.Attribute.owner ->
  ?destination:Rdk.Attribute.owner ->
  ?pattern:string ->
  ?method_:Rdk.Attribute_ops.method_ ->
  ?delete_source:bool ->
  ?piece_attribute:string ->
  ?into_pattern:string ->
  ?index_pattern:string ->
  Node.t ->
  Node.t
(* Promote stable source-order attributes selected by a Houdini-style glob.
   One topology/piece plan is shared by every payload. [into_pattern] performs
   aligned multi-term capture renaming and [index_pattern] names per-value
   contributing-source integer attributes with the same aligned rules. Packed array methods
   require every selected source to use supported scalar integer/float
   storage; failure remains atomic. *)
(* Assign a stable dense sequence within an optional typed group. A same-owner
   integer/text [piece_attribute] can restart numbering within each piece or
   assign one dense number per piece in first-selected-occurrence order. *)
type enumerate_storage = Enumerate_integer | Enumerate_text

val enumerate :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?group:string ->
  ?start:int ->
  ?step:int ->
  ?storage:enumerate_storage ->
  ?prefix:string ->
  ?piece_attribute:string ->
  ?mode:Rdk.Attribute_ops.enumeration_mode ->
  Node.t ->
  Node.t
val attribute_blur :
  ?label:string ->
  ?attributes:string ->
  ?group:string ->
  ?iterations:int ->
  ?method_:Rdk.Attribute_ops.blur_method ->
  ?mode:smoothing_mode ->
  ?laplacian_step:float ->
  ?odd_step:float ->
  ?even_step:float ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?pin_borders:bool ->
  ?original_blend:float ->
  ?blurred_blend:float ->
  Node.t ->
  Node.t
(** Blur canonical [P] and matching floating point attributes over shared-edge
    point connectivity using the packed deterministic Attribute Blur kernel. *)

type numeric_kind = Numeric_scalar | Numeric_vec2 | Numeric_vec3 | Numeric_vec4
type random_distribution = Random_constant | Random_two_values | Random_uniform | Random_uniform_discrete | Random_normal | Random_exponential | Random_log_normal | Random_cauchy | Random_direction | Random_inside_sphere | Random_inside_sphere_cone | Random_custom_ramp | Random_custom_discrete | Random_custom_discrete_text

val attribute_randomize : ?label:string ->
  ?selection_owner:element_owner ->
  ?selection_group:string ->
  ?ramp:string ->
  ?entries:string ->
  ?text_entries:string ->
  ?use_vector_limits:bool ->
  ?minimum_vector:Rays_math.Vec3.t ->
  ?minimum_w:float ->
  ?maximum_vector:Rays_math.Vec3.t ->
  ?maximum_w:float ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?group:string ->
  ?kind:numeric_kind ->
  ?distribution:random_distribution ->
  ?context_seed:bool ->
  ?seed:int ->
  ?seed_attribute:string ->
  ?fraction_attribute:string ->
  ?a:Rays_math.Vec3.t ->
  ?a_w:float ->
  ?b:Rays_math.Vec3.t ->
  ?b_w:float ->
  ?step:Rays_math.Vec3.t ->
  ?step_w:float ->
  ?probability_b:float ->
  ?cone_angle:float ->
  ?dimensions:int ->
  ?use_minimum:bool ->
  ?minimum:float ->
  ?use_maximum:bool ->
  ?maximum:float ->
  ?direction_bias:float ->
  ?operation:Rdk.Attribute_ops.random_operation ->
  ?scale:float ->
  Node.t ->
  Node.t
(** Attribute Randomize's flat Lisp fields, including custom distributions,
    explicit selections and per-component limits. Fraction sampling ignores
    seed controls; otherwise [context_seed] selects a context-dependent stream. *)

type noise_location = Noise_position | Noise_element_number | Noise_attribute
type noise_range = Noise_positive | Noise_zero_centered | Noise_min_max

val attribute_noise : ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?group:string ->
  ?kind:Rdk.Attribute_ops.noise_kind ->
  ?context_seed:bool ->
  ?seed:int ->
  ?location:noise_location ->
  ?location_attribute:string ->
  ?range:noise_range ->
  ?min:Rays_math.Vec3.t ->
  ?min_w:float ->
  ?max:Rays_math.Vec3.t ->
  ?max_w:float ->
  ?operation:Rdk.Attribute_ops.noise_operation ->
  ?blend:float ->
  ?frequency:Rays_math.Vec3.t ->
  ?offset:Rays_math.Vec3.t ->
  ?octaves:int ->
  ?lacunarity:float ->
  ?roughness:float ->
  Node.t ->
  Node.t
(** Coherent Attribute Noise, with Lisp defaults and flat sampling/range controls.
    An explicit seed is the default; [context_seed] mixes the context seed with
    the node label. Quaternion output supports set and set-initial operations. *)

type remap_range = Remap_automatic | Remap_explicit

val attribute_remap :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?into:string ->
  ?group:string ->
  ?kind:numeric_kind ->
  ?input_range:remap_range ->
  ?input_min:Rays_math.Vec3.t ->
  ?input_min_w:float ->
  ?input_max:Rays_math.Vec3.t ->
  ?input_max_w:float ->
  ?output_min:Rays_math.Vec3.t ->
  ?output_min_w:float ->
  ?output_max:Rays_math.Vec3.t ->
  ?output_max_w:float ->
  ?policy:Rdk.Attribute_ops.remap_policy ->
  ?ramp:string ->
  Node.t ->
  Node.t
(** Remap scalar/tuple floating attributes component-wise through explicit or
    selected-data ranges. XYZ ranges are grouped vectors; W is separate.
    A ramp is comma-separated position:value knots with strictly increasing
    positions and endpoints at 0 and 1; blank is linear. Ranges and ramp values
    must be finite; active explicit maxima exceed minima. Blank optional names
    are unset. *)


type copy_match = Copy_cyclic | Copy_by_values | Copy_to_element
val attribute_copy :
  ?label:string ->
  ?group_owner:Rdk.Group.owner ->
  ?match_:copy_match ->
  ?source_match_attribute:string ->
  ?target_match_attribute:string ->
  ?target_element_attribute:string ->
  ?allow_position:bool ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  ?rules:string ->
  Node.t ->
  Node.t ->
  Node.t
(* Direct ordered/cyclic or attribute-matched copying between equal-class
   source and destination group selections. Attribute rules may target any
   owner independently of the group owner; topology projections are shared by
   all fields of an owner. Rules use Lisp's owner/pattern/destination table.
   Nonblank group patterns take precedence over exact group names. *)

type interpolate_driver = Interpolate_primitive_uvw | Interpolate_point_weights | Interpolate_vertex_weights | Interpolate_primitive_weights

val attribute_interpolate :
  ?label:string ->
  ?target_owner:Rdk.Attribute.owner ->
  ?attributes:string ->
  ?group:string ->
  ?group_pattern:string ->
  ?driver:interpolate_driver ->
  ?primitive_attribute:string ->
  ?uvw_attribute:string ->
  ?numbers_attribute:string ->
  ?weights_attribute:string ->
  ?compute_weights:bool ->
  ?computed_owner:Rdk.Attribute.owner ->
  ?computed_numbers_attribute:string ->
  ?computed_weights_attribute:string ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?pre_scale:float ->
  ?normalize_weights:bool ->
  ?threshold:float ->
  ?blend:float ->
  ?unmatched:Rdk.Attribute_ops.unmatched ->
  Node.t ->
  Node.t ->
  Node.t
(** Lisp's flat interpolation controls. Attribute rules use the escaped
    owner/source/target table; group patterns take precedence over exact names. *)

type transfer_falloff = Transfer_linear | Transfer_smoothstep | Transfer_uniform
type transfer_mode = Transfer_nearest | Transfer_inverse | Transfer_links | Transfer_renderman | Transfer_hart
val attribute_transfer :
  ?label:string ->
  ?owner:Rdk.Attribute.owner ->
  ?use_names:bool ->
  ?names:string ->
  ?pattern:string ->
  ?mode:transfer_mode ->
  ?neighbors:int ->
  ?power:float ->
  ?kernel_radius:float ->
  ?distance_mode:kernel_mode ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:transfer_falloff ->
  ?uniform_bias:float ->
  ?unmatched:Rdk.Attribute_ops.unmatched ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?source_vertex_group:string ->
  ?source_vertex_group_pattern:string ->
  ?source_vertex_selection:Rdk.Attribute_ops.surface_vertex_selection ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  Node.t ->
  Node.t ->
  Node.t
(** Same-owner attribute transfer with Lisp defaults and positional inputs.
    Exact names use one escaped table column per row when [use_names] is true;
    otherwise [pattern] selects attributes. Auto distance is unbounded. Group
    patterns take precedence over exact names. *)

val attribute_transfer_surface :
  ?label:string ->
  ?target_owner:Rdk.Attribute.owner ->
  ?attributes:string ->
  ?distance_mode:kernel_mode ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:transfer_falloff ->
  ?uniform_bias:float ->
  ?unmatched:Rdk.Attribute_ops.unmatched ->
  ?distance_attribute:string ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?source_vertex_group:string ->
  ?source_vertex_group_pattern:string ->
  ?source_vertex_selection:Rdk.Attribute_ops.surface_vertex_selection ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  Node.t ->
  Node.t ->
  Node.t
(* Transfer point/vertex/primitive payloads at closest polygon-surface
   barycentric coordinates into target points, vertices, or primitive
   barycenters through the shared packed surface index. Optional group names
   restrict source primitives, source vertices, and destination-owner
   elements. Source-vertex selection retains emitted triangles whose corners
   satisfy the requested all/any rule. Group patterns union all matching
   groups; a pattern matching none is an empty selection. *)


val attribute_transfer_all :
  ?label:string ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?mode:transfer_mode ->
  ?neighbors:int ->
  ?power:float ->
  ?kernel_radius:float ->
  ?distance_mode:kernel_mode ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:transfer_falloff ->
  ?uniform_bias:float ->
  ?unmatched:Rdk.Attribute_ops.unmatched ->
  Node.t ->
  Node.t ->
  Node.t
(* Transfer explicitly requested attribute patterns for multiple owners in
    one graph node. At least one owner pattern is required. Each owner shares
    one spatial plan across all of its matching attributes; owner kernels are
    sequenced to avoid nested parallel-pool oversubscription. *)
val delete_edge_group : ?label:string ->
  ?name:string ->
  Node.t ->
  Node.t
val rename_edge_group :
  ?label:string ->
  ?from:string ->
  ?into:string ->
  Node.t ->
  Node.t
val group : ?label:string -> name:string -> 'owner Select.t -> Node.t -> Node.t
(** Materialize a typed selection as a named packed group. *)

val group_random :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?probability:float ->
  ?context_seed:bool ->
  ?seed:int ->
  ?seed_attribute:string ->
  ?base:string ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Deterministic random point, vertex, primitive, or native-edge grouping.
    The default uses explicit seed 0. With [context_seed:true], a stable node
    identity is mixed with the procedural context seed. *)

type group_bounds_shape = Box | Sphere
val group_bounds :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?shape:group_bounds_shape ->
  ?center:Rays_math.Vec3.t ->
  ?size:Rays_math.Vec3.t ->
  ?radius:float ->
  ?base:string ->
  ?containment:Rdk.Group_ops.containment ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Inclusive box/sphere grouping for all four topology owners. Partial native
    edges use geometric segment intersection, not endpoint approximation. *)

val group_normal :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?direction:Rays_math.Vec3.t ->
  ?spread_angle:float ->
  ?normal_attribute:string ->
  ?use_existing_normal:bool ->
  ?include_opposite:bool ->
  ?base:string ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Deterministic packed grouping by geometric or owner-matched float3
    normals. Supports point, primitive, and native-edge groups; vertex groups
    are intentionally unsupported, matching Group Create. Existing point [N]
    is reused by default for point/edge owners. Angles are radians. *)

val group_non_planar :
  ?label:string ->
  ?name:string ->
  ?tolerance:float ->
  ?base:string ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Select non-planar polygon primitives using an absolute world-space
    tolerance. Use union merge when composing it as Group Create's additive
    non-planarity plane. *)

val group_backface :
  ?label:string ->
  ?name:string ->
  ?viewpoint:Rays_math.Vec3.t ->
  ?base:string ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Select winding-derived primitive backfaces relative to a finite viewpoint.
    Subtract merge removes backfaces from an existing same-name group. *)

val group_edge_depth :
  ?label:string ->
  ?point_group:string ->
  ?name:string ->
  ?depth:int ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Grow a seed point group by bounded shortest topology-edge distance. *)

val group_unshared :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  Node.t ->
  Node.t
(** Select points, primitives, or native edges incident to unshared topology. *)

val group_boundary_components :
  ?label:string ->
  ?prefix:string ->
  ?conflict:Rdk.Group_ops.name_conflict ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  Node.t ->
  Node.t
(** Create stable point groups for connected polygon boundary components. *)

val ordered_group :
  ?label:string ->
  ?owner:Rdk.Group.owner ->
  ?name:string ->
  ?elements:int list ->
  Node.t ->
  Node.t
(** Materialize unique element indices in their supplied traversal order.
    Elements are immutable; the packed traversal array is owned by the node. *)

val group_promotions :
  ?label:string ->
  ?rules:Rdk.Group_ops.promotion_rule list ->
  ?max_outputs:int ->
  ?max_payload_bytes:int ->
  Node.t ->
  Node.t
(** Apply ordered wildcard ordinary or boundary promotions in one inspectable
    node. Blank-pattern rules are disabled when cooking.
    Later rules observe earlier outputs. Output count and generated payload are
    bounded before each allocation; all-disabled rules preserve cooked geometry
    and retain the node's own parameter/cache identity. *)

val group_promote_boundary :
  ?label:string ->
  ?source:Rdk.Group_ops.owner ->
  ?destination:Rdk.Group_ops.owner ->
  ?group:string ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?attributes:Rdk.Group_ops.boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  Node.t ->
  Node.t
(** Convert a named group and retain its topology boundary, optionally unioning
    typed attribute seams and polygon/curve unshared edges. The result is
    intersected with ordinary promotion so the opposite side is excluded. *)

val group_expand :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?group:string ->
  ?name:string ->
  ?steps:int ->
  ?flood:bool ->
  ?step_attribute:string ->
  ?primitive_connectivity:Rdk.Group_ops.primitive_connectivity ->
  ?normal_spread:float ->
  ?use_normal_attribute:bool ->
  ?normal_owner:Rdk.Attribute.owner ->
  ?normal_name:string ->
  ?connectivity_attributes:Rdk.Group_ops.boundary_attribute list ->
  ?connectivity_tolerance:float ->
  ?use_collision:bool ->
  ?collision_owner:Rdk.Group_ops.owner ->
  ?collision_group:string ->
  ?collision_contain:bool ->
  ?collision_allow_boundary:bool ->
  Node.t ->
  Node.t
(** Grow, shrink, or flood-fill a named group using owner-specific topology
    adjacency. Negative [steps] shrink. Point and edge-connected primitive
    groups may restrict growth by a radian normal spread, typed point/vertex/
    primitive normal source, typed connectivity-attribute seams, and an
    independently owned collision group with containment/boundary policy.
    Connectivity and collision seams become erosion boundaries when shrinking.
    Normal spread compares adjacent mapped unit directions and affects growth
    only. Vertex/edge targets and shared-point primitive seams are rejected
    until their boundary semantics can be represented exactly.
    [step_attribute] records the first positive change iteration or
    multi-source flood distance on ordinary owners. *)

val group_combine :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?base_pattern:string ->
  ?base_inverted:bool ->
  ?steps:Rdk.Group_ops.combine_step list ->
  Node.t ->
  Node.t
(** Boolean-combine named group patterns, including complemented operands,
    into one point, vertex, primitive, or native-edge group. *)

type group_range_mode = Start_end | From_ends | Start_length | Partition
type group_range_connectivity = No_connectivity | Disconnected | Connected

val group_range :
  ?label:string ->
  ?owner:Rdk.Group_ops.owner ->
  ?name:string ->
  ?base:string ->
  ?invert:bool ->
  ?merge:Rdk.Group_ops.boolean_operation ->
  ?range_mode:group_range_mode ->
  ?start:int ->
  ?end_:int ->
  ?end_offset:int ->
  ?length:int ->
  ?partition:int ->
  ?partitions:int ->
  ?use_filter:bool ->
  ?filter_select:int ->
  ?filter_of:int ->
  ?filter_offset:int ->
  ?connectivity_mode:group_range_connectivity ->
  ?use_region:bool ->
  ?region:int ->
  ?connectivity_attributes:string ->
  ?connectivity_tolerance:float ->
  ?use_collision:bool ->
  ?collision_owner:Rdk.Group_ops.owner ->
  ?collision_pattern:string ->
  ?keep_boundary:bool ->
  ?remove_other_regions:bool ->
  Node.t ->
  Node.t
(** Create a packed group from an absolute/relative/length/partition range,
    with an optional periodic selection filter and base-group mask. Optional
    connectivity evaluates the range independently in stable point or
    primitive components. Advanced connectivity can split at same-owner
    attribute discontinuities or independently owned collision-group
    boundaries, control boundary retention, and either preserve or remove
    components outside a one-region restriction. *)

val group_ranges :
  ?label:string ->
  ?rules:Rdk.Group_ops.range_rule list ->
  Node.t ->
  Node.t
(** Apply ordered Group Range rules in one inspectable node. Blank-name rules
    are disabled when cooking. Later rules may use groups
    emitted by earlier rules as bases or collision groups. Empty/all-disabled
    rules preserve cooked geometry and retain the node's own parameter/cache identity. *)

type group_invert_owner = Any | Owner of Rdk.Group_ops.owner
(** [Any] applies to every group owner, as in Lisp. *)

val group_invert :
  ?label:string ->
  ?owner:group_invert_owner ->
  ?pattern:string ->
  ?new_name:string ->
  ?conflict:Rdk.Group_ops.rename_conflict ->
  Node.t ->
  Node.t
(** Invert one or many groups selected by a name pattern, optionally rewriting
    their names with wildcard captures. *)

val group_delete :
  ?label:string ->
  ?rules:Rdk.Group_ops.delete_rule list ->
  ?delete_unused:bool ->
  Node.t ->
  Node.t
(** Delete group metadata by ordered owner/name rules without deleting
    geometry elements. *)

val group_rename :
  ?label:string ->
  ?rules:Rdk.Group_ops.rename_rule list ->
  Node.t ->
  Node.t
(** Apply sequential wildcard-capture group renames with explicit conflict
    behavior. *)

val group_copy :
  ?label:string ->
  ?use_rules:bool ->
  ?rules:Rdk.Group_ops.copy_rule list ->
  ?conflict:Rdk.Group_ops.copy_conflict ->
  ?copy_empty:bool ->
  Node.t ->
  Node.t ->
  Node.t
(** Copy group membership from [source] onto [target] by element identity or
    an integer/text matching attribute. *)

val group_transfer :
  ?label:string ->
  ?use_rules:bool ->
  ?rules:Rdk.Group_ops.transfer_rule list ->
  ?conflict:Rdk.Group_ops.copy_conflict ->
  ?create_empty:bool ->
  ?distance:float ->
  Node.t ->
  Node.t ->
  Node.t
(** Transfer point, primitive, and native-edge groups by exact closest
    same-owner geometry proximity within [distance]. Polygon/curve primitive
    and edge distances use accelerated triangle/segment queries rather than
    centroids. *)

val group_find_path :
  ?label:string ->
  ?owner:Rdk.Group.owner ->
  ?base_group:string ->
  ?name:string ->
  ?mode:Rdk.Group_mesh.path_mode ->
  ?ending:Rdk.Group_mesh.path_ending ->
  ?avoid_self_intersection:bool ->
  ?collision_group:string ->
  ?contain:bool ->
  Node.t ->
  Node.t
(** Construct an ordered point or primitive group from an explicitly ordered
    same-owner base group. Point paths follow topology edges; primitive paths
    follow the manifold shared-edge dual graph. Independent paths cook in
    parallel; paths with intersection avoidance retain deterministic
    base-order priority. Vertex paths are not supported. *)

(* Select points or primitives from a same-owner scalar numeric attribute.
    The optional named base group restricts both normal and inverted
    classification. Output either deletes through RDK's stable topology
    planner or replaces a named group. Unused-point removal is valid only for
    primitive deletion. *)
type blast_attribute_mode = Blast_below | Blast_range | Blast_width
type blast_attribute_output = Blast_delete | Blast_group
val blast_by_attribute :
  ?label:string ->
  ?owner:Rdk.Blast_by_attribute.owner ->
  ?attribute:string ->
  ?mode:blast_attribute_mode ->
  ?threshold:float ->
  ?minimum:float ->
  ?maximum:float ->
  ?center:float ->
  ?width:float ->
  ?group:string ->
  ?invert:bool ->
  ?output:blast_attribute_output ->
  ?output_group:string ->
  ?remove_unused_points:bool ->
  Node.t ->
  Node.t
val blast :
  ?label:string ->
  ?owner:Rdk.Group.owner ->
  ?group:string ->
  ?selected:bool ->
  ?compact_points:bool ->
  ?policy:Rdk.Deletion.topology_policy ->
  Node.t ->
  Node.t
val compact_points : ?label:string ->
  Node.t ->
  Node.t
(* Construct a deterministic lower-dimensional or closed 3D convex hull from
    an optional typed component selection. Point/detail ancestry preservation,
    source-number output, and the generated primitive group participate in the
    immutable node identity. *)
val convex_hull :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?preserve_point_payload:bool ->
  ?source_point_attribute:string ->
  ?hull_group:string ->
  Node.t ->
  Node.t
(* Emit detail, primitive, or stable integer/text piece centers through the
    packed RDK kernel. Point-mass, bounding-box, and exact convex-hull mass
    methods, provenance names, and piece identity are immutable cache facts. *)
type centroid_run_mode = Detail | Primitives | Point_pieces | Primitive_pieces

val extract_centroid :
  ?label:string ->
  ?run_over:centroid_run_mode ->
  ?piece_attribute:string ->
  ?method_:Rdk.Curve_topology.centroid_method ->
  ?source_primitive_attribute:string ->
  ?piece_output_attribute:string ->
  Node.t ->
  Node.t
val bound :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?shape:group_bounds_shape ->
  ?divisions_x:int ->
  ?divisions_y:int ->
  ?divisions_z:int ->
  ?segments:int ->
  ?rings:int ->
  ?minimum_radius:float ->
  ?lower:Rays_math.Vec3.t ->
  ?upper:Rays_math.Vec3.t ->
  ?bounds_group:string ->
  ?center_attribute:string ->
  ?radii_attribute:string ->
  Node.t ->
  Node.t
(* Create a divided box or polygon sphere/ovoid around an optional typed
    component selection, with inspectable output group and detail metadata. *)
val match_axis :
  ?label:string ->
  ?from:Rays_math.Vec3.t ->
  ?into:Rays_math.Vec3.t ->
  Node.t ->
  Node.t
(* Stable packed point/primitive sort, including point topology keys and
    point/primitive Morton spatial locality. [Random] is deterministic from
    its immutable seed. [Index_attribute] consumes an exact permutation.
    [output_indices] emits destination ranks without reordering, and
    [combine_indices] chains stable indirect sorts through an existing rank
    field. *)
type sort_key = Sort_x | Sort_y | Sort_z | Sort_distance | Sort_vector
  | Sort_attribute | Sort_vertex_order | Sort_primitive_index | Sort_spatial
  | Sort_random | Sort_index_attribute | Sort_reverse | Sort_shift

val sort :
  ?label:string ->
  ?owner:Rdk.Ordering.owner ->
  ?key:sort_key ->
  ?group:string ->
  ?descending:bool ->
  ?x:float ->
  ?y:float ->
  ?z:float ->
  ?attribute:string ->
  ?component:int ->
  ?seed:int ->
  ?shift:int ->
  ?output_indices:string ->
  ?combine_indices:bool ->
  Node.t ->
  Node.t
type target_justify_mode = Justify_explicit | Justify_auto
val match_size :
  ?label:string ->
  ?group_owner:element_owner ->
  ?group:string ->
  ?source_group_owner:element_owner ->
  ?source_group:string ->
  ?target_group_owner:element_owner ->
  ?target_group:string ->
  ?target_justify_mode:target_justify_mode ->
  ?fit:Rdk.Match_size.match_size_fit ->
  ?translate_x:bool ->
  ?translate_y:bool ->
  ?translate_z:bool ->
  ?scale_x:bool ->
  ?scale_y:bool ->
  ?scale_z:bool ->
  ?justify:Rays_math.Vec3.t ->
  ?target_justify:Rays_math.Vec3.t ->
  ?offset:Rays_math.Vec3.t ->
  ?scale:float ->
  ?target_center:Rays_math.Vec3.t ->
  ?target_size:Rays_math.Vec3.t ->
  Node.t ->
  Node.t option ->
  Node.t
(** Match selected source geometry to another node's selected bounds, or to a
    unit/explicit numeric reference when [target] is [None]. Move, source
    bounds, and target bounds selections are independent. Per-axis alignment,
    offsets, scale controls, and all RDK metric-fit modes participate in the
    immutable node cache identity. *)

val custom :
  ?label:string ->
  ?version:int ->
  ?parameters:string ->
  ?cook_mode:Node.cook_mode ->
  ?dependencies:Context.Dependencies.t ->
  operation:string ->
  Node.t list ->
  (context:Context.t -> Rdk.Geometry.t array ->
   (Rdk.Geometry.t, string) result) ->
  Node.t
(** Define an inspectable custom node from RDK operations or their
    composition. Identity fields and declared context dependencies are
    part of its cache key. The callback may retain immutable geometry values,
    but must not mutate or retain the supplied array. Long work must poll
    [Context.cancel_token]. *)

val noise_displace :
  ?label:string ->
  ?context_seed:bool ->
  ?seed:int ->
  ?amplitude:float ->
  ?frequency:float ->
  Node.t ->
  Node.t
(** With [context_seed:true], the node derives a deterministic stream from the cook
    context seed and node identity, and therefore declares a seed dependency.
    An explicit [label] makes that identity stable across unrelated graph
    construction edits. The default uses explicit seed 0. *)

val color_by_height :
  ?label:string ->
  ?low_red:int ->
  ?low_green:int ->
  ?low_blue:int ->
  ?low_alpha:int ->
  ?high_red:int ->
  ?high_green:int ->
  ?high_blue:int ->
  ?high_alpha:int ->
  Node.t ->
  Node.t

val scatter :
  ?label:string ->
  ?count:int ->
  ?context_seed:bool ->
  ?seed:int ->
  ?group:string ->
  ?use_density:bool ->
  ?density_owner:Rdk.Attribute.owner ->
  ?density_attribute:string ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?source_primitive_attribute:string ->
  ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string ->
  Node.t ->
  Node.t
(** Deterministically scatter an exact point count over selected polygon area.
    Density weighting, attribute/group interpolation, and exact source
    primitive plus vertex-weight provenance delegate to the shared packed RDK
    kernel. [N], optional [Cd], and stable [id] remain default outputs. An
    explicit label stabilizes an implicit context-derived seed across unrelated
    graph edits. *)

type velocity_initialization = Velocity_compute | Velocity_keep | Velocity_set | Velocity_from_attribute
val point_velocity :
  ?label:string ->
  ?group:string ->
  ?approximation:Rdk.Motion.velocity_approximation ->
  ?dt:float ->
  ?initialization:velocity_initialization ->
  ?set:Rays_math.Vec3.t ->
  ?source_attribute:string ->
  ?source_scale:float ->
  ?match_attribute:string ->
  ?unmatched:Rdk.Motion.velocity_unmatched ->
  ?velocity_attribute:string ->
  ?add:Rays_math.Vec3.t ->
  ?compute_acceleration:bool ->
  ?acceleration_attribute:string ->
  Node.t ->
  Node.t option ->
  Node.t option ->
  Node.t
(** Point velocity with independent previous/next samples and Lisp defaults.
    A positive time step and valid output names are checked at construction.
    Selection and matching names use blank for unset. *)

val attribute_noise_quaternion : ?label:string ->
  ?group:string ->
  ?owner:Rdk.Attribute.owner ->
  ?name:string ->
  ?location:string ->
  ?range:string ->
  ?seed:int ->
  ?frequency:Rays_math.Vec3.t ->
  ?octaves:int ->
  Node.t ->
  Node.t
