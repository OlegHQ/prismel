type capability_source =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  ; ray_tracing : bool
  ; metal_fx : bool
  }

let capabilities source =
  let value : Ogpu.Caps.t =
    { limits =
        { max_buffer_size = source.max_buffer_size
        ; max_texture_dimension_2d = source.max_texture_dimension_2d
        ; max_bind_groups = source.max_bind_groups
        ; max_sample_count = source.max_sample_count
        }
    ; ray_tracing = source.ray_tracing
    ; metal_fx = source.metal_fx
    ; timestamp_queries = false
    ; sparse_memory = false
    ; conservative_limits = []
    }
  in
  Result.map (fun () -> value) (Ogpu.Caps.validate value)

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
