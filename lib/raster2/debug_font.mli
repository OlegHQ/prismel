include module type of Scene_command.Debug_font

val draw : target:Surface.t -> blend:Composite.blend -> x:int -> y:int ->
  color:int32 -> string -> (unit, error) result
