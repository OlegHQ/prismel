open Support
let fail format=Printf.ksprintf failwith format
let string name value=match member_string name value with Some x->x|None->fail"missing %s"name
let declaration value=
 let d:Binding_pipeline_header_plan.declaration={id=string"id"value;header=string"header"value;kind=string"kind"value;owner=member_string"owner"value;name=string"name"value;signature=string"signature"value}in d,string"classification"value
let ()=
 if Array.length Sys.argv<>2 then fail"usage: %s INVENTORY"Sys.argv.(0);
 Binding_pipeline_expanded_reachability.validate();
 let json=read_file Sys.argv.(1)|>Yojson.Safe.from_string in
 let all=match member_list"symbols"json with Some xs->List.map declaration xs|None->fail"missing symbols"in
 let inventory_ids=List.map(fun(d,_)->d.Binding_pipeline_header_plan.id)all in
 if List.exists(fun id->not(List.mem id inventory_ids))Binding_pipeline_expanded_reachability.pending_family_ids then fail"Pipeline113 pending selector absent";
 if List.exists(fun id->not(List.mem id inventory_ids))Binding_pipeline_expanded_reachability.enabling_device_ids then fail"Pipeline113 enabling selector absent";
 if 113-List.length Binding_pipeline_expanded_reachability.pending_family_ids<>61 then fail"Pipeline113 blocked complement drift";
 Printf.printf"Pipeline113 expanded audit: 52 pending-safe, 61 blocked, plus 2 enabling Device selectors; no promotion\n"
