type capability_source =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  ; ray_tracing : bool
  ; metal_fx : bool
  }

let capabilities source =
  let value : Ogpu.Capabilities.t =
    { limits =
        { max_buffer_size = source.max_buffer_size
        ; max_texture_dimension_2d = source.max_texture_dimension_2d
        ; max_bind_groups = source.max_bind_groups
        ; max_sample_count = source.max_sample_count
        }
    ; ray_tracing = source.ray_tracing
    ; metal_fx = source.metal_fx
    }
  in
  Result.map (fun () -> value) (Ogpu.Capabilities.validate value)

type operation=Buffer|Texture|Sampler|Compute_pipeline|Render_pipeline|Queue|Surface|Memory|Native_pass|Event_synchronization|Timeline_fence|Timestamp_queries|Ray_tracing|Metal_fx|Sparse_memory|Unknown of string
type profile={capabilities:Ogpu.Capabilities.t;timestamp_queries:bool;sparse_memory:bool;conservative_limits:string list}
let profile source ~timestamp_queries ~sparse_memory:_ ~conservative_limits=
  Result.map(fun capabilities->{capabilities={capabilities with metal_fx=false};timestamp_queries;sparse_memory=false;conservative_limits})(capabilities source)
let supports value operation=
  let supported=match operation with
    |Buffer|Texture|Sampler|Compute_pipeline|Render_pipeline|Queue|Surface|Memory|Native_pass|Event_synchronization->true
    |Timeline_fence->false
    |Timestamp_queries->value.timestamp_queries
    |Ray_tracing->value.capabilities.ray_tracing
    |Metal_fx->value.capabilities.metal_fx
    |Sparse_memory->value.sparse_memory
    |Unknown _->false in
  if supported then Ok()else Error(Ogpu.Error.make"Ogpu_metal.Adapter.supports"Ogpu.Error.Unsupported"operation is unavailable on this adapter profile")

let error ~operation (value : Metal.error) =
  let kind =
    match value.kind with
    | Metal.Invalid_argument -> Ogpu.Error.Invalid_argument
    | Metal.Invalid_state | Metal.Parent_has_dependents -> Ogpu.Error.Invalid_state
    | Metal.Destroyed -> Ogpu.Error.Stale_handle
    | Metal.Device_mismatch -> Ogpu.Error.Cross_device
    | Metal.Unsupported -> Ogpu.Error.Unsupported
    | Metal.Native_error | Metal.Wrong_domain | Metal.Release_queue_overflow ->
        Ogpu.Error.Device_lost
  in
  Ogpu.Error.make operation kind value.message
