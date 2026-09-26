(** Explicit render boundary from cooked procedural geometry to Prismel
    meshes and Scene3 nodes. [procedural] stays renderer-free; this module
    owns the Prismel-dependent glue and a bounded mesh cache keyed by
    immutable geometry identity. It does not render or retain backend
    resources. *)

type t

type stats = { hits : int; misses : int; retained : int }

val create :
  max_entries:int -> max_payload_bytes:int -> Procedural.Session.t ->
  (t, string) result
(** Wrap a cook session with a mesh cache of the given bounds. *)

val context_of_frame :
  ?seed:int64 -> ?domains:int -> ?grain:int -> Prismel.Frame.t ->
  (Procedural.Context.t, string) result
(** Copy target-neutral timing facts from a Prismel frame. No canvas,
    renderer, input resource, or backend handle is retained. *)

val mesh : ?cancel:Pdk.Cancel.t -> t -> Pdk.Geometry.t ->
  (Prismel.Mesh.t, Pdk.Error.t) result
(** Convert and cache a render mesh by immutable geometry identity. Fails once
    the wrapped session is closed. *)

val cook_to_mesh :
  t -> context:Procedural.Context.t -> Procedural.Node.t ->
  (Prismel.Mesh.t * Procedural.Diagnostic.t list, Procedural.Diagnostic.error) result

val cook_to_instances :
  t -> context:Procedural.Context.t -> Procedural.Instances.t ->
  (Prismel.Mesh.t * Prismel.Mat4.t array * Procedural.Diagnostic.t list,
   Procedural.Diagnostic.error) result
(** Cook/cache one prototype mesh and return an owned copy of its packed
    instance transforms. Pass the result to [Prismel.Scene3.instances_array]. *)

val cook_to_scene3 :
  ?material:Prismel.Material.t ->
  ?texture:Prismel.Scene3.texture ->
  ?mode:Prismel.Scene3.render_mode ->
  ?cull:Prismel.Scene3.cull ->
  ?shading:Prismel.Scene3.shading ->
  t ->
  context:Procedural.Context.t ->
  Procedural.Instances.t ->
  (Prismel.Scene3.node * Procedural.Diagnostic.t list, Procedural.Diagnostic.error) result
(** Cook/cache one prototype directly into an immutable Scene3 instance node. *)

val stats : t -> stats
