(** Sketch presets: the full editable document as versioned JSON.

    A preset records topology, per-node parameters, graph tile positions, the
    display node, the active camera, and environment view settings. Nodes added
    from the catalog are recreated from their factory; nodes from the sketch's
    code graph (including custom, non-catalog SOPs) rebind by their stable
    node id, so a preset only loads into the sketch whose code produced it. *)

type loaded = {
  document : Procedural.Edit_graph.t;
  positions : (int * float * float) list;  (** graph-space tile positions *)
  display : int option;
  active_camera : int option;
  view : Yojson.Safe.t;  (** environment camera/render settings *)
}

val sanitize : string -> string
(** Keep [A-Za-z0-9_-]; every other character becomes [_]. *)

val default_name : unit -> string
(** Local time as [YYYY-MM-DD_HH-MM-SS]. *)

val path : directory:string -> name:string -> string

val save :
  directory:string -> name:string -> sketch:string ->
  document:Procedural.Edit_graph.t -> positions:(int * float * float) list ->
  display:int option -> active_camera:int option -> view:Yojson.Safe.t ->
  (string, string) result
(** Write [<directory>/<name>.json] (creating directories) through a temporary
    file and rename; returns the path. *)

val list : directory:string -> (string * float) list
(** Preset names with modification times, newest first; empty when the
    directory is missing. *)

val delete : directory:string -> name:string -> (unit, string) result

val load :
  path:string -> code:Procedural.Graph.t ->
  factories:Procedural.Edit_graph.factory list -> (loaded, string) result
(** Rebuild the saved document from [code]: code nodes rebind by id, catalog
    nodes are instantiated from [factories] with disconnected placeholders,
    then inputs are connected, parameters applied, and the display node set.
    Code nodes absent from the preset are removed. Corrupt JSON, an unknown
    version, a missing code node, or an unknown factory is an [Error]; the
    caller's document is never touched. *)
