(** Explicit render boundary from cooked procedural geometry to Rays
    meshes and Scene3 nodes. [procedural] stays renderer-free; this module
    owns the Rays-dependent glue and a bounded mesh cache keyed by
    immutable geometry identity. It does not render or retain backend
    resources. *)

type t

type stats = { hits : int; misses : int; retained : int }

val create :
  max_entries:int -> max_payload_bytes:int -> Procedural.Session.t ->
  (t, string) result
(** Wrap a cook session with a mesh cache of the given bounds. *)

val context_of_frame :
  ?seed:int64 -> ?domains:int -> ?grain:int -> Rays.Frame.t ->
  (Procedural.Context.t, string) result
(** Copy target-neutral timing facts from a Rays frame. No canvas,
    renderer, input resource, or backend handle is retained. *)

val mesh : ?cancel:Rdk.Cancel.t -> t -> Rdk.Geometry.t ->
  (Rays.Mesh.t, Rdk.Error.t) result
(** Convert and cache a render mesh by immutable geometry identity. Fails once
    the wrapped session is closed. *)

val cook_to_mesh :
  t -> context:Procedural.Context.t -> Procedural.Node.t ->
  (Rays.Mesh.t * Procedural.Diagnostic.t list, Procedural.Diagnostic.error) result

val cook_to_instances :
  t -> context:Procedural.Context.t -> Procedural.Instances.t ->
  (Rays.Mesh.t * Rays.Mat4.t array * Procedural.Diagnostic.t list,
   Procedural.Diagnostic.error) result
(** Cook/cache one prototype mesh and return an owned copy of its packed
    instance transforms. Pass the result to [Rays.Scene3.instances_array]. *)

val cook_to_scene3 :
  ?material:Rays.Material.t ->
  ?texture:Rays.Scene3.texture ->
  ?mode:Rays.Scene3.render_mode ->
  ?cull:Rays.Scene3.cull ->
  ?shading:Rays.Scene3.shading ->
  t ->
  context:Procedural.Context.t ->
  Procedural.Instances.t ->
  (Rays.Scene3.node * Procedural.Diagnostic.t list, Procedural.Diagnostic.error) result
(** Cook/cache one prototype directly into an immutable Scene3 instance node. *)

val stats : t -> stats
