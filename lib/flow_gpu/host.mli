type t
val create : ?cost:(Flow_ir.Packed.t -> count:int -> float option) ->
  clock:(unit -> float) -> Rays_execution.gpu -> t
(** Owns at most 64 runners and 64 pipelines. An absent cost keeps production
    CPU placement until native measurements supply a model. The caller owns the GPU lease. *)

val backend : t -> Flow_ir.Gpu.backend
val output : t -> Flow_ir.Gpu.value -> Run.output option
(** Borrow the current output; closed, evicted or superseded generations return [None]. *)

val close : t -> unit
(** Close before releasing the caller's GPU lease. *)
