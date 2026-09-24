type t
type receipt={epoch:int64}
type synchronous_submission={receipt:receipt;completion:(unit,Ogpu.Error.t)result}
type presentation=Metal.Command_buffer.t -> (unit,Ogpu.Error.t) result
type gpu_timing={supported:bool;duration_seconds:float;sample_count:int64}
val gpu_timing_for_device : Device.t -> gpu_timing
val create : ?max_frames:int -> Device.t -> (t,Ogpu.Error.t) result
val submit : t -> Command.t -> (receipt,Ogpu.Error.t) result
val submit_render_pass : t -> Render_pass.t ->
  (receipt,Ogpu.Error.t) result
val submit_render_pass_present : t -> presentation -> Render_pass.t ->
  (receipt,Ogpu.Error.t) result
val submit_render_pass_sync : t -> Render_pass.t ->
  (synchronous_submission,Ogpu.Error.t) result
val submit_render_pass_present_sync : t -> presentation -> Render_pass.t ->
  (synchronous_submission,Ogpu.Error.t) result
val submit_transfer_pass : t -> Transfer_pass.t -> (receipt,Ogpu.Error.t) result
val submit_compute_pass : t -> Compute_pass.t -> (receipt,Ogpu.Error.t) result
val wait_through : t -> int64 -> (unit,Ogpu.Error.t) result
val in_flight : t -> int
val completed_epoch : t -> int64
val inject_next_error : t -> unit
val inject_next_completion_error : t -> unit
val destroyed : t -> bool
val destroy : t -> (unit,Ogpu.Error.t) result
module Private : sig
  val metal : t -> Metal.Command_queue.t
  val gpu_timing_total : unit -> gpu_timing
  val gpu_timing_entry_count : unit -> int
  val valid_gpu_duration : float -> bool
  val arm_scoped_render : ?on_committed:(int64 -> unit) -> t -> unit
  val take_scoped_completion : t -> (unit,Ogpu.Error.t) result option
end
