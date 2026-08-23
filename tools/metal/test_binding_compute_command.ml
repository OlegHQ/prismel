open Binding_compute_command_safe
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_compute_command_audit.count Mechanical_value and h=Binding_compute_command_audit.count Handwritten_command in
 if m+h<>103 then failwith"partition";
 let b={id=1;device=4;length=4096;live=true}in let e=get(bind(empty~device:4)~index:0~offset:256 b)in
 get(dispatch e~grid:(8,8,1)~threads:(8,8,1));reject(dispatch e~grid:(1,1,1)~threads:(1024,2,1));
 reject(bind e~index:0~offset:0 {b with device=5});let ended=get(finish e)in reject(dispatch ended~grid:(1,1,1)~threads:(1,1,1));
 Printf.printf"compute command103: %d mechanical values + %d handwritten commands\n"m h
