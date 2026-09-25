type t
type frame
type acquire_result = Acquired of frame | Timeout | Occluded | Device_lost

val create : Device.t -> layer:Metal.Metal_layer.t ->
  Ogpu_core.Surface.configuration -> (t,Ogpu_core.Error.t) result
val configure : t -> Ogpu_core.Surface.configuration -> (unit,Ogpu_core.Error.t) result
val resize : t -> logical_width:int -> logical_height:int ->
  physical_width:int -> physical_height:int -> (unit,Ogpu_core.Error.t) result
val set_availability : t -> Ogpu_core.Surface.availability -> unit
val acquire : t -> (acquire_result,Ogpu_core.Error.t) result
val frame_id : frame -> int64
val frame_generation : frame -> int64
val frame_texture : frame -> (Metal.Texture.t,Ogpu_core.Error.t) result
val discard : t -> frame -> (unit,Ogpu_core.Error.t) result
val generation : t -> int64
val outstanding : t -> int
val in_flight_presentations : t -> int
val destroyed : t -> bool
val destroy : t -> unit

module Private : sig
  val acquire_scoped : t -> (acquire_result,Ogpu_core.Error.t) result
  type pending_presentation

  (** Reusable backend-owned presentation state.  A queue keeps only its native
      command/resources; completion of these concrete epoch-tagged slots is
      driven by the backend after [Queue.wait_through]. *)
  val create_pending_presentation : unit -> pending_presentation
  val pending_presentation_available : pending_presentation -> bool
  val prepare_present :
    pending_presentation -> t -> frame -> source:Texture.t ->
    (unit,Ogpu_core.Error.t) result
  val presentation_encoder : pending_presentation -> Metal.Command_buffer.t -> (unit,Ogpu_core.Error.t) result
  val rollback_present : pending_presentation -> unit
  val commit_present : pending_presentation -> epoch:int64 -> unit
  val complete_presentations_through :
    pending_presentation array -> int64 -> unit
  val clear_pending_presentations : pending_presentation array -> unit
end
