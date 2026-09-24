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
  let listener=get(Shared_event_listener.create(Serial_queue "prismel.event10.safe"))in
  let queue=get(Shared_event_listener.queue listener)in
  if Shared_event_listener.Queue.label queue<>"prismel.event10.safe"then fail "listener queue label drift";
  expect Parent_has_dependents(Shared_event_listener.destroy listener);
  get(Shared_event_listener.Queue.destroy queue);
  let handle=get(Shared_event.export_handle shared)in
  if get(Shared_event_handle.label handle)<>None then fail "unexpected exported event label";
  let calls=Atomic.make 0 in
  let threshold=Int64.add initial 2L in
  let notification=get(Shared_event.notify shared~listener~at_value:threshold(fun observed->
    if observed<threshold then fail "notification value below threshold";
    Atomic.incr calls))in
  get(Shared_event.set_signaled_value shared threshold);
  let deadline=Unix.gettimeofday()+.2.0 in
  while Atomic.get calls=0&&Unix.gettimeofday()<deadline do Unix.sleepf 0.001 done;
  if Atomic.get calls<>1 then fail "shared-event notification was not exactly once";
  get(Shared_event.set_signaled_value shared(Int64.succ threshold));
  if Atomic.get calls<>1 then fail "shared-event notification fired twice";
  get(Shared_event.Notification.cancel notification);
  let pending=get(Shared_event.notify shared~listener~at_value:(Int64.add threshold 10L)(fun _->fail "cancelled callback fired"))in
  expect Parent_has_dependents(Shared_event.destroy shared);
  get(Shared_event.Notification.cancel pending);
  get(Shared_event_handle.destroy handle);
  expect Invalid_argument(Shared_event.notify shared~listener~at_value:(-1L)(fun _->()));
  get(Shared_event_listener.destroy listener);
  expect Parent_has_dependents(Device.destroy device);
  get(Shared_event.destroy shared);get(Event.destroy event);get(Device.destroy device)
