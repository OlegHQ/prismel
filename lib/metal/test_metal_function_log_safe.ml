open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok value -> value | Error error -> fail "%s" error.message
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" error.message
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let queue = get (Command_queue.create device) in
  let commands = get (Command_buffer.create queue ()) in
  expect Invalid_state (Command_buffer.function_logs commands);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  let logs = get (Command_buffer.function_logs commands) in
  List.iter (fun (log:Function_log.t) ->
    match log.location with
    | None -> ()
    | Some location ->
        if location.line < 0L || location.column < 0L then
          fail "negative Metal source position") logs;
  get (Command_buffer.destroy commands);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
