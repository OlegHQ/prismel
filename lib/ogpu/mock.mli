type profile = M1 | M3_plus | Missing_ray_tracing | Missing_metal_fx | Future_unknown
type operation = Create_queue | Create_buffer | Create_texture
type capacities = { queues : int; buffers : int; textures : int }
type device
type queue
type buffer
type texture

val create_device : profile:profile -> capacities:capacities -> (device, Error.t) result
val device_id : device -> int64
val capabilities : device -> Capabilities.t
val destroy_device : device -> unit
val inject_fault : device -> operation -> unit
val require_ray_tracing : device -> (unit, Error.t) result
val require_metal_fx : device -> (unit, Error.t) result

val create_queue : device -> (queue, Error.t) result
val queue_id : queue -> int64
val destroy_queue : queue -> unit
val validate_queue : device -> queue -> (unit, Error.t) result

val create_buffer : device -> Types.buffer_descriptor -> (buffer, Error.t) result
val buffer_id : buffer -> int64
val buffer_descriptor : device -> buffer -> (Types.buffer_descriptor, Error.t) result
val destroy_buffer : buffer -> unit

val create_texture : device -> Types.texture_descriptor -> (texture, Error.t) result
val texture_id : texture -> int64
val texture_descriptor : device -> texture -> (Types.texture_descriptor, Error.t) result
val destroy_texture : texture -> unit

val live_counts : device -> int * int * int
