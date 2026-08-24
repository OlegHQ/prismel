type data_type = Bool | Int32 | UInt32 | Float32 | Int64 | Unsupported of int
type value = Bool_value of bool | Int32_value of int32 | UInt32_value of int32 | Float32_value of float | Int64_value of int64
type t
val callable_ids : string list
val create : max_constants:int -> (t, string) result
val set_single : t -> index:int -> data_type:data_type -> value -> (unit, string) result
val set_range : t -> start:int -> length:int -> data_type:data_type -> value list -> (unit, string) result
val snapshot : t -> (int * data_type * value) list
val reset : t -> unit
val validate_handoff : unit -> unit
