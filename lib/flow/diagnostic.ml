type span = { start : int; finish : int }
type severity = Error | Warning
type position = { line : int; col : int }
type t = { code : string; severity : severity; position : position option;
  message : string; span : span option }

let error ?span ?position ~code message =
  {code; severity = Error; position; message; span}
let warning ?span ?position ~code message =
  {code; severity = Warning; position; message; span}
let to_string value = match value.position with
  | None -> value.code ^ ": " ^ value.message
  | Some position -> Printf.sprintf "%s at %d:%d: %s"
      value.code position.line position.col value.message
