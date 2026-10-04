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
(** What [(settings/config :title :width :height :fps :seed)] asks of the host
    when it starts. These fields apply on restart; editing saved settings does
    not reconfigure the running window, frame scheduler or cook seed. *)

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
    the document settings.  [previous] keeps object ids (matched by where the text
    is, then by operation and label), tile layouts, the objects the workspace does not declare (the host's
    camera, lights and World), and the lowering's compiled ids.  The workspace owns
    geometry always, every object when it has a scene graph (an empty one means
    none: the host seeds nothing) and the World when it has a world graph
    ([world/none] means none). Light intensity/color retain their residuals for
    timeline composition. Other time-dependent fields in scene, World, settings
    and editor structs are refused with [E_CONTEXT_TIME], naming the graph and
    field. Geometry references with live SOP parameters are supported. *)

val group_triples : Editor_core.Param.field_view list -> Editor_core.Param.field_view list
(** Three consecutive [_x _y _z] (or [_r _g _b]) floats of one folder as one vec3 field. *)

val resolve_scene : ?previous:Procedural.Edit_graph.t -> Document.t -> time:float ->
  Procedural.Edit_graph.t * Flow.Diagnostic.t list
(** Resolve recorded live light intensity/color fields for composition, without
    changing source, networks, identities or history. A failed light retains
    its previous value (or the authored zero-time value without [previous]);
    successful siblings still advance. Diagnostics name its fields and view. *)

val instance_root : Flow.Eval.value -> Objects.Root.parameters option
(** The render settings a viewport's scene instance names: its [scene/root]'s, with the
    defaults for what the root leaves out; [None] for a part, which renders as the document does. *)

val graph_of : Workspace_doc.t -> Flow.Workspace.context -> Flow.Workspace.graph option
(** The first graph of a context. *)

val world_kinds : (string * Procedural.Edit_graph.factory) list
(** The qualified World kinds ([world/sky], ...) with their factories. *)

val sha256 : string -> string
(** Lower-case hex SHA-256: the digest of a sketch source. *)

val catalog_digest : Procedural.Edit_graph.factory list -> string
(** {!sha256} of the manifest text the catalog generates (with {!descriptors}),
    or of its error: what a [.plisp] binary compares against the catalog it
    runs with. *)
