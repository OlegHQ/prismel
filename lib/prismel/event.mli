(** Input events delivered, in order, through [Frame.events]. *)

type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (float * float)                            (* logical-point position *)
  | MousePressed of Input.mouse_button * (float * float)    (* button and position *)
  | MouseReleased of Input.mouse_button * (float * float)   (* button and position *)
  | PointerCancelled of Input.mouse_button                  (* OS cancelled the pointer *)
  | MouseScrolled of (float * float)                         (* scroll delta x,y; trackpads send fractions *)
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string                                   (* absolute path; not read *)
  | WindowResized of (int * int)                             (* new width and height *)
  | WindowFocusLost
  | WindowClosed                                             (* user attempted to close *)

module Private : sig
  val key_of_name : string -> Input.key
  (* The runtime key-name contract; exposed for tests. *)
end
