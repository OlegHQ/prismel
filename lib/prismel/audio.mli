(** SDL_mixer audio with headless dummy-device support.

    All operations are initial-domain-only. Volume values use 0..1. *)

val init :
  ?frequency:int -> ?channels:int -> ?chunk_size:int -> unit ->
  (unit, string) result
val is_initialized : unit -> bool
val shutdown : unit -> unit

val set_master_volume : float -> unit
val stop_all : unit -> unit

module Sample : sig
  type t
  type waveform = Sine | Square | Saw | Triangle

  val load : string -> (t, string) result
  val load_exn : string -> t
  val synth :
    ?sample_rate:int ->
    ?volume:float ->
    waveform:waveform ->
    frequency:float ->
    duration:float ->
    unit ->
    (t, string) result
  val play :
    ?loops:int -> ?volume:float -> t -> (int, string) result
  val set_volume : t -> float -> unit
  val stop : int -> unit
  val pause : int -> unit
  val resume : int -> unit
  val is_playing : int -> bool
  val destroy : t -> unit
end

module Music : sig
  type t

  val load : string -> (t, string) result
  val load_exn : string -> t
  val play : ?loops:int -> ?fade_ms:int -> t -> (unit, string) result
  val set_volume : float -> unit
  val pause : unit -> unit
  val resume : unit -> unit
  val stop : ?fade_ms:int -> unit -> unit
  val is_playing : unit -> bool
  val destroy : t -> unit
end
