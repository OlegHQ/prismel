type kind = Invalid_argument | Invalid_state | Stale_handle | Cross_device
type t = { operation : string; kind : kind; message : string }
val make : string -> kind -> string -> t
val to_string : t -> string
