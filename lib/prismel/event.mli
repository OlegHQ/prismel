(* Event module interface for handling input events *)

(* Event type representing all framework events *)
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (int * int)                                (* new mouse position *)
  | MousePressed of Input.mouse_button * (int * int)        (* button and position *)
  | MouseReleased of Input.mouse_button * (int * int)       (* button and position *)
  | PointerCancelled of Input.mouse_button                  (* browser/OS cancelled pointer *)
  | MouseScrolled of (int * int)                             (* scroll delta x,y *)
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string
  | WindowResized of (int * int)                             (* new width and height *)
  | WindowFocusLost
  | WindowClosed                                             (* user attempted to close *)

(* Bind the event stream to the running window's logical size. *)
val configure : logical_width:int -> logical_height:int -> unit

(* Poll pending native events and update Input state *)
val poll_events : unit -> t list

(* Process events through optional user event handler *)
val process_events : t list -> 'a -> ('a -> t -> 'a) option -> 'a

(* Main event processing function - polls events and processes them *)
val handle_events : 'a -> ('a -> t -> 'a) option -> 'a * t list

(* Utility function for debugging *)
val event_to_string : t -> string 

