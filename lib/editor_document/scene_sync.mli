(** Edits of the derived scene and World, written back to the workspace text (plan W10).

    The scene list, the inspector, the handles and the World keys edit a document's derived
    objects; the text is the truth, so every such edit goes through {!reconcile}. *)

val reconcile : factories:Procedural.Edit_graph.factory list -> ?adopt:bool ->
  Document.t -> Document.t -> (Document.t, string) result
(** [reconcile ~factories before after]: [after] is [before] with its scene, World networks,
    active camera or settings edited.  Each difference becomes a {!Flow_sop.Flow_edit} op on the
    graph that declares the object (an inline call is unfolded into a binding first), and the
    result is [after] with the new text lowered again (objects keep their ids).  An edit the text
    cannot take (an object made by an expression, a name two objects share, a field a loop
    computes) is an [Error] and changes nothing.  The copies of a loop are one template: an edit
    of a literal field of one is written to the template (every copy changes).  Deleting one
    is exact at any nesting depth and for any number of clauses: the iteration that made it (or,
    when its iteration made other objects that stay, its place in the [scene/merge] that holds it)
    is added to a [:skip] list (register L16), and every other copy keeps its iteration tuple.
    An object only the host made is written to a scene graph by its first explicit
    edit; [~adopt:false] (a camera following the viewport) leaves such edits to the host. *)

val in_text : Document.t -> Document.level -> int -> bool
(** The scene object (at the scene level) or World layer (inside the World) with this id has text
    of its own that an edit can be written to. *)

val set_fields : factories:Procedural.Edit_graph.factory list -> Document.t -> Document.level ->
  node:int -> (string * Editor_core.Param.value) list ->
  ((Document.t * Editor_core.Param.effects * Document.home) option, string) result
(** Field values of one object written to its text and lowered again, the derived object never
    edited in between: the values as the node's ranges leave them, an inline call unfolded first, a
    loop's copy its template (a computed argument refuses).  The document, the effects of the
    fields and the home written; [None] when the object has no text ({!reconcile} adopts it). *)

type edit =
  | Fields of (int * (string * Editor_core.Param.value) list) list
      (** field values of several objects (a stroke down a flag column) *)
  | Rename of int * string  (** an object's name; its children's [:parent] follows *)
  | Delete of int list  (** objects (their children are unparented) or layers (the stack closes) *)
  | Restack of int list  (** the World's layers, bottom first *)
  | Layers of Document.network * (string * Editor_core.Param.value) list
      (** a preset: the World's layers replaced and its own fields set (the level is the World) *)
  | Camera of int option
      (** the render camera: the root's [:camera], else [:active]; the document's alone when the
          text has neither camera *)
(** A derived edit as its caller means it: scene objects at the scene level, World layers inside
    the World. *)

val writes : Document.t -> Document.level -> edit -> bool
(** Every object the edit names has text of its own, so {!write} takes it. *)

val write : factories:Procedural.Edit_graph.factory list -> Document.t -> Document.level -> edit ->
  ((Document.t * string option) option, string) result
(** The edit written to the text and lowered again, the derived document never edited in between,
    with what it did to a loop's copies for the status line; the same text as {!reconcile} writes
    for the same edit of the derived document.  [None] when not {!writes}: the caller edits the
    derived document and {!reconcile} adopts it. *)

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

val add_geometry : Document.t -> existing:string option -> Flow_sop.Flow_edit.op list
(** The ops of adding geometry to the scene's merge, one gesture: a new SOP graph, a
    [scene/geometry] binding of it and the merge input; with [~existing] the object of an
    existing SOP graph only (two objects share it). *)

val add_world : Document.t -> (Flow_sop.Flow_edit.op list, string) result
(** The ops of adding a World (a world graph and a [scene/world] member); refused when the scene
    has one. *)
