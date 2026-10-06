(** Axis-aligned 2D bounds. *)

type t = private {
  min : Vec2.t;
  max : Vec2.t;
}

val make : min:Vec2.t -> max:Vec2.t -> t
val corners : t -> Vec2.t list
