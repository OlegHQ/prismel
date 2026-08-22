(** Ownership-aware compiled bindings to the pinned stable SDL3 headers. *)

type error_kind =
  | Sdl_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Incompatible_version
  | Invalid_argument

type error = private {
  operation : string;
  kind : error_kind;
  message : string;
}

type rect = { x : int; y : int; width : int; height : int }

val pp_error : Format.formatter -> error -> unit

module Version : sig
  type t = { major : int; minor : int; patch : int }

  val compiled : t
  val linked : unit -> t
  val revision : unit -> string
  val stable_headers : bool
  val generator_version : string
  val header_sha256 : string
  val target_triple : string
  val function_count : int
  val safe_function_count : int
  val validate : release:bool -> linked:t -> (unit, error) result
  val check : ?release:bool -> unit -> (unit, error) result
end

module Thread : sig
  val is_initial_domain : unit -> bool
  val is_sdl_main_thread : unit -> bool
end

module Init : sig
  type subsystem =
    | Audio
    | Video
    | Joystick
    | Haptic
    | Gamepad
    | Events
    | Sensor
    | Camera

  val init : ?release:bool -> subsystem list -> (unit, error) result
  val initialized : subsystem list -> (bool, error) result
  val quit_subsystems : subsystem list -> (unit, error) result
  val quit : unit -> (unit, error) result
end

module Display : sig
  type t

  val all : unit -> (t list, error) result
  val primary : unit -> (t, error) result
  val id : t -> int64
  val name : t -> (string, error) result
  val bounds : t -> (rect, error) result
  val usable_bounds : t -> (rect, error) result
  val content_scale : t -> (float, error) result
end

module Window : sig
  type t

  type flag =
    | Fullscreen
    | Hidden
    | Borderless
    | Resizable
    | High_pixel_density
    | Always_on_top
    | Utility
    | Metal
    | Transparent

  val create :
    title:string -> width:int -> height:int -> ?flags:flag list -> unit ->
    (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val id : t -> (int64, error) result
  val display : t -> (Display.t, error) result
  val size : t -> (int * int, error) result
  val size_in_pixels : t -> (int * int, error) result
  val pixel_density : t -> (float, error) result
  val display_scale : t -> (float, error) result
  val position : t -> (int * int, error) result
  val set_position : t -> x:int -> y:int -> (unit, error) result
  val set_size : t -> width:int -> height:int -> (unit, error) result
  val flags : t -> (int64, error) result
  val show : t -> (unit, error) result
  val hide : t -> (unit, error) result
  val maximize : t -> (unit, error) result
  val minimize : t -> (unit, error) result
  val restore : t -> (unit, error) result
  val set_fullscreen : t -> bool -> (unit, error) result
  val sync : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Clipboard : sig
  val set_text : string -> (unit, error) result
  val get_text : unit -> (string, error) result
  val has_text : unit -> (bool, error) result
end

module Text_input : sig
  val start : Window.t -> (unit, error) result
  val stop : Window.t -> (unit, error) result
  val active : Window.t -> (bool, error) result
  val set_area : Window.t -> rect option -> cursor:int -> (unit, error) result
  val area : Window.t -> ((rect * int), error) result
end

module Event : sig
  type id = int64

  type application_change =
    | Terminating
    | Low_memory
    | Will_enter_background
    | Did_enter_background
    | Will_enter_foreground
    | Did_enter_foreground
    | Locale_changed
    | System_theme_changed

  type display_change =
    | Orientation of int
    | Added
    | Removed
    | Moved
    | Desktop_mode_changed
    | Current_mode_changed
    | Content_scale_changed
    | Usable_bounds_changed
    | Other_display_change of int * int * int

  type window_change =
    | Shown
    | Hidden
    | Exposed
    | Window_moved of int * int
    | Resized of int * int
    | Pixel_size_changed of int * int
    | Metal_view_resized
    | Minimized
    | Maximized
    | Restored
    | Mouse_entered
    | Mouse_left
    | Focus_gained
    | Focus_lost
    | Close_requested
    | Hit_test
    | Icc_profile_changed
    | Display_changed of id
    | Display_scale_changed
    | Safe_area_changed
    | Occluded
    | Entered_fullscreen
    | Left_fullscreen
    | Destroyed
    | Hdr_state_changed
    | Other_window_change of int * int * int

  type device_change = Added | Removed
  type wheel_direction = Normal | Flipped | Other_wheel_direction of int
  type touch_phase = Down | Up | Motion | Cancelled
  type pinch_phase = Began | Updated | Ended
  type pen_proximity_change = Entered | Left

  type gamepad_change =
    | Gamepad_added
    | Gamepad_removed
    | Remapped
    | Update_complete
    | Steam_handle_updated
    | Other_gamepad_change of int

  type drop_change =
    | File of string
    | Text of string
    | Drop_began
    | Drop_complete
    | Drop_position
    | Other_drop_change of int

  type audio_device_change =
    | Audio_added
    | Audio_removed
    | Format_changed
    | Other_audio_device_change of int

  type t =
    | Quit of { timestamp_ns : int64 }
    | Application of { timestamp_ns : int64; change : application_change }
    | Display of {
        timestamp_ns : int64;
        display_id : id;
        change : display_change;
      }
    | Window of {
        timestamp_ns : int64;
        window_id : id;
        change : window_change;
      }
    | Keyboard_device of {
        timestamp_ns : int64;
        which : id;
        change : device_change;
      }
    | Key of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        scancode : int;
        keycode : int;
        modifiers : int;
        raw_scancode : int;
        down : bool;
        repeat : bool;
      }
    | Keymap_changed of { timestamp_ns : int64 }
    | Text_editing of {
        timestamp_ns : int64;
        window_id : id;
        text : string;
        start : int;
        length : int;
      }
    | Text_editing_candidates of {
        timestamp_ns : int64;
        window_id : id;
        candidates : string list;
        selected : int option;
        horizontal : bool;
      }
    | Text_input of {
        timestamp_ns : int64;
        window_id : id;
        text : string;
      }
    | Screen_keyboard of { timestamp_ns : int64; shown : bool }
    | Mouse_device of {
        timestamp_ns : int64;
        which : id;
        change : device_change;
      }
    | Mouse_motion of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        buttons : int64;
        x : float;
        y : float;
        dx : float;
        dy : float;
      }
    | Mouse_button of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        button : int;
        down : bool;
        clicks : int;
        x : float;
        y : float;
      }
    | Mouse_wheel of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        x : float;
        y : float;
        direction : wheel_direction;
        mouse_x : float;
        mouse_y : float;
        integer_x : int;
        integer_y : int;
      }
    | Touch of {
        timestamp_ns : int64;
        window_id : id;
        touch_id : id;
        finger_id : id;
        phase : touch_phase;
        x : float;
        y : float;
        dx : float;
        dy : float;
        pressure : float;
      }
    | Pinch of {
        timestamp_ns : int64;
        window_id : id;
        phase : pinch_phase;
        scale : float;
      }
    | Pen_proximity of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        change : pen_proximity_change;
      }
    | Pen_motion of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
      }
    | Pen_touch of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        eraser : bool;
        down : bool;
      }
    | Pen_button of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        button : int;
        down : bool;
      }
    | Pen_axis of {
        timestamp_ns : int64;
        window_id : id;
        which : id;
        state : int64;
        x : float;
        y : float;
        axis : int;
        value : float;
      }
    | Gamepad_axis of {
        timestamp_ns : int64;
        which : id;
        axis : int;
        value : int;
      }
    | Gamepad_button of {
        timestamp_ns : int64;
        which : id;
        button : int;
        down : bool;
      }
    | Gamepad_device of {
        timestamp_ns : int64;
        which : id;
        change : gamepad_change;
      }
    | Gamepad_touchpad of {
        timestamp_ns : int64;
        which : id;
        touchpad : int;
        finger : int;
        phase : touch_phase;
        x : float;
        y : float;
        pressure : float;
      }
    | Gamepad_sensor of {
        timestamp_ns : int64;
        sensor_timestamp_ns : int64;
        which : id;
        sensor : int;
        data : float * float * float;
      }
    | Drop of {
        timestamp_ns : int64;
        window_id : id;
        x : float;
        y : float;
        source : string option;
        change : drop_change;
      }
    | Clipboard of {
        timestamp_ns : int64;
        owner : bool;
        mime_types : string list;
      }
    | Audio_device of {
        timestamp_ns : int64;
        which : id;
        recording : bool;
        change : audio_device_change;
      }
    | Sensor of {
        timestamp_ns : int64;
        sensor_timestamp_ns : int64;
        which : id;
        data : float * float * float * float * float * float;
      }
    | Unknown of { timestamp_ns : int64; event_type : int }

  val poll : unit -> (t option, error) result
  val poll_all : unit -> (t list, error) result

  (** [wait ~timeout_ms] uses [-1] for an unbounded wait. The OCaml runtime
      lock is released only while SDL blocks on its independently owned event
      storage. *)
  val wait : timeout_ms:int -> (t option, error) result

  val mouse_delta : t list -> float * float
end

module Surface : sig
  type t

  type rgba = private {
    width : int;
    height : int;
    stride : int;
    pixels : bytes;
  }

  val create_rgba : width:int -> height:int -> (t, error) result

  (** Copy tightly packed or explicitly strided RGBA8 rows into an owned SDL
      CPU surface. The source bytes remain owned by the caller. *)
  val of_rgba :
    width:int -> height:int -> ?stride:int -> bytes -> (t, error) result

  val generation : t -> int
  val destroyed : t -> bool
  val size : t -> (int * int, error) result
  val pitch : t -> (int, error) result

  (** Return a tightly packed RGBA8 snapshot. No SDL pointer escapes. *)
  val copy_rgba : t -> (rgba, error) result

  val destroy : t -> (unit, error) result
end

module Metal_view : sig
  type t
  type layer

  val create : Window.t -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val layer : t -> (layer, error) result
  val destroy : t -> (unit, error) result
end

(** Drain finalizer release tokens on the initial domain. Explicit destruction
    remains the primary ownership mechanism. *)
val drain_release_queue : unit -> (unit, error) result
val dropped_release_tokens : unit -> int
