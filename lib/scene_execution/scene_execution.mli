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
type pipeline_family = Scene2 | Scene3 | Scene3_textured
type texture_level = { width:int; height:int; bytes:bytes }
type sampled_texture = {
  key:string;
  levels:texture_level array;
  sampler:Ogpu.Types.sampler_descriptor;
}

val create : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (t, Ogpu.Error.t) result
val create_variants : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  (t, Ogpu.Error.t) result
val create_with_pipeline : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  (Ogpu.Backend.device -> (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val create_with_pipeline_variants : Ogpu.Backend.driver -> Ogpu.Surface.configuration ->
  ?before_device_destroy:(unit -> (unit, Ogpu.Error.t) result) ->
  (Ogpu.Backend.device -> pipeline_family -> Ogpu.Pipeline.blend ->
    (Ogpu.Pipeline.t, Ogpu.Error.t) result) ->
  (t, Ogpu.Error.t) result
val render : ?clear:(float * float * float * float) -> t -> draw list ->
  (bool, Ogpu.Error.t) result
val render_blended : ?clear:(float * float * float * float) -> t ->
  (Ogpu.Pipeline.blend * draw) list -> (bool, Ogpu.Error.t) result
val render_family : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * draw) list ->
  (bool, Ogpu.Error.t) result
val render_textured : ?clear:(float * float * float * float) -> t ->
  (pipeline_family * Ogpu.Pipeline.blend * sampled_texture option * draw) list ->
  (bool, Ogpu.Error.t) result
val resize : t -> Ogpu.Surface.configuration -> (unit, Ogpu.Error.t) result
val upload_bytes : t -> int64
val cache_entries : t -> int
val read_pixels : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
