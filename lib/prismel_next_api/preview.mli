val start : ?width:int -> ?height:int -> ?title:string -> unit -> unit
val show : Scene.t -> unit
val step : Scene.t -> Event.t list
val is_open : unit -> bool
val stop : unit -> unit
