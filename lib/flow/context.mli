type t = Sop | Value | Scene | World | Settings

val name : t -> string
val of_string : string -> (t, Diagnostic.t) result
val supports_values : t -> bool
