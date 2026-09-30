(** Sketch presets: the editable document as one s-expression file.

    A preset is a workspace ({!Workspace_doc.to_text}: the [(workspace ...)]
    form, then optional [(layout ...)] and [(settings ...)] forms) followed by
    a [(view {...})] form holding the environment's camera and render
    settings.  Comments in the source survive save and load.  There is no
    other format and no older version: a file that is not this fails with a
    message, and a document that is not a workspace cannot be saved. *)

type loaded = {
  doc : Document.t;
  view : Yojson.Safe.t;  (** environment camera/render settings *)
}

val sanitize : string -> string
(** Keep [A-Za-z0-9_-]; every other character becomes [_]. *)

val default_name : unit -> string
(** Local time as [YYYY-MM-DD_HH-MM-SS]. *)

val path : directory:string -> name:string -> string
(** [<directory>/<name>.plisp]. *)

val save :
  directory:string -> name:string -> doc:Document.t -> view:Yojson.Safe.t ->
  (string, string) result
(** Write atomically ({!Editor_core.Store.write_text}); returns the path.
    [Error] when [doc] has no workspace or the view has nonfinite numbers.
    The document's current settings are saved. *)

val text : Document.t -> (string, string) result
(** The canonical workspace text of [doc] (its settings beside it), as a preset
    or a [.plisp] source is written; [Error] when [doc] is not a workspace. *)

val list : directory:string -> (string * float) list
(** Preset names with modification times, newest first; empty when the
    directory is missing. *)

val delete : directory:string -> name:string -> (unit, string) result

val load :
  path:string -> factories:Procedural.Edit_graph.factory list ->
  settings:Settings.t -> (loaded, string) result
(** Parse, check and lower the file; [settings] is the sketch's settings
    value the saved fields apply to.  An unreadable, unchecked or unlowerable
    file is an [Error] carrying the diagnostic text; nothing else is touched. *)
