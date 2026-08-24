type store_action = Dont_care | Store | Multisample_resolve | Store_and_multisample_resolve
type store_options = No_options | Custom_sample_positions
type attachment = { token : int; device : int; destroyed : bool }
type parent
type child
val callable_ids : string list
val create_parent : device:int -> colors:attachment option array -> depth:attachment option -> stencil:attachment option -> (parent, string) result
val create_child : parent -> token:int -> (child, string) result
val set_color_store : parent -> index:int -> store_action -> store_options -> (unit, string) result
val set_depth_store : parent -> store_action -> store_options -> (unit, string) result
val set_stencil_store : parent -> store_action -> store_options -> (unit, string) result
val end_child : child -> (unit, string) result
val end_parent : parent -> (unit, string) result
val retained_attachment_tokens : parent -> int list
val parent_device : parent -> int
val child_token : child -> int
val configured_write_count : parent -> int
val validate_handoff : unit -> unit
