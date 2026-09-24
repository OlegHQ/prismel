type buffer = { token : int; device : int; length : int; destroyed : bool }
type buffer_range = { buffer : buffer; offset : int; stride : int; count : int; element_size : int }
type vertex_format = Float3 | Float4
type index_format = UInt16 | UInt32
type geometry = Bounding_boxes of buffer_range | Triangles of buffer_range * index_format option | Curves of buffer_range | Motion of geometry list
type instance_record = { acceleration_structure_index : int; options : int; mask : int; intersection_function_table_offset : int }
type descriptor = Geometry of geometry | Instances of buffer_range | Indirect_instances of buffer_range | Primitive of geometry list | Motion_keyframe of buffer_range
val validate_buffer_range : device:int -> buffer_range -> (unit, string) result
val create : device:int -> descriptor -> (descriptor, string) result
val validate_instance_record : instance_record -> (instance_record, string) result
val retained_tokens : descriptor -> int list
val validate_handoff : unit -> unit
