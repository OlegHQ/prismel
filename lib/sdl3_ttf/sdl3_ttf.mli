(** Ownership-aware CPU font metrics and rasterization through SDL3_ttf. *)

type error_kind =
  | Ttf_error
  | Wrong_domain
  | Destroyed
  | Invalid_argument
  | Incompatible_version
  | Not_initialized
  | Fonts_still_open
  | Surface_error of Sdl3.error

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
  val stable_headers : bool
  val generator_version : string
  val header_sha256 : string
  val function_count : int
  val safe_function_count : int
  val check : ?release:bool -> unit -> (unit, error) result
end

module Init : sig
  val init : unit -> (unit, error) result
  val initialized : unit -> bool
  val quit : unit -> (unit, error) result
end

module Font : sig
  type t

  type metrics = {
    height : int;
    ascent : int;
    descent : int;
    line_skip : int;
  }

  val open_file : path:string -> size:float -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val metrics : t -> (metrics, error) result
  val family_name : t -> (string option, error) result
  val style_name : t -> (string option, error) result
  val set_size : t -> float -> (unit, error) result
  val size_text : t -> string -> (int * int, error) result

  (** Render UTF-8 to a CPU RGBA8 surface. Empty text is [Ok None], preserving
      the high-level no-op contract instead of asking SDL_ttf for a 0-width
      surface. Color channels are straight RGBA values in [0,255]. *)
  val render_blended :
    t -> color:int * int * int * int -> string ->
    (Sdl3.Surface.t option, error) result

  val destroy : t -> (unit, error) result
end

val drain_release_queue : unit -> (unit, error) result
val dropped_release_tokens : unit -> int
