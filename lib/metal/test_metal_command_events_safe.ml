open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->fail "%s"(Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"
let run () =
  let device=get(Device.system_default())in
  let shared=get(Device.new_shared_event device)in
  if Shared_event.device_registry_id shared<>Device.registry_id device then fail "shared event device identity drift";
  let initial=get(Shared_event.signaled_value shared)in
  get(Shared_event.set_signaled_value shared(Int64.succ initial));
  expect Invalid_argument(Shared_event.set_signaled_value shared initial);
  (* Shared events on a classic command buffer: the GPU waits for a host
     signal, then signals the next value; host waits observe both. *)
  let queue=get(Command_queue.create device)in
  let command=get(Command_buffer.create queue())in
  let gpu_shared=get(Device.new_shared_event device)in
  let shared_for_listener=shared in
  let shared=gpu_shared in
  let gate=10L in
  get(Command_buffer.encode_wait_for_shared_event command shared~value:gate);
  expect Invalid_argument(Command_buffer.encode_signal_shared_event command shared~value:(-1L));
  let encoder=get(Blit_encoder.create command)in
  expect Invalid_state(Command_buffer.encode_signal_shared_event command shared~value:(Int64.succ gate));
  get(Blit_encoder.end_encoding encoder);
  get(Command_buffer.encode_signal_shared_event command shared~value:(Int64.succ gate));
  get(Command_buffer.commit command);
  expect Invalid_argument(Shared_event.wait_until_signaled shared~value:(-1L)~timeout_ms:1L);
  if get(Shared_event.wait_until_signaled shared~value:(Int64.succ gate)~timeout_ms:20L)then fail "GPU signalled before the host gate";
  get(Shared_event.set_signaled_value shared gate);
  if not(get(Shared_event.wait_until_signaled shared~value:(Int64.succ gate)~timeout_ms:2000L))then fail "GPU shared-event signal never arrived";
  get(Command_buffer.wait_until_completed command);
  expect Invalid_state(Command_buffer.encode_signal_shared_event command shared~value:(Int64.add gate 2L));
  get(Command_buffer.destroy command);
  get(Command_queue.destroy queue);
  get(Shared_event.destroy gpu_shared);
  let shared=shared_for_listener in
  expect Parent_has_dependents(Device.destroy device);
  get(Shared_event.destroy shared);get(Device.destroy device)
