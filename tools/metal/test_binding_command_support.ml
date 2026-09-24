open Binding_command_support_safe
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_command_support_audit.count Mechanical_value and h=Binding_command_support_audit.count Handwritten_lifecycle in
 if m+h<>121 then failwith"partition";
 let a={id=1;device=2;length=64;live=true}and b={id=2;device=2;length=64;live=true}in
 let t=get(copy(empty~device:2)~source:a~source_offset:0~destination:b~destination_offset:0~size:64)in
 reject(copy t~source:a~source_offset:1~destination:b~destination_offset:0~size:64);
 let t=get(signal t 4L)in reject(signal t 3L);let t=get(begin_capture t)in reject(begin_capture t);ignore(get(end_capture t));
 Printf.printf"command support121: %d mechanical values + %d handwritten lifecycle IDs\n"m h
