open Ogpu_core
type control
val create : ?capabilities:Caps.t -> unit -> Backend.driver * control
val live_counts : control -> int * int * int * int * int
