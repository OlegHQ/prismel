let mesh_tile_render_ids =
  [ "method:-[MTLRenderCommandEncoder dispatchThreadsPerTile:]"
  ; "method:-[MTLRenderCommandEncoder drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTLRenderCommandEncoder drawMeshThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTLRenderCommandEncoder drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]" ]
let () =
  let claimed=Binding_render_encoder_manifest.ids in
  let render19=List.map(fun (entry:Binding_render_encoder_resource_plan.entry)->entry.id)
    Binding_render_encoder_resource_plan.entries in
  let overlap excluded=List.filter(fun id->List.mem id excluded)claimed in
  if overlap render19<>[] then failwith "overlap with render19";
  if overlap mesh_tile_render_ids<>[] then failwith "overlap with mesh/tile render methods";
  if List.length claimed<>102 then failwith "claim cardinality drift";
  print_endline "render/counter102 disjoint from render19 and mesh/tile command IDs"
