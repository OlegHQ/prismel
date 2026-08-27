type color_format = Rgba8_unorm | Bgra8_unorm
type depth_format = No_depth | Depth32_float
type render_descriptor =
  { backend : string; label : string option; layout : Binding.pipeline_layout
  ; vertex : Shader.t; vertex_entry : string
  ; fragment : Shader.t option; fragment_entry : string option
  ; color_format : color_format; depth_format : depth_format; sample_count : int }
type compute_descriptor =
  { backend : string; label : string option; layout : Binding.pipeline_layout
  ; shader : Shader.t; entry : string }
type kind = Render | Compute
type t

val create_render : Capabilities.t -> render_descriptor -> (t, Error.t) result
val create_compute : Capabilities.t -> compute_descriptor -> (t, Error.t) result
val kind : t -> kind
val backend : t -> string
val label : t -> string option
val cache_key : t -> string
val description : t -> string
