let overlap a b=List.filter(fun id->List.mem id b)a
let ()=
 let claimed=Binding_command_support_manifest.ids in
 List.iter(fun(name,ids)->if overlap claimed ids<>[]then failwith("overlap "^name))
  ["resource100",Binding_resource_manifest.ids;"presentation125",Binding_presentation_manifest.ids;
   "render102",Binding_render_encoder_manifest.ids;"shader157",Binding_shader_graph_manifest.ids;
   "io111",Binding_io_counter_manifest.ids;"compute103",Binding_compute_command_manifest.ids];
 let forbidden=["MTLDevice";"MTLTensor";"MTLRasterizationRate";"MTLRenderPipeline";
  "MTLAccelerationStructure";"CAMetalLayer";"MTLRenderCommandEncoder"]in
 let has id fragment=let n=String.length fragment in let rec f i=i+n<=String.length id&&(String.sub id i n=fragment||f(i+1))in f 0 in
 if List.exists(fun id->List.exists(has id)forbidden)claimed then failwith"owner overlap";
 if List.length claimed<>121 then failwith"count drift";
 print_endline"command support121 globally disjoint from all prepared manifests"
