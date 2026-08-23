open Binding_device_header_safe_graph
let get=function Ok x->x|Error _->failwith"unexpected rejection"
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 let d=device()in let child=get(create_child d)and job=get(schedule d)in
 reject(destroy_device d);get(complete job);reject(destroy_device d);
 get(destroy_child child);get(destroy_device d);
 if validate_array~count:0~capacity:8||not(validate_array~count:8~capacity:8)
 then failwith"array range validation";
 if validate_size3(0,1,1)||not(validate_size3(1,1,1))then failwith"size validation";
 let d2=device()in let failed=get(schedule d2)in unwind failed;get(destroy_device d2)
