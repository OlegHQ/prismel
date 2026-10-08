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
    key but not displayed; [###id] replaces the label in the key) together with the
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
    [Rays.Assets]: thread it through the model and call {!destroy} from
    [Sketch.run_state ~on_stop]. *)

type t

val create : ?theme:Theme.t -> ?font:Rays.Font.t -> ?font_size:int -> unit -> t
(** [font] (borrowed) overrides the kit face; [font_size] is the logical size
    of kit text. *)

val destroy : t -> unit
(** Release the glyph atlas and the kit faces this UI loaded. The handle must
    not be used afterwards. *)

val theme : t -> Theme.t
val set_theme : t -> Theme.t -> unit
val font_size : t -> int

val set_font_size : t -> int -> unit
(** The kit text size from the next frame on, and the row height with it ([max 24 (size + 11)]:
    24-point rows up to the default 13 points).  Call it between frames, never inside {!frame}. *)

(** {1 Frames} *)

val frame : t -> Rays.Frame.t -> (t -> 'a) -> 'a
(** Route the frame's ordered events, run the builder, lay out, and paint.
    Tab/Shift-Tab traverse visible focusable boxes in presentation order,
    restricted to an open popup. Enter/Space activate controls; arrows adjust
    choices, sliders and XY controls, Home/End set slider bounds. Shift makes
    slider steps ten times larger. Enter opens numeric entry; Enter commits
    and Escape cancels it. Range controls use Enter/Space to switch handles.
    Kit controls take keyboard focus through Tab; text-entry controls also
    focus on a pointer press. *)

val input : ?owner:int -> t -> Rays.Frame.t
(** After {!frame}, the ordered events not consumed by UI controls, plus
    events captured by the exact [owner] box key (e.g. a viewport root).
    Children of [owner] retain their events. Held keys, buttons and motion
    follow the same ownership; release or disappearance cancels an excluded
    gesture. An explicit nonzero [owner] excludes unowned pointer events;
    omitting it retains unconsumed pointer events. Focus-loss and pointer
    cancellation always pass through. *)

val scene : ?under:(int -> Rays.Scene.t) -> t -> Rays.Scene.t
(** The most recently completed frame, including text-input regions.
    [under] inserts a host scene immediately before a floating root's paint,
    addressed by its box key. This keeps native viewport content in panel order. *)

val wants_pointer : t -> bool
(** The pointer was over a UI box, or a box holds pointer capture. *)

val cursor : t -> [`Horizontal_resize|`Vertical_resize|`Text] option
val request_cursor : t -> [`Horizontal_resize|`Vertical_resize|`Text] -> unit
(** Cursor requested by a hovered or captured PXUI control: a resize edge, or
    the I-beam over a text field or text area. The last request of a frame
    wins. *)

val key_pressed : t -> Rays.Input.key -> bool
(** The key was pressed in this frame's events (a dialog's Enter). *)

val text_input_focused : t -> bool
(** A focused control owns keyboard input (including text and numeric entry).
    Hosts suppress their shortcuts while a control owns it. *)

val passed_undo : t -> [`Undo | `Redo] option
(** Command-Z or Shift-Command-Z (Command-Y) pressed in the focused text last frame while
    its own stack was empty: the host runs its document undo or redo instead. *)

val ellipsis : width:(string -> float) -> limit:float -> string -> string
(** [label] cut to [limit] points (measured by [width], e.g. [Paint.text_width paint]) with an
    ellipsis, on a character boundary: a row label that stops short of its right-hand detail.
    [width] is the sum of a text's characters, each measured once up to the cut: the cost follows
    what is shown, not the label's length. *)

val unfocus : t -> unit

val dismiss_popup : t -> unit
(** When the host closes a popup after accepting its result, release focus
    and capture. Its current frame remains consumed; next frame is unblocked. *)

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
    [focusable] boxes take keyboard focus when pressed or traversed with Tab;
    their signals click on Enter/Space; [scroll] boxes receive
    wheel events and scroll their children vertically; [clip] clips children
    to the padded content rectangle; [blocking] boxes consume hover and
    presses so boxes below them do not receive them. *)
type flags

val none : flags
val clickable : flags
val focusable : flags
val tab_stop : flags
(** Keyboard traversal focus for a control whose pointer interaction leaves
    keyboard input with its host. Escape relinquishes this keyboard focus. *)

val tab_stop_marked : flags
(** {!tab_stop} for a control that draws its own keyboard mark (the accent line under a button,
    {!Ui.focused}): the engine strokes no ring round it. *)

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

val set_at : t -> box -> at:float * float -> unit
(** Move an already built, absolutely positioned box before layout runs. *)

val within : t -> box -> (unit -> 'a) -> 'a
(** Build children of [box]. *)

val scope : t -> string -> (unit -> 'a) -> 'a
(** Mix a label into the keys of boxes built inside, without a box. *)

val key : box -> int

val rect : t -> box -> float * float * float * float
(** The box's screen rectangle from the previous frame. *)

val hovered_within : t -> box -> bool
(** The box or a hit descendant owns hover in the shared hit tree. *)

(** {1 Carry}

    A payload in flight: a [kind] and a [value], both strings (a Flow value such as
    [(ref cobalt)] and what sort of graph it names).  The hit list and the single capture
    are unchanged: while a box owns the press, {!val-drop_target} lets any other box see that it
    is the one under the pointer and what is held.  Nothing is built or painted on frames
    without a payload. *)

type payload = { kind : string; value : string }

type drop =
  | Hover of payload  (** the pointer is over the box while a payload is held *)
  | Dropped of payload  (** the payload was released over the box, this frame only *)

val carry : t -> ?from:box -> kind:string -> value:string -> unit -> unit
(** Hold a payload.  With [from], the box that owns the pressed left button: it is held once
    the pointer has moved 4 points from the press, so a widget calls it every frame while
    pressed.  Without [from] (a key) it is held at once, with no capture; then a left press
    is the put, on the box under it, and nothing else sees that press. *)

val carrying : t -> payload option
(** The payload in flight; [None] after a release, a pointer cancellation or a focus loss
    ({!val-drop_target} reports a release for that one frame). *)

val cancel_carry : t -> unit
(** Forget the payload: the host cancelled (Escape) or finished a carry it started. *)

val drop_target : t -> box -> drop option
(** [Hover] while a payload is held and the topmost box under the pointer is [box] or inside
    it; [Dropped] on the frame the pointer released it there.  A box takes the pointer
    ({!clickable}, {!blocking} ...) to be found.  The ghost that follows the pointer is
    painted by {!frame} above every root (including popups), never hit. *)

val hover_delay : t -> key:string -> bool
(** Call for the current hovered target during the builder. True after
    380 ms of pointer rest; movement, a target change, a skipped frame,
    capture, a popup or focus loss resets the single timer. *)

val tooltip : ?shortcut:string -> t -> key:string -> text:string -> unit
(** Delayed, noninteractive overlay using {!hover_delay}. Call only for the
    current hovered target. It does not change focus or pointer ownership. *)

val last_press_within : t -> Rays.Frame.t -> int list -> int option
(** Last root key pressed in [frame], using PXUI's previous hit tree.
    The keys come from [key] on pane roots; a press on any child counts. *)

type signal = {
  hovered : bool;  (** topmost box under the pointer, or captured *)
  pressed : bool;  (** a press on this box began this frame *)
  subtree_press : int option;
  (** Ordinal of the last press on this box or any hit descendant this frame. *)
  held : bool;  (** holds pointer capture after this frame's events *)
  released : bool;  (** capture ended this frame *)
  clicked : bool;  (** left press and release both inside the hit rect *)
  double_clicked : bool;
  clicks : int;
  (** on the frame of a left press: 1, or 2 and 3 for the second and third press within
      0.35 s and 5 points (a double and a triple click); 0 otherwise *)
  dragging : bool;  (** captured and the pointer moved this frame *)
  drag : float * float;  (** captured pointer motion this frame *)
  pointer : float * float;  (** latest pointer, screen space *)
  press_point : float * float;  (** where the current or last press began *)
  release_point : float * float;
  button : Rays.Input.mouse_button option;
  scroll : float * float;  (** wheel steps routed to this box *)
  pinch : float;
  (** product of the trackpad pinch factors routed to this box this frame
      (the box under the pointer, like the wheel): above 1 zooms in, 1 when
      there was none *)
  keys : Rays.Event.t list;  (** ordered key/text events while focused *)
}

val signal : t -> box -> signal
val key_events : t -> box -> (Rays.Event.t * Rays.Input.key list) list
(** The focused key/text events paired with their event-time held keys.
    Use this for custom controls that interpret Shift, Command or Control. *)

val press_keys : t -> box -> Rays.Input.key list
(** Held keys at this box's captured press, retained through release. *)

val focused : t -> box -> bool
val focus : t -> box -> unit
val active : t -> box -> bool

val scroll_offset : t -> box -> float
(* Current painted scroll position, including elastic edge movement. *)
val scroll_position : t -> box -> float
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
    Rays.Color.t -> unit
  (** Square fills cover exactly the pixels of the equivalent triangle
      rectangle; [radius > 0] is anti-aliased. *)

  val stroke :
    t -> x:float -> y:float -> w:float -> h:float -> ?width:float ->
    ?radius:float -> Rays.Color.t -> unit
  (** A band of [width] centred on the rectangle's edges. *)

  val frame :
    t -> x:float -> y:float -> w:float -> h:float -> ?width:float -> ?radius:float ->
    Rays.Color.t -> unit
  (** A border drawn inside the box, as CSS draws one: [stroke] centres its band on the edge, so
      a caller handing it the box of a frame ends half a [width] outside; [frame] insets by half a
      [width], so a 1-point border covers exactly the box's outermost whole point.  The one way to
      frame a box. *)

  val rect :
    t -> x:float -> y:float -> w:float -> h:float -> ?fill:Rays.Color.t ->
    ?stroke:Rays.Color.t -> ?radius:float -> unit -> unit

  val line :
    t -> from_:float * float -> to_:float * float -> ?width:float ->
    Rays.Color.t -> unit
  (** Butt-capped; axis-aligned lines are exact rectangles. *)

  val circle :
    t -> at:float * float -> radius:float -> ?fill:Rays.Color.t ->
    ?stroke:Rays.Color.t -> unit -> unit

  val wire :
    t -> float * float -> float * float -> float * float -> float * float ->
    ?width:float -> Rays.Color.t -> unit
  (** Cubic Bézier stroked on the GPU. *)

  val grid :
    t -> x:float -> y:float -> w:float -> h:float -> origin:float * float ->
    spacing:float -> ?dot:float -> Rays.Color.t -> unit
  (** Dots every [spacing] points from [origin], drawn by one quad. *)

  val text :
    t -> at:float * float -> ?size:int -> ?tracking:float -> ?color:Rays.Color.t -> string ->
    unit
  (** Kit text with its top-left corner at [at]. Without [size] it uses the
      UI's own font; with [size] the kit face at that size. Inside a canvas
      the size is in screen points and glyphs stay on physical pixels.
      [tracking] adds points between glyphs. *)

  val text_width : t -> ?size:int -> string -> float

  (** {2 Kit marks}  The label style and the five shapes of the kit
      ([specification/pxui.md], Design kit). *)

  val label_size : t -> int
  (** The label size: two points under the kit text. *)

  val cap : t -> at:float * float -> ?color:Rays.Color.t -> string -> unit
  (** A label: upper case at {!label_size} with 0.08 em of tracking, ink-2 by default.
      Sections, headers, units. *)

  val cap_width : t -> string -> float
  (** The width of {!cap}: the tracking follows every letter but the last. *)

  val chevron : t -> at:float * float -> [ `Down | `Up | `Left | `Right ] -> Rays.Color.t -> unit
  (** A chevron centred at [at]: strokes 7 by 3.5 points, 9 by 5.5 of ink with the line. *)

  val brackets :
    t -> x:float -> y:float -> w:float -> h:float -> ?offset:float -> ?length:float ->
    ?width:float -> Rays.Color.t -> unit
  (** Corner brackets [offset] (default 4) outside the rectangle: the selected object. *)

  val dashed : t -> from_:float * float -> to_:float * float -> ?width:float -> Rays.Color.t -> unit
  val dashed_rect : t -> x:float -> y:float -> w:float -> h:float -> Rays.Color.t -> unit
  (** 4 on, 3 off: a zone, a drop target. *)

  val cross : t -> x:float -> y:float -> w:float -> h:float -> Rays.Color.t -> unit
  (** A hairline box crossed corner to corner: nothing displayed, a missing input. *)

  val hatch : t -> x:float -> y:float -> w:float -> h:float -> Rays.Color.t -> unit
  (** Diagonal hairlines clipped to the rectangle: bypassed, stale, cooking. *)

  val flag : t -> at:float * float -> ?round:bool -> bool -> unit
  (** An outline flag centred at [at]: 12 points, the input fill, a line-3 edge inside the box and,
      when on, a 6-point mark in ink-2; square, or [round] for the columns after the first. *)

  val progress : t -> x:float -> y:float -> ?w:float -> ?h:float -> float -> unit
  (** A progress bar, 96 by 8 by default: hatched with a line-3 edge, and the done fraction a
      bar in ink one point inside the edge. *)

  val ratio : t -> at:float * float -> int -> int -> unit
  (** The ratio of a splitter being dragged, [first / second], as an accent label with no box. *)

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

val to_front : t -> ?order:int -> box -> unit
(* Raise a root box and its children above ordinary boxes, below modal popups.
   Higher [order] values paint later; equal values retain their order of calls. *)

val table : t -> at:float * float -> w:float -> h:float -> headers:string array ->
  rows:int -> cell:(int -> int -> string) -> string -> int option * signal
(** Read-only table with a fixed 24-point header and rows, hairlines and
    right-aligned values. Only visible rows request cells or build hit boxes.
    Returns a clicked row index and the body's shared scroll signal. *)

(** {1 Layout helpers} *)

val row :
  t -> ?w:size -> ?h:size -> ?gap:float -> ?padding:float -> string ->
  (unit -> 'a) -> 'a

val col :
  t -> ?w:size -> ?h:size -> ?gap:float -> ?padding:float -> string ->
  (unit -> 'a) -> 'a

(** {1 Kit widgets}

    A panel stacks rows of the PXUI design kit (rev 3): 24-point rows with 12 points
    at each side, a label column (0.3 of the panel less 16, for inspector rows), 20-point controls and the kit face.
    A field is a value on a hairline, a button is its text; nothing has a radius
    or an ink fill. Widgets must be built inside a {!val-panel}. *)

val panel :
  ?window:bool -> t -> ?x:float -> ?y:float -> ?width:float -> ?height:float -> ?max_height:float ->
  ?row_height:int -> ?padding:int -> string -> (unit -> 'a) -> 'a
(** A light panel at [(x, y)] (default [(12, 12)], width 280). [height]
    fills a fixed pane; otherwise content sets the height. Rows beyond the
    height or [max_height] use the shared elastic scroll.  [window] lays inspector rows and heads
    out as a floating window's (label at 12, 88-point column, no pin slot, a 20-point title). *)

val inspector_row :
  t -> ?width:float -> ?pin:bool -> key:string -> label:string -> unit ->
  box * float * float * float
(** An inspector row of the kit's inspector sheet and the local x, y, width of its value control
    (always 20 high at y 2): 12 of padding, a 6-point slot for the pin dot (drawn when [pin] is
    given: filled ink for a row on its card, an ink-3 ring for one that is not), 8, the label column
    (0.3 of the panel less 16 points: 98 at 380 wide, 80 at 320), 8, the control to 12 from the
    right edge.  A long label ellipsizes in its column.  The hovered row has the line-1 fill. *)

val inspector_label_x : t -> float
(** Where an inspector row's label starts: 26 (after the pin slot), 12 in a window. *)

val inspector_width : t -> float
(** The width of the panel being built: what an inspector row lays its columns out in. *)

val inspector_section :
  t -> key:string -> ?expanded:bool -> ?set_expanded:bool ->
  string -> (unit -> 'a) -> 'a option
(** A collapsible inspector section. *)

val inspector_toggle : t -> ?pin:bool -> key:string -> label:string -> bool -> bool
(** A switch row: the switch sits at the start of the control column. *)

val inspector_toggle_value : t -> key:string -> at:float * float -> bool -> bool
(** The value control inside an inspector row. *)

type head_action = { caption : string; keycap : string; active : bool; usable : bool }
(** A text button of an inspector head: its label, its key in ink-3, whether it is on (the control
    fill) and whether it can be pressed. *)

type head = { renamed : string; chosen : int option; reset_pressed : bool }
(** What a head reports for a frame: the name as edited, the index of the pressed action, and
    whether the trailing [reset] button was pressed. *)

val inspector_header :
  t -> key:string -> ?kind:string -> ?badge:string -> ?index:string ->
  ?rename:(string -> bool) -> ?actions:head_action list -> ?reset:string -> ?reset_enabled:bool ->
  title:string -> detail:string -> unit -> head
(** The head block of an inspector: a chips row ([kind] in ink-2, [badge] in the accent, [index]
    at the right in ink-3), the name at the display size (edited in place when [rename] accepts
    names), one detail line in ink-2, a row of text [actions] and a bare [reset] button at the
    right (ink-3 and inert when [reset_enabled] is false: nothing to reset), then a line-2 hairline. *)

val inspector_body : t -> (unit -> 'a) -> 'a
(** The part of an inspector under its head: a column filling the rest of the panel that scrolls
    on its own (the head stays), with a 4-point line-3 thumb 2 points from the right edge. *)

val inspector_bar : t -> hints:(string * string) list -> count:int -> unit
(** The bar under an inspector body: a line-2 hairline, then a 24-point bar of [hints] (a key in
    ink-3 at the label size, what it does in ink-2) and at the right a dot and "[count] on card". *)

val inspector_button : t -> key:string -> string -> bool
(** A full-width action row with the inspector's spacing and colors. *)

val inspector_readout :
  t -> ?width:float -> key:string -> label:string -> string -> unit
(** A read-only value in the same responsive inspector row. *)

val inspector_message : t -> key:string -> string -> unit
(** A short muted inspector note, clipped to the available width. *)

val popup :
  t -> ?stroke:Rays.Color.t -> ?max_height:float -> ?dismiss_initial:bool -> ?attached:bool ->
  ?keep:(float * float * float * float) list ->
  at:float * float -> width:float -> height:float -> string ->
  (unit -> 'a) -> 'a option
(** A floating panel dismissed by Escape, focus loss, or a press outside its
    last laid-out bounds. [height] supplies the first-frame hit area.
    Build it before the body it shields; it paints on top and consumes
    underlying input, including its opening/dismissal frame.  An [attached] popup (a submenu,
    built after the popup it belongs to) shares that popup's events and is never dismissed by
    itself; the owner passes the rectangles of its attached popups as [keep] so that a press
    in one of them is not a press outside. *)

val modal : t -> ?width:float -> string -> (unit -> 'a) -> 'a option
(** A kit panel centered in the frame, outlined in the accent colour. Build it
    before the body it shields, at the root level; it paints on top. Escape, window focus loss, or a
    press outside it dismisses it: the builder is skipped and [None] is
    returned, so the host drops its open state. Keys still reach the host and
    focused children. It consumes underlying input even when opening or
    closing in this frame; {!val-input} still delivers cancellation. *)

val label : t -> string -> unit
(** A window's title or a panel's caption: ink-2 capitals 12 points from the left, with 4 points
    above it when it is the first thing of its parent. *)

val footer : t -> ?right:string -> (string * string) list -> unit
(** A window's foot: a line-2 hairline, then [(key, what it does)] pairs (the key in ink-3, the text
    in ink-2) and [right], a count as a label, at the end. *)

val button :
  t -> ?key:string -> ?primary:bool -> ?on:bool -> ?disabled:bool -> ?bare:bool -> ?icon:bool ->
  ?at_end:bool -> ?ink:Rays.Color.t -> string -> bool
(** [true] on the frame a press and release both land inside the button. A button is its text
    (kit rev 3): [key] is the shortcut shown after it in ink-3, [primary] outlines the one
    button of a panel, [on] fills a button that is switched on, [disabled] greys it and makes it
    inert.  [bare] narrows the padding to 4 points (a button in a head); [icon] makes it the
    20-point square with its glyph (a [x], [+], [<]) centred; [at_end] puts the box at the row's end,
    8 points from the edge; [ink] colours the text.  The keyboard focus is an accent line over the
    last row of the box. *)

val paint_button_ground :
  Paint.t -> Theme.t -> held:bool -> hovered:bool -> on:bool -> primary:bool ->
  float * float * float * float -> unit
(** The ground {!button} paints (fill on press, hover or [on]; a line-3 edge for [primary]) over a
    rectangle, so a button placed by hand looks the same. *)

val message : t -> ?error:bool -> key:string -> string -> unit
(** A message row: a 6-point dot (accent, or the error ink with [error]) and the text, wrapped to
    the parent's width on lines of 20 points with 4 above and below (28 high for one line). *)

val toggle : t -> ?disabled:bool -> string -> bool -> bool

val slider : t -> ?disabled:bool -> string -> range:float * float -> float -> float
(** The range is a soft drag range; values outside it are kept and may also
    be typed after double-clicking the label (Enter commits, Escape
    cancels). *)

val int_slider : t -> ?disabled:bool -> string -> range:int * int -> int -> int
val text_field : t -> ?disabled:bool -> ?placeholder:string -> ?invalid:string -> string -> string -> string
(** A single-line field.  Every text widget edits as macOS does: a click places the caret and
    Shift-click or a drag extends the selection, a double click selects the word (a triple the
    line), Option-arrows move by words and Command-arrows (or Home/End) by lines, each with
    Shift extending, Option-Backspace/Delete take a word and Command-Backspace/Delete the line
    to the caret, Command-A/C/X/V select all, copy, cut and paste, and Command-Z and
    Shift-Command-Z (or Command-Y) undo and redo the focused text (consecutive typing is one
    step; the stack is dropped when the focus or the value changes from outside).  An empty field
    shows [placeholder] in ink-3; with [invalid] (the reason) the underline and the value take the
    error ink and a 24-point row under the field says why, in 11 points. *)

type completion = {
  replace : int * int;  (** the byte span [insert] replaces *)
  insert : string;
  label : string;  (** the row *)
  detail : string;  (** the row's right column: a type, a category *)
  doc : string;  (** one line under the rows while the row is selected *)
}
(** One ranked suggestion of {!language.complete}. *)

type language = {
  colorize : string -> (int * int * Rays.Color.t) list;
      (** sorted, non-overlapping byte spans and their colour; the rest is the foreground *)
  brackets : string -> (int * int) list;
      (** the matched bracket pairs as (open, close) byte positions: the pair at the caret is lit *)
  indent : string -> int -> string;
      (** [indent text caret]: the indentation Enter puts after the line break at [caret] *)
  pairs : (char * char) list;
      (** brackets typed in pairs: the opener wraps the selection or inserts both, the closer
          typed before itself steps over it, Backspace between an empty pair takes both *)
  complete : string -> int -> completion list;
      (** [complete text caret]: the ranked suggestions for the token ending at [caret], best
          first; [[]] shows nothing.  Typing opens the popup under the caret; Up/Down choose,
          Tab, Enter or a click accept, Escape closes it *)
  describe : string -> int -> (int * int * string) option;
      (** [describe text byte]: the token at [byte] and its description, shown as a tooltip
          after the pointer rests on it *)
  number_at : string -> int -> (int * int) option;
      (** [number_at text byte]: the numeric literal at [byte]; dragging it sideways changes
          the value in place (see [on_scrub] of {!text_area_submit}) *)
  rewrite : (string -> int -> string * int) option;
      (** [rewrite text caret], run after every frame that edited the text: the text as the
          language keeps it (parinfer infers the closing brackets from indentation) and where
          [caret] lands in it; the anchor of a selection maps the same way *)
}
(** What a code editor knows about its text.  A host supplies one (the editor's Lisp);
    {!text_area} itself is language-free. *)

val text_area :
  t -> at:float * float -> w:float -> h:float -> ?readonly:bool ->
  ?errors:int list -> ?spans:(int * int) list -> ?reveal:int -> ?language:language ->
  string -> string -> string
(** [text_area ui ~at ~w ~h label text] is a scrolling multiline editor with a
    line-number gutter, returning the edited text. It shares [text_field]'s
    focus, IME composition, clipboard, caret, selection and undo code; Enter inserts a line,
    Up/Down keep the column, Page Up/Down move by a page, Command-Up/Down go to the ends of
    the text, Home/End and Command-Left/Right are row-scoped, Escape leaves it.
    [readonly] keeps the caret and selection (copy works) but never changes
    the text. [errors] are 1-based lines marked in the gutter, [spans] byte
    ranges tinted (a marked selection), and [reveal] a byte offset scrolled into
    view once each time it or the text length changes. The value lives in the caller's model. *)

val text_area_submit :
  t -> at:float * float -> w:float -> h:float -> ?readonly:bool -> ?wrap:bool ->
  ?errors:int list -> ?messages:(int * (int * int) option * string) list -> ?spans:(int * int) list -> ?reveal:int -> ?language:language ->
  ?on_context:(float * float -> unit) -> ?on_scrub:([ `Live | `Done ] -> unit) ->
  ?on_scrub_edit:(int * int -> string -> unit) ->
  ?on_click:(int -> bool -> unit) -> ?on_caret:(int -> unit) -> ?on_drop:(int -> drop -> unit) ->
  ?chips:(int * int * Rays.Color.t) list ->
  string -> string -> string * bool
(** {!text_area} that also reports Command- or Ctrl-Enter pressed in it this frame (the host's
    "apply").  Tab inserts two spaces and Shift-Tab takes up to two leading spaces off the line
    (the editor keeps Tab instead of moving the focus).  With [wrap] a long line continues on
    the next row, so nothing scrolls sideways; the gutter numbers logical lines and [errors] are
    logical lines.  A [messages] entry (1-based line, the wrong byte span, the text) is a row of its
    own in the error colour under that line, with the span underlined.  [language] colours the text, lights the bracket pair at the caret, indents
    after Enter, pairs brackets, completes the token at the caret and describes the token under
    the pointer; [on_context] is called with the pointer when the area is right-clicked (the
    host opens its menu).  A numeric literal of the language dragged sideways follows the
    pointer (a float by a tenth of its last decimal place per point, an integer by one per five
    points, Shift ten times faster): [on_scrub `Live] is called on each frame the returned text
    changed that way and [on_scrub `Done] when the drag ends, so a host can apply the text live
    and merge the drag into one history entry. [on_scrub_edit (start, finish) replacement]
    reports the token's byte range before replacement on each live scrub, so a host can
    edit its syntax without reparsing the whole text. [on_click byte command] is called when the area is
    left-clicked at byte offset [byte] without a drag, [command] being true when Command or Ctrl is
    held; [on_caret] receives the caret offset each frame the area has focus;
    [on_drop byte drop] is called while a payload ({!val-carry}) is held over the area, with the byte
    offset under the pointer and whether it is hovering or was released there; [chips] are byte
    ranges underlined with a colour bar (a colour literal shows its colour). *)

val value_field : t -> at:float * float -> w:float -> h:float ->
  ?size:int -> ?display:string -> ?fraction:float ->
  ?slide:(float -> string) ->
  ?scrub:(string -> float -> bool -> string) -> ?left:bool -> ?edit:bool ->
  ?lead:string * Rays.Color.t -> ?trail:string * Rays.Color.t -> ?line:Rays.Color.t ->
  ?bare:bool -> ?placeholder:string -> ?tracking:float -> valid:(string -> bool) ->
  string -> string -> string * bool
(** Compact field. Numeric sliders follow the pointer with [slide]; Option-click, a
    double-click or [edit] opens text entry. [scrub] handles fields without a track.
    [left] aligns text values to the left (default false for numeric fields).
    [lead] and [trail] frame the value at the left and right with 6 points between (an
    expression's ƒ and its live value); [line] is the idle hairline's colour (an expression's port
    colour); [bare] leaves the hairline out until the field is edited or invalid; [placeholder] is
    shown in ink-3 where an empty value would be.
    Only valid text commits; the boolean reports an open text editor. *)

val choice : t -> ?disabled:bool -> string -> string list -> int -> int
(** A field showing the current option; a click opens the options as the kit's menu (accent
    underline and a chevron up while open, the menu a point under the field and as wide, the
    current option marked with the accent square) and picking one returns it.  The arrow keys
    step through the options. *)

val range_slider :
  t -> string -> range:float * float -> float * float -> float * float

val xy :
  t -> string -> x_range:float * float -> y_range:float * float ->
  float * float -> float * float

type pick = [ `None | `Pick of int | `Delete of int | `Submit | `Back | `Cancel ]

val fuzzy_match : query:string -> string -> bool
(** Case-insensitive subsequence match. *)

val picker :
  t -> ?limit:int -> ?mark:(int -> Rays.Color.t option) -> ?off:(int -> bool) -> ?slash:bool -> ?at_rest:bool ->
  string -> query:string ->
  (string -> (string * string) array) -> string * pick
(** A focused search row (the label is its placeholder and key) over the
    [(label, detail)] rows for the current query, windowed to [limit] (default
    10) around the cursor. Rows are recomputed as typing changes the query, so
    indices refer to the rows of the returned query. Returns the edited query
    and at most one result: [`Pick] on Enter or a
    row click, [`Submit] on Enter with no rows, [`Delete] on a second Delete
    over the same (red, armed) row, [`Back] on Backspace or Left with an empty
    query, and [`Cancel] on Escape. [mark] gives a row its type square.  An [off] row (one that
    cannot be chosen here) reads in ink-3 whole, square included, and neither Enter nor a click
    picks it.  With [at_rest] the field keeps the keyboard but looks at rest (a hairline, no caret) until
    something is typed in it.  Build it inside a panel or {!modal}. *)

val context_clicked : signal -> bool
(** A right press and release that moved less than 4 points: open a context
    menu rather than pan. *)

type submenu = {
  row : int;  (** the row of the menu that opens it (drawn with a chevron) *)
  rows : (string * bool) list;
  keys : string list;
  current : int option;  (** the row marked with the accent square *)
}

val context_menu :
  t -> at:float * float -> ?width:float -> ?selected:int -> ?swatches:Rays.Color.t option list ->
  ?keys:string list -> ?danger:int list -> ?submenus:submenu list -> ?lead_from:int -> ?dismiss_initial:bool -> string ->
  (string * bool) list ->
  [ `Open | `Pick of int | `Dismiss ]
(** A floating menu at [at] with [(label, enabled)] rows, as wide as its longest
    row and at least [width] wide, capped to the frame. An empty label is a separator
    line (never picked). [selected] marks the current choice; [swatches] gives a row a small colour square
    before its label. The host keeps it
    open while this returns [`Open]; a row commits on press and release inside
    it, and Escape, focus loss, or a press outside return [`Dismiss]. Build it
    before content it shields; it floats at the root regardless of its parent.
    [keys] are the shortcuts in ink-2 at the right; [danger] rows (a delete) read in the error ink.
    A row named by a {!submenu} has a chevron and, while the pointer is on it, opens a second menu
    overlapping the first by a point, level with the row; the rows of the submenus are numbered after
    those of the menu, in the order the submenus are given.  With [selected], the rows from
    [lead_from] (default 0) on keep a slot for the accent square before their label.  A press outside the menu in the frame
    that first builds it dismisses it, unless [dismiss_initial] is false (the press that opened it). *)

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

val text_top : t -> ?size:int -> float -> float -> float
(** [text_top ui ?size y h]: where the top of kit text of [size] points goes to sit centred in a
    row at [y] of height [h].  Every row, bar and field places its text with this one rule. *)

val text_width : t -> ?size:int -> string -> float
(** The width of kit text in points, for layout during the build ({!Paint.text_width} while painting). *)

val view_size : t -> float * float
(** The frame being built, in points. *)

val text_line_height : t -> int
(** The pitch of a line in {!text_area}: one and a half times the text size (17 points at 11,
    20 at 13), as code editors set it; a control's row is {!row_height}. *)
