open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->fail "%s"(Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"
let ()=
  let device=get(Device.system_default())in
  let event=get(Device.new_event device)in
  if Event.device_registry_id event<>Device.registry_id device then fail "event device identity drift";
  get(Event.set_label event(Some "safe-event"));
  if get(Event.label event)<>Some "safe-event" then fail "event label drift";
  expect Invalid_argument(Event.set_label event(Some "bad\000label"));
  let shared=get(Device.new_shared_event device)in
  if Shared_event.device_registry_id shared<>Device.registry_id device then fail "shared event device identity drift";
  let initial=get(Shared_event.signaled_value shared)in
  get(Shared_event.set_signaled_value shared(Int64.succ initial));
  expect Invalid_argument(Shared_event.set_signaled_value shared initial);
  expect Parent_has_dependents(Device.destroy device);
  get(Shared_event.destroy shared);get(Event.destroy event);get(Device.destroy device)
