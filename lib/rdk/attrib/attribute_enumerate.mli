type storage = Integer | Text of { prefix : string }
type mode = Enumerate_piece_elements | Enumerate_pieces

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Group.t ->
  ?start:int -> ?step:int -> ?storage:storage -> ?piece_attribute:string ->
  ?mode:mode -> owner:Attribute.owner -> name:string -> Geometry.t ->
  (Geometry.t, Error.t) result
