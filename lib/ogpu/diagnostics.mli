type severity = Info | Warning | Error
type category = Validation | Performance | Resource | Submission
type message = { sequence:int64; severity:severity; category:category; label:string option; text:string }
type trace = Timestamp of { sequence:int64; label:string; value:int64 } | Counter of { sequence:int64; label:string; value:int64 }
type t
val create : device:Handle.device -> message_capacity:int -> trace_capacity:int -> max_label_length:int -> max_message_length:int -> (t,Error.t) result
val validate : Handle.device -> t -> (unit,Error.t) result
val add_message : t -> severity:severity -> category:category -> ?label:string -> string -> (unit,Error.t) result
val push_debug : t -> string -> (unit,Error.t) result
val pop_debug : t -> (unit,Error.t) result
val begin_capture : t -> string -> (unit,Error.t) result
val end_capture : t -> (unit,Error.t) result
val timestamp : t -> label:string -> int64 -> (unit,Error.t) result
val counter : t -> label:string -> int64 -> (unit,Error.t) result
val messages : t -> message list
val traces : t -> trace list
val dropped_messages : t -> int
val dropped_traces : t -> int
val clear : t -> unit
val drain_device_loss : t -> unit
val destroy : t -> unit
