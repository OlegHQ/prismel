open Binding_metal4_safe
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_metal4_audit.count Mechanical_value and h=Binding_metal4_audit.count Handwritten_lifecycle in
 if m+h<>190 then failwith"partition";
 let t=get(begin_recording(create~device:9))in let o={id=1;device=9;live=true}in
 let t=get(retain t[o])in reject(retain t[{o with device=8}]);let t=get(end_recording t)in
 reject(retain t[o]);ignore(get(commit t));
 Printf.printf"metal4 batch190: %d mechanical values + %d handwritten lifecycle IDs\n"m h
