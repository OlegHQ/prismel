(* Event module interface for handling input events *)

(* Event type representing all framework events *)
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (float * float)                            (* logical-point position *)
  | MousePressed of Input.mouse_button * (float * float)    (* button and position *)
  | MouseReleased of Input.mouse_button * (float * float)   (* button and position *)
  | PointerCancelled of Input.mouse_button                  (* browser/OS cancelled pointer *)
  | MouseScrolled of (float * float)                         (* scroll delta x,y; trackpads send fractions *)
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string                                   (* absolute path; not read *)
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

module Private : sig
  val set_relative : bool -> unit
  (* Relative pointer motion drives [Input.mouse_delta]; see
     [Sketch.set_relative_mouse]. *)
  val key_of_name : string -> Input.key
  (* The runtime key-name contract; exposed for tests. *)
end
