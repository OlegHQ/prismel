open Metal
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"pp_error error)
let expect kind=function Error error when error.kind=kind->()|Error error->failwith error.message|Ok _->failwith"expected rejection"
let ()=match Device.system_default()with Error _->print_endline"capture-scope11: skipped"|Ok device->
  let manager=get(Capture.Manager.shared())in
  let queue=get(Command_queue.create device)in
  let scope=get(Capture.Scope.create manager(Capture.Capture_command_queue queue))in
  (match Capture.Scope.command_queue scope,Capture.Scope.metal4_command_queue scope with
   | Some _,None->()|_->failwith"capture scope queue identity drift");
  get(Capture.Scope.set_label scope(Some"scope_λ"));
  if Capture.Scope.label scope<>Some"scope_λ"then failwith"capture scope label drift";
  get(Capture.Scope.begin_scope scope);expect Invalid_state(Capture.Scope.begin_scope scope);
  expect Invalid_state(Capture.Scope.destroy scope);
  get(Capture.Scope.end_scope scope);expect Invalid_state(Capture.Scope.end_scope scope);
  expect Parent_has_dependents(Command_queue.destroy queue);
  get(Capture.Scope.destroy scope);get(Command_queue.destroy queue);get(Capture.Manager.destroy manager);get(Device.destroy device);
  print_endline"capture-scope11 safe: ownership/lifecycle ok"
