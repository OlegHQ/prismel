type t={width:int;height:int;size:int*int;drawable_width:int;drawable_height:int;drawable_size:int*int;pixel_scale:float*float;time:float;dt:float;fps:float;count:int;mouse:int*int;mouse_delta:int*int;keys:Input.key list;mouse_buttons:Input.mouse_button list;events:Event.t list}
val key_down : Input.key -> t -> bool
val mouse_down : Input.mouse_button -> t -> bool
val has_event : (Event.t->bool) -> t -> bool
