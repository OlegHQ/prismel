type t = Native | Headless

val of_string : string -> (t, string) result
val selected : unit -> (t, string) result
val select_with : (string -> string option) -> (t, string) result
val get : unit -> t
val is_headless : unit -> bool
val is_web : unit -> bool
val is_displayless : unit -> bool
val configure_sdl_environment : t -> unit
