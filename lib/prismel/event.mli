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
  | FileDragMoved of (float * float)                         (* files from the OS are over the window at this point *)
  | FileDragEnded                                            (* the drag left the window or finished *)
  | MousePinched of float                                    (* trackpad pinch: zoom factor since the last event; above 1 zooms in *)
  | FileDialog of { id : int; result : (string list, string) result }
      (** a native file dialog from {!Sketch.show_file_dialog} finished: the
          chosen paths (empty when the user cancelled) or what went wrong *)
  | WindowResized of (int * int)                             (* new width and height *)
  | WindowFocusLost
  | WindowClosed                                             (* user attempted to close *)

module Private : sig
  val key_of_runtime : Runtime_input.key -> Input.key
  (** The one move from the binding's key to Prismel's; exposed for tests. *)

  val keys_before : previous:Input.key list -> held:Input.key list ->
    t list -> Input.key list
  (** Initial held keys: changed keys and focus cancellation take [previous];
      unchanged keys use the final [held] snapshot. These hooks are internal
      input plumbing; their output can be advanced through ordered events. *)

  val keys_after : Input.key list -> t -> Input.key list
end
