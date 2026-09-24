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

let create capabilities ~timestamp_queries ~sparse_memory ~conservative_limits =
  Result.map (fun () ->
    { capabilities; timestamp_queries; sparse_memory; conservative_limits })
    (Capabilities.validate capabilities)

let has value = function
  | Buffer | Texture | Sampler | Compute_pipeline | Render_pipeline | Queue
  | Surface | Memory | Event_synchronization -> true
  | Timeline_fence -> false
  | Timestamp_queries -> value.timestamp_queries
  | Ray_tracing -> value.capabilities.ray_tracing
  | Metal_fx -> value.capabilities.metal_fx
  | Sparse_memory -> value.sparse_memory
  | Unknown _ -> false

let require ?(operation="Ogpu.Caps.require") value feature =
  if has value feature then Ok ()
  else Error (Error.make operation Error.Unsupported
    "operation is unavailable on this adapter profile")
