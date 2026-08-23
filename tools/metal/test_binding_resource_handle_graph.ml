open Binding_resource_handle_graph
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith "expected rejection"
let ()=
  let state,pool=get(create empty ~kind:Resource_view_pool ~device:1 ~parent:None) in
  let state,view=get(create state ~kind:Texture_view_pool ~device:1 ~parent:(Some pool)) in
  reject(require_live state view ~kind:Texture_view_pool ~device:2);
  reject(destroy state pool);
  get(retain_for_completion state [pool;view] ~device:1);
  let state=get(destroy state view) in let state=get(destroy state pool) in
  reject(require_live state view ~kind:Texture_view_pool ~device:1);
  if live_count state<>0 then failwith "handle leak";
  for _=1 to 10000 do
    let state,layout=get(create empty ~kind:Buffer_layout ~device:0 ~parent:None) in
    let state=get(destroy state layout) in if live_count state<>0 then failwith "stress leak"
  done;
  print_endline "resource handle graph ownership and 10000-cycle teardown passed"
