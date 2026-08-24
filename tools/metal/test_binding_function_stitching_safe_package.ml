let ok=function Ok x->x|Error e->failwith e
let error=function Error _->()|Ok _->failwith"expected FunctionStitching rejection"
let ()=
 let open Binding_function_stitching_safe_package in validate_handoff();
 let input={id=1;name="input";arguments=[|Input 0|];dependencies=[||]} in
 let output={id=2;name="output";arguments=[|Node 1|];dependencies=[|1|]} in
 let source=[|input;output|] in
 let graph=ok(validate_graph~argument_count:1~function_name:"main"~nodes:source~output:(Some 2)~attributes:[|"a"|])in
 source.(0)<-{input with name="mutated"}; if graph.nodes.(0).name<>"input"then failwith"graph not snapshotted";
 error(validate_graph~argument_count:1~function_name:"main"~nodes:[|{input with arguments=[|Node 2|]};{output with arguments=[|Node 1|]}|]~output:(Some 2)~attributes:[||]);
 error(validate_graph~argument_count:1~function_name:"main"~nodes:[|input|]~output:(Some 9)~attributes:[||]);
 error(validate_graph~argument_count:1~function_name:"main"~nodes:[|{input with arguments=[|Input 2|]}|]~output:None~attributes:[||]);
 let function_={token=1;device=7;destroyed=false}and archive={token=2;device=7;destroyed=false}in
 let descriptor=ok(create_descriptor~device:7~functions:[|function_|]~archives:[|archive|]~graphs:[|graph|]~options:1L)in
 error(create_descriptor~device:7~functions:[|{function_ with device=8}|]~archives:[||]~graphs:[||]~options:0L);
 error(create_descriptor~device:7~functions:[|{function_ with destroyed=true}|]~archives:[||]~graphs:[||]~options:0L);
 let next=replace_graphs descriptor[||]in if Array.length descriptor.graphs<>1||Array.length next.graphs<>0 then failwith"descriptor mutation not atomic";
 Printf.printf"FunctionStitching safe package: callable36; graph membership/cycle/input, snapshots, same-device/lifetime, atomic descriptor replacement passed\n%!"
