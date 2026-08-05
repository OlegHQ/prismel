(** Human-first SOP graph constructors. One-input modifiers take their input
    last so they compose with [(|>)]. *)

type point_range_kernel =
  context:Context.t ->
  first:int ->
  last:int ->
  x:float array ->
  y:float array ->
  z:float array ->
  unit

type element_group =
  | Point_group of string
  | Vertex_group of string
  | Primitive_group of string
  | Edge_group of string
(** Named topology component group. Each SOP documents whether it promotes the
    selection to referenced points or incident primitives. *)

val snapshot : ?label:string -> Pdk.Geometry.t -> Node.t
(** Use an immutable cooked geometry value as an explicit graph source. This
    is the feedback boundary for iterative [Sketch.run_state] applications;
    it does not create a cycle inside the SOP DAG. *)

val points : ?label:string -> (float * float * float) array -> Node.t

(* Generate an origin point cloud without an input. The generated point and
    local-index metadata default to [sourcepoint] (always [-1]) and
    [sourceindex] (the stable generated point number). *)
val point_generate_origin :
  ?label:string ->
  ?generated_group:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  points:int ->
  unit -> Node.t
val line :
  ?label:string -> ?kind:Pdk.Ops.line_kind -> ?points:int ->
  origin:Prismel.Vec3.t -> direction:Prismel.Vec3.t -> length:float -> unit ->
  Node.t
val polyline :
  ?label:string -> ?closed:bool -> (float * float * float) array -> Node.t
val circle :
  ?label:string ->
  ?arc:Pdk.Ops.circle_arc ->
  ?orientation:Pdk.Ops.circle_orientation ->
  ?reverse:bool ->
  ?center:Prismel.Vec3.t ->
  ?radius_x:float ->
  ?radius_y:float ->
  ?rotation:float ->
  ?uniform_scale:float ->
  ?segments:int -> radius:float -> unit -> Node.t
(* Immutable polygon circle, ellipse, open/chord-closed arc, or sliced arc.
    Plane, transform, dimensions, traversal, and arc parameters participate in
    cache identity; cooking uses the context's cancellation token and grain. *)
(* Packed planar lattice with division- or point-count resolution and
    point/row/column/quad/triangle topology. Orientation, dimensions, center,
    in-plane rotation, and optional normalized point UVs are immutable cache
    parameters. *)
val grid :
  ?label:string ->
  ?counts:Pdk.Ops.grid_counts ->
  ?connectivity:Pdk.Ops.grid_connectivity ->
  ?orientation:Pdk.Ops.grid_orientation ->
  ?center:Prismel.Vec3.t ->
  ?width:float ->
  ?height:float ->
  ?rotation:float ->
  ?uv_attribute:string ->
  columns:int -> rows:int -> size:float -> unit -> Node.t
val box :
  ?label:string ->
  ?size:Prismel.Vec3.t ->
  ?connectivity:Pdk.Ops.box_connectivity ->
  ?consolidate_points:bool ->
  ?normals:Pdk.Ops.box_normals ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.box_rotation_order ->
  ?uniform_scale:float ->
  ?x_divisions:int ->
  ?y_divisions:int ->
  ?z_divisions:int ->
  ?uv_attribute:string ->
  ?face_groups:string ->
  unit -> Node.t
(* Immutable divided triangle/quad Box or surface/volume point lattice. Every
   topology, sharing, normal, transform, UV, and face-group parameter is part
   of the node's stable cache identity. *)
val uv_sphere :
  ?label:string ->
  ?connectivity:Pdk.Ops.sphere_connectivity ->
  ?unique_points_per_pole:bool ->
  ?triangular_poles:bool ->
  ?normals:Pdk.Ops.sphere_normals ->
  ?orientation:Pdk.Ops.sphere_orientation ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.sphere_rotation_order ->
  ?uniform_scale:float ->
  ?radius_x:float ->
  ?radius_y:float ->
  ?radius_z:float ->
  ?uv_attribute:string ->
  ?segments:int ->
  ?rings:int ->
  radius:float ->
  unit -> Node.t
(** Immutable latitude/longitude sphere/ellipsoid generator. Every topology,
    pole-sharing, normal, frame/transform, radii, and UV parameter contributes
    to the stable cache identity and cooks through the PDK packed kernel. *)

val torus :
  ?label:string ->
  ?connectivity:Pdk.Ops.torus_connectivity ->
  ?normals:Pdk.Ops.torus_normals ->
  ?orientation:Pdk.Ops.torus_orientation ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.torus_rotation_order ->
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
  unit -> Node.t
(** Immutable full/partial torus generator. Connectivity, independent U/V
    angle and wrap policy, polygon caps, normals, frame/transform, resolution,
    radii, and UV parameters all participate in stable cache identity. *)

val tube :
  ?label:string ->
  ?connectivity:Pdk.Ops.tube_connectivity ->
  ?end_caps:bool ->
  ?consolidate_cap_points:bool ->
  ?normals:Pdk.Ops.tube_normals ->
  ?orientation:Pdk.Ops.tube_orientation ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.tube_rotation_order ->
  ?radius_scale:float ->
  ?uv_attribute:string ->
  ?cap_group:string ->
  ?rows:int ->
  ?columns:int ->
  top_radius:float ->
  bottom_radius:float ->
  height:float ->
  unit -> Node.t
(** Immutable cylinder/frustum/cone/pyramid generator. Connectivity, cap
    sharing, normals, frame/transform, dual radii, resolution, UV, and cap
    group parameters all participate in stable cache identity. *)

val platonic :
  ?label:string ->
  ?kind:Pdk.Ops.platonic_kind ->
  ?normals:Pdk.Ops.platonic_normals ->
  ?orientation:Pdk.Ops.platonic_orientation ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.platonic_rotation_order ->
  ?face_groups:string ->
  radius:float ->
  unit -> Node.t
(** Immutable regular-polyhedron generator. Kind, normals, frame/transform,
    face-group prefix, and circumsphere radius all participate in stable cache
    identity. The soccer-ball kind also carries black/white primitive [Cd]. *)

val spiral :
  ?label:string ->
  ?extent:Pdk.Ops.spiral_extent ->
  ?radius:Pdk.Ops.spiral_radius ->
  ?height_ramp:(float * float) list ->
  ?radius_scale:float ->
  ?radius_ramp:(float * float) list ->
  ?direction:Pdk.Ops.spiral_direction ->
  ?start_angle:float ->
  ?divisions:Pdk.Ops.spiral_divisions ->
  ?uniform_angle:bool ->
  ?spiral_count:int ->
  ?orientation:Pdk.Ops.spiral_orientation ->
  ?center:Prismel.Vec3.t ->
  ?rotation:Prismel.Vec3.t ->
  ?rotation_order:Pdk.Ops.spiral_rotation_order ->
  ?uniform_scale:float ->
  ?angle_attribute:string ->
  ?x_axis_attribute:string ->
  ?y_axis_attribute:string ->
  ?tangent_attribute:string ->
  ?orient_attribute:string ->
  ?distance_attribute:string ->
  unit -> Node.t
(** Immutable polygon spiral/helix generator. Curve family, extent, ramps,
    sampling policy, phase count, transform, and optional frame/distance
    attributes all participate in stable cache identity. Cooking delegates to
    the deterministic packed PDK kernel using the context grain and
    cancellation token. *)

val transform :
  ?label:string ->
  ?selection:element_group ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Prismel.Mat4.t -> Node.t -> Node.t
(** Apply one matrix to points referenced by an optional typed group. Point
    and vertex normals follow the inverse transpose; singular transforms drop
    them, or [recompute_normals] rebuilds pre-existing normal planes. *)

val transform_trs :
  ?label:string ->
  ?order:Pdk.Ops.transform_order ->
  ?rotation_order:Pdk.Ops.transform_rotation_order ->
  ?translate:Prismel.Vec3.t ->
  ?rotate:Prismel.Vec3.t ->
  ?scale:Prismel.Vec3.t ->
  ?shear:Prismel.Vec3.t ->
  ?uniform_scale:float ->
  ?pivot:Prismel.Vec3.t ->
  ?pivot_rotation:Prismel.Vec3.t ->
  ?invert:bool ->
  ?selection:element_group ->
  ?preserve_normal_length:bool ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(** Typed affine Transform SOP. Orders describe the sequence applied to
    column-vector points; rotations are radians and shear components are
    X-on-XY, X-on-XZ, and Y-on-YZ. *)

val soft_transform :
  ?label:string ->
  ?selection:element_group ->
  ?metric:Pdk.Ops.soft_transform_metric ->
  ?falloff:Pdk.Ops.soft_transform_falloff ->
  ?radius:float ->
  ?falloff_attribute:string ->
  ?recompute_normals:bool ->
  Prismel.Mat4.t -> Node.t -> Node.t
(** Apply a matrix with radius, edge-path, or point-attribute falloff. The
    optional selected group supplies source points for geometric metrics and
    the affected points for attribute weights. *)

val soft_transform_trs :
  ?label:string ->
  ?order:Pdk.Ops.transform_order ->
  ?rotation_order:Pdk.Ops.transform_rotation_order ->
  ?translate:Prismel.Vec3.t ->
  ?rotate:Prismel.Vec3.t ->
  ?scale:Prismel.Vec3.t ->
  ?shear:Prismel.Vec3.t ->
  ?uniform_scale:float ->
  ?pivot:Prismel.Vec3.t ->
  ?pivot_rotation:Prismel.Vec3.t ->
  ?invert:bool ->
  ?selection:element_group ->
  ?metric:Pdk.Ops.soft_transform_metric ->
  ?falloff:Pdk.Ops.soft_transform_falloff ->
  ?radius:float ->
  ?falloff_attribute:string ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(** Typed TRS/shear/pivot convenience for {!soft_transform}. *)

val distance_along_geometry :
  ?label:string ->
  ?affected:element_group ->
  ?falloff:Pdk.Ops.soft_transform_falloff ->
  ?radius:Pdk.Ops.distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  start:element_group ->
  Node.t -> Node.t
(** Compute point distance along mesh edges from a required typed start group.
    The optional affected group limits writes. Raw distance defaults to the
    point-float [distance] plane; pass [~distance_attribute:None] to omit it.
    An optional mask uses fixed or maximum-distance normalization. *)

val distance_from_geometry :
  ?label:string ->
  ?affected:element_group ->
  ?reference_selection:element_group ->
  ?reference_kind:Pdk.Ops.distance_from_geometry_reference ->
  ?falloff:Pdk.Ops.soft_transform_falloff ->
  ?radius:Pdk.Ops.distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  reference:Node.t ->
  Node.t -> Node.t
(** Measure source points to the closest selected reference point or polygon
    surface. Typed affected/reference groups are resolved against their own
    inputs. Raw distance and optional fixed/maximum-radius masks share the
    packed spatial query and preserve source values outside the affected set. *)

val distance_from_target :
  ?label:string ->
  ?affected:element_group ->
  ?projection:Pdk.Ops.distance_from_target_projection ->
  ?origin:Prismel.Vec3.t ->
  ?direction:Prismel.Vec3.t ->
  ?metric:Pdk.Ops.distance_from_target_metric ->
  ?falloff:Pdk.Ops.soft_transform_falloff ->
  ?radius:Pdk.Ops.distance_along_radius ->
  ?distance_attribute:string option ->
  ?mask_attribute:string ->
  Node.t -> Node.t
(** Measure source points from an analytic point, axis, or plane. Typed affected
    groups are promoted once; planar distance may be signed, while masks use
    magnitude and fixed or maximum-distance normalization. *)

val merge : ?label:string -> Node.t list -> Node.t
(* Deterministic packed Fuse 2.0 point snapping/consolidation. A second target
    remains immutable and supplies an independent named target group. Near
    targeting supports least-number or closest targets, radius expansion, and
    scalar match filters; specified targeting reads query point target numbers.
    Position reducers, same-input Modify Target, Keep Fused Points, and
    topology/unused-point cleanup correspond to Pdk.Ops.fuse. Snap-only mode
    preserves topology, while output metadata records mapped queries and
    destinations. *)
val fuse :
  ?label:string ->
  ?group:string ->
  ?target_group:string ->
  ?targeting:Pdk.Ops.fuse_targeting ->
  ?using:Pdk.Ops.fuse_using ->
  ?tolerance:float ->
  ?position:Pdk.Ops.fuse_position ->
  ?weight_attribute:string ->
  ?attributes:Pdk.Ops.fuse_attributes ->
  ?attribute_rules:Pdk.Ops.fuse_attribute_rule list ->
  ?group_rules:Pdk.Ops.fuse_group_rule list ->
  ?metric:Pdk.Ops.fuse_metric ->
  ?inclusive:bool ->
  ?match_attributes:bool ->
  ?radius_attribute:string ->
  ?match_attribute:string ->
  ?match_condition:Pdk.Ops.fuse_match_condition ->
  ?match_tolerance:float ->
  ?modify_target:bool ->
  ?fuse_points:bool ->
  ?keep_fused_points:bool ->
  ?snapped_group:string ->
  ?snapped_destination_attribute:string ->
  ?remove_degenerate_primitives:bool ->
  ?remove_unused_points_from_degenerate_primitives:bool ->
  ?remove_all_unused_points:bool ->
  ?target:Node.t ->
  Node.t -> Node.t
val snap_to_grid :
  ?label:string ->
  ?group:string ->
  ?spacing:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
  ?rounding:Pdk.Ops.grid_rounding ->
  ?max_distance:float ->
  ?fuse_points:bool ->
  ?position:Pdk.Ops.fuse_position ->
  ?weight_attribute:string ->
  ?attributes:Pdk.Ops.fuse_attributes ->
  ?attribute_rules:Pdk.Ops.fuse_attribute_rule list ->
  ?group_rules:Pdk.Ops.fuse_group_rule list ->
  ?snapped_group:string ->
  Node.t -> Node.t
(* Snap a named point group, or every point, to a deterministic axis-aligned
    grid. Optional post-snap fusion uses the same group restriction and packed
    Fuse core, including weighted position reduction. *)
(* Reflect across an arbitrary plane with corrected polygon winding. *)
val mirror :
  ?label:string ->
  ?keep_original:bool ->
  origin:Prismel.Vec3.t ->
  normal:Prismel.Vec3.t ->
  Node.t -> Node.t
val clip :
  ?label:string ->
  ?keep:Pdk.Ops.clip_keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:element_group ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  origin:Prismel.Vec3.t ->
  normal:Prismel.Vec3.t ->
  Node.t -> Node.t
(* Plane clipping/creasing with a canonical or numeric point clip attribute,
    distance offset, typed interpolation, native clipped-edge output, and
    optional manifold caps. *)
val clip_transform :
  ?label:string ->
  ?keep:Pdk.Ops.clip_keep ->
  ?snapping_tolerance:float ->
  ?fill:bool ->
  ?split_connectivity:bool ->
  ?clip_attribute:string ->
  ?distance:float ->
  ?selection:element_group ->
  ?replace_existing_groups:bool ->
  ?clipped_edge_group:string ->
  ?cap_group:string ->
  ?clipped_group:string ->
  ?above_group:string ->
  ?below_group:string ->
  ?local_normal:Prismel.Vec3.t ->
  transform:Prismel.Mat4.t ->
  Node.t -> Node.t
(* Matrix-oriented convenience for [clip], with +Y as the default local
    plane normal. The effective origin and direction participate in the same
    immutable Clip cache identity. *)
val crease :
  ?label:string ->
  ?group:string ->
  ?operation:Pdk.Ops.crease_operation ->
  ?weight:float ->
  ?add_vertex_color:bool ->
  Node.t -> Node.t
(** Add, set, or delete [creaseweight] on a named native edge group, or every
    topology edge when [group] is omitted. The immutable graph node delegates
    unique-edge reduction and packed corner/color fills to PDK; its result can
    feed [subdivide] directly. [weight] is ignored for delete. *)

val attribute_fade :
  ?label:string ->
  ?group:string ->
  ?start_source:Node.t ->
  ?hold_source:Node.t ->
  ?fade_attribute:string ->
  ?start_attribute:string ->
  ?start_retime:(float * float) ->
  ?hold_scale_attribute:string ->
  ?frame_offset:float ->
  ?fade_in:float ->
  ?fade_hold:float ->
  ?fade_out:float ->
  ?fade_in_ramp:(float * float) list ->
  ?fade_out_ramp:(float * float) list ->
  ?visualize:bool ->
  Node.t -> Node.t
(** Frame-dependent scalar point-attribute fade. A missing fade field starts
    at one; optional start and hold-scale fields may come from independent
    equal-point-count graphs. The immutable node declares only the frame fact,
    so bounded sessions reuse a cook across irrelevant time/seed changes while
    invalidating exactly when the frame or any input snapshot changes. *)

val poly_cut :
  ?label:string ->
  ?group:string ->
  ?cut_group:string ->
  ?element:Pdk.Ops.poly_cut_element ->
  ?strategy:Pdk.Ops.poly_cut_strategy ->
  ?detection:Pdk.Ops.poly_cut_detection ->
  ?keep_closed:bool ->
  Node.t -> Node.t
(** Break polygon curves at selected point or native-edge attribute events.
    [group] restricts source primitives; [cut_group] resolves as a point group
    for [Poly_cut_points] and a native edge group for [Poly_cut_edges]. The
    immutable node delegates packed planning, interpolation, ancestry, and
    deterministic parallel fills to {!Pdk.Ops.poly_cut}. *)

val separate_pieces :
  ?label:string ->
  ?owner:Pdk.Attribute.owner ->
  ?translation_attribute:string ->
  ?axis:Prismel.Vec3.t ->
  ?gap:float ->
  ?mode:Pdk.Ops.separate_pieces_mode ->
  piece_attribute:string ->
  Node.t -> Node.t
(** Deterministically separate point- or primitive-identified pieces into
    disjoint intervals along an axis, or restore them from the stored float3
    translation. The immutable node delegates ownership validation, packed
    bounds, reversible position fills, and cancellation to
    {!Pdk.Ops.separate_pieces}. *)

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
val subdivide :
  ?label:string ->
  ?group:string ->
  ?scheme:Pdk.Ops.subdivision_scheme ->
  ?iterations:int ->
  ?cracks:Pdk.Ops.subdivision_crack_policy ->
  ?consistent_topology:bool ->
  ?creases:Node.t ->
  ?crease_group:string ->
  ?crease_weight:float ->
  ?generate_resulting_creases:bool ->
  ?resulting_crease_group:string ->
  ?hole_group:string ->
  ?remove_holes:bool ->
  ?boundary_interpolation:Pdk.Ops.subdivision_boundary_interpolation ->
  ?face_varying_interpolation:Pdk.Ops.subdivision_face_varying_interpolation ->
  ?triangle_policy:Pdk.Ops.subdivision_triangle_policy ->
  ?creasing_method:Pdk.Ops.subdivision_creasing_method ->
  ?treat_curves_as_independent:bool ->
  ?recompute_point_normals:bool ->
  Node.t -> Node.t
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
  Node.t -> Node.t
(* Collapse each connected component of a named native edge group to its
    arithmetic center. An omitted group selects all topology edges. Exact
    point [connectivity_attribute] boundaries partition the components.
    Degenerate cleanup and recomputation of an existing point [N] field are
    enabled by default. *)
val edge_collapse :
  ?label:string ->
  ?group:string ->
  ?connectivity_attribute:string ->
  ?position:Pdk.Ops.fuse_position ->
  ?remove_degenerate_primitives:bool ->
  ?recompute_point_normals:bool ->
  Node.t -> Node.t
(* Remove a named set of polygon edges and merge consistently wound incident
   faces. Non-selected inversion, bridge-loop policy, boundary-to-curve
   output, selected-edge inline cleanup, point compaction, and normal
   recomputation map directly to the packed PDK Dissolve kernel. *)
val dissolve :
  ?label:string ->
  ?group:string ->
  ?operation:Pdk.Ops.dissolve_operation ->
  ?bridge_policy:Pdk.Ops.dissolve_bridge_policy ->
  ?remove_inline_points:bool ->
  ?collinearity_tolerance:float ->
  ?remove_unused_points:bool ->
  ?create_boundary_curves:bool ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(* Cut selected two-sided polygon edges back into their first face ring, emit
   connected fillet strips and close arbitrary manifold junctions. Chamfer or
   rational-circular round profiles, point-scale control, flat-edge exclusion,
   collision limiting, generated face/boundary groups, payload interpolation,
   and existing-normal regeneration map to the packed PDK PolyBevel kernel.
   An omitted group selects all eligible edges. *)
val poly_bevel :
  ?label:string ->
  ?group:string ->
  ?shape:Pdk.Ops.poly_bevel_shape ->
  ?divisions:int ->
  ?point_scale_attribute:string ->
  ?ignore_flat_angle:float ->
  ?clamp_overlap:bool ->
  ?edge_group:string ->
  ?corner_group:string ->
  ?offset_group:string ->
  ?recompute_point_normals:bool ->
  distance:float ->
  Node.t -> Node.t
(* Split selected shared points into unique or attribute-compatible clusters.
    [selection] accepts point, vertex, or primitive groups. A blank attribute
    pattern makes selected corners unique; otherwise the shared Houdini-style
    glob language selects vertex/primitive seam fields and named groups.
    Optional promotion moves matched attributes—not groups—to point ownership
    after topology is separated. *)
val point_split :
  ?label:string ->
  ?selection:element_group ->
  ?attributes:string ->
  ?tolerance:float ->
  ?promote_attributes:bool ->
  Node.t -> Node.t
(* Emit points from selected source points in stable source/local order.
    Per-point mode supports deterministic fractional stochastic rounding and
    an optional point-float count scale; probability mode reads a point float
    in [[0,1]]. Matched point/detail payload, optional input retention,
    generated grouping, and source provenance map directly to the packed PDK
    kernel. Without an explicit seed, the node derives a stable stream from
    context seed and node identity. *)
val point_generate :
  ?label:string ->
  ?group:string ->
  ?keep_input:bool ->
  ?seed:int ->
  ?generated_group:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  mode:Pdk.Ops.point_generate_mode ->
  Node.t -> Node.t
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
  ?seed:int ->
  ?id_attribute:string ->
  ?generated_group:string ->
  ?copy_point_attributes:string ->
  ?keep_source_attributes:bool ->
  ?transform_attributes:string ->
  ?source_point_attribute:string ->
  ?source_index_attribute:string ->
  ?shape:Pdk.Ops.point_replicate_shape ->
  ?custom_shape:Node.t ->
  ?center:Prismel.Vec3.t ->
  ?size:Prismel.Vec3.t ->
  ?orientation:Prismel.Vec3.t ->
  ?uniform_scale:float ->
  ?quasi_stratified:bool ->
  ?velocity_stretch:Pdk.Ops.point_replicate_velocity_stretch ->
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
  Node.t -> Node.t
(* Triangulate between consecutive selected polygon curves or faces. Unequal
   section cardinalities use a deterministic two- or three-distance zipper;
   closest-end alignment can use an equal-point-count rest snapshot. U/V wrap,
   source retention, generated-face grouping, collinearity policy, and existing
   normal regeneration map directly to the packed PDK PolyLoft kernel. *)
val poly_loft :
  ?label:string ->
  ?group:string ->
  ?rest:Node.t ->
  ?connect_closest_ends:bool ->
  ?minimize:Pdk.Ops.poly_loft_minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(* Build a linear polygon skin between consecutive selected curves or faces.
   Equal-cardinality pairs retain quad topology; unequal pairs use the shared
   deterministic PolyLoft zipper. Selection, rest alignment, U/V wrapping,
   source retention, grouping, and normal policy map to the PDK Skin kernel. *)
val skin :
  ?label:string ->
  ?group:string ->
  ?rest:Node.t ->
  ?connect_closest_ends:bool ->
  ?minimize:Pdk.Ops.poly_loft_minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(* Bridge paired simple source and destination edge paths/loops. Components
   pair in authored or centroid-sorted order; equal counts emit quads and
   unequal counts use the shared loft zipper. Reverse, closed-loop shift,
   input-retention, grouping, collinearity, and normal controls map directly
   to PDK. *)
val poly_bridge :
  ?label:string ->
  source_group:string ->
  destination_group:string ->
  ?pairing:Pdk.Ops.poly_bridge_pairing ->
  ?connect_closest_ends:bool ->
  ?minimize:Pdk.Ops.poly_loft_minimize ->
  ?reverse_source:bool ->
  ?reverse_destination:bool ->
  ?pairing_shift:int ->
  ?divisions:int ->
  ?keep_input:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
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
  Node.t -> Node.t
(* Split polygon point fans along the interior vertices of a named native edge
   path. Path endpoints remain shared; an omitted group is a no-op. Point
   payload and groups duplicate exactly, native edge groups retain ancestry,
   and an existing point-normal field is rebuilt by default. *)
val edge_cusp :
  ?label:string ->
  ?group:string ->
  ?update_point_normals:bool ->
  Node.t -> Node.t
(* Project every connected component of a named native edge group onto its
   least-squares best-fit line. An omitted group uses all topology edges;
   [output_group] optionally records the transformed selection. *)
val edge_straighten :
  ?label:string ->
  ?group:string ->
  ?output_group:string ->
  Node.t -> Node.t
(* Fit each simple connected path or loop in a named native edge group to its
   least-squares plane and circle. An omitted group uses topology boundary
   edges; [radius] overrides the best-fit radius, [scale] transforms each
   circle about its fitted center, and [output_group] records the selection. *)
val circle_from_edges :
  ?label:string ->
  ?group:string ->
  ?radius:float ->
  ?scale:Prismel.Vec3.t ->
  ?output_group:string ->
  Node.t -> Node.t
(* Color a point/primitive adjacency graph through the single packed PDK core.
   Typed groups promote to the selected connectivity owner; unselected elements
   receive -1. Stable sorting and optional detail workset ranges use the shared
   Sort remapper and remain exact across domain counts. *)
val graph_color :
  ?label:string ->
  ?selection:element_group ->
  ?connectivity:Pdk.Ops.graph_color_connectivity ->
  ?color_attribute:string ->
  ?sort_output:bool ->
  ?worksets:Pdk.Ops.graph_color_worksets ->
  Node.t -> Node.t
(* Equalize the initial selected edge lengths to their average, longest, or
   shortest value. Connected selections use the deterministic PDK iterative
   projection; [iterations] and relative [tolerance] bound convergence. *)
val edge_equalize :
  ?label:string ->
  ?group:string ->
  ?method_:Pdk.Ops.edge_equalize_method ->
  ?iterations:int ->
  ?tolerance:float ->
  ?output_group:string ->
  Node.t -> Node.t
(* Match source edge lengths to an exactly topology-compatible reference.
   Point/primitive restriction and point pins are resolved on the source.
   Scale-independent mode preserves the source mean while adopting the
   reference length distribution. *)
val edge_relax :
  ?label:string ->
  ?group:element_group ->
  ?pin_group:string ->
  ?iterations:int ->
  ?step_size:float ->
  ?target_mode:Pdk.Ops.edge_relax_target_mode ->
  ?only_shorten:bool ->
  ?tolerance:float ->
  reference:Node.t ->
  Node.t -> Node.t
type blend_shape
val blend_shape :
  ?mask_attribute:string ->
  ?mask_source:Pdk.Ops.blend_shape_mask_source ->
  weight:float ->
  Node.t ->
  blend_shape
(* Blend the first immutable snapshot toward multiple point shapes while
   retaining its topology. Normalized and extrapolating differencing modes,
   source/shape masks, integer/text point-ID matching, point restriction, and
   fixed-width floating point-attribute patterns are immutable node identity. *)
val blend_shapes :
  ?label:string ->
  ?point_group:string ->
  ?mode:Pdk.Ops.blend_shapes_mode ->
  ?masking:Pdk.Ops.blend_shapes_masking ->
  ?mask_attribute:string ->
  ?point_id_attribute:string ->
  ?attributes:string ->
  shapes:blend_shape list ->
  Node.t -> Node.t
type attribute_composite_input
val attribute_composite_input :
  weight:float -> Node.t -> attribute_composite_input
(* Composite fixed-width floating attributes from this additional immutable
   input using its finite global weight. *)
val attribute_composite :
  ?label:string ->
  ?operation:Pdk.Ops.attribute_composite_operation ->
  ?weight:float ->
  ?detail_attributes:string ->
  ?primitive_attributes:string ->
  ?point_attributes:string ->
  ?vertex_attributes:string ->
  ?allow_position:bool ->
  ?alpha_attribute:string ->
  inputs:attribute_composite_input list ->
  Node.t -> Node.t
(* Composite ordered inputs with independent owner patterns and Mean, Max,
   Min, Over, or Under semantics. The graph retains the first input topology;
   all patterns, weights, alpha policy, order, and P eligibility participate
   in immutable cache identity. *)
type attribute_mirror_method =
  | Attribute_mirror_plane of {
      origin : Prismel.Vec3.t;
      normal : Prismel.Vec3.t;
      distance : float;
      tolerance : float;
    }
  | Attribute_mirror_mapping of {
      mapping_attribute : string;
      destination_group : string;
    }
(** Mirror named point, vertex, or primitive attributes from a source side to
    a destination side. Plane mode uses reflected nearest correspondence for
    points and primitive bounding-box centers; mapping mode resolves a named
    integer map and named destination group at cook time. All policies and
    output metadata participate in immutable cache identity. *)
val attribute_mirror :
  ?label:string ->
  ?group:string ->
  ?group_use:Pdk.Ops.attribute_mirror_group_use ->
  ?attributes:string ->
  ?transform:Pdk.Ops.attribute_mirror_transform ->
  ?string_replace:(string * string) ->
  ?output_mapping:string ->
  ?source_group:string ->
  ?destination_group:string ->
  owner:Pdk.Ops.attribute_mirror_owner ->
  method_:attribute_mirror_method ->
  Node.t -> Node.t

(** Reassign polygon/curve corners using a scalar integer point, vertex, or
    primitive attribute. Selection is typed and promoted to the target owner;
    recursive point chains, target deletion, newly-unused cleanup, and original
    corner-point provenance are immutable cache parameters. *)
val rewire_vertices :
  ?label:string ->
  ?selection:element_group ->
  ?recursive:bool ->
  ?delete_target_attribute:bool ->
  ?keep_unused_points:bool ->
  ?original_point_attribute:string ->
  owner:Pdk.Attribute.owner ->
  target_attribute:string ->
  Node.t -> Node.t
(* Transport a scalar point field over the deterministic PDK shortest-path
   edge forest. [root_group] selects explicit multi-source roots; otherwise
   [roots] chooses the first or last point of each selected component. *)
val edge_transport :
  ?label:string ->
  ?point_group:string ->
  ?root_group:string ->
  ?roots:Pdk.Ops.edge_transport_roots ->
  ?direction:Pdk.Ops.edge_transport_direction ->
  ?operation:Pdk.Ops.edge_transport_operation ->
  ?root_value:Pdk.Ops.edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:Pdk.Ops.edge_transport_split ->
  ?merge:Pdk.Ops.edge_transport_merge ->
  ?normalization:Pdk.Ops.edge_transport_normalization ->
  attribute:string ->
  Node.t -> Node.t
(* Transport a scalar point or vertex field independently along selected
    polygon/curve primitives. Open curves orient from the lower-numbered
    endpoint; closed curves use a deterministic lowest-point seam. Independent
    curves cook in parallel, while shared point writes are rejected rather
    than made scheduling-dependent. *)
val edge_transport_curves :
  ?label:string ->
  ?primitive_group:string ->
  ?owner:Pdk.Attribute.owner ->
  ?direction:Pdk.Ops.edge_transport_direction ->
  ?operation:Pdk.Ops.edge_transport_operation ->
  ?root_value:Pdk.Ops.edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?normalization:Pdk.Ops.edge_transport_normalization ->
  attribute:string ->
  Node.t -> Node.t
(* Transport a scalar point field through an integer parent forest without
   requiring topology edges. Forward split and backward branch merge are
   explicit, and independent rooted trees cook in parallel. *)
val edge_transport_parent :
  ?label:string ->
  ?point_group:string ->
  ?parent_attribute:string ->
  ?direction:Pdk.Ops.edge_transport_direction ->
  ?operation:Pdk.Ops.edge_transport_operation ->
  ?root_value:Pdk.Ops.edge_transport_root_value ->
  ?integrate_constant:bool ->
  ?scale_by_edge_length:bool ->
  ?split:Pdk.Ops.edge_transport_split ->
  ?merge:Pdk.Ops.edge_transport_merge ->
  ?normalization:Pdk.Ops.edge_transport_normalization ->
  attribute:string ->
  Node.t -> Node.t
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
   primitive owners. [Pdk.Ops.Copy_target_nothing] cancels an earlier match;
   group arithmetic is intersection, union, and subtraction. *)
val copy_to_points :
  ?label:string -> ?source_group:string -> ?target_group:string ->
  ?piece_attribute:string ->
  ?target_attributes:Pdk.Ops.copy_target_attribute_rule list ->
  source:Node.t -> targets:Node.t -> unit -> Node.t
val duplicate :
  ?label:string -> ?copies:int -> ?cumulative:bool ->
  ?transform:Prismel.Mat4.t -> ?group:string ->
  ?copy_group_prefix:string -> ?preserve_groups:bool -> Node.t -> Node.t
(* Append transformed materialized copies. [group] restricts the copied
    primitives while preserving the full input prefix. A copy-group prefix
    emits one one-based primitive group per appended copy. *)
val pack : ?transforms:Prismel.Mat4.t array -> Node.t -> Instances.t
val duplicate_packed :
  ?copies:int -> ?cumulative:bool -> ?transform:Prismel.Mat4.t ->
  Instances.t -> Instances.t
(* Materialize editable copy-major topology from terminal packed instances.
    Instance transforms are applied by default; disabling transform application
    emits overlapping prototype-space copies. This is the explicit boundary
    required before feeding per-copy topology into later SOPs or an iterative
    sketch step. *)
val unpack : ?label:string -> ?apply_transform:bool -> Instances.t -> Node.t
val switch : ?label:string -> index:int -> Node.t list -> Node.t
val null : ?label:string -> Node.t -> Node.t
(* Deterministically ear-clip all polygon primitives or a named primitive
   group. Unselected polygons and curves pass through with exact payload. *)
val triangulate : ?label:string -> ?group:string -> Node.t -> Node.t
val triangulate_2d :
  ?label:string ->
  ?point_group:string ->
  ?constraint_edge_group:string ->
  ?constraint_primitive_group:string ->
  ?projection:Pdk.Ops.triangulate_2d_projection ->
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
  Node.t -> Node.t
(* Delaunay-triangulate point geometry through the shared exact-predicate PDK
    kernel. The named point group is promoted nowhere: it selects exactly its
    members. Crossing-constraint splitting, bounded quality refinement,
    regularization, projection, original-position restoration, primitive
    retention, seed, payload policy, and output groups participate in immutable
    node identity. Angles are radians. *)
val remesh :
  ?label:string ->
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
  target_length:float ->
  Node.t -> Node.t
(* Isotropically remesh a complete polygon surface through the shared packed
    PDK split/collapse/flip/relax/project kernel. Named hard point and native
    edge groups, point target sizes, UV seams, diagnostic outputs, and input-
    points-only mode are part of the immutable node identity. *)
val boolean :
  ?label:string ->
  ?operation:Pdk.Boolean.operation ->
  ?left_treatment:Pdk.Boolean.treatment ->
  ?right_treatment:Pdk.Boolean.treatment ->
  ?resolve_left_self_intersections:bool ->
  ?resolve_right_self_intersections:bool ->
  ?point_conflict:Pdk.Boolean.point_conflict ->
  ?point_tolerance:float ->
  ?tiny_seam_threshold:float ->
  ?cleanup_max_batches:int ->
  ?strict_cleanup:bool ->
  ?seam_points:Pdk.Boolean.seam_points ->
  ?detriangulation:Pdk.Boolean.detriangulation ->
  ?assume_flat:bool ->
  ?require_closed:bool ->
  ?left_piece_group:string option ->
  ?overlap_piece_group:string option ->
  ?right_piece_group:string option ->
  right:Node.t -> Node.t -> Node.t
(* Exact two-input polygon Boolean SOP. Operand treatment, product/shatter, payload
    conflict, seam-point, detriangulation, self-intersection, flatness, and
    closed-output policies are immutable cache identity. The node delegates
    all geometry work to {!Pdk.Boolean.run}; it does not own another kernel. *)
val boolean_seam :
  ?label:string -> ?output:Pdk.Boolean.seam_output ->
  ?left_treatment:Pdk.Boolean.treatment ->
  ?right_treatment:Pdk.Boolean.treatment ->
  ?resolve_left_self_intersections:bool ->
  ?resolve_right_self_intersections:bool ->
  ?left_self_group:string option -> ?between_group:string option ->
  ?right_self_group:string option -> ?coincident_group:string option ->
  right:Node.t -> Node.t -> Node.t
(* Exact two-input seam/coincident-area product from the same PDK arrangement
   core. Curve-kind and coincident group names are explicit cache identity. *)
(* Detect AxB intersections between source and optional collision polygon
    surfaces, plus AxA self-intersections on the source, while retaining source
    topology and payload. Named primitive groups restrict the inputs. With a
    collision input the default output is [boolean_intersections]; without one,
    the default is [boolean_self_intersections]. Pass explicit [None] group
    options to omit those defaults.

    The optional primitive integer-array [intersections_attribute] contains
    sorted unique collision primitive numbers for every source primitive, and
    [count_attribute] contains the AxB row lengths; the corresponding [self_*]
    controls emit symmetric AxA rows and counts. Ordinary shared-edge/vertex
    topology contacts are not self-intersections. At least one output is required.
    All controls and both graph inputs participate in immutable cache identity;
    the packed BVH and narrow phase are owned by [Pdk.Ops.boolean_detect]. *)
val boolean_detect :
  ?label:string ->
  ?source_group:string ->
  ?collision_group:string ->
  ?tolerance:float ->
  ?include_coplanar:bool ->
  ?intersecting_group:string option ->
  ?intersections_attribute:string ->
  ?count_attribute:string ->
  ?self_intersecting_group:string option ->
  ?self_intersections_attribute:string ->
  ?self_count_attribute:string ->
  ?collision:Node.t ->
  Node.t -> Node.t
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
  ?input_attribute:string option ->
  ?primitive_attribute:string option ->
  ?primitive_uvw_attribute:string option ->
  ?point_attribute:string option ->
  ?collision:Node.t ->
  Node.t -> Node.t
(* Deterministic adaptive quadric-error polygon reduction. Named hard point
   and native-edge groups are exact constraints; preserving unshared
   boundaries is enabled by default. A primitive group restricts reduction
   and locks its interface. Constraints may stop above the requested target. *)
val poly_reduce :
  ?label:string ->
  ?group:string ->
  ?hard_point_group:string ->
  ?hard_edge_group:string ->
  ?target:Pdk.Ops.poly_reduce_target ->
  ?preserve_boundary:bool ->
  ?only_original_positions:bool ->
  ?equalize_lengths:float ->
  ?max_normal_deviation:float ->
  ?output_group:string ->
  ?recompute_point_normals:bool ->
  Node.t -> Node.t
(* Reverse or cyclically shift corners of every primitive or of a named
    primitive group. Signed shift offsets wrap independently per primitive;
    all vertex fields/groups follow the corner permutation. *)
val reverse :
  ?label:string ->
  ?group:string ->
  ?operation:Pdk.Ops.reverse_operation ->
  Node.t -> Node.t
(* Compute point, vertex, primitive, or detail normals through the packed PDK
   kernel. Typed selections are promoted to the requested output owner;
   [cusp_angle] is in radians and only affects vertex normals. *)
val normals :
  ?label:string ->
  ?selection:element_group ->
  ?owner:Pdk.Attribute.owner ->
  ?weighting:Pdk.Ops.normal_weighting ->
  ?cusp_angle:float ->
  ?keep_original_zero:bool ->
  ?reverse:bool ->
  ?attribute:string ->
  Node.t -> Node.t

val measure_curvature :
  ?label:string ->
  ?point_group:string ->
  ?boundary:Pdk.Ops.curvature_boundary ->
  ?smoothing_iterations:int ->
  ?smoothing_strength:float ->
  ?outputs:Pdk.Ops.curvature_outputs ->
  Node.t -> Node.t
(* Estimate signed mean, Gaussian, principal, curvedness, and shape-index
   point fields through the shared packed PDK curvature kernel. The default
   writes signed mean curvature to [curvature]. A point group limits output
   replacement while metric estimation remains topology-complete. *)
val polyframe :
  ?label:string -> ?selection:element_group -> ?orthogonal:bool ->
  ?left_handed:bool -> ?normal_attribute:string ->
  ?tangent_attribute:string option ->
  ?bitangent_attribute:string option -> Pdk.Ops.polyframe_style ->
  Node.t -> Node.t
(* Generate point or vertex coordinate-frame fields with deterministic packed
   PDK kernels. First-edge, two-edge, centroid, and texture-UV styles produce
   point fields; texture-UV-gradient and attribute-gradient produce
   seam-preserving vertex fields. Empty texture names resolve to [uv].
   Passing [None] disables tangent or bitangent output. Orthogonal frames are
   right-handed unless [left_handed] is enabled. *)
(* Smooth point positions and matching point-owned floating attributes without
    changing topology. [group] is a primitive group; [constrained_points]
    names an additional point group to lock. Boundary policy, packed weighting,
    alternating low-pass steps, and normal handling delegate to the shared PDK
    Smooth/Attribute Blur kernel. *)
val smooth :
  ?label:string ->
  ?group:string ->
  ?constrained_points:string ->
  ?boundary:Pdk.Ops.smooth_boundary ->
  ?iterations:int ->
  ?method_:Pdk.Attribute_ops.blur_method ->
  ?mode:Pdk.Attribute_ops.blur_mode ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?recompute_normals:bool ->
  ?original_blend:float ->
  ?smoothed_blend:float ->
  attributes:string ->
  Node.t -> Node.t
val ray :
  ?label:string ->
  ?selection:element_group ->
  ?collision_group:string ->
  ?method_:Pdk.Ops.ray_method ->
  ?direction:Pdk.Ops.ray_direction ->
  ?direction_mode:Pdk.Ops.ray_direction_mode ->
  ?surface_hit:Pdk.Ops.ray_surface_hit ->
  ?samples:int ->
  ?jitter_scale:float ->
  ?seed:int ->
  ?combine:Pdk.Ops.ray_combine ->
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
  collision:Node.t ->
  Node.t -> Node.t
(* Project source points onto collision polygons using closest-distance or
    directional BVH queries. Bounded deterministic multi-ray jitter and its
    average/median/shortest/longest combiner are part of immutable node
    identity. The source remains the pipe-friendly final argument. *)
val peak :
  ?label:string ->
  ?selection:element_group ->
  ?direction_attribute:string ->
  ?normalize_direction:bool ->
  ?mask_attribute:string ->
  distance:float ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(** Move selected point/vertex/primitive/edge components along resolved normals
    or a custom point direction. The group name is resolved at cook time and
    remains part of the inspectable cache identity. *)

val bend :
  ?label:string ->
  ?selection:element_group ->
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
  Node.t -> Node.t
(** Captured arc-length-preserving bend and axial twist in an arbitrary frame.
    Angles are radians. Typed point/vertex/primitive/edge selections resolve at
    cook time; an optional point float mask scales deformation in [[0,1]]. *)

val mountain :
  ?label:string ->
  ?group:string ->
  ?seed:int ->
  ?direction_attribute:string ->
  ?normalize_direction:bool ->
  ?mask_attribute:string ->
  height:float ->
  ?frequency:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
  ?octaves:int ->
  ?lacunarity:float ->
  ?roughness:float ->
  ?height_attribute:string ->
  ?recompute_normals:bool ->
  Node.t -> Node.t
(** Deterministic Perlin-fBm normal displacement. Without an explicit seed,
    the node derives a stable stream from context seed and node identity. *)

val point_jitter :
  ?label:string ->
  ?group:string ->
  ?mask_attribute:string ->
  ?id_attribute:string ->
  ?seed:int ->
  ?scale:float ->
  ?axis_scales:Prismel.Vec3.t ->
  ?use_point_scale:bool ->
  Node.t -> Node.t
(** Add deterministic component-wise uniform offsets to points. [group] limits
    the affected points, [mask_attribute] blends the displacement, and
    [id_attribute] supplies stable integer identities when point numbering may
    change. [use_point_scale] multiplies the offset by point float [pscale].
    Without an explicit seed, the node derives a stable stream from context
    seed and node identity. *)

val clean :
  ?label:string ->
  ?epsilon:float ->
  ?remove_degenerate:bool ->
  ?consolidate_distance:float ->
  ?overlaps:Pdk.Ops.clean_overlap_policy ->
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
  Node.t -> Node.t
val facet :
  ?label:string ->
  ?group:string ->
  ?selection:element_group ->
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
  Node.t -> Node.t
(* Ordered Facet pipeline, optionally restricted to a typed named point,
    vertex, primitive, or native-edge selection. [group] remains the primitive
    selection convenience. Point/vertex/edge selections promote to every
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
  ?divide:Pdk.Ops.poly_extrude_divide ->
  ?divisions:int ->
  ?output_front:bool ->
  ?output_back:bool ->
  ?output_side:bool ->
  ?front_group:string ->
  ?back_group:string ->
  ?side_group:string ->
  ?front_boundary_group:string ->
  ?back_boundary_group:string ->
  distance:float -> Node.t -> Node.t
(* Fill all manifold polygon boundary loops, or auto-complete only loops
    touched by a named native edge group. Supports a single polygon,
    deterministic concave-safe triangles, or an averaged triangle fan;
    shared/unique boundary points, patch winding, point-normal refresh, and a
    generated primitive group are immutable cook parameters. *)
val poly_fill :
  ?label:string ->
  ?boundary_group:string ->
  ?mode:Pdk.Ops.poly_fill_mode ->
  ?reverse_patches:bool ->
  ?unique_points:bool ->
  ?update_point_normals:bool ->
  ?patch_group:string ->
  Node.t -> Node.t
val resample :
  ?label:string -> ?group:string -> ?segments:int ->
  ?maximum_segment_length:float -> ?segment_length_attribute:string ->
  ?segments_attribute:string -> ?even_last_segment:bool -> ?curve_u_attribute:string ->
  ?curve_number_attribute:string -> ?distance_attribute:string ->
  ?tangent_attribute:string -> Node.t -> Node.t
(* Arc-length curve Resample. A segment count, maximum segment length, or both
    may be supplied. Optional generated point fields expose input polygon U,
    source curve number, output-point coverage distance, and curve tangent. *)
type extract_point_cut =
  | Extract_point_constant of float
  | Extract_point_primitive_attribute of string
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
  ?cut:extract_point_cut ->
  ?point_attributes:string ->
  ?copy_primitive_attributes:bool ->
  ?primitive_attributes:string ->
  ?curve_u_attribute:string ->
  ?number_cuts_attribute:string ->
  ?curve_number_attribute:string ->
  distance_attribute:string ->
  Node.t -> Node.t
(* Convert unique topology edges to canonical two-point curves. [group]
   names an optional native edge group. [connect_path] emits maximal paths and
   enables the endpoint-distance and isolated-loop controls. *)
val convert_line :
  ?label:string -> ?group:string -> ?connect_path:bool ->
  ?maximum_distance:float -> ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool -> ?remove_unused_points:bool ->
  ?length_attribute:string -> Node.t -> Node.t
(* Carve selected polygon curves to a normalized interval. [group] names an
   optional primitive group; unselected primitives pass through exactly.
   Primitive float endpoint attributes replace or scale constants. Breakpoint
   mode snaps inward to source vertices and can split/extract every retained
   vertex boundary. Outside breakpoint mode, positive [divisions] splits a Cut
   interval into equal ordered pieces or controls the inclusive Extract sample
   count. *)
val carve :
  ?label:string -> ?group:string -> ?relative_arc_length:bool -> ?first:float ->
  ?last:float -> ?first_attribute:string -> ?last_attribute:string ->
  ?attribute_mode:Pdk.Ops.carve_attribute_mode ->
  ?only_at_breakpoints:bool -> ?cut_at_all_internal_breakpoints:bool ->
  ?keep:Pdk.Ops.carve_keep -> ?extract_points:bool -> ?divisions:int ->
  ?keep_original:bool -> Node.t -> Node.t
val curve_ends :
  ?label:string -> ?group:string -> Pdk.Ops.curve_end_mode -> Node.t -> Node.t
val ends :
  ?label:string -> ?group:string -> Pdk.Ops.ends_mode -> Node.t -> Node.t
(* Open, close straight, or unroll selected polygon faces and polygon curves.
    Shared unroll repeats the first point reference; new-point unroll duplicates
    the complete seam point payload. [curve_ends] remains the curve-only
    compatibility API. *)
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
  ?label:string -> ?group:string -> ?picked_ends:Pdk.Ops.curve_join_pick array ->
  ?orient_closest:bool ->
  ?connect_closest_ends:bool -> ?only_connected:bool -> ?group_size:int ->
  ?keep_originals:bool -> ?tolerance:float -> ?wrap:bool -> Node.t -> Node.t
val poly_path :
  ?label:string -> ?connect_end_points:bool -> ?maximum_distance:float ->
  ?connect_only_to_other_end_points:bool ->
  ?make_isolated_loops_closed:bool -> Node.t -> Node.t
(* Clean unique topology edges into maximal polygon paths. Optional spatial
   endpoint rewiring and isolated-loop closing mirror Houdini PolyPath's
   topology controls. *)
val revolve :
  ?label:string ->
  ?group:string ->
  ?revolve_type:Pdk.Ops.revolve_type ->
  ?connectivity:Pdk.Ops.grid_connectivity ->
  ?start_angle:float ->
  ?end_angle:float ->
  ?reverse_cross_sections:bool ->
  ?caps:bool ->
  ?cap_group:string ->
  ?uv_attribute:string option ->
  divisions:int ->
  origin:Prismel.Vec3.t ->
  axis:Prismel.Vec3.t ->
  Node.t ->
  Node.t
(* Cached polygon-curve Revolve node backed by [Pdk.Ops.revolve]. *)
val sweep :
  ?label:string ->
  ?backbone_group:string ->
  ?cross_section_group:string ->
  ?connectivity:Pdk.Ops.grid_connectivity ->
  ?tangent:Pdk.Ops.sweep_tangent ->
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
  backbone:Node.t ->
  cross_section:Node.t ->
  unit ->
  Node.t
(* Cached two-input general-profile Sweep backed by [Pdk.Ops.sweep]. Both
    optional group names select primitive curves on their corresponding input.
    Cross-section payload is namespaced by default so both input ancestries
    remain inspectable. *)
val sweep_circle :
  ?label:string -> ?group:string -> ?sides:int -> ?divisions_attribute:string ->
  ?segments:int -> ?segments_attribute:string ->
  ?segment_scales:(float * float) -> ?segment_scales_attribute:string ->
  ?prevent_joint_buckling:bool -> ?maximum_joint_scale:float ->
  ?maximum_joint_scale_attribute:string ->
  ?smooth_point:bool -> ?smooth_attribute:string -> ?max_valence:int ->
  ?scale_attribute:string -> ?seam_offset:int ->
  ?seam_attribute:string -> ?segment_seam_attribute:string ->
  ?v_attribute:string -> ?up_attribute:string ->
  ?generate_uv:bool -> ?u_range:(float * float) -> ?v_range:(float * float) ->
  ?uv_range_attribute:string -> ?caps:bool -> ?cap_group:string ->
  radius:float -> Node.t -> Node.t
val polywire :
  ?label:string -> ?group:string -> ?sides:int -> ?divisions_attribute:string ->
  ?segments:int -> ?segments_attribute:string ->
  ?segment_scales:(float * float) -> ?segment_scales_attribute:string ->
  ?prevent_joint_buckling:bool -> ?maximum_joint_scale:float ->
  ?maximum_joint_scale_attribute:string ->
  ?smooth_point:bool -> ?smooth_attribute:string -> ?max_valence:int ->
  ?scale_attribute:string -> ?seam_offset:int ->
  ?seam_attribute:string -> ?segment_seam_attribute:string ->
  ?v_attribute:string -> ?up_attribute:string ->
  ?generate_uv:bool -> ?u_range:(float * float) -> ?v_range:(float * float) ->
  ?uv_range_attribute:string -> ?caps:bool -> ?cap_group:string ->
  radius:float -> Node.t -> Node.t
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
val uv_project :
  ?label:string ->
  ?name:string ->
  ?group:string ->
  ?u_range:float * float ->
  ?v_range:float * float ->
  ?fix_seams:bool ->
  ?fix_poles:bool ->
  Pdk.Ops.uv_projection ->
  Node.t -> Node.t
(* Project seam-safe vertex UVs. [group] names an optional primitive group. *)
val uv_transform :
  ?label:string ->
  ?name:string ->
  ?owner:Pdk.Attribute.owner ->
  ?group:string ->
  ?translate:Prismel.Vec2.t ->
  ?scale:Prismel.Vec2.t ->
  ?angle:float ->
  ?pivot:Prismel.Vec2.t ->
  Node.t -> Node.t
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
  Node.t -> Node.t
(* Detect angle, boundary, non-manifold, partition, and existing-UV cuts.
   [name] identifies the native edge output and compatibility outgoing-corner
   vertex group; [group] restricts selected primitives. *)
val group_edges :
  ?label:string ->
  ?name:string ->
  ?group:string ->
  ?incidence:Pdk.Ops.edge_incidence ->
  ?min_length:float ->
  ?max_length:float ->
  ?angle_basis:Pdk.Ops.edge_angle_basis ->
  ?min_angle:float ->
  ?max_angle:float ->
  Node.t -> Node.t
(* Create a native topology-affine edge group using conjunctive incidence,
   length, angle, and optional primitive-group filters. Angles use primitive
   dihedrals by default or pairwise incident-edge directions. *)
(* Create a point, primitive, or native-edge group from point, vertex, or
    primitive attribute discontinuities. Numeric values use [tolerance];
    integer and text values compare exactly. Optional unshared topology and
    point-sharing primitive expansion follow the PDK boundary contract. *)
val group_from_attribute_boundary :
  ?label:string ->
  ?attributes:Pdk.Ops.group_boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Node.t -> Node.t
(* Create bounded, stable point or primitive groups from distinct non-empty
    values of a text attribute. Dense output is rejected before allocation
    when either configured limit would be exceeded. *)
val groups_from_name :
  ?label:string ->
  ?prefix:string ->
  ?conflict:Pdk.Ops.group_name_conflict ->
  ?invalid_names:Pdk.Ops.invalid_group_name_policy ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  owner:Pdk.Attribute.owner ->
  attribute:string ->
  Node.t -> Node.t
(* Convert stable same-owner group names back to a point, vertex, or primitive
   text attribute. This is the memory-efficient inverse for partition-style
   workflows, especially with [delete_groups=true]. *)
val name_from_groups :
  ?label:string ->
  ?attribute:string ->
  ?pattern:string ->
  ?default:string ->
  ?overlap:Pdk.Ops.group_name_overlap ->
  ?delete_groups:bool ->
  owner:Pdk.Attribute.owner ->
  Node.t -> Node.t
val uv_unitize :
  ?label:string ->
  ?name:string ->
  ?group:string ->
  ?seams:string ->
  ?tolerance:float ->
  ?uniform:bool ->
  Pdk.Ops.uv_unitize_mode ->
  Node.t -> Node.t
(* Fit each selected face or UV island into the unit square. [seams] names
   a native edge group; outgoing-edge vertex groups remain accepted for
   compatibility. *)
val uv_flatten :
  ?label:string -> ?name:string -> ?seams:string -> ?iterations:int ->
  ?tolerance:float -> Node.t -> Node.t
(* Flatten seam-delimited manifold triangle disk islands with deterministic
   positive mean-value harmonic coordinates. *)
val uv_relax :
  ?label:string -> ?name:string -> ?seams:string -> ?uv_tolerance:float ->
  ?iterations:int -> ?tolerance:float -> Node.t -> Node.t
(* Relax UV interiors while preserving existing island boundaries. *)
val measure :
  ?label:string ->
  ?group:string ->
  ?accumulation:Pdk.Analysis.accumulation ->
  ?name:string ->
  ?total_name:string ->
  Pdk.Analysis.measure -> Node.t -> Node.t
(* Measure polygon area, polygon/curve perimeter, or oriented polygon volume
   contribution into primitive attributes, optionally restricted, accumulated
   throughout, and/or accompanied by one detail total. *)
val measure_area : ?label:string -> ?name:string -> Node.t -> Node.t
(* Compatibility shorthand for [measure Pdk.Analysis.Area]. *)
val connectivity :
  ?label:string ->
  ?primitive_group:string ->
  ?point_group:string ->
  ?seam_group:string ->
  ?uv_attribute:string ->
  ?owner:Pdk.Analysis.connectivity_owner ->
  ?name:string ->
  ?attribute:Pdk.Analysis.connectivity_attribute ->
  Node.t -> Node.t
(* Add stable point or primitive connected-component IDs, [class] by default.
   Include groups exclude elements and topology outside their membership.
   Primitive connectivity may be cut by a native edge seam group or split at
   exact vertex float2/float3 UV discontinuities. Output may be integer IDs or
   prefixed text labels. *)
val set_float :
  ?label:string -> owner:Pdk.Attribute.owner -> name:string -> float ->
  Node.t -> Node.t
val set_int :
  ?label:string -> owner:Pdk.Attribute.owner -> name:string -> int ->
  Node.t -> Node.t
val set_vector :
  ?label:string -> owner:Pdk.Attribute.owner -> name:string -> Prismel.Vec3.t ->
  Node.t -> Node.t
val set_orient : ?label:string -> Prismel.Quat.t -> Node.t -> Node.t
(* Install a constant point [transform] matrix for Copy to Points. The matrix
   must be finite and affine. *)
val set_transform : ?label:string -> Prismel.Mat4.t -> Node.t -> Node.t
val set_color :
  ?label:string -> owner:Pdk.Attribute.owner -> Prismel.Color.t ->
  Node.t -> Node.t
val delete_attribute :
  ?label:string -> owner:Pdk.Attribute.owner -> name:string -> Node.t -> Node.t
val rename_attribute :
  ?label:string -> owner:Pdk.Attribute.owner -> from:string -> into:string ->
  Node.t -> Node.t
(* Delete or keep ordinary attributes with owner-specific compiled patterns.
    Optional reference geometry prepends its attribute names to each owner
    selection, matching Attribute Delete SOP reference semantics. *)
val delete_attributes :
  ?label:string ->
  ?reference:Node.t ->
  ?delete_non_selected:bool ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  Node.t -> Node.t
(* Apply sequential capture-pattern attribute renames with explicit
    skip/error/overwrite conflict behavior. *)
val rename_attributes :
  ?label:string ->
  rules:Pdk.Attribute_ops.rename_rule list ->
  Node.t -> Node.t
(* Apply ordered owner-specific Attribute Swap rules. Copy, move, and swap
   preserve packed payload sharing; paired wildcard captures are supported.
   Canonical point [P] participates as float3, and moving [P] becomes Copy. *)
val swap_attributes :
  ?label:string ->
  rules:Pdk.Attribute_ops.swap_rule list ->
  Node.t -> Node.t

val rest_position :
  ?label:string ->
  ?reference:Node.t ->
  ?rest_attribute:string ->
  ?normals:Pdk.Motion.rest_normals ->
  ?normal_attribute:string ->
  ?rest_normal_attribute:string ->
  Pdk.Motion.rest_mode ->
  Node.t -> Node.t
(* Store, extract, or swap rest position and optional point-normal planes.
    The optional reference is an explicit immutable graph input. *)

val point_velocity :
  ?label:string ->
  ?group:string ->
  ?previous:Node.t ->
  ?next:Node.t ->
  ?approximation:Pdk.Motion.velocity_approximation ->
  ?dt:float ->
  ?initialization:Pdk.Motion.velocity_initialization ->
  ?match_attribute:string ->
  ?unmatched:Pdk.Motion.velocity_unmatched ->
  ?velocity_attribute:string ->
  ?add_velocity:Prismel.Vec3.t ->
  ?compute_acceleration:bool ->
  ?acceleration_attribute:string ->
  Node.t -> Node.t
(* Derive or initialize point velocity through the shared PDK kernel. Motion
    samples are explicit graph inputs, so iterative sketches pass
    [Sop.snapshot previous_geometry] without creating a cycle or hidden
    retained history. *)
val promote_attribute :
  ?label:string ->
  ?into:string ->
  ?method_:Pdk.Attribute_ops.method_ ->
  ?delete_source:bool ->
  ?piece_attribute:string ->
  ?index_attribute:string ->
  source:Pdk.Attribute.owner ->
  destination:Pdk.Attribute.owner ->
  name:string ->
  Node.t -> Node.t
(* Promote/reduce an attribute through packed point/vertex/primitive incidence.
   An integer/text destination [piece_attribute] reduces the unique ordered
   source elements corresponding to every partition independently.
   [index_attribute] records the stable contributing source element for
   first/last/minimum/maximum/mode reductions; tuple values emit fixed-width
   packed integer CSR index rows. String/index reductions follow Houdini's
   median/concatenation/first fallback policy. [Array_all] and
   [Unique_values] emit packed integer/float CSR rows for scalar sources. *)
val promote_attributes :
  ?label:string ->
  ?method_:Pdk.Attribute_ops.method_ ->
  ?delete_source:bool ->
  ?piece_attribute:string ->
  ?into_pattern:string ->
  ?index_pattern:string ->
  source:Pdk.Attribute.owner ->
  destination:Pdk.Attribute.owner ->
  pattern:string ->
  Node.t -> Node.t
(* Promote stable source-order attributes selected by a Houdini-style glob.
   One topology/piece plan is shared by every payload. [into_pattern] performs
   aligned multi-term capture renaming and [index_pattern] names per-value
   contributing-source integer attributes with the same aligned rules. Packed array methods
   require every selected source to use supported scalar integer/float
   storage; failure remains atomic. *)
(* Assign a stable dense sequence within an optional typed group. A same-owner
   integer/text [piece_attribute] can restart numbering within each piece or
   assign one dense number per piece in first-selected-occurrence order. *)
val enumerate :
  ?label:string ->
  ?group:string ->
  ?start:int ->
  ?step:int ->
  ?storage:Pdk.Attribute_ops.enumeration_storage ->
  ?piece_attribute:string ->
  ?mode:Pdk.Attribute_ops.enumeration_mode ->
  owner:Pdk.Attribute.owner ->
  name:string ->
  Node.t -> Node.t
val attribute_blur :
  ?label:string ->
  ?group:string ->
  ?iterations:int ->
  ?method_:Pdk.Attribute_ops.blur_method ->
  ?mode:Pdk.Attribute_ops.blur_mode ->
  ?weight_attribute:string ->
  ?alpha_attribute:string ->
  ?pin_borders:bool ->
  ?original_blend:float ->
  ?blurred_blend:float ->
  attributes:string ->
  Node.t -> Node.t
(** Blur canonical [P] and matching floating point attributes over shared-edge
    point connectivity using the packed deterministic Attribute Blur kernel. *)

val attribute_randomize :
  ?label:string ->
  ?group:string ->
  ?selection:element_group ->
  ?seed:int ->
  ?seed_attribute:string ->
  ?fraction_attribute:string ->
  ?minimum:Pdk.Attribute_ops.numeric_value ->
  ?maximum:Pdk.Attribute_ops.numeric_value ->
  ?direction_bias:float ->
  ?operation:Pdk.Attribute_ops.random_operation ->
  ?scale:float ->
  owner:Pdk.Attribute.owner ->
  name:string ->
  Pdk.Attribute_ops.random_distribution ->
  Node.t -> Node.t
(** Create or modify a floating attribute with indexed deterministic random
    samples, or create/modify weighted-discrete text with Set Value. [group]
    retains the owner-matched shorthand; [selection] accepts a typed point,
    vertex, primitive, or native-edge group and expands incident membership to
    the attribute owner. [minimum]/[maximum] limit numeric distribution tails
    before Global Scale and the operation. Without [seed], the node derives a stable stream from the cook
    context and declares that dependency; an explicit label stabilizes the
    stream identity across unrelated graph construction edits. A
    [fraction_attribute] instead supplies deterministic quantiles, makes the
    node independent of context seed, and excludes both seed controls. *)

val attribute_remap :
  ?label:string ->
  ?group:string ->
  ?into:string ->
  ?policy:Pdk.Attribute_ops.remap_policy ->
  ?ramp:(float * float) list ->
  owner:Pdk.Attribute.owner ->
  name:string ->
  input:Pdk.Attribute_ops.remap_input ->
  output_min:Pdk.Attribute_ops.numeric_value ->
  output_max:Pdk.Attribute_ops.numeric_value ->
  Node.t -> Node.t
(** Remap scalar/tuple floating attributes component-wise through explicit or
    selected-data ranges. The optional ramp is immutable node data and forms
    part of the cache identity. *)

val attribute_copy :
  ?label:string ->
  ?match_:Pdk.Attribute_ops.copy_match ->
  ?allow_position:bool ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  group_owner:Pdk.Group.owner ->
  rules:Pdk.Attribute_ops.copy_rule list ->
  source:Node.t ->
  target:Node.t ->
  unit -> Node.t
(* Direct ordered/cyclic or attribute-matched copying between equal-class
   source and destination group selections. Attribute rules may target any
   owner independently of the group owner; topology projections are shared by
   all fields of an owner. Exact group names and compiled group-pattern unions
   are mutually exclusive per input. *)

val attribute_combine :
  ?label:string ->
  ?group:string ->
  ?group_pattern:string ->
  ?match_attribute:string ->
  ?create_missing:bool ->
  ?create_missing_as_scalar:bool ->
  ?delete_sources:bool ->
  ?error_on_missing:bool ->
  ?overall_scale:float ->
  ?threshold:float ->
  ?minimum:float ->
  ?maximum:float ->
  owner:Pdk.Attribute.owner ->
  destination:string ->
  layers:Pdk.Attribute_ops.combine_layer list ->
  ?sources:Node.t list ->
  target:Node.t ->
  unit -> Node.t
(** Fuse ordered numeric attribute layers into one destination. Input zero is
    [target]; entries in [sources] are numbered from one by each layer's source
    and blend input fields. Exact groups and compiled group-pattern unions are
    mutually exclusive. Cross-input matching, tuple conversion, preprocessing,
    blending, postprocessing, destination creation, cleanup, and deterministic
    parallel semantics follow {!Pdk.Attribute_ops.combine}. *)

val attribute_interpolate :
  ?label:string ->
  ?group:string ->
  ?group_pattern:string ->
  ?driver:Pdk.Attribute_ops.interpolate_driver ->
  ?compute_weights:Pdk.Attribute_ops.interpolate_computed ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?primitive_attribute:string ->
  ?uvw_attribute:string ->
  ?pre_scale:float ->
  ?normalize_weights:bool ->
  ?threshold:float ->
  ?blend:float ->
  ?unmatched:Pdk.Attribute_ops.unmatched ->
  target_owner:Pdk.Attribute.owner ->
  attributes:Pdk.Attribute_ops.interpolate_attribute list ->
  source:Node.t ->
  target:Node.t ->
  unit -> Node.t
(** Interpolate mixed-owner source fields at primitive-number/UVW coordinates
    or explicit packed point/vertex/primitive number-and-weight rows stored on
    destination elements. Exact groups and compiled group-pattern
    unions are mutually exclusive. Polygon and curve parameterization,
    signed-sum normalization, inclusive group thresholding, discrete selection,
    opaque packed array-row transfer, normal handling, miss policy, fused
    parallel traversal, and atomic output behavior follow
    {!Pdk.Attribute_ops.interpolate}. *)

val attribute_transfer :
  ?label:string ->
  ?owner:Pdk.Attribute.owner ->
  ?names:string list ->
  ?pattern:string ->
  ?mode:Pdk.Attribute_ops.transfer_mode ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:Pdk.Attribute_ops.transfer_falloff ->
  ?unmatched:Pdk.Attribute_ops.unmatched ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?source_vertex_group:string ->
  ?source_vertex_group_pattern:string ->
  ?source_vertex_selection:Pdk.Attribute_ops.surface_vertex_selection ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  source:Node.t ->
  target:Node.t ->
  unit -> Node.t
(* Transfer same-owner source attributes onto target elements. [names] selects
   exact names; [pattern] selects stable Houdini-style include/exclude globs
   and is mutually exclusive with [names]. Points use
   point proximity, primitives use arithmetic-barycenter proximity, vertices
   use closest-polygon barycentric interpolation, and detail attributes are
   structurally shared. Point and primitive modes include nearest,
   inverse-distance, and the exact published Links/RenderMan/Hart compact
   kernels with independent maximum sample count and radius. For vertex
   transfer, [source_group] selects source
   primitives and [source_vertex_group] can further retain triangulated source
   regions whose corners satisfy [source_vertex_selection]. Other spatial
   groups match the attribute owner. Exact group names and group patterns are
   mutually exclusive per input; a pattern unions every same-owner matching
   packed group in one pass. Point/primitive/vertex distance bands support the
   same falloff controls. Inputs cook in source/target order. *)
val attribute_transfer_surface :
  ?label:string ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:Pdk.Attribute_ops.surface_falloff ->
  ?unmatched:Pdk.Attribute_ops.unmatched ->
  ?target_owner:Pdk.Attribute.owner ->
  ?distance_attribute:string ->
  ?source_group:string ->
  ?source_group_pattern:string ->
  ?source_vertex_group:string ->
  ?source_vertex_group_pattern:string ->
  ?source_vertex_selection:Pdk.Attribute_ops.surface_vertex_selection ->
  ?target_group:string ->
  ?target_group_pattern:string ->
  attributes:Pdk.Attribute_ops.surface_attribute list ->
  source:Node.t -> target:Node.t -> unit -> Node.t
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
  ?mode:Pdk.Attribute_ops.transfer_mode ->
  ?max_distance:float ->
  ?blend_width:float ->
  ?falloff:Pdk.Attribute_ops.transfer_falloff ->
  ?unmatched:Pdk.Attribute_ops.unmatched ->
  source:Node.t -> target:Node.t -> unit -> Node.t
(* Transfer explicitly requested attribute patterns for multiple owners in
    one graph node. At least one owner pattern is required. Each owner shares
    one spatial plan across all of its matching attributes; owner kernels are
    sequenced to avoid nested parallel-pool oversubscription. *)
val rename_group :
  ?label:string -> owner:Pdk.Group.owner -> from:string -> into:string ->
  Node.t -> Node.t
val delete_edge_group : ?label:string -> name:string -> Node.t -> Node.t
val rename_edge_group :
  ?label:string -> from:string -> into:string -> Node.t -> Node.t
val group : ?label:string -> name:string -> 'owner Select.t -> Node.t -> Node.t
(** Materialize a typed selection as a named packed group. *)

val group_random :
  ?label:string ->
  ?seed:int ->
  ?seed_attribute:string ->
  ?base:string ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  probability:float ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Node.t -> Node.t
(** Deterministic random point, vertex, primitive, or native-edge grouping.
    Without [seed], a stable node identity is mixed with the procedural context
    seed; explicit seeds make the node context-independent. *)

val group_bounds :
  ?label:string ->
  ?base:string ->
  ?containment:Pdk.Ops.group_containment ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  Pdk.Ops.group_bounds ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Node.t -> Node.t
(** Inclusive box/sphere grouping for all four topology owners. Partial native
    edges use geometric segment intersection, not endpoint approximation. *)

val group_normal :
  ?label:string ->
  ?normal_attribute:string ->
  ?use_existing_normal:bool ->
  ?base:string ->
  ?include_opposite:bool ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  direction:Prismel.Vec3.t ->
  spread_angle:float ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Node.t -> Node.t
(** Deterministic packed grouping by geometric or owner-matched float3
    normals. Supports point, primitive, and native-edge groups; vertex groups
    are intentionally unsupported, matching Group Create. Existing point [N]
    is reused by default for point/edge owners. Angles are radians. *)

val group_non_planar :
  ?label:string ->
  ?base:string ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  tolerance:float ->
  name:string ->
  Node.t -> Node.t
(** Select non-planar polygon primitives using an absolute world-space
    tolerance. Use union merge when composing it as Group Create's additive
    non-planarity plane. *)

val group_backface :
  ?label:string ->
  ?base:string ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  viewpoint:Prismel.Vec3.t ->
  name:string ->
  Node.t -> Node.t
(** Select winding-derived primitive backfaces relative to a finite viewpoint.
    Subtract merge removes backfaces from an existing same-name group. *)

val group_edge_depth :
  ?label:string ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  depth:int ->
  point_group:string ->
  name:string ->
  Node.t -> Node.t
(** Grow a seed point group by bounded shortest topology-edge distance. *)

val group_unshared :
  ?label:string ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Node.t -> Node.t
(** Select points, primitives, or native edges incident to unshared topology. *)

val group_boundary_components :
  ?label:string ->
  ?prefix:string ->
  ?conflict:Pdk.Ops.group_name_conflict ->
  ?max_groups:int ->
  ?max_payload_bytes:int ->
  Node.t -> Node.t
(** Create stable point groups for connected polygon boundary components. *)

val ordered_group :
  ?label:string -> owner:Pdk.Group.owner -> name:string -> int array ->
  Node.t -> Node.t
(** Materialize unique element indices in their supplied traversal order.
    The source array is copied when the node is constructed. *)

val group_promote :
  ?label:string ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?mode:Pdk.Ops.group_promote_mode ->
  source:Pdk.Ops.group_owner ->
  destination:Pdk.Ops.group_owner ->
  group:string ->
  Node.t -> Node.t
(** Convert a named point, vertex, primitive, or native edge group through the
    packed PDK topology kernel. [output_attribute] emits an ordinary-owner 0/1
    integer mask instead of a group. *)

val group_promotions :
  ?label:string ->
  ?max_outputs:int ->
  ?max_payload_bytes:int ->
  Pdk.Ops.group_promotion_rule list ->
  Node.t -> Node.t
(** Apply ordered wildcard ordinary or boundary promotions in one inspectable
    node. Blank-pattern rules are disabled and removed from cache identity.
    Later rules observe earlier outputs. Output count and generated payload are
    bounded before each allocation; all-disabled rules preserve input node
    identity. *)

val group_promote_boundary :
  ?label:string ->
  ?name:string ->
  ?keep_original:bool ->
  ?output_attribute:string ->
  ?attributes:Pdk.Ops.group_boundary_attribute list ->
  ?tolerance:float ->
  ?include_unshared_edges:bool ->
  ?include_all_unshared_curve_edges:bool ->
  ?include_all_primitives_sharing_boundary_points:bool ->
  source:Pdk.Ops.group_owner ->
  destination:Pdk.Ops.group_owner ->
  group:string ->
  Node.t -> Node.t
(** Convert a named group and retain its topology boundary, optionally unioning
    typed attribute seams and polygon/curve unshared edges. The result is
    intersected with ordinary promotion so the opposite side is excluded. *)

val group_expand :
  ?label:string ->
  ?name:string ->
  ?steps:int ->
  ?flood:bool ->
  ?step_attribute:string ->
  ?primitive_connectivity:Pdk.Ops.primitive_group_connectivity ->
  ?normal_spread:float ->
  ?normal_attribute:Pdk.Ops.group_expand_normal_attribute ->
  ?connectivity_attributes:Pdk.Ops.group_boundary_attribute list ->
  ?connectivity_tolerance:float ->
  ?collision:Pdk.Ops.group_expand_collision ->
  owner:Pdk.Ops.group_owner ->
  group:string ->
  Node.t -> Node.t
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
  owner:Pdk.Ops.group_owner ->
  name:string ->
  base:Pdk.Ops.group_operand ->
  steps:Pdk.Ops.group_combine_step list ->
  Node.t -> Node.t
(** Boolean-combine named group patterns, including complemented operands,
    into one point, vertex, primitive, or native-edge group. *)

val group_range :
  ?label:string ->
  ?base:string ->
  ?invert:bool ->
  ?filter:Pdk.Ops.group_range_filter ->
  ?connectivity:Pdk.Ops.group_range_connectivity ->
  ?merge:Pdk.Ops.group_boolean_operation ->
  owner:Pdk.Ops.group_owner ->
  name:string ->
  Pdk.Ops.group_range ->
  Node.t -> Node.t
(** Create a packed group from an absolute/relative/length/partition range,
    with an optional periodic selection filter and base-group mask. Optional
    connectivity evaluates the range independently in stable point or
    primitive components. Advanced connectivity can split at same-owner
    attribute discontinuities or independently owned collision-group
    boundaries, control boundary retention, and either preserve or remove
    components outside a one-region restriction. *)

val group_ranges :
  ?label:string ->
  Pdk.Ops.group_range_rule list ->
  Node.t -> Node.t
(** Apply ordered Group Range rules in one inspectable node. Blank-name rules
    are disabled and removed from cache identity. Later rules may use groups
    emitted by earlier rules as bases or collision groups. Empty/all-disabled
    rules preserve the input node identity. *)

val group_invert :
  ?label:string ->
  ?conflict:Pdk.Ops.group_rename_conflict ->
  ?owner:Pdk.Ops.group_owner ->
  pattern:string ->
  ?new_name:string ->
  Node.t -> Node.t
(** Invert one or many groups selected by a name pattern, optionally rewriting
    their names with wildcard captures. *)

val group_delete :
  ?label:string ->
  ?delete_unused:bool ->
  rules:Pdk.Ops.group_delete_rule list ->
  Node.t -> Node.t
(** Delete group metadata by ordered owner/name rules without deleting
    geometry elements. *)

val group_rename :
  ?label:string ->
  rules:Pdk.Ops.group_rename_rule list ->
  Node.t -> Node.t
(** Apply sequential wildcard-capture group renames with explicit conflict
    behavior. *)

val group_copy :
  ?label:string ->
  ?rules:Pdk.Ops.group_copy_rule list ->
  ?conflict:Pdk.Ops.group_copy_conflict ->
  ?copy_empty:bool ->
  source:Node.t -> target:Node.t -> unit -> Node.t
(** Copy group membership from [source] onto [target] by element identity or
    an integer/text matching attribute. *)

val group_transfer :
  ?label:string ->
  ?rules:Pdk.Ops.group_transfer_rule list ->
  ?conflict:Pdk.Ops.group_copy_conflict ->
  ?create_empty:bool ->
  ?distance:float ->
  source:Node.t -> target:Node.t -> unit -> Node.t
(** Transfer point, primitive, and native-edge groups by exact closest
    same-owner geometry proximity within [distance]. Polygon/curve primitive
    and edge distances use accelerated triangle/segment queries rather than
    centroids. *)

val group_find_path :
  ?label:string ->
  ?mode:Pdk.Ops.group_path_mode ->
  ?ending:Pdk.Ops.group_path_ending ->
  ?avoid_self_intersection:bool ->
  ?owner:Pdk.Group.owner ->
  ?collision_group:string ->
  ?contain:bool ->
  base_group:string ->
  name:string ->
  Node.t -> Node.t
(** Construct an ordered point or primitive group from an explicitly ordered
    same-owner base group. Point paths follow topology edges; primitive paths
    follow the manifold shared-edge dual graph. Independent paths cook in
    parallel; paths with intersection avoidance retain deterministic
    base-order priority. Vertex paths are not supported. *)

val delete :
  ?label:string -> ?selected:bool -> ?compact_points:bool ->
  ?policy:Pdk.Ops.delete_topology_policy ->
  'owner Select.t -> Node.t -> Node.t
(* Select points or primitives from a same-owner scalar numeric attribute.
    The optional named base group restricts both normal and inverted
    classification. Output either deletes through PDK's stable topology
    planner or replaces a named group. Unused-point removal is valid only for
    primitive deletion. *)
val blast_by_attribute :
  ?label:string ->
  ?group:string ->
  ?invert:bool ->
  ?remove_unused_points:bool ->
  owner:Pdk.Ops.blast_attribute_owner ->
  attribute:string ->
  mode:Pdk.Ops.blast_attribute_mode ->
  output:Pdk.Ops.blast_attribute_output ->
  Node.t ->
  Node.t
val blast :
  ?label:string -> ?selected:bool -> ?compact_points:bool ->
  ?policy:Pdk.Ops.delete_topology_policy ->
  owner:Pdk.Group.owner -> group:string -> Node.t -> Node.t
val split :
  ?label:string -> ?compact_points:bool ->
  ?policy:Pdk.Ops.delete_topology_policy ->
  'owner Select.t -> Node.t -> Node.t * Node.t
(* Return selected geometry and its remainder as two cache-sharing graph
   branches in that order. *)
val compact_points : ?label:string -> Node.t -> Node.t
(* Construct a deterministic lower-dimensional or closed 3D convex hull from
    an optional typed component selection. Point/detail ancestry preservation,
    source-number output, and the generated primitive group participate in the
    immutable node identity. *)
val convex_hull :
  ?label:string ->
  ?selection:element_group ->
  ?preserve_point_payload:bool ->
  ?source_point_attribute:string ->
  ?hull_group:string ->
  Node.t -> Node.t
(* Emit detail, primitive, or stable integer/text piece centers through the
    packed PDK kernel. Point-mass, bounding-box, and exact convex-hull mass
    methods, provenance names, and piece identity are immutable cache facts. *)
val extract_centroid :
  ?label:string ->
  ?run_over:Pdk.Ops.centroid_run_over ->
  ?method_:Pdk.Ops.centroid_method ->
  ?source_primitive_attribute:string ->
  ?piece_output_attribute:string ->
  Node.t -> Node.t
val bound :
  ?label:string ->
  ?selection:element_group ->
  ?shape:Pdk.Ops.bound_shape ->
  ?lower_padding:Prismel.Vec3.t ->
  ?upper_padding:Prismel.Vec3.t ->
  ?bounds_group:string ->
  ?center_attribute:string ->
  ?radii_attribute:string ->
  Node.t -> Node.t
(* Create a divided box or polygon sphere/ovoid around an optional typed
    component selection, with inspectable output group and detail metadata. *)
val bounding_box :
  ?label:string -> ?padding:Prismel.Vec3.t -> Node.t -> Node.t
val match_axis :
  ?label:string -> from:Prismel.Vec3.t -> into:Prismel.Vec3.t -> Node.t -> Node.t
(* Stable packed point/primitive sort, including point topology keys and
    point/primitive Morton spatial locality. [Random] is deterministic from
    its immutable seed. [Index_attribute] consumes an exact permutation.
    [output_indices] emits destination ranks without reordering, and
    [combine_indices] chains stable indirect sorts through an existing rank
    field. *)
val sort :
  ?label:string -> ?group:string -> ?descending:bool ->
  ?output_indices:string -> ?combine_indices:bool ->
  owner:Pdk.Ops.sort_owner -> key:Pdk.Ops.sort_key -> Node.t -> Node.t
val match_size :
  ?label:string ->
  ?selection:element_group ->
  ?source_selection:element_group ->
  ?target_selection:element_group ->
  ?fit:Pdk.Ops.match_size_fit ->
  ?translate_axes:(bool * bool * bool) ->
  ?scale_axes:(bool * bool * bool) ->
  ?justify:Prismel.Vec3.t ->
  ?target_justify:Prismel.Vec3.t ->
  ?offset:Prismel.Vec3.t ->
  ?scale:float ->
  ?target_center:Prismel.Vec3.t ->
  ?target_size:Prismel.Vec3.t ->
  ?target:Node.t ->
  Node.t -> Node.t
(** Match selected source geometry to another node's selected bounds, or to a
    unit/explicit numeric reference when [target] is omitted. Move, source
    bounds, and target bounds selections are independent. Per-axis alignment,
    offsets, scale controls, and all PDK metric-fit modes participate in the
    immutable node cache identity. *)

val custom :
  ?label:string ->
  ?version:int ->
  ?parameters:string ->
  ?cook_mode:Node.cook_mode ->
  ?dependencies:Context.Dependencies.t ->
  operation:string ->
  Node.t list ->
  (context:Context.t -> Pdk.Geometry.t array ->
   (Pdk.Geometry.t, string) result) ->
  Node.t
(** Define an inspectable custom node from PDK operations or a Geom/Pdk
    adapter composition. Identity fields and declared context dependencies are
    part of its cache key. The callback may retain immutable geometry values,
    but must not mutate or retain the supplied array. Long work must poll
    [Context.cancel_token]. *)

val native_point_ranges :
  ?label:string ->
  ?grain:int ->
  key:string ->
  version:int ->
  dependencies:Context.Dependencies.t ->
  point_range_kernel ->
  Node.t ->
  Node.t
(** The callback must be deterministic, may mutate only indices greater than
    or equal to [first] and strictly less than [last] in the supplied position
    planes, and must not retain those arrays. [key] and
    [version] identify captured immutable parameters for inspection. *)

val noise_displace :
  ?label:string ->
  ?seed:int ->
  amplitude:float ->
  frequency:float ->
  Node.t ->
  Node.t
(** Without [seed], the node derives a deterministic stream from the cook
    context seed and node identity, and therefore declares a seed dependency.
    An explicit [label] makes that identity stable across unrelated graph
    construction edits. *)

val color_by_height :
  ?label:string ->
  low:Prismel.Color.t ->
  high:Prismel.Color.t ->
  Node.t ->
  Node.t

val scatter :
  ?label:string ->
  ?seed:int ->
  ?group:string ->
  ?density:Pdk.Ops.scatter_density ->
  ?point_pattern:string ->
  ?vertex_pattern:string ->
  ?primitive_pattern:string ->
  ?detail_pattern:string ->
  ?match_groups:bool ->
  ?source_primitive_attribute:string ->
  ?source_vertex_numbers_attribute:string ->
  ?source_vertex_weights_attribute:string ->
  count:int -> Node.t -> Node.t
(** Deterministically scatter an exact point count over selected polygon area.
    Typed density weighting, attribute/group interpolation, and exact source
    primitive plus vertex-weight provenance delegate to the shared packed PDK
    kernel. [N], optional [Cd], and stable [id] remain default outputs. An
    explicit label stabilizes an implicit context-derived seed across unrelated
    graph edits. *)
