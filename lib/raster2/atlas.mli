type key =
  | Glyph of { font : int64; codepoint : int; density : int }
  | Image of { id : int64; generation : int64; density : int }

type placement = { page : int; x : int; y : int; width : int; height : int }

type error =
  | Invalid_capacity
  | Invalid_dimensions
  | Invalid_density
  | Storage_too_small
  | Full

type t

val create :
  page_width:int -> page_height:int -> max_pages:int -> max_entries:int ->
  padding:int -> (t, error) result

(** [add] copies tightly-packed RGBA pixels. Replacing a key is atomic. *)
val add : t -> key -> width:int -> height:int -> bytes ->
  (placement, error) result
val find : t -> key -> placement option
val invalidate : t -> key -> unit
val invalidate_density : t -> density:int -> unit
val length : t -> int
val page_count : t -> int
val page_bytes : t -> page:int -> bytes option
val placements : t -> (key * placement) list
