(** Ownership-aware binding to SDL3_mixer's mixer/audio/track model. *)

type error_kind =
  | Mixer_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Incompatible_version
  | Not_initialized
  | Handles_still_open

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
  val initialized : unit -> (bool, error) result
  val quit : unit -> (unit, error) result
end

module Mixer : sig
  type t
  type mode = Device | Memory
  type format = { sample_rate : int; channels : int }
  type generated = private { mixed_bytes : int; pcm_f32 : bytes }

  val create_device : unit -> (t, error) result
  val create_memory : sample_rate:int -> channels:int -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val mode : t -> mode
  val format : t -> (format, error) result
  val set_gain : t -> float -> (unit, error) result
  val gain : t -> (float, error) result
  val stop_all : t -> ?fade_ms:int -> unit -> (unit, error) result

  (** Generate exactly [frames] of interleaved native-endian float32 PCM from
      a memory mixer. [mixed_bytes] excludes silence appended after tracks
      finish, while [pcm_f32] always has the requested length. *)
  val generate : t -> frames:int -> (generated, error) result

  val destroy : t -> (unit, error) result
end

module Audio : sig
  type t

  val load_file :
    Mixer.t -> path:string -> ?predecode:bool -> unit -> (t, error) result
  val load_bytes : Mixer.t -> bytes -> (t, error) result
  val create_sine :
    Mixer.t -> frequency:int -> amplitude:float -> duration_ms:int ->
    (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val duration_frames : t -> (int64, error) result
  val destroy : t -> (unit, error) result
end

module Track : sig
  type t

  val create : Mixer.t -> (t, error) result
  val generation : t -> int
  val destroyed : t -> bool
  val set_audio : t -> Audio.t -> (unit, error) result
  val set_gain : t -> float -> (unit, error) result
  val gain : t -> (float, error) result
  val set_loops : t -> int -> (unit, error) result
  val loops : t -> (int, error) result
  val play : t -> ?loops:int -> ?fade_in_ms:int -> unit -> (unit, error) result
  val stop : t -> ?fade_out_ms:int -> unit -> (unit, error) result
  val pause : t -> (unit, error) result
  val resume : t -> (unit, error) result
  val playing : t -> (bool, error) result
  val paused : t -> (bool, error) result
  val destroy : t -> (unit, error) result
end

val drain_release_queue : unit -> (unit, error) result
val dropped_release_tokens : unit -> int
