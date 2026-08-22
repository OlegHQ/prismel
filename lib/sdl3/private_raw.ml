type version = { major : int; minor : int; patch : int }

external linked_version_number : unit -> int = "caml_sdl3_linked_version"
external revision : unit -> string = "caml_sdl3_revision"
external get_error : unit -> string = "caml_sdl3_get_error"
external clear_error : unit -> unit = "caml_sdl3_clear_error"
external is_main_thread : unit -> bool = "caml_sdl3_is_main_thread"
external init_subsystem : int -> bool = "caml_sdl3_init_subsystem"
external quit_subsystem : int -> unit = "caml_sdl3_quit_subsystem"
external quit : unit -> unit = "caml_sdl3_quit"
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

external create_metal_view : nativeint -> nativeint = "caml_sdl3_create_metal_view"
external destroy_metal_view : nativeint -> unit = "caml_sdl3_destroy_metal_view"
external metal_layer_is_nonnull : nativeint -> bool
  = "caml_sdl3_metal_layer_is_nonnull"
