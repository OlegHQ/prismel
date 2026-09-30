(** The host bars of the workspace: the top bar (title, Shell layouts, Undo, Redo, Copy Lisp)
    and the graph panel's toolbar (Add, Repeat, Iterate, function, macro, defn).  Buttons only
    report a click; [Core] maps it to the one command or edit it means. *)

type top_intent = Undo | Redo | Copy_lisp | Keys | Layout of string  (** a name of {!layouts} *)
type tool = Add | Repeat | Iterate | Fn | Macro | Defn

val height : int
(** The top bar's height in points. *)

val layouts : (string * string) list
(** The shell layouts of the "Shell layouts" menu: key and label. *)

val top : Pxui.Ui.t -> width:float -> title:string -> status:bool * string -> can_undo:bool -> can_redo:bool ->
  top_intent list
(** Draw the bar across [width] points inside [Pxui.Ui.frame]; [status] is the checker's verdict: ok or not, and its words. *)

val top_button_rect : width:float -> string -> float * float * float * float
(** Where a top bar button (by its label) sits in a bar [width] points wide. *)

val tools_from : string -> float
(** The toolbar starts after a header title (and subtitle) of this text. *)

val tool_rect : header:int * int * int * int -> from:float -> tool -> (float * float * float * float) option
(** Where a toolbar button sits; none when the header is too narrow for it. *)

val graph_tools : Pxui.Ui.t -> header:int * int * int * int -> from:float -> enabled:bool -> tool option
(** The toolbar in a panel header, [from] points after the header's left edge; the tool
    clicked this frame. *)

val layout_text : name:string -> graph:string option -> scene:string -> string -> string
(** [layout_text ~name ~graph ~scene layout]: the editor graph [name] of a shell layout
    ([default], [code], [focus], [floating]), its graph panel showing [graph]. *)
