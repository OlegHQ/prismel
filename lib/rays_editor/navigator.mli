(** The Outline panel: a map of the document.  A search field, then a section per kind of graph
    (the scene with its objects and their visible and render flags, geometry and materials with
    how many graphs use each, the World, the layouts), the active graph unfolded into its loops
    and bindings, the reusable functions and macros, the active graph's inputs as sliders and
    the data flow around it.  The behavioural reference is [specification/workspace/prototype] (navigator).

    Pure state and rows; {!view} draws inside [Pxui.Ui.frame] and returns intents that
    [Core] applies after the frame. *)

type path = Flow.Workspace.path

type intent =
  | Open of { graph : string; node : path option }
      (** show a graph (a [defn] is ["def:name"]) in the graph pane, selecting [node] there *)
  | Set_default of { graph : string; input : string; value : float; integer : bool }
      (** a graph input's default, dragged or typed in its slider *)
  | Macro of string  (** a macro row: its definition in the text pane *)
  | Rename of { graph : string; to_ : string }  (** F2 on a graph row *)
  | Remove of string  (** Delete on a graph row *)
  | Layout of int  (** a row of the Layout section: show that layout *)
  | Add  (** the [+] beside the search field: the add menu *)
  | Flag of { node : path; name : string; value : bool }
      (** a press on an object's visible or render flag: that argument of its binding *)

type state

val initial : state

val editing : state -> bool
(** The search field holds the keyboard. *)

val with_query : string -> state -> state
val query : state -> string
(** The search field holding this text. *)

type obj = { depth : int; letter : string; name : string; detail : string;
             visible : bool option; render : bool option; lead : bool; inert : bool; chosen : bool;
             home : path option }
(** A scene object's row: its kind's letter, name and detail, its visible and render flags
    (where it has them), [lead] for the render camera, [inert] when the render mark only shows
    (the camera's, the World's: a press on it opens the row), [chosen] when selected, and the binding
    that places it (a click opens its graph on it). *)

type params = {
  workspace : Flow.Workspace.t;
  active : string option;  (** the graph the pane shows *)
  scope : Flow_sop.Projection.scope option;  (** the projection of [active] *)
  records : Flow_sop.Probe.t option;
  probes : path -> int;  (** the iteration each zone shows *)
  selected : path list;
  chips : (string * Rays.Color.t) list;  (** the evaluated colour of each material graph *)
  objects : obj list;  (** the scene's objects, in tree order *)
  root_detail : string;  (** what the scene's root row says beside its name *)
  layouts : (string list * int) option;  (** the layouts of the editor graph, and the one shown *)
  notes : (string * string) list;  (** what a material graph says beside its swatch ({!notes}) *)
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

val jump_rows : Flow.Workspace.t -> (string * string) list
(** Every graph with its outline group (Scene, Geometry, Materials, World, Layout, ...), in the
    outline's order: what [Space j] filters. *)

val notes : Flow.Eval.t -> (string * string) list
(** The roughness of each evaluated material graph, as its row's detail. *)

val chips : Flow.Eval.t -> (string * Rays.Color.t) list
(** The evaluated colour of each material graph (a vector or hex text; white when unset). *)
