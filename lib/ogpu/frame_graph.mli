type tracking = Safe | Untracked
type resource = { id:int64; handle:unit Handle.t; initialized:bool }
type access = { resource_id:int64; access:Command.access; stages:Command.stage list }
type pass = { id:int; kind:Command.pass; accesses:access array; depends_on:int array; barriers:int64 array; native:Native_pass.plan option }
type scheduled = { id:int; commands:Command.description array; native_resource_count:int }
val compile : Handle.device -> tracking:tracking -> resources:resource array -> passes:pass array -> (scheduled array,Error.t) result
