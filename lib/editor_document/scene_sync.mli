(** Edits of the derived scene and World, written back to the workspace text (plan W10).

    The scene list, the inspector, the handles and the World keys edit a document's derived
    objects; the text is the truth, so every such edit goes through {!reconcile}. *)

val reconcile : factories:Procedural.Edit_graph.factory list -> ?adopt:bool ->
  Document.t -> Document.t -> (Document.t, string) result
(** [reconcile ~factories before after]: [after] is [before] with its scene, World networks,
    active camera or settings edited.  Each difference becomes a {!Flow_sop.Flow_edit} op on the
    graph that declares the object (an inline call is unfolded into a binding first), and the
    result is [after] with the new text lowered again (objects keep their ids).  An edit the text
    cannot take (an object made by a loop, a name two objects share) is an [Error] and changes
    nothing.  An object only the host made is written to a scene graph by its first explicit
    edit; [~adopt:false] (a camera following the viewport) leaves such edits to the host. *)

val value_syntax : Editor_core.Param.field_view list -> Flow.Syntax.t
(** The text of a parameter's current value: a number, flag or text, or a vector of numbers
    for the three fields of a vec3. *)

val adopt : factories:Procedural.Edit_graph.factory list -> world:bool -> Document.t ->
  (Document.t, string) result
(** The scene graph ([~world:false]) or the World graph of a document that has none, written
    from the objects or World the host made (an empty one when there are none). *)

val bind_home : factories:Procedural.Edit_graph.factory list -> Document.t -> Document.home ->
  (Document.t * Flow.Workspace.path, string) result
(** The binding that holds a home, made by unfolding what is written in place (several rewrites,
    one new document); an error when a loop or an expression made it. *)
