type t = Native

(** Parse the sole supported native target.  Environment values never select a
    renderer. *)
val of_string : string -> (t, string) result
val selected : unit -> (t, string) result
val select_with : (string -> string option) -> (t, string) result
val get : unit -> t
val is_displayless : unit -> bool
val configure_sdl_environment : t -> unit
