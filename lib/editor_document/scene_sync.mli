(** Edits of the derived scene and World, written back to the workspace text (plan W10).

    The scene list, the inspector, the handles and the World keys edit a document's derived
    objects; the text is the truth, so every such edit goes through {!reconcile}. *)

val reconcile : factories:Procedural.Edit_graph.factory list -> ?adopt:bool -> ?whole:bool ->
  Document.t -> Document.t -> (Document.t, string) result
(** [reconcile ~factories before after]: [after] is [before] with its scene, World networks,
    active camera or settings edited.  Each difference becomes a {!Flow_sop.Flow_edit} op on the
    graph that declares the object (an inline call is unfolded into a binding first), and the
    result is [after] with the new text lowered again (objects keep their ids).  An edit the text
    cannot take (an object made by an expression, a name two objects share, a field a loop
    computes) is an [Error] and changes nothing.  The copies of a loop are one template: an edit
    of a literal field of one is written to the template (every copy changes), deleting one
    rewrites the collection it loops over, and when that cannot be done (several clauses, or
    the copy made other objects that stay) the whole loop goes only with [~whole:true], which
    {!confirming} asks the person for.  An object only the host made is written to a scene graph by its first explicit
    edit; [~adopt:false] (a camera following the viewport) leaves such edits to the host. *)

val confirming : factories:Procedural.Edit_graph.factory list -> Document.t -> Document.t ->
  string option
(** [Some question] when [reconcile] refused the deletion of a loop'"'"'s copy because no single copy
    can go: the whole loop, with the number of copies that go, waits for a yes. *)

val template_note : Document.t -> Document.home -> string option
(** The status line for an edit written to a loop'"'"'s template: every copy changes. *)

val note : Document.t -> Document.t -> string option
(** What a {!reconcile}d edit did to the copies of a loop, for the status line. *)

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
