type capability = Ray_tracing | Metal_fx | Timestamp_queries | Unknown of string
type adapter_descriptor = { backend_id:string; name:string; priority:int; capabilities:capability list; limits:Capabilities.limits }
type t
type adapter
type device
val create : adapter_descriptor list -> (t,Error.t) result
val adapters : t -> (adapter array,Error.t) result
val select : t -> required:capability list -> (adapter,Error.t) result
val adapter_id : adapter -> int64
val adapter_descriptor : adapter -> adapter_descriptor
val request_device : adapter -> required:capability list -> (device,Error.t) result
val device_handle : device -> Handle.device
val device_generation : device -> int64
val destroy_device : device -> unit
val destroy_adapter : adapter -> unit
val destroy : t -> unit
