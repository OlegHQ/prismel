(** The shell as data (plan W10): a tree of panels.  The editor graph
    evaluates to one; [Pxui_shell.Layout] gives it geometry.  Pure and
    presentation-free, so the document library can lower into it. *)

type panel = View of string | Graph | List | Lisp | Inspector | Outline | Timeline
(** [View key] identifies a viewport by its unique named binding; inline,
    looped and repeated panels use a tree path. The default layout uses [main].
    [Graph] shows the
    graph/list/text views of the open network, [List] and [Lisp] force one of
    them, [Outline] lists the workspace's graphs. *)

type axis = [ `H | `V ]  (** [`H] puts [a] left of [b], [`V] puts [a] above [b] *)

type t =
  | Leaf of panel
  | Split of { axis : axis; ratio : float; a : t; b : t }
  | Tile of t list  (** a grid of equal cells *)
  | Float of t  (** an overlay on its parent's rectangle, never a window *)

type path = int list
(** Child indices from the root: [a]/[b] are 0/1, a tile's cells and a float's
    content are numbered from 0. *)

type state = { collapsed : bool; window : (int * int * int * int) option }
(** A panel's saved disclosure and optional floating window bounds in logical points. *)

val default_state : state

val default : t
(** The three columns: view 45%, graph 35%, inspector 20%. *)

val main : panel
(** [View "main"], the viewport of the default layout. *)

val name : panel -> string
(** ["VIEW"], ["GRAPH"], ... *)

val leaves : t -> (path * panel) list
(** Every leaf in tree order, floats last. *)

val set_ratio : path -> float -> t -> t
(** The split at [path] gets this ratio, clamped to 0.1-0.9; anything else is unchanged. *)

val valid : t -> (unit, string) result
(** Ratios in 0.1-0.9, tiles of 1-16 cells, no empty tree. *)

val to_string : t -> string
(** A one-line shape such as [(h view (h graph inspector))], for messages and tests. *)
