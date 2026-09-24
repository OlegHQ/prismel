type capability_source =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  ; ray_tracing : bool
  ; metal_fx : bool
  }

type operation = Buffer | Texture | Sampler | Compute_pipeline | Render_pipeline
  | Queue | Surface | Memory | Native_pass | Event_synchronization
  | Timeline_fence | Timestamp_queries | Ray_tracing | Metal_fx | Sparse_memory
  | Unknown of string
type profile =
  { capabilities:Ogpu.Capabilities.t; timestamp_queries:bool;
    sparse_memory:bool; conservative_limits:string list }

val capabilities : capability_source -> (Ogpu.Capabilities.t, Ogpu.Error.t) result
val profile : capability_source -> timestamp_queries:bool -> sparse_memory:bool ->
  conservative_limits:string list -> (profile,Ogpu.Error.t) result
val supports : profile -> operation -> (unit,Ogpu.Error.t) result
val error : operation:string -> Metal.error -> Ogpu.Error.t
