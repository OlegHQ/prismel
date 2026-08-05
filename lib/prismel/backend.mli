val is_headless : unit -> bool
val is_web : unit -> bool
val is_displayless : unit -> bool
val start :
  width:int -> height:int -> title:string -> resizable:bool ->
  (Runtime.t, string) result
val stop : unit -> unit
val present :
  Tsdl.Sdl.renderer -> logical_width:int -> logical_height:int ->
  (unit, string) result
val drain_web_events : unit -> Runtime.web_event list
val web_url : unit -> string option
val web_drawable_size : logical_width:int -> logical_height:int -> int * int
val register_web_file : ?content_type:string -> string -> string option
val register_web_bytes : ?content_type:string -> bytes -> string option
val remove_web_asset : string -> unit
val send_web_audio : Runtime.web_audio_command -> unit
val download_web_frame : filename:string -> (unit, string) result
val add_web_text_input_region :
  x:int -> y:int -> width:int -> height:int -> focused:bool -> unit
