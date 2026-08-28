val is_displayless : unit -> bool
val start :
  width:int -> height:int -> title:string -> resizable:bool ->
  (Runtime.t, string) result
val stop : unit -> unit
val present :
  Tsdl.Sdl.renderer -> logical_width:int -> logical_height:int ->
  (unit, string) result
