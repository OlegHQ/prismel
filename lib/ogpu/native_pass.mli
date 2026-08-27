type owner = Ogpu | Native
type resource_state = Undefined | Shader_read | Shader_write | Copy_source | Copy_destination | Acceleration_read | Acceleration_write
type declaration = { resource_id:int64; resource:unit Handle.t; access:Command.access; stages:Command.stage list; owner:owner; resulting_state:resource_state }
type transition = { resource_id:int64; before:resource_state; after:resource_state }
type plan
type 'scope encoder
type callback = { run : 'scope. 'scope encoder -> (unit,Error.t) result }
val create : Handle.device -> declarations:declaration array -> transitions:transition array -> (plan,Error.t) result
val execute : plan -> callback -> (unit,Error.t) result
val declarations : plan -> declaration array
val transitions : plan -> transition array
