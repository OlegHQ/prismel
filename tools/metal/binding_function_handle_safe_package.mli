type function_type = Vertex | Fragment | Kernel | Intersection | Mesh | Object
type native_kind = Function_handle | Other_handle
type device = { token : int; destroyed : bool }
type t
val callable_ids : string list
val create : native_kind:native_kind -> device:device -> function_type:function_type -> gpu_resource_id:int64 -> name:string -> (t, string) result
val device : t -> (device, string) result
val function_type : t -> (function_type, string) result
val gpu_resource_id : t -> (int64, string) result
val name : t -> (string, string) result
val destroy : t -> unit
val validate_handoff : unit -> unit
