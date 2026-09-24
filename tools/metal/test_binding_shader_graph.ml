open Binding_shader_graph_safe
let reject=function Error _->()|Ok()->failwith "expected rejection"
let ()=
  let m=Binding_shader_graph_audit.count Mechanical_value and h=Binding_shader_graph_audit.count Handwritten_graph in
  if m+h<>157 then failwith "partition";
  let f={id=1;device=3;live=true} in let n0={id=0;name="input";function_=f;arguments=[];dependencies=[]} in
  let n1={id=1;name="output";function_=f;arguments=[0];dependencies=[0]} in
  let graph={device=3;nodes=[n0;n1];output=1;archives=[];functions=[f]} in
  (match validate graph with Ok()->()|Error e->failwith e);
  reject(validate{graph with nodes=[{n0 with dependencies=[1]};n1]});
  reject(validate{graph with functions=[{f with device=4}]});
  Printf.printf "shader graph157: %d mechanical values + %d handwritten graph IDs\n" m h
