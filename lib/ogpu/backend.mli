type token = int64
type command =
  | Transfer of Transfer_pass.description array
  | Compute of Compute_pass.description
  | Render of Render_pass.submission
type receipt = { epoch:int64 }
type driver_resource = { token:token; write:int64 -> bytes -> (unit,Error.t) result; read:int64 -> int -> (bytes,Error.t) result; destroy:unit -> (unit,Error.t) result }
type driver_pipeline = { pipeline_token:token; destroy_pipeline:unit -> (unit,Error.t) result }
type driver_frame = { frame_token:token }
type driver_surface =
  { surface_token:token
  ; configure:Surface.configuration -> (unit,Error.t) result
  ; acquire:unit -> ([ `Acquired of driver_frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
  ; present:driver_frame -> (unit,Error.t) result
  ; discard:driver_frame -> (unit,Error.t) result
  ; destroy_surface:unit -> (unit,Error.t) result }
type driver_queue =
  { queue_token:token
  ; submit:command -> resources:(int64*token) list -> pipelines:token list -> (receipt,Error.t) result
  ; complete_through:int64 -> (unit,Error.t) result
  ; destroy_queue:unit -> (unit,Error.t) result }
type driver_device =
  { device_token:token; device_handle:Handle.device; capabilities:Capabilities.t
  ; create_buffer:Types.buffer_descriptor -> (driver_resource,Error.t) result
  ; create_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_depth_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_stencil_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_pipeline:Pipeline.t -> (driver_pipeline,Error.t) result
  ; create_queue:unit -> (driver_queue,Error.t) result
  ; create_surface:Surface.configuration -> (driver_surface,Error.t) result
  ; destroy_device:unit -> (unit,Error.t) result }
type driver = { create_device:unit -> (driver_device,Error.t) result }

type device
type buffer
type texture
type pipeline
type queue
type surface
type frame

val create_device : driver -> (device,Error.t) result
val capabilities : device -> Capabilities.t
val device_handle : device -> Handle.device
val create_buffer : device -> Types.buffer_descriptor -> (buffer,Error.t) result
val create_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val create_depth_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val create_stencil_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val adopt_pipeline : device -> Pipeline.t -> (pipeline,Error.t) result
val create_queue : device -> (queue,Error.t) result
val create_surface : device -> Surface.configuration -> (surface,Error.t) result
val transfer_buffer : buffer -> Transfer_pass.buffer
val transfer_texture : texture -> Transfer_pass.texture
val binding_buffer : buffer -> Binding.resource
val binding_texture : texture -> Binding.resource
val buffer_id : buffer -> int64
val texture_id : texture -> int64
val render_texture : texture -> format:Render_pass.format -> usage:Render_pass.usage -> Render_pass.texture
val write_buffer : buffer -> offset:int64 -> bytes -> (unit,Error.t) result
val read_buffer : buffer -> offset:int64 -> length:int -> (bytes,Error.t) result
val read_texture : texture -> bytes_per_row:int -> (bytes,Error.t) result
val transfer : Transfer_pass.t -> (command,Error.t) result
val compute : Compute_pass.t -> command
val render : Render_pass.t -> Render_pass.draw list -> (command,Error.t) result
val submit : queue -> command -> resources:[ `Buffer of buffer | `Texture of texture ] list -> pipelines:pipeline list -> (receipt,Error.t) result
val complete_through : queue -> int64 -> (unit,Error.t) result
val configure : surface -> Surface.configuration -> (unit,Error.t) result
val acquire : surface -> ([ `Acquired of frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
val present : frame -> (unit,Error.t) result
val discard : frame -> (unit,Error.t) result
val destroy_buffer : buffer -> (unit,Error.t) result
val destroy_texture : texture -> (unit,Error.t) result
val destroy_pipeline : pipeline -> (unit,Error.t) result
val destroy_queue : queue -> (unit,Error.t) result
val destroy_surface : surface -> (unit,Error.t) result
val destroy_device : device -> (unit,Error.t) result
