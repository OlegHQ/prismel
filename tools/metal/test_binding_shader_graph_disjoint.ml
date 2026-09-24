let overlap left right=List.filter(fun id->List.mem id right)left
let ()=
  let claimed=Binding_shader_graph_manifest.ids in
  List.iter(fun(name,ids)->if overlap claimed ids<>[] then failwith("overlap with "^name))
    ["resource100",Binding_resource_manifest.ids;
     "presentation125",Binding_presentation_manifest.ids;
     "render102",Binding_render_encoder_manifest.ids];
  let forbidden_fragments=
    [ "MTLMeshRenderPipelineDescriptor";"MTLTileRenderPipelineDescriptor";
      "MTLAccelerationStructure";"MTLRenderPassDescriptor";"CAMetalLayer";
      "MTLCommandBuffer";"MTLRenderCommandEncoder";"MTLDevice" ] in
  if List.exists(fun id->List.exists(fun fragment->String.contains id fragment.[0] &&
    let n=String.length fragment in let rec find i=i+n<=String.length id&&(String.sub id i n=fragment||find(i+1))in find 0)forbidden_fragments)claimed
  then failwith "owner overlap with active plan";
  if List.length claimed<>157 then failwith "shader graph count drift";
  print_endline "shader graph157 disjoint from resource/presentation/render/mesh/tile/acceleration/device plans"
