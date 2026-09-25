type feature = Buffer | Texture | Sampler | Compute_pipeline | Render_pipeline
  | Queue | Surface | Memory | Event_synchronization
  | Timeline_fence | Timestamp_queries | Ray_tracing | Metal_fx | Sparse_memory
  | Unknown of string

type limits =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  }

type t =
  { limits : limits
  ; compute_pipeline : bool
  ; ray_tracing : bool
  ; metal_fx : bool
  ; timestamp_queries : bool
  ; sparse_memory : bool
  ; conservative_limits : string list
  }

val minimum_m1 : t
val validate : t -> (unit, Error.t) result
val create : t -> timestamp_queries:bool -> sparse_memory:bool ->
  conservative_limits:string list -> (t, Error.t) result
val has : t -> feature -> bool
val require : ?operation:string -> t -> feature -> (unit, Error.t) result
