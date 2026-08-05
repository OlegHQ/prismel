type t = {
  operation : string;
  code : string;
  message : string;
  hints : string list;
}

let make ?(hints = []) ~operation ~code message =
  if String.trim operation = "" then invalid_arg "Pdk.Error.make: empty operation";
  if String.trim code = "" then invalid_arg "Pdk.Error.make: empty code";
  { operation; code; message; hints }

let of_string ~operation ~code message = make ~operation ~code message
let operation value = value.operation
let code value = value.code
let message value = value.message
let hints value = value.hints
let to_string value =
  let base = Printf.sprintf "%s [%s]: %s" value.operation value.code value.message in
  match value.hints with
  | [] -> base
  | hints -> base ^ " (" ^ String.concat "; " hints ^ ")"
