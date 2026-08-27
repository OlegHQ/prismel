type t
type stats = { pipeline_cache_entries:int; uploaded_bytes:int64 }
val create : width:int -> height:int -> (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t ->
  Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val resize : t -> width:int -> height:int -> (unit, Ogpu.Error.t) result
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val stats : t -> stats
val destroy : t -> (unit, Ogpu.Error.t) result
