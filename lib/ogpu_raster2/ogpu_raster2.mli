type control
val create : unit -> Ogpu.Backend.driver * control
val inject_device_loss : control -> unit
val trace : control -> string list
val trace_stats : control -> int * int
val live_counts : control -> int * int * int * int * int
