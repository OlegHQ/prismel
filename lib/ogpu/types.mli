type buffer_usage = Copy_src | Copy_dst | Uniform | Storage | Vertex | Index
type buffer_descriptor = { label:string option; size:int64; usage:buffer_usage list }
type texture_usage = Texture_binding | Render_attachment | Texture_copy_src | Texture_copy_dst
type texture_descriptor =
  { label:string option; width:int; height:int; depth:int; mip_levels:int
  ; sample_count:int; usage:texture_usage list }
type sampler_filter = Nearest | Linear
type mip_filter = No_mip | Nearest_mip | Linear_mip
type address_mode = Clamp_to_edge | Repeat | Mirror_repeat
type sampler_descriptor =
  { label:string option; min_filter:sampler_filter; mag_filter:sampler_filter
  ; mip_filter:mip_filter; address_u:address_mode; address_v:address_mode
  ; lod_min:float; lod_max:float; max_anisotropy:int }
val validate_buffer : Capabilities.t -> buffer_descriptor -> (unit,Error.t) result
val validate_texture : Capabilities.t -> texture_descriptor -> (unit,Error.t) result
val validate_sampler : sampler_descriptor -> (unit,Error.t) result
