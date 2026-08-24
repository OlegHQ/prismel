let ()=
 Binding_io_command_queue34_safe_closure.validate();
 let open Binding_io_command_queue34_safe_closure in
 let require ownership=if not(List.exists(fun e->e.ownership=ownership)entries)then failwith"missing IO ownership lane"in
 List.iter require[Value;Queue;Command;Callback;Resource;Allocator];
 Printf.printf"IO command queue safe closure: exact34 ownership partition passed\n"
