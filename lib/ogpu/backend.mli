type token = int64
type command
type receipt = { epoch:int64 }
type synchronous_submission = { receipt:receipt; completion:(unit,Error.t) result }
(* The byte count covers cache-owned numeric identity/token metadata. Commands,
   resources, pipelines, and driver payloads remain externally owned. *)
type submission_cache_stats =
  { entries:int
  ; retained_bytes:int64
  ; entry_capacity:int
  ; byte_capacity:int64 }
type driver_resource = { token:token; write:int64 -> bytes -> (unit,Error.t) result;
  read:int64 -> int -> (bytes,Error.t) result;
  read_into:int64 -> bytes -> int -> int -> (unit,Error.t) result;
  destroy:unit -> (unit,Error.t) result }
type driver_pipeline = { pipeline_token:token; destroy_pipeline:unit -> (unit,Error.t) result }
type driver_frame = { frame_token:token }
type driver_surface =
  { surface_token:token
  ; configure:Surface.configuration -> (unit,Error.t) result
  ; acquire:unit -> ([ `Acquired of driver_frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
  ; acquire_sync:unit -> ([ `Acquired of driver_frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
  ; present:queue:token -> source:token -> driver_frame -> (unit,Error.t) result
  ; submit_present:queue:token -> source:token -> command ->
      resources:(int64*token) list -> pipelines:token list -> driver_frame ->
      (receipt,Error.t) result
  ; submit_present_sync:queue:token -> source:token -> command ->
      resources:(int64*token) list -> pipelines:token list -> driver_frame ->
      (synchronous_submission,Error.t) result
  ; discard:driver_frame -> (unit,Error.t) result
  ; destroy_surface:unit -> (unit,Error.t) result }
type driver_queue =
  { queue_token:token
  ; submit:command -> resources:(int64*token) list -> pipelines:token list -> (receipt,Error.t) result
  ; submit_sync:command -> resources:(int64*token) list -> pipelines:token list ->
      (synchronous_submission,Error.t) result
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
val create_queue : ?submission_cache_byte_capacity:int64 -> device ->
  (queue,Error.t) result
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
val read_texture_into : texture -> bytes_per_row:int -> destination:bytes ->
  (unit,Error.t) result
val transfer : Transfer_pass.t -> (command,Error.t) result
val compute : Compute_pass.t -> command
val render : Render_pass.t -> Render_pass.draw list -> (command,Error.t) result
val submit : queue -> command -> resources:[ `Buffer of buffer | `Texture of texture ] list -> pipelines:pipeline list -> (receipt,Error.t) result
val submit_sync : queue -> command ->
  resources:[ `Buffer of buffer | `Texture of texture ] list ->
  pipelines:pipeline list -> (synchronous_submission,Error.t) result
val complete_through : queue -> int64 -> (unit,Error.t) result
val configure : surface -> Surface.configuration -> (unit,Error.t) result
val acquire : surface -> ([ `Acquired of frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
val acquire_sync : surface -> ([ `Acquired of frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
val present : queue:queue -> source:texture -> frame -> (unit,Error.t) result
val submit_present : queue -> command ->
  resources:[ `Buffer of buffer | `Texture of texture ] list ->
  pipelines:pipeline list -> source:texture -> frame -> (receipt,Error.t) result
val submit_present_sync : queue -> command ->
  resources:[ `Buffer of buffer | `Texture of texture ] list ->
  pipelines:pipeline list -> source:texture -> frame ->
  (synchronous_submission,Error.t) result
val discard : frame -> (unit,Error.t) result
val destroy_buffer : buffer -> (unit,Error.t) result
val destroy_texture : texture -> (unit,Error.t) result
val destroy_pipeline : pipeline -> (unit,Error.t) result
val destroy_queue : queue -> (unit,Error.t) result
val destroy_surface : surface -> (unit,Error.t) result
val destroy_device : device -> (unit,Error.t) result

module Private : sig
  type command_view =
    | Transfer of Transfer_pass.description array
    | Compute of Compute_pass.description
    | Render of Render_pass.submission
  (** This view is borrowed and immutable. Driver implementations must not
      mutate reachable arrays or retain the view beyond the driver call. *)
  val command_view : command -> command_view
  val snapshot_command : command_view -> command
  val command_retained_bytes : command -> int64
  val submission_cache_stats : queue -> submission_cache_stats
  val submission_cache_contains : queue -> command ->
    resources:[ `Buffer of buffer | `Texture of texture ] list ->
    pipelines:pipeline list -> bool
end
