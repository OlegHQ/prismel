type t
type frame
type acquire_result = Acquired of frame | Timeout | Occluded | Device_lost

val create : Device.t -> layer:Metal.Metal_layer.t ->
  Ogpu.Surface.configuration -> (t,Ogpu.Error.t) result
val configure : t -> Ogpu.Surface.configuration -> (unit,Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int ->
  physical_width:int -> physical_height:int -> (unit,Ogpu.Error.t) result
val set_availability : t -> Ogpu.Surface.availability -> unit
val acquire : t -> (acquire_result,Ogpu.Error.t) result
val frame_id : frame -> int64
val frame_generation : frame -> int64
val frame_texture : frame -> (Metal.Texture.t,Ogpu.Error.t) result
val present_from :
  t -> frame -> queue:Queue.t -> source:Texture.t ->
  (unit,Ogpu.Error.t) result
val discard : t -> frame -> (unit,Ogpu.Error.t) result
val generation : t -> int64
val outstanding : t -> int
val in_flight_presentations : t -> int
val destroyed : t -> bool
val destroy : t -> unit

module Private : sig
  val acquire_scoped : t -> (acquire_result,Ogpu.Error.t) result
  type pending_presentation

  (** Creates the only non-framebuffer-only surface configuration.  This is
      restricted to exact drawable-byte tests; production uses [create]. *)
  val create_readable : Device.t -> layer:Metal.Metal_layer.t ->
    Ogpu.Surface.configuration -> (t,Ogpu.Error.t) result

  (** Exercises the same GPU-only presentation conversion with an ordinary
      readable BGRA8 render target.  Intended for exact backend tests. *)
  val render_for_test :
    t -> queue:Queue.t -> source:Texture.t -> target:Texture.t ->
    (unit,Ogpu.Error.t) result

  (** Renders into the actual drawable texture and leaves [frame] live so its
      exact native BGRA bytes can be inspected before discard/presentation. *)
  val render_source_into_frame :
    t -> frame -> queue:Queue.t -> source:Texture.t ->
    (unit,Ogpu.Error.t) result

  (** Copies a rendered private drawable into an ordinary readable BGRA8
      target through the GPU, without consuming the frame. *)
  val copy_frame_for_test :
    t -> frame -> queue:Queue.t -> target:Texture.t ->
    (unit,Ogpu.Error.t) result

  (** Reusable backend-owned presentation state.  A queue keeps only its native
      command/resources; completion of these concrete epoch-tagged slots is
      driven by the backend after [Queue.wait_through]. *)
  val create_pending_presentation : unit -> pending_presentation
  val pending_presentation_available : pending_presentation -> bool
  val prepare_present :
    pending_presentation -> t -> frame -> source:Texture.t ->
    (unit,Ogpu.Error.t) result
  val presentation_encoder : pending_presentation -> Queue.presentation
  val presentation_encoder_scoped : pending_presentation -> Queue.presentation
  val rollback_present : pending_presentation -> unit
  val commit_present : pending_presentation -> epoch:int64 -> unit
  val complete_presentations_through :
    pending_presentation array -> int64 -> unit
  val clear_pending_presentations : pending_presentation array -> unit
end
