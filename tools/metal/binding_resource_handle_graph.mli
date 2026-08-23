type kind = Buffer_layout | Sample_attachment | Resource_view_pool | Texture_view_pool
type handle
type t
val empty : t
val create : t -> kind:kind -> device:int -> parent:handle option -> (t * handle, string) result
val require_live : t -> handle -> kind:kind -> device:int -> (unit, string) result
val destroy : t -> handle -> (t, string) result
val retain_for_completion : t -> handle list -> device:int -> (unit, string) result
val live_count : t -> int
