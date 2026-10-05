(** The PXUI design kit: palette and typography shared by every PXUI host. *)

type t = {
  panel : Rays.Color.t;
  foreground : Rays.Color.t;
  control : Rays.Color.t;
  input : Rays.Color.t;
  track : Rays.Color.t;
  accent : Rays.Color.t;
  ink_ground : Rays.Color.t option;
      (** the ground the inks blend against when it is not [panel] (a window sheet paints [input]
          as [panel] and keeps the inks of the ground); [None] means [panel] *)
}

val default : t

(** Type sizes in logical points: body (the default kit text), the upper-case label, a window
    title or viewport readout, and the selected thing's name (once per panel). *)
val font_size : int
val label_size : int
val title_size : int
val display_size : int

(** Derived kit colours.  Text: the foreground, [ink_2] for labels and secondary text (4.8:1 on
    the panel) and [ink_3] for disabled text, placeholders and keys.  [muted] is [ink_2]. *)
val ink_2 : t -> Rays.Color.t
val ink_3 : t -> Rays.Color.t
val muted : t -> Rays.Color.t

(** Lines, the foreground at 30, 15 and 8 percent: [border] (line-3) for the one outlined
    button and switches, [edge] (line-2) between panes and under fields, [faint_border]
    (line-1) inside a list. *)
val border : t -> Rays.Color.t
val edge : t -> Rays.Color.t
val faint_border : t -> Rays.Color.t

(** Fills: hover, pressed, and the accent wash of a text selection or a dock target.  The
    current row and an active button are [control]. *)
val hover_fill : t -> Rays.Color.t
val pressed_fill : t -> Rays.Color.t
val tint : t -> Rays.Color.t
val invalid : Rays.Color.t

type ports = {
  geometry : Rays.Color.t; float : Rays.Color.t; int : Rays.Color.t;
  vec3 : Rays.Color.t; bool : Rays.Color.t; compound : Rays.Color.t;
  output : Rays.Color.t; hint : Rays.Color.t;
  text : Rays.Color.t; fn : Rays.Color.t; record : Rays.Color.t;
}
val ports : t -> ports
(** [text], [fn] (diamond socket) and [record] colour the workspace types; a
    list draws its element colour on a stacked socket. *)

(** Zone tokens of the graph pane: [fill] tints the region, [edge] is its
    border, [dashed] draws the border as dashes (functions and [let*] scopes
    are hollow, a [fn] zone keeps a faint tint). *)
type zone = { fill : Rays.Color.t; edge : Rays.Color.t; dashed : bool }
val zone_for : t -> zone
val zone_fold : t -> zone
val zone_sum : t -> zone
val zone_fn : t -> zone
val zone_let : t -> zone

val dark : t -> bool
(** The panel is a dark colour. *)
