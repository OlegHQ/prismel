type span = { start : int; finish : int }
type t = { code : string; message : string; span : span option }

let error ?span ~code message = { code; message; span }
let to_string value = value.code ^ ": " ^ value.message
