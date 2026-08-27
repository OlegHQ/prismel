type t
type receipt={epoch:int64}
val create : ?max_frames:int -> Device.t -> (t,Ogpu.Error.t) result
val submit : t -> Command.t -> (receipt,Ogpu.Error.t) result
val submit_render_pass : t -> Render_pass.t -> (receipt,Ogpu.Error.t) result
val submit_transfer_pass : t -> Transfer_pass.t -> (receipt,Ogpu.Error.t) result
val submit_compute_pass : t -> Compute_pass.t -> (receipt,Ogpu.Error.t) result
val wait_through : t -> int64 -> (unit,Ogpu.Error.t) result
val in_flight : t -> int
val completed_epoch : t -> int64
val inject_next_error : t -> unit
val destroyed : t -> bool
val destroy : t -> (unit,Ogpu.Error.t) result
