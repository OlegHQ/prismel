(** Sketch presets: the full editable document as versioned JSON.

    A preset records the scene network (objects, their parents and
    parameters), every object's own network (a geometry object's SOPs, the
    World's layers) with tile positions and display nodes, the active camera,
    sketch settings, and environment view settings. Nodes added from a
    catalog are recreated from their factory; nodes from the sketch's code
    graph (including custom, non-catalog SOPs) rebind by their stable node
    id, so a preset only loads into the sketch whose code produced it.
    Version 1 presets (one SOP network) load as the geometry object geo1,
    their camera SOPs becoming camera objects. *)

type loaded = {
  doc : Document.t;
  view : Yojson.Safe.t;  (** environment camera/render settings *)
}

val sanitize : string -> string
(** Keep [A-Za-z0-9_-]; every other character becomes [_]. *)

val default_name : unit -> string
(** Local time as [YYYY-MM-DD_HH-MM-SS]. *)

val path : directory:string -> name:string -> string

val save :
  directory:string -> name:string -> sketch:string -> doc:Document.t ->
  view:Yojson.Safe.t -> (string, string) result
(** Write [<directory>/<name>.json] through {!Editor_core.Store}'s atomic JSON
    envelope; returns the path. *)

val list : directory:string -> (string * float) list
(** Preset names with modification times, newest first; empty when the
    directory is missing. *)

val delete : directory:string -> name:string -> (unit, string) result

val load :
  path:string -> code:Procedural.Graph.t ->
  factories:Procedural.Edit_graph.factory list -> settings:Settings.t ->
  (loaded, string) result
(** Rebuild the saved document from [code] and the catalogs; [settings] is
    the sketch's settings value the saved fields apply to. Corrupt JSON, an
    unknown version, a missing code node, or an unknown factory is an
    [Error]; the caller's document is never touched. *)
