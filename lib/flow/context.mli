type t = Sop | Value | Draw | Scene | World | Settings | Editor | Material
(** The context of a graph or a catalog kind.  No kind is an [Editor] kind: an editor graph sees
    the value kinds and its own operators. *)

val all : t list
val name : t -> string
val of_string : string -> (t, Diagnostic.t) result
val supports_values : t -> bool
