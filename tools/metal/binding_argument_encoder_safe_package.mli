type resource_kind = Buffer | Texture | Sampler | Render_pipeline | Compute_pipeline | Indirect_command_buffer
type resource = { token : int; device : int; kind : resource_kind; destroyed : bool }
type range = { location : int; length : int }
type retained = resource option array
val callable_ids : string list
val validate_resource : device:int -> expected:resource_kind -> resource option -> (resource option, string) result
val validate_array : capacity:int -> device:int -> expected:resource_kind -> range:range -> resource option array -> (resource option array, string) result
val replace_atomic : retained -> range:range -> resource option array -> (retained, string) result
type encoder = { token : int; device : int; parent : encoder option; mutable destroyed : bool }
val nested : parent:encoder -> token:int -> (encoder, string) result
type constant_policy = Availability_only
val constant_policy : constant_policy
val validate_handoff : unit -> unit
