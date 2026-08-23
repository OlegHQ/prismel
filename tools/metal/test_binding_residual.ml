open Binding_residual_safe
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let m=Binding_residual_audit.count Mechanical_value and h=Binding_residual_audit.count Handwritten_ownership in
 if m+h<>87 then failwith"partition";
 let routed=List.fold_left(fun n(_,v)->n+v)0 Binding_residual_audit.routed_active_counts in
 if routed<>524 then failwith"active routing proof drift";
 let o={id=1;device=2;live=true}in let g={device=2;archives=[o];functions=[];fences=[];indirect_buffers=[]}in
 (match validate g with Ok()->()|Error e->failwith e);reject(validate{g with fences=[o]});reject(validate{g with archives=[{o with device=3}]});
 Printf.printf"final residual87: %d mechanical + %d handwritten; 524 remaining IDs routed to active plans\n"m h
