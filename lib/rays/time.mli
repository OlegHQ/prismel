(* Private: the realtime clock and frame pacing behind [Sketch]'s loop. *)

val init : unit -> unit
val now : unit -> float
(* Seconds since [init]. *)
val delta : unit -> float
(* Seconds between the last two [update]s, clamped to 0.1. *)
val update : unit -> unit
val set_frame_rate : int -> unit
(* A positive cap, or 0 for none. *)
val set_vsync : bool -> unit
val limit_frame_rate : unit -> unit
(* Sleeps out the rest of the frame when capped and vsync is off. *)
