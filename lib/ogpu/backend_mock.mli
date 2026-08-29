type control
val create : ?capabilities:Capabilities.t -> unit -> Backend.driver * control
val inject_device_loss : control -> unit
val fail_texture_allocation_after : control -> int -> unit
val fail_depth_allocation_after : control -> int -> unit
val fail_next_configure : control -> unit
val inject_next_completion_error : control -> unit
val trace : control -> string list
val clear_trace : control -> unit
val live_counts : control -> int * int * int * int * int
