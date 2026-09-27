type t = { code : string; message : string }

let error ~code message = { code; message }
let to_string value = value.code ^ ": " ^ value.message
