type mode =
  | Address
  | Undefined
  | Address_undefined
  | Thread
  | Leaks
  | Guard_malloc

val of_string : string -> (mode, string) result
val name : mode -> string
val diagnostic_markers : mode -> string list
val required_runtime_markers : mode -> string list
val missing_runtime_markers : mode -> string -> string list
val required_instrumentation_markers : mode -> string list
val missing_instrumentation_markers : mode -> string -> string list
