type eviction_reason = Replaced | Capacity | Cleared | Device_lost
type 'value t

val create :
  capacity:int -> on_evict:(key:string -> 'value -> eviction_reason -> unit) ->
  ('value t, Error.t) result
val capacity : 'value t -> int
val length : 'value t -> int
val callback_errors : 'value t -> int
val get : 'value t -> string -> 'value option
val insert : 'value t -> string -> 'value -> (unit, Error.t) result
val remove : 'value t -> string -> bool
val keys_lru : 'value t -> string list
val clear : 'value t -> unit
val drain_device_loss : 'value t -> unit
