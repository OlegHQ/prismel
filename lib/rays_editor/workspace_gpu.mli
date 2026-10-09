type t
val create : unit -> t
val with_backend : t -> (unit -> 'a) -> 'a
val qualification : t -> unit
val policy : t -> Flow_ir.Gpu.policy
val image : t -> key:string -> width:int -> height:int ->
  publish:(Flow_gpu.Image_sink.output -> ('a,Flow.Diagnostic.t) result) ->
  Flow_ir.Gpu.value -> ('a,Flow.Diagnostic.t) result
val circles : t -> Flow_ir.Gpu.value -> radius:float -> fill:int32 -> stroke:int32 -> stroke_width:float ->
  (Scene_command.Shape_batch.gpu_token,Flow.Diagnostic.t)result
val close : t -> unit
val image_stats : t -> Flow_gpu.Host.Private.stats * int * int * int * int
(** Host totals, sinks created/closed and sink buffer/texture creations, including
    failed uncommitted sinks and totals retained after close. *)
