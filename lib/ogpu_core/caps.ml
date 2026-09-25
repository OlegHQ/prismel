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

let minimum_m1 =
  { limits = { max_buffer_size = 268_435_456L
             ; max_texture_dimension_2d = 16_384
             ; max_bind_groups = 4
             ; max_sample_count = 4 }
  ; compute_pipeline = true; ray_tracing = false; metal_fx = false; timestamp_queries = false
  ; sparse_memory = false; conservative_limits = [] }

let validate value =
  let limits = value.limits in
  if limits.max_buffer_size <= 0L || limits.max_texture_dimension_2d <= 0
     || limits.max_bind_groups <= 0 || limits.max_sample_count <= 0 then
    Error (Error.make "Ogpu.Caps.validate" Error.Invalid_argument
      "limits must be positive")
  else Ok ()

let create value ~timestamp_queries ~sparse_memory ~conservative_limits =
  Result.map (fun () ->
    { value with timestamp_queries; sparse_memory; conservative_limits })
    (validate value)

let has value = function
  | Buffer | Texture | Sampler | Render_pipeline | Queue
  | Surface | Memory | Event_synchronization -> true
  | Compute_pipeline -> value.compute_pipeline
  | Timeline_fence -> false
  | Timestamp_queries -> value.timestamp_queries
  | Ray_tracing -> value.ray_tracing
  | Metal_fx -> value.metal_fx
  | Sparse_memory -> value.sparse_memory
  | Unknown _ -> false

let require ?(operation="Ogpu.Caps.require") value feature =
  if has value feature then Ok ()
  else Error (Error.make operation Error.Unsupported
    "operation is unavailable on this adapter profile")
