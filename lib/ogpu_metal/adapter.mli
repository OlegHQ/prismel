type capability_source =
  { max_buffer_size : int64
  ; max_texture_dimension_2d : int
  ; max_bind_groups : int
  ; max_sample_count : int
  ; ray_tracing : bool
  ; metal_fx : bool
  }

val capabilities : capability_source -> (Ogpu.Capabilities.t, Ogpu.Error.t) result
val error : operation:string -> Metal.error -> Ogpu.Error.t
