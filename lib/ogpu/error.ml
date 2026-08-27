type kind = Invalid_argument | Stale_handle | Cross_device
type t = { operation : string; kind : kind; message : string }
let make operation kind message = { operation; kind; message }
let to_string value = Printf.sprintf "%s: %s" value.operation value.message
