open Binding_io_counter_safe
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_io_counter_audit.count Mechanical_value and h=Binding_io_counter_audit.count Handwritten_io in
 if m+h<>111 then failwith"partition";
 let a={id=1;device=2;length=1024;live=true}and b={id=2;device=2;length=1024;live=true}in
 let io=get(create~device:2~max_commands:1)in let cmd={source=a;source_offset=0;destination=b;destination_offset=4;size=512}in
 let io=get(copy io cmd)in reject(copy io cmd);let io=get(commit io)in reject(copy io cmd);
 reject(copy(get(create~device:2~max_commands:1)){cmd with size=2048});
 Printf.printf"io/counter111: %d mechanical values + %d handwritten IO IDs\n"m h
