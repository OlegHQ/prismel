type buffer_range = { resource_id:int64; buffer:unit Handle.t; buffer_size:int64; offset:int64; length:int64 }
type operation = Build of Acceleration.t | Refit of Acceleration.t | Copy of Acceleration.t | Compact of Acceleration.t
type operation_kind = Build_op | Refit_op | Copy_op | Compact_op
type result = { kind:operation_kind; copied:Acceleration.t option; commands:Command.description array }
val execute : Handle.device -> ray_tracing:bool -> operation -> scratch:buffer_range -> auxiliary:buffer_range option -> (result,Error.t) Stdlib.result
