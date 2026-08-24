type resource = { token : int; device : int; length : int; destroyed : bool }
type binding = { resource : resource; offset : int; stride : int option }
type command
val empty : device:int -> max_slots:int -> command
val set_binding : command -> slot:int -> binding -> (command, string) result
val set_pipeline : command -> resource -> (command, string) result
val validate_draw : command -> vertex_count:int -> instance_count:int -> (unit, string) result
val validate_indexed_draw : command -> index_buffer:resource -> index_offset:int -> index_count:int -> index_size:int -> (unit, string) result
val validate_patch_draw : command -> patch_start:int -> patch_count:int -> control_points:int -> patch_indices:resource option -> tessellation:resource -> tessellation_offset:int -> tessellation_stride:int -> instance_count:int -> (unit, string) result
val retained_tokens : command -> int list
val reset : command -> command
val validate_handoff : unit -> unit
