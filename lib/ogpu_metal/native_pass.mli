type resource = Buffer of Buffer.t | Texture of Texture.t
type action =
  | Copy_buffer of {source:Buffer.t;source_offset:int64;destination:Buffer.t;destination_offset:int64;length:int64}
  | Dispatch of {pipeline:Pipeline.t;buffer:Buffer.t;threads:int}

val declaration : resource -> access:Ogpu.Command.access ->
  stages:Ogpu.Command.stage list -> owner:Ogpu.Native_pass.owner ->
  resulting_state:Ogpu.Native_pass.resource_state -> Ogpu.Native_pass.declaration
val record : Device.t -> Command.t -> Ogpu.Native_pass.plan ->
  resources:resource list -> Ogpu.Native_pass.callback -> action ->
  (unit,Ogpu.Error.t) result
