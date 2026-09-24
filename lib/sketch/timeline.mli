(** Deterministic sketch-owned playback clock.

    The runtime frame clock always advances, while this clock can pause, stop,
    and reset without touching global state. Default shortcuts are [P]
    pause/resume, [S] stop, and [R] reset-and-play. *)

type mode = Playing | Paused | Stopped
type t

type shortcuts = {
  pause : Prismel.Input.key;
  stop : Prismel.Input.key;
  reset : Prismel.Input.key;
}

type change = Advanced | Paused_now | Resumed | Stopped_now | Reset_now

val default_shortcuts : shortcuts
val create : ?shortcuts:shortcuts -> unit -> t
val update : t -> Prismel.Frame.t -> t * change list

val mode : t -> mode
val time : t -> float
val frame : t -> int64
val changed_context : change list -> bool

(** Build the exact procedural context used by a graph cook. *)
val context :
  ?seed:int64 ->
  ?domains:int ->
  ?grain:int ->
  ?cancel:Procedural.Context.Cancel.t ->
  t ->
  (Procedural.Context.t, string) result
