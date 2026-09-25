type color_format = Rgba8_unorm | Bgra8_unorm
type depth_format = No_depth | Depth32_float | Stencil8 | Depth32_float_stencil8
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract
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

val create_render : ?blend:blend -> Caps.t -> render_descriptor -> (t, Error.t) result
val create_compute : Caps.t -> compute_descriptor -> (t, Error.t) result
val kind : t -> kind
val backend : t -> string
val label : t -> string option
val cache_key : t -> string
val description : t -> string

module Private : sig
  (** A compute pipeline identity created from a shared library entry point;
      its key is the library provenance, entry name, and constants. *)
  val compute_of_key : ?label:string -> string -> t

  (** A mesh or tile pipeline identity created from a shared library. *)
  val render_of_key : ?label:string -> string -> t
end
