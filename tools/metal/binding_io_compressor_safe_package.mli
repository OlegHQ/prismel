type method_ = Lz4 | Lzfse | Lzma | Zlib
type t
val callable_ids : string list
val default_chunk_size : native_value:int -> (int, string) result
val create : path:string -> method_:method_ -> chunk_size:int -> native_ok:bool -> (t, string) result
val append : t -> bytes -> offset:int -> length:int -> native_ok:bool -> (unit, string) result
val flush_and_destroy : t -> native_status:(unit, string) result -> (unit, string) result
val appended_bytes : t -> int
val configuration : t -> string * method_ * int
val is_finalized : t -> bool
val validate_handoff : unit -> unit
