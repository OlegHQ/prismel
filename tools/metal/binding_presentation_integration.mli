type drawable = private Drawable of nativeint
type layer = private Layer of nativeint
type command_buffer = private Command_buffer of nativeint
type texture = private Texture of nativeint
type render_pass = private Render_pass of nativeint

type loss = Timeout | Occluded | Zero_sized | Detached
type acquisition = Drawable_available of drawable * texture | Drawable_unavailable of loss
type present_time = Immediate | At_time of float | After_minimum_duration of float

type window_state =
  { attached : bool; visible : bool; minimized : bool
  ; pixel_width : int; pixel_height : int }

val classify_nil : window_state -> timed_out:bool -> loss
val validate_present_time : present_time -> (unit, string) result
val selector_contract : string list
val sdl3_attached_window_strategy : string list
