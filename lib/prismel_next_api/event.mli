type t = KeyPressed of Input.key | KeyReleased of Input.key | MouseMoved of int*int
  | MousePressed of Input.mouse_button*(int*int) | MouseReleased of Input.mouse_button*(int*int)
  | PointerCancelled of Input.mouse_button | MouseScrolled of int*int | TextInput of string
  | TextEditing of {text:string;start:int;length:int} | FileDropped of string
  | WindowResized of int*int | WindowFocusLost | WindowClosed
val poll_events : unit -> t list
val process_events : t list -> 'a -> ('a -> t -> 'a) option -> 'a
val handle_events : 'a -> ('a -> t -> 'a) option -> 'a*t list
val event_to_string : t -> string
module Private : sig val push : Runtime_next_input.event -> (unit,string) result end
