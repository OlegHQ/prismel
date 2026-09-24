(** Explicit conversion from cooked PDK geometry to Prismel's render mesh.
    This module does not render or retain backend resources. *)

val to_mesh :
  ?cancel:Pdk.Cancel.t -> Pdk.Geometry.t -> (Prismel.Mesh.t, Pdk.Error.t) result
val cook_to_mesh :
  Session.t ->
  context:Context.t ->
  Node.t ->
  (Prismel.Mesh.t * Diagnostic.t list, Diagnostic.error) result

val cook_to_instances :
  Session.t -> context:Context.t -> Instances.t ->
  (Prismel.Mesh.t * Prismel.Mat4.t array * Diagnostic.t list,
   Diagnostic.error) result
(** Cook/cache one prototype mesh and return an owned copy of its packed
    instance transforms. Pass the result to [Prismel.Scene3.instances_array]. *)

val cook_to_scene3 :
  ?material:Prismel.Material.t ->
  ?texture:Prismel.Scene3.texture ->
  ?shader:Prismel.Shader3.t ->
  ?mode:Prismel.Scene3.render_mode ->
  ?cull:Prismel.Scene3.cull ->
  ?shading:Prismel.Scene3.shading ->
  Session.t ->
  context:Context.t ->
  Instances.t ->
  (Prismel.Scene3.node * Diagnostic.t list, Diagnostic.error) result
(** Cook/cache one prototype directly into an immutable Scene3 instance node.
    This is the allocation-preferred render boundary because no owned transform
    copy escapes between Procedural and Scene3. *)
