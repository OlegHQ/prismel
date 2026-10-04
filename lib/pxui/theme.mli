(** The PXUI design kit: palette and typography shared by every PXUI host. *)

type t = {
  panel : Rays.Color.t;
  foreground : Rays.Color.t;
  control : Rays.Color.t;
  input : Rays.Color.t;
  track : Rays.Color.t;
  accent : Rays.Color.t;
}

val default : t

(** Default text size in logical points. *)
val font_size : int

(** Derived kit colors. *)
val muted : t -> Rays.Color.t
val border : t -> Rays.Color.t
val edge : t -> Rays.Color.t
(* hairline for structure: separators, pane headers, window frames *)
val sheen : t -> Rays.Color.t
(* near-white line inside the top edge of a sheet *)
val faint_border : t -> Rays.Color.t
val hover_fill : t -> Rays.Color.t
val pressed_fill : t -> Rays.Color.t
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
