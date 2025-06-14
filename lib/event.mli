(* Event module interface for handling input events *)

(* Event type representing all framework events *)
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (int * int)                                (* new mouse position *)
  | MousePressed of Input.mouse_button * (int * int)        (* button and position *)
  | MouseReleased of Input.mouse_button * (int * int)       (* button and position *)
  | MouseScrolled of (int * int)                             (* scroll delta x,y *)
  | WindowResized of (int * int)                             (* new width and height *)
  | WindowClosed                                             (* user attempted to close *)

(* Poll all pending events and update Input state *)
val poll_events : unit -> t list

(* Process events through optional user event handler *)
val process_events : t list -> 'a -> ('a -> t -> 'a) option -> 'a

(* Main event processing function - polls events and processes them *)
val handle_events : 'a -> ('a -> t -> 'a) option -> 'a * t list

(* Utility function for debugging *)
val event_to_string : t -> string 