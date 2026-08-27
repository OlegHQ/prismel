open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)
let reject kind = function Error error when error.kind=kind -> () | Error error -> failwith(Format.asprintf "%a" pp_error error)|Ok _->failwith"expected queue rejection"

let () = match Device.system_default() with
| Error _ -> print_endline "Device queue3: skipped (no device)"
| Ok device ->
  reject Invalid_argument(Command_queue.create_with_max device 0L);
  let bounded=get(Command_queue.create_with_max device 2L)in
  if Command_queue.device bounded!=device then failwith"bounded queue device drift";
  let descriptor=get(Command_queue.Descriptor.create device~max_command_buffer_count:2L())in
  let described=get(Command_queue.create_from_descriptor device descriptor)in
  get(Command_queue.Descriptor.destroy descriptor);get(Command_queue.destroy described);
  get(Command_queue.destroy bounded);
  (match Command4.Queue.create_default device with
   |Ok queue->if Command4.Queue.device queue!=device then failwith"Metal4 queue device drift";get(Command4.Queue.destroy queue)
   |Error error when error.kind=Unsupported||error.kind=Native_error->()
   |Error error->failwith(Format.asprintf"%a"pp_error error));
  get(Device.destroy device);print_endline"Device queue3: exact ownership/default/capability passed"
