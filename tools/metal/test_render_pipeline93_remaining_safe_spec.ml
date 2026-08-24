type lane = Execute | Capability_gate | Reject | Lifetime
type case = { id:string; lanes:lane list; requirement:string }

let cases =
  [ {id="method:-[MTLRenderPipelineState newVisibleFunctionTableWithDescriptor:stage:]";lanes=[Execute;Reject;Lifetime];requirement="positive capacity, exact stage, same pipeline device, owned table"}
  ; {id="method:-[MTLRenderPipelineState newIntersectionFunctionTableWithDescriptor:stage:]";lanes=[Execute;Reject;Lifetime];requirement="positive capacity, exact stage, same pipeline device, owned table"}
  ; {id="method:-[MTLRenderPipelineState functionHandleWithBinaryFunction:stage:]";lanes=[Execute;Capability_gate;Reject;Lifetime];requirement="later Binary_function wrapper, same device, exact stage, nullable owned result"}
  ; {id="method:-[MTLRenderPipelineState newRenderPipelineStateWithAdditionalBinaryFunctions:error:]";lanes=[Execute;Reject;Lifetime];requirement="functions graph validated atomically, source pipeline and graph retained through call"}
  ; {id="method:-[MTLRenderPipelineState newRenderPipelineStateWithBinaryFunctions:error:]";lanes=[Execute;Capability_gate;Reject;Lifetime];requirement="macOS26 binary graph, same device, NSError remains atomic"}
  ; {id="method:-[MTLRenderPipelineState newRenderPipelineDescriptorForSpecialization]";lanes=[Execute;Capability_gate;Lifetime];requirement="macOS26 exact concrete descriptor behind owned abstract base"}
  ; {id="method:-[MTLRenderPipelineDescriptor vertexDescriptor]";lanes=[Execute;Lifetime];requirement="copied immutable snapshot; SDK nil normalizes to a default descriptor"}
  ; {id="method:-[MTLRenderPipelineDescriptor setVertexDescriptor:]";lanes=[Execute;Reject;Lifetime];requirement="validated public Vertex_descriptor materialization before native copy"}
  ; {id="property:MTLRenderPipelineDescriptor:vertexDescriptor";lanes=[Execute;Lifetime];requirement="getter/setter pair has one retained logical snapshot"}
  ; {id="method:-[MTLRenderPipelineReflection vertexArguments]";lanes=[Execute;Capability_gate];requirement="deprecated reflection copied before autorelease scope ends"}
  ; {id="property:MTLRenderPipelineReflection:vertexArguments";lanes=[Execute;Capability_gate];requirement="immutable typed argument snapshot"}
  ; {id="method:-[MTLRenderPipelineReflection fragmentArguments]";lanes=[Execute;Capability_gate];requirement="deprecated reflection copied before autorelease scope ends"}
  ; {id="property:MTLRenderPipelineReflection:fragmentArguments";lanes=[Execute;Capability_gate];requirement="immutable typed argument snapshot"}
  ; {id="method:-[MTLRenderPipelineReflection tileArguments]";lanes=[Execute;Capability_gate];requirement="deprecated reflection copied before autorelease scope ends"}
  ; {id="property:MTLRenderPipelineReflection:tileArguments";lanes=[Execute;Capability_gate];requirement="immutable typed argument snapshot"} ]

let () =
  if List.length cases <> 15 then invalid_arg "RenderPipeline93 remaining safe count";
  let ids=List.map(fun case->case.id)cases in
  if List.length(List.sort_uniq String.compare ids)<>15 then
    invalid_arg "RenderPipeline93 remaining safe duplicate ID";
  List.iter(fun case->
    if case.requirement=""||not(List.mem Execute case.lanes)then
      invalid_arg("RenderPipeline93 incomplete safe case: "^case.id))cases;
  let binary=List.find(fun case->String.equal case.id "method:-[MTLRenderPipelineState functionHandleWithBinaryFunction:stage:]")cases in
  if not(List.mem Capability_gate binary.lanes&&List.mem Reject binary.lanes&&List.mem Lifetime binary.lanes)then
    invalid_arg "RenderPipeline93 binary lookup ownership contract"
