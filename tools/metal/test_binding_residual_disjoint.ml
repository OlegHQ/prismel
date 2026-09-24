let overlap a b=List.filter(fun id->List.mem id b)a
let ()=
 let claimed=Binding_residual_manifest.ids in
 List.iter(fun(name,ids)->if overlap claimed ids<>[]then failwith("overlap "^name))
  ["resource100",Binding_resource_manifest.ids;"presentation125",Binding_presentation_manifest.ids;
   "render102",Binding_render_encoder_manifest.ids;"shader157",Binding_shader_graph_manifest.ids;
   "io111",Binding_io_counter_manifest.ids;"compute76",Binding_compute_command_manifest.ids;
   "command121",Binding_command_support_manifest.ids;"metal4-190",Binding_metal4_manifest.ids;
   "submission118",Binding_submission_manifest.ids];
 Binding_residual_coverage.validate();
 if List.length claimed<>87 then failwith"residual count drift";
 print_endline"residual87 disjoint; 1099 static + 87 residual + 524 active-routed = 1710 unreviewed"
