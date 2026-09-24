type sanitizer =
  | Address
  | Undefined
  | Thread

val parse_sanitizers : string -> (sanitizer list, string) result
val compile_flags : sanitizer list -> string list
val link_flags : sanitizer list -> string list
val profile_compile_flags : string -> string list
val framework_link_flags : string list
val write_sexp : string -> string list -> unit
