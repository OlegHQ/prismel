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
}
val ports : t -> ports
