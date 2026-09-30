(** The Navigator panel (the workspace's outline): a map of the document.  The case-study
    header, the active graph's inputs as sliders, the composition (every graph, with the
    active one unfolded into its loops and bindings and their values), the reusable
    functions and macros, the data flow around the active graph and the shell's panel
    tree.  The behavioural reference is [specification/workspace/prototype] (navigator).

    Pure state and rows; {!view} draws inside [Pxui.Ui.frame] and returns intents that
    [Core] applies after the frame. *)

type path = Flow.Workspace.path

type intent =
  | Open of { graph : string; node : path option }
      (** show a graph (a [defn] is ["def:name"]) in the graph pane, selecting [node] there *)
  | Set_default of { graph : string; input : string; value : float; integer : bool }
      (** a graph input's default, dragged or typed in its slider *)
  | Macro of string  (** a macro row: its definition in the text pane *)

type state

val initial : state

val editing : state -> bool
(** The search field holds the keyboard. *)

val with_query : string -> state -> state
(** The search field holding this text. *)

type params = {
  workspace : Flow.Workspace.t;
  title : string;
  active : string option;  (** the graph the pane shows *)
  scope : Flow_sop.Projection.scope option;  (** the projection of [active] *)
  records : Flow_sop.Probe.t option;
  probes : path -> int;  (** the iteration each zone shows *)
  selected : path list;
  shell : Editor_core.Panels.t option;  (** the applied editor graph's panel tree *)
}

type row

val pretty : string -> string
(** A workspace name as a title: [bloom_studio] is [Bloom studio]. *)

val rows : state -> params -> row array
(** Every row in order; a search shows the matching bindings instead. *)

val row_rects : ?row_height:int -> state -> params -> bounds:int * int * int * int ->
  (row * (float * float * float * float)) array
(** Every row with its rectangle when not scrolled: where {!view} draws it and where a click
    on it lands. *)

val describe : row -> string
(** One line per row, for tests and crash reports. *)

val view : state -> Pxui.Ui.t -> bounds:int * int * int * int -> params -> state * intent list
(** Draw the panel in [bounds] (scrolling, searching, sliders). *)
