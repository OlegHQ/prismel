type dispatch = Direct of { x:int; y:int; z:int } | Indirect of { buffer:unit Handle.t; buffer_size:int64; offset:int64 }
type resource = { id:int64; access:Command.access; stages:Command.stage list }
type t
type description = { pipeline_key:string; groups:(int * (int * Binding.kind) list) array; dispatch:dispatch; commands:Command.description array }
val create : Handle.device -> limits:Capabilities.limits -> pipeline:Pipeline.t -> layout:Binding.pipeline_layout -> groups:(int * Binding.bind_group) array -> resources:resource array -> dispatch:dispatch -> (t,Error.t) result
val describe : t -> description
module Private : sig
  val of_description : description -> t
  val map_resource_ids : (int64 -> int64) -> description -> description
end
