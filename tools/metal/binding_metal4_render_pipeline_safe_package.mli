type attachment
type attachment_array
val callable_ids : string list
val create_attachment : available:bool -> (attachment, string) result
val configure : attachment -> pixel_format:int -> write_mask:int -> blending:bool -> (unit, string) result
val snapshot : attachment -> (int option * int * bool, string) result
val reset_attachment : attachment -> (unit, string) result
val create_array : available:bool -> length:int -> (attachment_array, string) result
val set : attachment_array -> index:int -> attachment option -> (unit, string) result
val retained_count : attachment_array -> int
val reset_array : attachment_array -> (unit, string) result
val destroy_attachment : attachment -> unit
val destroy_array : attachment_array -> unit
val validate_handoff : unit -> unit
