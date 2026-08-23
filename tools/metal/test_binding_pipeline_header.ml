let ()=
 if Binding_pipeline_header_plan.expected_count<>113 then failwith"count";
 if Binding_pipeline_header_plan.expected_digest<>"ca20299ddb844da5bd51c664b71b1d33e21491f8db75346144d170a96f098a0c"then failwith"digest";
 let open Binding_pipeline_safe_graph in
 let d=descriptor 1 in
 (match set_vertex d(Some{device=2;id=9})with Error _->()|Ok _->failwith"same-device rejection");
 let d=match set_vertex d(Some{device=1;id=9})with Ok x->x|Error e->failwith e in
 if retained_count d<>1 then failwith"retention";
 let p=match materialize d with Ok x->x|Error e->failwith e in release_pipeline p;release_pipeline p
