type version = { major : int; minor : int; patch : int }

external linked_version_number : unit -> int = "caml_sdl3_linked_version"
external revision : unit -> string = "caml_sdl3_revision"
external get_error : unit -> string = "caml_sdl3_get_error"
external clear_error : unit -> unit = "caml_sdl3_clear_error"
external is_main_thread : unit -> bool = "caml_sdl3_is_main_thread"
external performance_counter : unit -> int64 = "caml_sdl3_performance_counter"
external performance_frequency : unit -> int64 = "caml_sdl3_performance_frequency"
external delay_precise_ns : int64 -> unit = "caml_sdl3_delay_precise_ns"
external init_subsystem : int -> bool = "caml_sdl3_init_subsystem"
external quit_subsystem : int -> unit = "caml_sdl3_quit_subsystem"
external quit : unit -> unit = "caml_sdl3_quit"
external current_video_driver : unit -> string option
  = "caml_sdl3_current_video_driver"
external was_init : int -> int = "caml_sdl3_was_init"

external create_window : string -> int -> int -> int64 -> nativeint
  = "caml_sdl3_create_window"
external destroy_window : nativeint -> unit = "caml_sdl3_destroy_window"
external window_size : nativeint -> (int * int) option = "caml_sdl3_window_size"
external window_size_in_pixels : nativeint -> (int * int) option
  = "caml_sdl3_window_size_in_pixels"
external window_flags : nativeint -> int64 = "caml_sdl3_window_flags"
external show_window : nativeint -> bool = "caml_sdl3_show_window"
external hide_window : nativeint -> bool = "caml_sdl3_hide_window"
external set_window_fullscreen : nativeint -> bool -> bool
  = "caml_sdl3_set_window_fullscreen"
external window_id : nativeint -> int64 = "caml_sdl3_window_id"
external window_display : nativeint -> int64 = "caml_sdl3_window_display"
external window_pixel_density : nativeint -> float
  = "caml_sdl3_window_pixel_density"
external window_display_scale : nativeint -> float
  = "caml_sdl3_window_display_scale"
external window_position : nativeint -> (int * int) option
  = "caml_sdl3_window_position"
external window_title : nativeint -> string = "caml_sdl3_window_title"
external set_window_title : nativeint -> string -> bool
  = "caml_sdl3_set_window_title"
external center_window : nativeint -> bool = "caml_sdl3_center_window"
external set_window_bordered : nativeint -> bool -> bool
  = "caml_sdl3_set_window_bordered"
external set_window_resizable : nativeint -> bool -> bool
  = "caml_sdl3_set_window_resizable"
external set_window_always_on_top : nativeint -> bool -> bool
  = "caml_sdl3_set_window_always_on_top"
external set_window_relative_mouse : nativeint -> bool -> bool
  = "caml_sdl3_set_window_relative_mouse"
external window_relative_mouse : nativeint -> bool
  = "caml_sdl3_window_relative_mouse"
external capture_mouse : bool -> bool = "caml_sdl3_capture_mouse"
external display_refresh_rate : int64 -> float option
  = "caml_sdl3_display_refresh_rate"
external create_system_cursor : int -> nativeint = "caml_sdl3_create_system_cursor"
external set_cursor : nativeint -> bool = "caml_sdl3_set_cursor"
external destroy_cursor : nativeint -> unit = "caml_sdl3_destroy_cursor"
external show_cursor : unit -> bool = "caml_sdl3_show_cursor"
external hide_cursor : unit -> bool = "caml_sdl3_hide_cursor"
external cursor_visible : unit -> bool = "caml_sdl3_cursor_visible"
external set_window_position : nativeint -> int -> int -> bool
  = "caml_sdl3_set_window_position"
external set_window_size : nativeint -> int -> int -> bool
  = "caml_sdl3_set_window_size"
external maximize_window : nativeint -> bool = "caml_sdl3_maximize_window"
external minimize_window : nativeint -> bool = "caml_sdl3_minimize_window"
external restore_window : nativeint -> bool = "caml_sdl3_restore_window"
external sync_window : nativeint -> bool = "caml_sdl3_sync_window"

external displays : unit -> int64 array option = "caml_sdl3_displays"
external primary_display : unit -> int64 = "caml_sdl3_primary_display"
external display_name : int64 -> string option = "caml_sdl3_display_name"
external display_bounds : int64 -> bool -> (int * int * int * int) option
  = "caml_sdl3_display_bounds"
external display_content_scale : int64 -> float
  = "caml_sdl3_display_content_scale"

external clipboard_set_text : string -> bool = "caml_sdl3_clipboard_set_text"
external clipboard_get_text : unit -> string option = "caml_sdl3_clipboard_get_text"
external clipboard_has_text : unit -> bool = "caml_sdl3_clipboard_has_text"

external start_text_input : nativeint -> bool = "caml_sdl3_start_text_input"
external stop_text_input : nativeint -> bool = "caml_sdl3_stop_text_input"
external text_input_active : nativeint -> bool = "caml_sdl3_text_input_active"
external set_text_input_area : nativeint -> (int * int * int * int) option -> int -> bool
  = "caml_sdl3_set_text_input_area"
external text_input_area : nativeint -> ((int * int * int * int) * int) option
  = "caml_sdl3_text_input_area"

external create_metal_view : nativeint -> nativeint = "caml_sdl3_create_metal_view"
external destroy_metal_view : nativeint -> unit = "caml_sdl3_destroy_metal_view"
external metal_layer_token : nativeint -> int64 -> int64 -> Native_layer_token.t
  = "caml_sdl3_metal_layer_token"
external invalidate_metal_layer_token : Native_layer_token.t -> unit
  = "caml_sdl3_invalidate_metal_layer_token"

external create_rgba_presenter : nativeint -> bool -> nativeint
  = "caml_sdl3_create_rgba_presenter"
external destroy_rgba_presenter : nativeint -> unit
  = "caml_sdl3_destroy_rgba_presenter"
external present_rgba : nativeint -> bytes -> int -> int -> int -> bool
  = "caml_sdl3_present_rgba"
external presenter_copy_rgba : nativeint -> bytes option
  = "caml_sdl3_presenter_copy_rgba"
external presenter_texture_size : nativeint -> int * int
  = "caml_sdl3_presenter_texture_size"
external presenter_renderer_name : nativeint -> string option
  = "caml_sdl3_presenter_renderer_name"

(* The SDL_Event union never crosses this module boundary.  The C stub copies
   only the active member into one of these constructors while SDL still owns
   any pointer payloads. *)
type raw_event =
  | Application of int * int64
  | Display of int * int64 * int64 * int * int
  | Window of int * int64 * int64 * int * int
  | Keyboard_device of int * int64 * int64
  | Key of
      int64 * int64 * int64 * int * int * int * int * bool * bool
  | Text_editing of int64 * int64 * string * int * int
  | Text_editing_candidates of int64 * int64 * string array * int * bool
  | Text_input of int64 * int64 * string
  | Mouse_device of int * int64 * int64
  | Mouse_motion of
      int64 * int64 * int64 * int64 * float * float * float * float
  | Mouse_button of
      int64 * int64 * int64 * int * bool * int * float * float
  | Mouse_wheel of
      int64 * int64 * int64 * float * float * int * float * float * int * int
  | Gamepad_axis of int64 * int64 * int * int
  | Gamepad_button of int64 * int64 * int * bool
  | Gamepad_device of int * int64 * int64
  | Gamepad_touchpad of
      int * int64 * int64 * int * int * float * float * float
  | Gamepad_sensor of int64 * int64 * int * float array * int64
  | Touch of
      int * int64 * int64 * int64 * float * float * float * float * float
      * int64
  | Pinch of int * int64 * float * int64
  | Pen_proximity of int * int64 * int64 * int64
  | Pen_motion of int64 * int64 * int64 * int64 * float * float
  | Pen_touch of
      int64 * int64 * int64 * int64 * float * float * bool * bool
  | Pen_button of
      int64 * int64 * int64 * int64 * float * float * int * bool
  | Pen_axis of
      int64 * int64 * int64 * int64 * float * float * int * float
  | Drop of
      int * int64 * int64 * float * float * string option * string option
  | Clipboard of int64 * bool * string array
  | Audio_device of int * int64 * int64 * bool
  | Sensor of int64 * int64 * float array * int64
  | Unknown of int * int64

external poll_event : unit -> raw_event option = "caml_sdl3_poll_event"
external wait_event_timeout : int -> raw_event option
  = "caml_sdl3_wait_event_timeout"

external create_surface_rgba : int -> int -> nativeint
  = "caml_sdl3_create_surface_rgba"
external destroy_surface : nativeint -> unit = "caml_sdl3_destroy_surface"
external surface_info : nativeint -> (int * int * int) option
  = "caml_sdl3_surface_info"
external surface_write_rgba : nativeint -> bytes -> int -> bool
  = "caml_sdl3_surface_write_rgba"
external surface_copy_rgba : nativeint -> bytes option
  = "caml_sdl3_surface_copy_rgba"
