type buffer_usage = Copy_src | Copy_dst | Uniform | Storage | Vertex | Index
type buffer_descriptor = { label:string option; size:int64; usage:buffer_usage list }
type texture_usage = Texture_binding | Render_attachment | Texture_copy_src | Texture_copy_dst
type texture_descriptor =
  { label:string option; width:int; height:int; depth:int; mip_levels:int
  ; sample_count:int; usage:texture_usage list }
val validate_buffer : Capabilities.t -> buffer_descriptor -> (unit,Error.t) result
val validate_texture : Capabilities.t -> texture_descriptor -> (unit,Error.t) result
