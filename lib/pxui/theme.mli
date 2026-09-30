(** The PXUI design kit: palette and typography shared by every PXUI host. *)

type t = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

val default : t

(** Default text size in logical points. *)
val font_size : int

(** Derived kit colors. *)
val muted : t -> Prismel.Color.t
val border : t -> Prismel.Color.t
val faint_border : t -> Prismel.Color.t
val hover_fill : t -> Prismel.Color.t
val pressed_fill : t -> Prismel.Color.t
val invalid : Prismel.Color.t

type ports = {
  geometry : Prismel.Color.t; float : Prismel.Color.t; int : Prismel.Color.t;
  vec3 : Prismel.Color.t; bool : Prismel.Color.t; compound : Prismel.Color.t;
  output : Prismel.Color.t; hint : Prismel.Color.t;
  text : Prismel.Color.t; fn : Prismel.Color.t; record : Prismel.Color.t;
}
val ports : t -> ports
(** [text], [fn] (diamond socket) and [record] colour the workspace types; a
    list draws its element colour on a stacked socket. *)

(** Zone tokens of the graph pane: [fill] tints the region, [edge] is its
    border, [dashed] draws the border as dashes (functions and [let*] scopes
    are hollow, a [fn] zone keeps a faint tint). *)
type zone = { fill : Prismel.Color.t; edge : Prismel.Color.t; dashed : bool }
val zone_for : t -> zone
val zone_fold : t -> zone
val zone_sum : t -> zone
val zone_fn : t -> zone
val zone_let : t -> zone

val dark : t -> bool
(** The panel is a dark colour. *)
