open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf"%a"pp_error e)|Ok _->failwith"expected rejection"
let source={|#include <metal_stdlib>
using namespace metal;
[[visible]] uint linked_a(uint x){return x+1;} [[visible]] uint linked_b(uint x){return x+2;}
|}
let ()=match Device.system_default()with Error _->print_endline"linked functions: skipped"|Ok device->
 let library=get(Library.compile_source~device source)in
 let a=get(Function.find~library "linked_a")and b=get(Function.find~library "linked_b")in
 let linked=get(Linked_functions.create device)in
 expect Invalid_argument(Linked_functions.set_binary_functions linked(Some[a;a]));
 expect Invalid_argument(Linked_functions.set_groups linked(Some["bad\000name",[a]]));
 get(Linked_functions.set_binary_functions linked(Some[a;b]));
 get(Linked_functions.set_private_functions linked(Some[b]));
 get(Linked_functions.set_groups linked(Some["group_b",[b];"group_a",[a;b]]));
 (match get(Linked_functions.binary_functions linked)with Some[x;y]when x==a&&y==b->()|_->failwith"binary identity drift");
 (match get(Linked_functions.private_functions linked)with Some[x]when x==b->()|_->failwith"private identity drift");
 (match get(Linked_functions.groups linked)with Some[("group_b",[x]);("group_a",[y;z])]when x==b&&y==a&&z==b->()|_->failwith"group identity drift");
 expect Parent_has_dependents(Function.destroy a);expect Parent_has_dependents(Function.destroy b);
 get(Linked_functions.set_binary_functions linked None);get(Linked_functions.set_private_functions linked None);get(Linked_functions.set_groups linked None);
 get(Linked_functions.destroy linked);get(Function.destroy a);get(Function.destroy b);get(Library.destroy library);get(Device.destroy device);
 print_endline"linked functions safe: ok"
