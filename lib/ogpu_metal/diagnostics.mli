type resource = Buffer of Buffer.t | Texture of Texture.t
type t

val create : Device.t -> capacity:int -> (t, Ogpu.Error.t) result
val add_error : t -> ?label:string -> Ogpu.Error.t -> (unit, Ogpu.Error.t) result
val classify_metal_error : operation:string -> Metal.error -> Ogpu.Error.t
val messages : t -> Ogpu.Diagnostics.message list
val dropped : t -> int
val serialize_capture : Device.t -> label:string -> resources:resource list ->
  commands:Command.t list -> (string, Ogpu.Error.t) result
val capture_hash : Device.t -> label:string -> resources:resource list ->
  commands:Command.t list -> (string, Ogpu.Error.t) result
val destroy : t -> unit
