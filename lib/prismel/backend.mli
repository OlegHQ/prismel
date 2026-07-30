(** Runtime backend selection. *)

val is_headless : unit -> bool
(** [is_headless ()] reflects the [HEADLESS] environment variable. *)

val configure_environment : unit -> unit
(** Configures SDL for the selected backend. Call before [Sdl.init]. *)
