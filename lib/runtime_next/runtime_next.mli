type t
val create : width:int -> height:int -> (t, Ogpu.Error.t) result
val render : t -> Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val resize : t -> width:int -> height:int -> (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
