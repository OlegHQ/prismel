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
  get (Command_queue.set_label queue (Some "classic queue"));
  if get (Command_queue.label queue) <> Some "classic queue" then
    fail "command queue label drift";
  let manager = get (Capture.Manager.shared ()) in
  expect Invalid_state (Command_queue.insert_capture_boundary queue manager);
  let descriptor =
    get (Command_queue.Descriptor.create device
           ~max_command_buffer_count:2L ())
  in
  if Command_queue.Descriptor.max_command_buffer_count descriptor <> 2L
     || Command_queue.Descriptor.log_state descriptor <> None
  then fail "command queue descriptor drift";
  let unretained = get (Command_buffer.create_unretained queue) in
  get (Command_buffer.commit unretained);
  get (Command_buffer.wait_until_completed unretained);
  get (Command_buffer.destroy unretained);
  let described = get (Command_buffer.create_with_descriptor queue ()) in
  expect Parent_has_dependents (Command_queue.destroy queue);
  get (Command_buffer.commit described);
  get (Command_buffer.wait_until_completed described);
  get (Command_buffer.destroy described);
  get (Command_queue.Descriptor.destroy descriptor);
  get (Capture.Manager.destroy manager);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
