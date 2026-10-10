type span = { start : int; finish : int }
type severity = Error | Warning
type position = { line : int; col : int }
type t = { code : string; severity : severity; position : position option;
  message : string; span : span option }

let error ?span ?position ~code message =
  {code; severity = Error; position; message; span}
let warning ?span ~code message =
  {code; severity = Warning; position = None; message; span}
let to_string value = match value.position with
  | None -> value.code ^ ": " ^ value.message
  | Some position -> Printf.sprintf "%s at %d:%d: %s"
      value.code position.line position.col value.message

let report ~file ~source d =
  let line_of offset =
    let offset = min (max offset 0) (String.length source) in
    let rec go i line start =
      if i >= offset then (line, start)
      else if source.[i] = '\n' then go (i + 1) (line + 1) (i + 1) else go (i + 1) line start in
    go 0 1 0 in
  let line, a, b = match d.span, d.position with
    | Some { start; finish }, _ ->
        let line, first = line_of start in
        let eol = try String.index_from source first '\n' with Not_found | Invalid_argument _ -> String.length source in
        (line, start - first, min (max finish (start + 1)) eol - first)
    | None, Some { line; col } -> (line, max 0 (col - 1), max 0 (col - 1))
    | None, None -> (1, 0, 0) in
  Printf.sprintf "File \"%s\", line %d, characters %d-%d:\n%s [%s]: %s" file line a b
    (match d.severity with Error -> "Error" | Warning -> "Warning") d.code d.message

let position_of_offset source offset : position =
  let line = ref 1 and col = ref 1 in
  for i = 0 to min (String.length source) offset - 1 do
    if source.[i] = '\n' then (incr line; col := 1) else incr col
  done;
  {line = !line; col = !col}
