type log_type = Validation
type location = { url : string option; function_name : string option; line : int; column : int }
type log = { log_type : log_type; encoder_label : string option; function_token : int option; location : location option }
type retained = { logs : log list; completed : bool }

let valid_utf8 value =
  let length = String.length value in
  let continuation index = index < length && Char.code value.[index] land 0xc0 = 0x80 in
  let rec loop index =
    if index = length then true else
    let byte = Char.code value.[index] in
    if byte < 0x80 then loop (index + 1)
    else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then loop (index + 2)
    else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1) && continuation (index + 2) then
      let second = Char.code value.[index + 1] in
      if (byte = 0xe0 && second < 0xa0) || (byte = 0xed && second >= 0xa0) then false else loop (index + 3)
    else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3) then
      let second = Char.code value.[index + 1] in
      if (byte = 0xf0 && second < 0x90) || (byte = 0xf4 && second >= 0x90) then false else loop (index + 4)
    else false
  in loop 0

let copy_optional = Option.map (fun value -> String.sub value 0 (String.length value))
let option_exists predicate = function Some value -> predicate value | None -> false

let validate_location location =
  if location.line <= 0 || location.column <= 0 then Error "source positions are one-based"
  else if option_exists (fun value -> not (valid_utf8 value)) location.url then Error "invalid UTF-8 URL"
  else if option_exists (fun value -> not (valid_utf8 value)) location.function_name then Error "invalid UTF-8 function name"
  else Ok { location with url = copy_optional location.url; function_name = copy_optional location.function_name }

let snapshot_log log =
  if option_exists (fun value -> not (valid_utf8 value)) log.encoder_label then Error "invalid UTF-8 encoder label"
  else match log.location with
  | None -> Ok { log with encoder_label = copy_optional log.encoder_label }
  | Some location -> Result.map (fun location ->
      { log with encoder_label = copy_optional log.encoder_label; location = Some location })
      (validate_location location)

let retain_until_completion logs =
  let rec snapshot reversed = function
    | [] -> Ok { logs = List.rev reversed; completed = false }
    | log :: rest ->
        (match snapshot_log log with Error error -> Error error | Ok log -> snapshot (log :: reversed) rest)
  in snapshot [] logs

let complete _retained = { logs = []; completed = true }

let validate_handoff () =
  if List.length Binding_function_log_tail_handoff.callable_ids <> 16 then
    invalid_arg "FunctionLog callable16 drift"
