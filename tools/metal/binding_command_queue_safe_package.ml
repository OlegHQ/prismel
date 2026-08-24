type log_state = { token : int; device : int; destroyed : bool }
type descriptor = { max_command_buffer_count : int; log_state : log_state option }
type queue = { token : int; device : int; label : string option; capture_active : bool; destroyed : bool }
type command_buffer = { token : int; queue_token : int; retains_references : bool; ocaml_retained : bool }

let validate_log_state ~device (state : log_state option) : (log_state option, string) result =
  match state with
  | Some state when state.destroyed -> Error "destroyed command queue log state"
  | Some state when state.device <> device -> Error "command queue log state belongs to another device"
  | state -> Ok state

let create_descriptor ~max_command_buffer_count ~log_state =
  if max_command_buffer_count <= 0 then Error "command buffer limit must be positive"
  else Ok { max_command_buffer_count; log_state }

let replace_log_state ~device descriptor log_state =
  Result.map (fun log_state -> { descriptor with log_state }) (validate_log_state ~device log_state)

let valid_utf8 value =
  let length = String.length value in
  let continuation index = index < length && Char.code value.[index] land 0xc0 = 0x80 in
  let rec loop index =
    if index = length then true else
    let byte = Char.code value.[index] in
    if byte < 0x80 then loop (index + 1)
    else if byte >= 0xc2 && byte <= 0xdf && continuation (index + 1) then loop (index + 2)
    else if byte >= 0xe0 && byte <= 0xef && continuation (index + 1) && continuation (index + 2)
    then loop (index + 3)
    else if byte >= 0xf0 && byte <= 0xf4 && continuation (index + 1)
            && continuation (index + 2) && continuation (index + 3)
    then loop (index + 4)
    else false
  in loop 0

let snapshot_label queue label =
  if queue.destroyed then Error "destroyed command queue"
  else if Option.fold ~none:false ~some:(fun value -> not (valid_utf8 value)) label then Error "invalid UTF-8 label"
  else Ok { queue with label = Option.map (fun value -> String.sub value 0 (String.length value)) label }

let create_command_buffer queue ~token ~retained_references =
  if queue.destroyed then Error "destroyed command queue"
  else if token <= 0 then Error "native command buffer creation failed"
  else Ok { token; queue_token = queue.token; retains_references = retained_references; ocaml_retained = true }

let insert_capture_boundary queue =
  if queue.destroyed then Error "destroyed command queue"
  else if not queue.capture_active then Error "debug capture is not active"
  else Ok ()

let validate_handoff () =
  if List.length Binding_command_queue_tail_handoff.callable_ids <> 14 then
    invalid_arg "CommandQueue callable14 drift"
