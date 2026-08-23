open Binding_layout_safe_graph
let get=function Ok x->x|Error _->failwith"unexpected"let reject=function Error _->()|Ok _->failwith"expected"
let ()=let o=owner()in let c=get(child o)in reject(destroy_owner o);get(destroy_child c);get(destroy_owner o);
 if validate_extents[||]||not(validate_extents[|1;2;3|])then failwith"extents";
 if validate_rates[|nan|]||not(validate_rates[|1.;0.5|])then failwith"rates";
 if validate_layer~index:2~count:2||not(validate_layer~index:1~count:2)then failwith"layer"
