type status = Pending | Completed

(** Polls a submitted receipt without waiting. Terminal GPU errors are returned
    as typed errors after the queue releases its submission resources. *)
val status : Backend.queue -> Backend.receipt -> (status, Error.t) result

val completed_epoch : Backend.queue -> int64
