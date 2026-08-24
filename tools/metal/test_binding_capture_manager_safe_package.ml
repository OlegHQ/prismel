let ok=function Ok x->x|Error e->failwith e
let error=function Error _->()|Ok _->failwith"expected CaptureManager rejection"
let ()=let open Binding_capture_manager_safe_package in validate_handoff();
 let device={token=1;device=7;kind=Device;destroyed=false;parent=None}in
 error(create_descriptor~capability:{mtl4_capture=true}~source:device~destination:Developer_tools~output_url:(Some"x"));
 let descriptor=ok(create_descriptor~capability:{mtl4_capture=true}~source:device~destination:Gpu_trace_document~output_url:(Some"trace.gputrace"))in
 error(create_descriptor~capability:{mtl4_capture=true}~source:{device with destroyed=true}~destination:Developer_tools~output_url:None);
 let mtl4={device with kind=Mtl4_command_queue}in error(create_scope~capability:{mtl4_capture=false}~parent:mtl4~token:2);
 let scope=ok(create_scope~capability:{mtl4_capture=true}~parent:mtl4~token:2)in if scope.parent<>Some mtl4 then failwith"scope parent not retained";
 error(set_default_scope~manager_device:8 scope);ignore(ok(set_default_scope~manager_device:7 scope));
 let starting=ok(begin_start Idle descriptor)in error(begin_start starting descriptor);
 (match finish_start starting~native_result:(Error"native")with Rolled_back(Idle,"native")->()|_->failwith"start rollback");
 let active=match finish_start starting~native_result:(Ok())with Started state->state|_->failwith"start"in if retained_parent active<>Some device then failwith"active parent not retained";
 ignore(ok(stop active));error(stop Idle);
 Printf.printf"CaptureManager safe package: callable19; URL/destination, graph retention, one-active rollback, MTL4/device/destroyed checks passed\n%!"
