type resource = Buffer of Buffer.t | Texture of Texture.t
type t

val create : Device.t -> capacity:int -> (t, Ogpu_core.Error.t) result
val add_error : t -> ?label:string -> Ogpu_core.Error.t -> (unit, Ogpu_core.Error.t) result
val classify_metal_error : operation:string -> Metal.error -> Ogpu_core.Error.t
val messages : t -> Ogpu_core.Diagnostics.message list
val dropped : t -> int
val serialize_capture : Device.t -> label:string -> resources:resource list ->
  commands:Command.t list -> (string, Ogpu_core.Error.t) result
val capture_hash : Device.t -> label:string -> resources:resource list ->
  commands:Command.t list -> (string, Ogpu_core.Error.t) result
val destroy : t -> unit
