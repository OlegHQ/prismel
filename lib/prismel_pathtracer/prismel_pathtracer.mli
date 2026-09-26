(** Metal ray-tracing path tracer.

    PDK meshes carry metallic-roughness materials and are lit by a procedural
    dome: a sky/ground gradient plus soft rectangular emitter panels, which
    together stand in for a studio HDRI. Rendering is progressive: every
    [render] call adds [spp] samples per pixel into an accumulation buffer and
    refreshes the borrowed [image]; a camera change restarts accumulation. *)

(** Linear floating-point RGB for materials and light. Channels are not
    quantized or clamped, so dim and HDR values survive GPU upload. *)
module Linear_color : sig
  type t = { r : float; g : float; b : float }

  val rgb : float -> float -> float -> t
end

type material =
  { albedo : Linear_color.t
  ; roughness : float  (** 0 = mirror, 1 = fully rough *)
  ; metallic : float
  ; emission : Linear_color.t
  ; round : float
    (** Round-corners radius in scene units (0 = off). A render-time shading
        bevel: the normal rolls over onto adjacent faces within this distance
        of an edge, like Redshift's Round Corners, without changing geometry. *) }

val material :
  ?roughness:float -> ?metallic:float -> ?emission:Linear_color.t -> ?round:float ->
  Linear_color.t -> material

(** A soft rectangle of light painted on the dome around [direction]. Extents
    are angular half-sizes in radians; [softness] is the edge falloff. *)
type panel =
  { direction : Prismel.Vec3.t
  ; width : float
  ; height : float
  ; softness : float
  ; color : Linear_color.t
  ; intensity : float }

val panel :
  ?softness:float -> ?color:Linear_color.t -> intensity:float -> width:float ->
  height:float -> Prismel.Vec3.t -> panel

type environment = { sky : Linear_color.t; ground : Linear_color.t; panels : panel list }

(** Rectangle area light of [size] (width, height) centred at [at], facing
    [target], two-sided. Sampled with shadow rays (next-event estimation);
    lights are analytic and never appear as visible geometry. *)
type light =
  { at : Prismel.Vec3.t; target : Prismel.Vec3.t; size : float * float; color : Linear_color.t; intensity : float }

val rect_light :
  ?color:Linear_color.t -> intensity:float -> size:float * float -> target:Prismel.Vec3.t ->
  Prismel.Vec3.t -> light

(** An analytic sphere, traced through a bounding-box intersection function
    rather than tessellated. *)
type sphere = { center : Prismel.Vec3.t; radius : float; sphere_material : material }

val sphere : radius:float -> material -> Prismel.Vec3.t -> sphere

(** A round polyline of constant [thickness] (diameter), traced as linear
    curve segments. Needs [Ogpu.Caps.Ray_tracing_curves]; [create] and
    [replace_mesh] fail with a typed message otherwise. *)
type strand = { points : Prismel.Vec3.t array; thickness : float; strand_material : material }

val strand : thickness:float -> material -> Prismel.Vec3.t array -> strand

type scene =
  { objects : (Pdk.Geometry.t * material) list
  ; spheres : sphere list
  ; strands : strand list
  ; environment : environment
  ; lights : light list }

type t

(** Pure prepared geometry: a flat triangle mesh or a prototype plus compact
    instance transforms. A SOP cook worker may prepare it off the initial domain. *)
type mesh

val mesh :
  ?spheres:sphere list -> ?strands:strand list -> (Pdk.Geometry.t * material) list ->
  (mesh, string) result
val triangle_count : mesh -> int

val mesh_instanced :
  prototype:(Pdk.Geometry.t * material) -> ?materials:material array ->
  ?motion:Prismel.Mat4.t array -> Prismel.Mat4.t array -> (mesh, string) result
(** One prototype and its instance transforms, without duplicated triangles.
    For [n] instances, preparation takes O(n) time and O(n) auxiliary memory;
    the prototype's topology is stored once. [materials] (one per instance)
    overrides the prototype material per instance through the instance user
    id. [motion] gives each instance a second transform at the end of the
    shutter; the instance structure carries both keyframes and every sample
    picks a shutter time, so instances blur along their motion. *)

(** Builds the primitive acceleration structure, compiles the kernels, and
    allocates accumulation and output storage. Fails with a typed message
    when no ray-tracing Metal device is available. *)
val create :
  ?spp:int -> ?bounces:int -> ?exposure:float -> ?round_samples:int ->
  width:int -> height:int -> scene -> (t, string) result
(** [round_samples] (default 4) is the number of probe rays per camera-visible
    shading point for round-corner materials; secondary bounces use a quarter. *)

(** Accepts a perspective camera with no lens offset, forced aspect, or
    vertical flip. Other projections return an error. Publishes the previous
    frame's pixels to [image], then submits a new frame
    without waiting for it (one frame of latency). A frame whose camera
    differs from the previous call is an interactive preview: full-resolution
    primary visibility, direct lighting, one round-corner probe, temporal
    reprojection with disocclusion rejection, and an edge-aware spatial
    resolve. Progressive accumulation restarts as soon as the camera rests. *)
val render : t -> Prismel.Camera.t -> (unit, string) result

val replace_mesh : t -> mesh -> (unit, string) result
(** Synchronously builds and swaps scene geometry, then restarts accumulation. *)

val queue_mesh : t -> mesh -> (unit, string) result
(** Starts a replacement build without waiting for the GPU. [render] continues
    showing the old scene until the new structure is complete. A newer queued
    mesh supersedes one still building; at most one build and one queued mesh
    are retained. [flush] waits for the latest replacement. *)

val flush : t -> (unit, string) result
(** Publishes the in-flight frame and waits for queued geometry;
    [render] then [flush] is a
    synchronous render. [render] itself never blocks: while the GPU is still
    busy with the previous frame it returns without submitting, so the
    caller's loop keeps its own frame rate. *)

val reset : t -> unit
val samples : t -> int
(** Accumulated samples per pixel. *)

val resize : t -> width:int -> height:int -> (unit, string) result
(** Match a new viewport: waits for the in-flight frame, reallocates the film,
    and restarts accumulation. Scene geometry is kept. No-op at the same size. *)

val size : t -> int * int
val image : t -> Prismel.Image.t
(** Borrowed; destroyed by [destroy]. In a native Sketch, Scene samples its
    completed GPU film directly. *)

val pixels : t -> (bytes, string) result
(** Last resolved RGBA8 frame, row-major. Explicit readback for GPU film;
    a failed readback is an [Error]. *)

val destroy : t -> unit
