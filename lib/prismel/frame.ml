type t = {
  width : int;
  height : int;
  size : int * int;
  drawable_width : int;
  drawable_height : int;
  drawable_size : int * int;
  pixel_scale : float * float;
  time : float;
  dt : float;
  fps : float;
  count : int;
  mouse : int * int;
  mouse_delta : int * int;
  keys : Input.key list;
  mouse_buttons : Input.mouse_button list;
  events : Event.t list;
}

let key_down key frame = List.mem key frame.keys
let mouse_down button frame = List.mem button frame.mouse_buttons
let has_event predicate frame = List.exists predicate frame.events

