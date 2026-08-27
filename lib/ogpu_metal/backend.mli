type control
val create : ?device:Device.t -> ?layer:Metal.Metal_layer.t -> unit -> Ogpu.Backend.driver * control
val register_pipeline : control -> Pipeline.t -> unit
val sampler_cache_entries : control -> int
