type t = {
  width : int;
  height : int;
  size : int * int;

  pixel_scale : float * float;
  time : float;
  dt : float;
  fps : float;
  count : int;
  mouse : float * float;
  mouse_delta : float * float;
  keys : Input.key list;
  mouse_buttons : Input.mouse_button list;
  events : Event.t list;
}

let mouse_down button frame = List.mem button frame.mouse_buttons
let has_event predicate frame = List.exists predicate frame.events
