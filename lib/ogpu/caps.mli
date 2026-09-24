type feature = Buffer | Texture | Sampler | Compute_pipeline | Render_pipeline
  | Queue | Surface | Memory | Event_synchronization
  | Timeline_fence | Timestamp_queries | Ray_tracing | Metal_fx | Sparse_memory
  | Unknown of string

type t =
  { capabilities : Capabilities.t
  ; timestamp_queries : bool
  ; sparse_memory : bool
  ; conservative_limits : string list
  }

val create : Capabilities.t -> timestamp_queries:bool -> sparse_memory:bool ->
  conservative_limits:string list -> (t, Error.t) result
val has : t -> feature -> bool
val require : ?operation:string -> t -> feature -> (unit, Error.t) result
