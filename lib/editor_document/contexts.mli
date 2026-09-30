(** The scene, world and settings contexts of a workspace (plan W10).

    Their Lisp spellings are generated from the schemas that exist:
    [scene/geometry], [scene/light] and [scene/camera] from the object
    factories, [world/world] and [world/gradient], [world/sky], [world/sun],
    [world/shape], [world/scatter], [world/room] from the World factories and
    [settings/config] from the workspace settings record.  A keyword is a
    schema field; three consecutive [_x _y _z] or [_r _g _b] floats are one
    vec3 or colour ([:translate [0 1 0]], [:color "#3b7d4e"]), and [:name] is
    the node's label.  A geometry object takes its geometry as the first
    argument, a World layer the layer below it.  [scene/merge] joins scenes.
    Scene, world and settings arguments are evaluated at [t = 0]. *)

val descriptors : Flow_sop.Catalog.descriptor list
(** Every generated kind; the manifest generator writes them. *)

val catalog : version:int -> Procedural.Edit_graph.factory list ->
  (Flow.Check.catalog, Flow.Diagnostic.t) result
(** {!Flow_sop.Catalog.of_factories} with {!descriptors}: what a workspace text
    is checked against. *)

type window = { title : string; width : int; height : int; fps : int; seed : int }
(** What [(settings/config :title :width :height :fps :seed)] asks of the host. *)

val window : Workspace_doc.t -> (window, Flow.Diagnostic.t) result
(** The window of a checked workspace: its settings graph evaluated, defaults
    without one. *)

val has_settings : Workspace_doc.t -> bool

val of_workspace : factories:Procedural.Edit_graph.factory list -> ?previous:Document.t ->
  Workspace_doc.t -> (Document.t, Flow.Diagnostic.t) result
(** The document of a workspace: the objects of its scene graph as nodes of the
    scene network (each geometry object owning the lowered network of its sop
    graph; without a scene graph, one geometry object per sop graph), the World
    of its world graph with its layers as a network, and its settings graph as
    the document settings.  [previous] keeps object ids (matched by operation and
    label), tile layouts, the objects the workspace does not declare (the host's
    camera and lights), and the lowering's compiled ids.  The workspace owns
    geometry always, cameras and lights when its scene declares one, and the
    World when it has a world graph. *)
