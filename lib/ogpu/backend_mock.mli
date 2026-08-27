type control
val create : ?capabilities:Capabilities.t -> unit -> Backend.driver * control
val inject_device_loss : control -> unit
val trace : control -> string list
val clear_trace : control -> unit
val live_counts : control -> int * int * int * int * int
