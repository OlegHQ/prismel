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
  val initialized : subsystem list -> bool
  val quit_subsystems : subsystem list -> (unit, error) result
  val quit : unit -> (unit, error) result
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
  val size : t -> (int * int, error) result
  val size_in_pixels : t -> (int * int, error) result
  val flags : t -> (int64, error) result
  val show : t -> (unit, error) result
  val hide : t -> (unit, error) result
  val set_fullscreen : t -> bool -> (unit, error) result
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
