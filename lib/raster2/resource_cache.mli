type key = Image of {id:int64;generation:int64} | Glyph of {font:int64;codepoint:int;density:int} | Geometry of {id:int64;version:int64}
type reason = Replaced | Evicted | Invalidated | Cleared
type 'a t
type error = Invalid_capacity | Invalid_key
val create : capacity:int -> on_destroy:(key -> 'a -> reason -> unit) -> ('a t,error) result
val insert : 'a t -> key -> 'a -> (unit,error) result
val get : 'a t -> key -> 'a option
val invalidate : 'a t -> (key -> bool) -> unit
val invalidate_image : 'a t -> id:int64 -> unit
val invalidate_density : 'a t -> density:int -> unit
val clear : 'a t -> unit
val length : 'a t -> int
val keys_lru : 'a t -> key list
val callback_errors : 'a t -> int
