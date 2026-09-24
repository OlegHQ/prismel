(** Immutable facts about one sketch frame. *)

type t = {
  width : int;
  height : int;
  size : int * int;
  (** Logical window dimensions used by scenes and pointer events. *)
  drawable_width : int;
  drawable_height : int;
  drawable_size : int * int;
  (** Native backing-pixel dimensions. *)
  pixel_scale : float * float;
  (** Backing pixels per logical point on each axis. *)
  time : float;
  dt : float;
  fps : float;
  count : int;
  mouse : int * int;
  mouse_delta : int * int;
  (** Logical pointer position and accumulated movement for this frame. *)
  keys : Input.key list;
  mouse_buttons : Input.mouse_button list;
  events : Event.t list;
}

val key_down : Input.key -> t -> bool
val mouse_down : Input.mouse_button -> t -> bool
val has_event : (Event.t -> bool) -> t -> bool

