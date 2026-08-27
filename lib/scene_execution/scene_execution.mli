type t
type mesh = {
  key : string;
  vertices : bytes;
  vertex_count : int;
  indices : bytes;
  index_count : int;
}
type state = {
  viewport : int * int * int * int;
  scissor : int * int * int * int;
}
type draw = { mesh : mesh; state : state }

val create : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (t, Ogpu.Error.t) result
val create_with_pipeline : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  (Ogpu.Backend.device -> (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t -> draw list ->
  (bool, Ogpu.Error.t) result
val resize : t -> Ogpu.Surface.configuration -> (unit, Ogpu.Error.t) result
val upload_bytes : t -> int64
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
