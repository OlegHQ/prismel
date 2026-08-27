type metadata =
  { source_hash:string; artifact_hash:string; compiler:string; sdk:string
  ; target:string; deployment:string; flags:string list }
type t
val load : source:Ogpu.Shader.t -> metallib:string -> metadata:string ->
  (t,Ogpu.Error.t) result
val metallib : t -> string
val metadata : t -> metadata
val hash_file : string -> (string,Ogpu.Error.t) result
