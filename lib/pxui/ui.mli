(** Immediate-mode PXUI.

    Build the whole interface every frame inside {!frame}; widgets return
    their current values directly, so values live in the sketch model rather
    than in the UI:

    {[
      let update model frame =
        Ui.frame model.ui frame @@ fun ui ->
        Ui.panel ui "Motion" @@ fun () ->
        let animate = Ui.toggle ui "Animate" model.animate in
        let radius = Ui.slider ui "Radius" ~range:(10., 120.) model.radius in
        if Ui.button ui "Quit" then Sketch.quit ();
        { model with animate; radius }

      let view model _frame = Scene.group [ scene_of model ] :: Ui.scene model.ui
    ]}

    Every call creates one {e box}: a node with an integer key, flags, and a
    size rule per axis. Keys hash the label (text after [##] is part of the
    key but not displayed; [###id] replaces the key) together with the
    enclosing box, so state follows the label rather than list positions.
    Per-key state (rectangles, scroll offsets, open accordions, text editing)
    lives in the retained cache owned by [t] and is dropped once a key is not
    built for a frame.

    Input is routed against the previous frame's rectangles: the topmost
    clickable box under a press becomes the single [active] box and captures
    the pointer until release; keyboard and text events go to the focused
    box; wheel events go to the topmost scrollable box under the pointer.
    Layout runs after the build, then boxes paint into one packed instance
    list that the native UI pipeline draws with a handful of draw calls.

    All coordinates are logical points. [t] is a mutable handle, like
    [Prismel.Assets]: thread it through the model and call {!destroy} from
    [Sketch.run_state ~on_stop]. *)

type t

val create : ?theme:Theme.t -> ?font:Prismel.Font.t -> ?font_size:int -> unit -> t
(** [font] (borrowed) overrides the kit face; [font_size] is the logical size
    of kit text. *)

val destroy : t -> unit
(** Release the glyph atlas. The handle must not be used afterwards. *)

val theme : t -> Theme.t
val set_theme : t -> Theme.t -> unit
val font_size : t -> int

(** {1 Frames} *)

val frame : t -> Prismel.Frame.t -> (t -> 'a) -> 'a
(** Route the frame's ordered events, run the builder, lay out, and paint. *)

val scene : t -> Prismel.Scene.t
(** The most recently completed frame, including text-input regions. *)

val wants_pointer : t -> bool
(** The pointer was over a UI box, or a box holds pointer capture. *)

val cursor : t -> [`Horizontal_resize|`Vertical_resize] option
val request_cursor : t -> [`Horizontal_resize|`Vertical_resize] -> unit
(** Cursor requested by a hovered or captured PXUI control. *)

val text_input_focused : t -> bool
(** A text field or numeric editor owns keyboard input. *)

val unfocus : t -> unit

(** {1 Boxes} *)

type box

type size =
  | Px of float  (** fixed *)
  | Pct of float  (** fraction of the parent's inner size *)
  | Rel of (float -> float)  (** function of the parent's inner size *)
  | Grow  (** share of the remaining space, or the full cross size *)
  | Fit  (** children's extent plus padding *)
  | Text  (** the box text's width or height plus padding *)

type axis = Row | Column

(** Box flags: [clickable] boxes receive presses and pointer capture;
    [focusable] boxes take keyboard focus when pressed; [scroll] boxes receive
    wheel events and scroll their children vertically; [clip] clips children
    to the padded content rectangle; [blocking] boxes consume hover and
    presses so boxes below them do not receive them. *)
type flags

val none : flags
val clickable : flags
val focusable : flags
val scroll : flags
val clip : flags
val blocking : flags
val ( + ) : flags -> flags -> flags

val box :
  t -> ?flags:flags -> ?w:size -> ?h:size -> ?max_h:float -> ?axis:axis ->
  ?padding:float -> ?gap:float -> ?at:float * float -> ?xform:float * float * float ->
  ?text:string -> ?text_size:int -> ?scroll_step:float ->
  ?hit:(float * float * float * float -> float * float * float * float) ->
  string -> box
(** Create a box under the current parent. [at] positions it outside the flow
    at an offset from the parent's origin (in canvas units inside a canvas).
    [xform] = [(scale, tx, ty)] makes the box a canvas: its children use
    canvas coordinates mapped to the screen by [p * scale + t], relative to
    the box origin. [max_h] caps a [Fit] height; overflowing [scroll] boxes
    reserve a 10-point scrollbar gutter. [hit] maps the laid-out rectangle to
    the rectangle that receives input (the default is the whole box). *)

val within : t -> box -> (unit -> 'a) -> 'a
(** Build children of [box]. *)

val scope : t -> string -> (unit -> 'a) -> 'a
(** Mix a label into the keys of boxes built inside, without a box. *)

val key : box -> int

val rect : t -> box -> float * float * float * float
(** The box's screen rectangle from the previous frame. *)

val hit_rect : t -> box -> float * float * float * float

type signal = {
  hovered : bool;  (** topmost box under the pointer, or captured *)
  pressed : bool;  (** a press on this box began this frame *)
  held : bool;  (** holds pointer capture after this frame's events *)
  released : bool;  (** capture ended this frame *)
  clicked : bool;  (** left press and release both inside the hit rect *)
  double_clicked : bool;
  dragging : bool;  (** captured and the pointer moved this frame *)
  drag : float * float;  (** captured pointer motion this frame *)
  pointer : float * float;  (** latest pointer, screen space *)
  press_point : float * float;  (** where the current or last press began *)
  release_point : float * float;
  button : Prismel.Input.mouse_button option;
  scroll : float * float;  (** wheel steps routed to this box *)
  keys : Prismel.Event.t list;  (** ordered key/text events while focused *)
}

val signal : t -> box -> signal
val focused : t -> box -> bool
val focus : t -> box -> unit
val active : t -> box -> bool

val scroll_offset : t -> box -> float
val set_scroll_offset : t -> box -> float -> unit

(** Retained per-box scalar state for custom widgets. *)
val state : t -> box -> default:int -> int
val set_state : t -> box -> int -> unit
val text_state : t -> box -> string option
val set_text_state : t -> box -> string option -> unit

(** {1 Painting} *)

module Paint : sig
  type t

  val fill :
    t -> x:float -> y:float -> w:float -> h:float -> ?radius:float ->
    Prismel.Color.t -> unit
  (** Square fills cover exactly the pixels of the equivalent triangle
      rectangle; [radius > 0] is anti-aliased. *)

  val stroke :
    t -> x:float -> y:float -> w:float -> h:float -> ?width:float ->
    ?radius:float -> Prismel.Color.t -> unit
  (** A band of [width] centred on the rectangle's edges. *)

  val rect :
    t -> x:float -> y:float -> w:float -> h:float -> ?fill:Prismel.Color.t ->
    ?stroke:Prismel.Color.t -> ?radius:float -> unit -> unit

  val line :
    t -> from_:float * float -> to_:float * float -> ?width:float ->
    Prismel.Color.t -> unit
  (** Butt-capped; axis-aligned lines are exact rectangles. *)

  val circle :
    t -> at:float * float -> radius:float -> ?fill:Prismel.Color.t ->
    ?stroke:Prismel.Color.t -> unit -> unit

  val wire :
    t -> float * float -> float * float -> float * float -> float * float ->
    ?width:float -> Prismel.Color.t -> unit
  (** Cubic Bézier stroked on the GPU. *)

  val arc :
    t -> at:float * float -> radius:float -> from_:float -> to_:float ->
    ?width:float -> Prismel.Color.t -> unit

  val grid :
    t -> x:float -> y:float -> w:float -> h:float -> origin:float * float ->
    spacing:float -> ?dot:float -> Prismel.Color.t -> unit
  (** Dots every [spacing] points from [origin], drawn by one quad. *)

  val text :
    t -> at:float * float -> ?size:int -> ?color:Prismel.Color.t -> string ->
    unit
  (** Kit text with its top-left corner at [at]. Without [size] it uses the
      UI's own font; with [size] the kit face at that size. Inside a canvas
      the size is in screen points and glyphs stay on physical pixels. *)

  val text_width : t -> ?size:int -> string -> float

  val input_region :
    t -> ?cursor:float -> x:float -> y:float -> w:float -> h:float -> focused:bool -> unit -> unit
  (** Text-input metadata for on-screen keyboards and IME placement. [cursor]
      is the caret offset in the paint's local points. *)
end

val draw :
  t -> box -> (Paint.t -> float * float * float * float -> unit) -> unit
(** Paint with the box's final laid-out rectangle, before its children. In a
    canvas the rectangle is in canvas units. *)

val draw_over :
  t -> box -> (Paint.t -> float * float * float * float -> unit) -> unit
(** Paint after the box's children, outside its content clip. *)

val cached : t -> key:string -> stamp:int -> (unit -> unit) -> unit
(** Replay the boxes and painting this subtree produced for the same [stamp]
    last frame instead of rebuilding it. Only for non-interactive content:
    replayed boxes keep last frame's hover and pressed appearance. *)

(** {1 Layout helpers} *)

val row :
  t -> ?w:size -> ?h:size -> ?gap:float -> ?padding:float -> string ->
  (unit -> 'a) -> 'a

val col :
  t -> ?w:size -> ?h:size -> ?gap:float -> ?padding:float -> string ->
  (unit -> 'a) -> 'a

val splitter : t -> ?axis:axis -> ?thickness:float -> string -> float
(** A draggable divider; returns this frame's drag along [axis] (default
    [Row], a vertical divider moved horizontally). *)

(** {1 Kit widgets}

    A panel stacks rows of the PXUI design kit: 24-point rows, 3-point
    padding, a label column of 120–140 points, square controls, and the kit
    face. Widgets must be built inside a {!val-panel}. *)

val panel :
  t -> ?x:float -> ?y:float -> ?width:float -> ?max_height:float ->
  ?row_height:int -> ?padding:int -> string -> (unit -> 'a) -> 'a
(** A light panel at [(x, y)] (default [(12, 12)], width 280). Rows beyond
    [max_height] scroll with the wheel by one row per step. *)

val popup :
  t -> ?stroke:Prismel.Color.t -> ?max_height:float -> ?dismiss_initial:bool ->
  at:float * float -> width:float -> height:float -> string ->
  (unit -> 'a) -> 'a option
(** A floating panel dismissed by Escape, focus loss, or a press outside its
    last laid-out bounds. [height] supplies the first-frame hit area. *)

val modal : t -> ?width:float -> string -> (unit -> 'a) -> 'a option
(** A kit panel centered in the frame, outlined in the accent colour. Build it
    last, at the root level, so it is topmost. Escape, window focus loss, or a
    press outside it dismisses it: the builder is skipped and [None] is
    returned, so the host drops its open state. Keys still reach the host and
    focused children; the host decides what the modal blocks. *)

val label : t -> string -> unit
val button : t -> string -> bool
(** [true] on the frame a press and release both land inside the button. *)

val toggle : t -> string -> bool -> bool

val slider : t -> string -> range:float * float -> float -> float
(** The range is a soft drag range; values outside it are kept and may also
    be typed after double-clicking the label (Enter commits, Escape
    cancels). *)

val int_slider : t -> string -> range:int * int -> int -> int
val text_field : t -> string -> string -> string
val choice : t -> string -> string list -> int -> int
(** Press the left or right half to step through the options. *)

val range_slider :
  t -> string -> range:float * float -> float * float -> float * float

val xy :
  t -> string -> x_range:float * float -> y_range:float * float ->
  float * float -> float * float

type pick = [ `None | `Pick of int | `Delete of int | `Submit | `Back | `Cancel ]

val fuzzy_match : query:string -> string -> bool
(** Case-insensitive subsequence match. *)

val picker :
  t -> ?limit:int -> string -> query:string ->
  (string -> (string * string) array) -> string * pick
(** A focused search row (the label is its placeholder and key) over the
    [(label, detail)] rows for the current query, windowed to [limit] (default
    10) around the cursor. Rows are recomputed as typing changes the query, so
    indices refer to the rows of the returned query. Returns the edited query
    and at most one result: [`Pick] on Enter or a
    row click, [`Submit] on Enter with no rows, [`Delete] on a second Delete
    over the same (red, armed) row, [`Back] on Backspace or Left with an empty
    query, and [`Cancel] on Escape. Build it inside a panel or {!modal}. *)

val context_clicked : signal -> bool
(** A right press and release that moved less than 4 points: open a context
    menu rather than pan. *)

val context_menu :
  t -> at:float * float -> string -> (string * bool) list ->
  [ `Open | `Pick of int | `Dismiss ]
(** A floating menu at [at] with [(label, enabled)] rows. The host keeps it
    open while this returns [`Open]; a row commits on press and release inside
    it, and Escape, focus loss, or a press outside return [`Dismiss]. Build it
    last, at the root level. *)

val accordion :
  t -> ?expanded:bool -> ?set_expanded:bool -> string -> (unit -> 'a) ->
  'a option
(** A disclosure header. [expanded] is the initial state; [set_expanded]
    forces it this frame. Children are built, and their result returned, only
    while expanded. *)

val expanded : t -> string -> bool option
(** The retained state of an accordion built in the current parent. *)

(** {1 Measurements} *)

val row_height : t -> int
val panel_padding : t -> int
