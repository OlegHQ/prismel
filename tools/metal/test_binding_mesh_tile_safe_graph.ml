open Binding_mesh_tile_safe_graph
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith "expected rejection"
let ()=
  if Binding_mesh_tile_callable_audit.mechanical_ids+Binding_mesh_tile_callable_audit.handwritten_ids<>105 then failwith "partition";
  let mesh={id=1;device=7;live=true} and fragment={id=2;device=7;live=true} in
  let pipeline={device=7;stages=[Mesh,mesh;Fragment,fragment];linking={functions=[];archives=[];libraries=[]};buffers=[0,1];attachments=[{index=0;pixel_format=80;write_mask=15}]} in
  get(validate pipeline); if List.length(get(retain_for_completion pipeline))<>2 then failwith "retention";
  reject(validate{pipeline with stages=[Mesh,mesh;Mesh,fragment]});
  reject(validate{pipeline with stages=[Mesh,{mesh with live=false}]});
  reject(validate{pipeline with attachments=[{index=8;pixel_format=80;write_mask=15}]});
  print_endline "mesh/tile105: 48 contained mechanical IDs + 57 handwritten lifecycle IDs"
