type format = Invalid | Float | Float2 | Float3 | Float4 | UChar4_normalized
type attribute = { format : format; offset : int; buffer_index : int }
type layout = { stride : int }
type t
val callable_ids : string list
val create : max_attributes:int -> max_buffers:int -> (t, string) result
val set_layout : t -> index:int -> layout option -> (unit, string) result
val set_attribute : t -> index:int -> attribute option -> (unit, string) result
val attribute : t -> index:int -> (attribute option, string) result
val attributes_snapshot : t -> attribute option array
val layouts_snapshot : t -> layout option array
val retained_attribute_count : t -> int
val reset : t -> unit
val validate_handoff : unit -> unit
