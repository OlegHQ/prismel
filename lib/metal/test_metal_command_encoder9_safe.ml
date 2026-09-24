open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith e.message|Ok _->failwith"expected rejection"
let exercise token label barrier=
  get(Command_encoder.set_label token(Some label));if get(Command_encoder.label token)<>Some label then failwith"encoder label drift";
  ignore(get(Command_encoder.checked_device token));get(Command_encoder.insert_debug_signpost token"signpost");get(Command_encoder.push_debug_group token"outer");get(Command_encoder.push_debug_group token"inner");
  if barrier then(match Command_encoder.barrier token~after:[Command_encoder.Dispatch]~before:[Command_encoder.Dispatch]with Ok()->()|Error e when e.kind=Unsupported->()|Error e->failwith e.message);
  get(Command_encoder.pop_debug_group token);get(Command_encoder.pop_debug_group token);expect Invalid_state(Command_encoder.pop_debug_group token);get(Command_encoder.set_label token None)
let ()=match Device.system_default()with Error _->print_endline"command-encoder9: skipped"|Ok device->
  let queue=get(Command_queue.create device)in for iteration=0 to 255 do let command=get(Command_buffer.create queue())in
  let compute=get(Compute_encoder.create command)in let token=Command_encoder.of_compute compute in exercise token"compute"true;get(Compute_encoder.end_encoding compute);expect Destroyed(Command_encoder.label token);
  let blit=get(Blit_encoder.create command)in exercise(Command_encoder.of_blit blit)"blit"false;get(Blit_encoder.end_encoding blit);
  get(Command_buffer.commit command);get(Command_buffer.wait_until_completed command);get(Command_buffer.destroy command);if iteration=255 then print_endline"command-encoder9 safe: 256 lifecycle passes ok"done;get(Command_queue.destroy queue);get(Device.destroy device)
