type descriptor = { pass:Command.pass; queries:Sync.query_set; first:int; count:int; destination:unit Handle.t; destination_resource_id:int64; destination_size:int64; destination_offset:int64; completion_epoch:int64 }
type t
type description = { resolve:Sync.description; commands:Command.description array }
val create : Handle.device -> timestamp_queries:bool -> descriptor -> (t,Error.t) result
val describe : t -> description
