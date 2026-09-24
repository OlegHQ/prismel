open Binding_submission_safe
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_submission_audit.count Mechanical_value and h=Binding_submission_audit.count Handwritten_lifecycle in
 if m+h<>118 then failwith"partition";
 let encoder={id=1;device=3;live=true}in let t=get(set_argument_encoder(create~device:3)encoder)in
 reject(set_argument_encoder t{encoder with device=4});let t=get(enqueue t)in reject(enqueue t);
 let t=get(commit t)in reject(commit t);ignore(get(complete t));
 Printf.printf"submission118: %d mechanical values + %d handwritten lifecycle IDs\n"m h
