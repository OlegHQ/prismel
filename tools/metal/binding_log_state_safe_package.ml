type level = Undefined | Debug | Info | Notice | Error | Fault
type descriptor = { level : level; buffer_size : int }
type handler_status = Active | Cancelled
type state =
  { max_handlers : int; mutable handlers : handler list; mutable destroyed : bool
  ; mutable handler_errors : int }
and handler =
  { state : state; callback : level -> string option -> unit; mutable status : handler_status }

let create_descriptor ~max_buffer_size ~level ~buffer_size =
  if max_buffer_size <= 0 then Result.error "invalid log-state buffer capability"
  else if buffer_size <= 0 || buffer_size > max_buffer_size then Result.error "log-state buffer size out of bounds"
  else Result.ok { level; buffer_size }

let create_state ~max_handlers =
  if max_handlers <= 0 then Result.error "log-state handler capacity must be positive"
  else Result.ok { max_handlers; handlers = []; destroyed = false; handler_errors = 0 }

let add_handler state callback =
  if state.destroyed then Result.error "destroyed log state"
  else if List.length state.handlers >= state.max_handlers then Result.error "log-state handler capacity exceeded"
  else
    let handler = { state; callback; status = Active } in
    state.handlers <- handler :: state.handlers;
    Result.ok handler

let cancel handler =
  match handler.status with
  | Cancelled -> false
  | Active ->
      handler.status <- Cancelled;
      handler.state.handlers <- List.filter (fun item -> item != handler) handler.state.handlers;
      true

let snapshot_message = Option.map (fun value -> String.sub value 0 (String.length value))

let emit state level message =
  if not state.destroyed then
    let message = snapshot_message message in
    List.iter (fun handler ->
      match handler.status with
      | Cancelled -> ()
      | Active ->
          (try handler.callback level message with _ ->
             state.handler_errors <- state.handler_errors + 1))
      (List.rev state.handlers)

let rooted_handler_count state = List.length state.handlers
let handler_error_count state = state.handler_errors

let cleanup state =
  if not state.destroyed then begin
    state.destroyed <- true;
    List.iter (fun handler -> handler.status <- Cancelled) state.handlers;
    state.handlers <- []
  end

let validate_handoff () =
  if List.length Binding_log_state_handoff.callable_ids <> 7 then
    invalid_arg "LogState callable7 drift"
