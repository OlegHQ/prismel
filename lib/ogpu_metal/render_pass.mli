type stage = Vertex | Fragment
type primitive = Triangle_list | Triangle_strip
type index_type = Uint16 | Uint32
type buffer_binding = { stage:stage; index:int; buffer:Buffer.t; offset:int64 }
type texture_binding = { stage:stage; index:int; texture:Texture.t }
type sampler_binding = { stage:stage; index:int; sampler:Sampler.t }
type draw =
  { pipeline:Pipeline.t
  ; buffers:buffer_binding list
  ; textures:texture_binding list
  ; samplers:sampler_binding list
  ; primitive:primitive
  ; vertex_start:int
  ; vertex_count:int
  ; index:(index_type * Buffer.t * int64 * int) option
  }
type t

val attachment : Device.t -> Texture.t -> usage:Ogpu.Render_pass.usage ->
  (Ogpu.Render_pass.texture,Ogpu.Error.t) result
val create : Device.t -> Ogpu.Render_pass.t -> attachments:Texture.t list ->
  draw -> (t,Ogpu.Error.t) result
val create_empty : Device.t -> Ogpu.Render_pass.t -> attachments:Texture.t list ->
  (t,Ogpu.Error.t) result
val create_batch : ?owned_samplers:Sampler.t list -> Device.t -> Ogpu.Render_pass.t -> attachments:Texture.t list ->
  draw list -> (t,Ogpu.Error.t) result
val with_indirect : t -> Metal.Indirect_command_buffer.t -> vertex_resources:Metal.Render_encoder.prepared_resources -> fragment_resources:Metal.Render_encoder.prepared_resources -> texture_resources:Metal.Render_encoder.prepared_resources -> t
val replay_indirect : t -> template:t -> t

module Private : sig
  val destroy : t -> (unit,Ogpu.Error.t) result
  val retain_encoding : t -> unit
  val encode_portable : t -> Ogpu.Command.t -> (unit,Ogpu.Error.t) result
  val retain : t -> ((unit -> unit) list,Ogpu.Error.t) result
  val encode : Metal.Command_buffer.t -> t -> ((unit -> unit) list,Ogpu.Error.t) result
  val portable_requires_command4 : Ogpu.Render_pass.t -> bool
  val requires_command4 : t -> bool
  val validation_retained : t -> bool
  val encode_command4 : Metal.Command4.Command_buffer.t -> t -> ((unit -> unit) list,Ogpu.Error.t) result
end
