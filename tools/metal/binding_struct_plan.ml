type declaration =
  { id : string
  ; kind : string
  ; owner : string option
  ; signature : string
  ; classification : string
  }

type selection =
  { declarations : declaration list
  ; method_count : int
  ; property_count : int
  ; owner_count : int
  }

let expected_method_count = 49
let expected_property_count = 23
let expected_declaration_count = 72
let expected_owner_count = 22

let expected_promoted_tensor_struct_ids =
  [ "method:-[MTLTensor gpuResourceID]"
  ; "property:MTLTensor:gpuResourceID"
  ]

let expected_promoted_rasterization_rate_struct_ids =
  [ "method:-[MTLRasterizationRateLayerDescriptor maxSampleCount]"
  ; "method:-[MTLRasterizationRateLayerDescriptor sampleCount]"
  ; "method:-[MTLRasterizationRateLayerDescriptor setSampleCount:]"
  ; "method:-[MTLRasterizationRateMap parameterBufferSizeAndAlign]"
  ; "method:-[MTLRasterizationRateMap physicalGranularity]"
  ; "method:-[MTLRasterizationRateMap physicalSizeForLayer:]"
  ; "method:-[MTLRasterizationRateMap screenSize]"
  ; "method:-[MTLRasterizationRateMapDescriptor screenSize]"
  ; "method:-[MTLRasterizationRateMapDescriptor setScreenSize:]"
  ; "property:MTLRasterizationRateLayerDescriptor:maxSampleCount"
  ; "property:MTLRasterizationRateLayerDescriptor:sampleCount"
  ; "property:MTLRasterizationRateMap:parameterBufferSizeAndAlign"
  ; "property:MTLRasterizationRateMap:physicalGranularity"
  ; "property:MTLRasterizationRateMap:screenSize"
  ; "property:MTLRasterizationRateMapDescriptor:screenSize"
  ]

let expected_promoted_library_struct_ids =
  [ "method:-[MTLCompileOptions requiredThreadsPerThreadgroup]"
  ; "method:-[MTLCompileOptions setRequiredThreadsPerThreadgroup:]"
  ; "property:MTLCompileOptions:requiredThreadsPerThreadgroup"
  ]
let expected_promoted_function_handle_struct_ids =
  [ "method:-[MTLFunctionHandle gpuResourceID]"
  ; "property:MTLFunctionHandle:gpuResourceID" ]
let expected_promoted_compute_encoder_struct_ids =
  [ "method:-[MTLComputeCommandEncoder dispatchThreadgroups:threadsPerThreadgroup:]"
  ; "method:-[MTLComputeCommandEncoder setStageInRegion:]" ]
let expected_promoted_render_required_struct_ids =
  [ "method:-[MTLRenderPipelineState requiredThreadsPerMeshThreadgroup]"
  ; "method:-[MTLRenderPipelineState requiredThreadsPerObjectThreadgroup]"
  ; "property:MTLRenderPipelineState:requiredThreadsPerMeshThreadgroup"
  ; "property:MTLRenderPipelineState:requiredThreadsPerObjectThreadgroup" ]
let expected_promoted_argument_table_struct_ids =
  [ "method:-[MTL4ArgumentTable setResource:atBufferIndex:]" ]

let expected_promoted_indirect_command_buffer_struct_ids =
  [ "method:-[MTLIndirectCommandBuffer gpuResourceID]"
  ; "property:MTLIndirectCommandBuffer:gpuResourceID"
  ]

let expected_promoted_render_encoder33_struct_ids =
  [ "method:-[MTLRenderCommandEncoder dispatchThreadsPerTile:]"
  ; "method:-[MTLRenderCommandEncoder drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ; "method:-[MTLRenderCommandEncoder drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:]"
  ]

let fail format =
  Printf.ksprintf (fun message -> invalid_arg ("Metal struct plan: " ^ message)) format

let relevant declaration =
  (String.equal declaration.classification "unreviewed"
   || (String.equal declaration.classification "bound"
       && List.mem declaration.id
            Binding_resource_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id
                  Binding_pipeline_state_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_pipeline_expanded_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_metal4_callable_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_metal4_second_slice_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_metal4_native32_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_metal4_final9_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_metal4_pending41_reachability.remaining_promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id
                  Binding_shader_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_mesh_tile_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_mesh_tile_compile_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_command_support_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_io_safe_reachability.promotable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_tensor_safe_handoff.safe41_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_rasterization_rate_safe_handoff.callable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id Binding_library_header_handoff.callable_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id expected_promoted_function_handle_struct_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id expected_promoted_compute_encoder_struct_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id expected_promoted_render_required_struct_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id expected_promoted_argument_table_struct_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id
                  expected_promoted_indirect_command_buffer_struct_ids
          || String.equal declaration.classification "bound"
             && List.mem declaration.id expected_promoted_render_encoder33_struct_ids))
  && (String.equal declaration.kind "method"
      || String.equal declaration.kind "property")
  && Binding_struct_spec.mechanically_safe_signature declaration.signature
  && List.exists
       (Binding_struct_spec.contains_type declaration.signature)
       Binding_struct_spec.objc_types

let select declarations =
  let promoted_render_encoder33_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id expected_promoted_render_encoder33_struct_ids
         && (String.equal declaration.kind "method" || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  if promoted_render_encoder33_struct_ids <> expected_promoted_render_encoder33_struct_ids then
    fail "promoted RenderEncoder33 struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_render_encoder33_struct_ids)
      (String.concat "; " promoted_render_encoder33_struct_ids);
  let promoted_indirect_command_buffer_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id
              expected_promoted_indirect_command_buffer_struct_ids
         && (String.equal declaration.kind "method"
             || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  if promoted_indirect_command_buffer_struct_ids
     <> expected_promoted_indirect_command_buffer_struct_ids then
    fail
      "promoted IndirectCommandBuffer struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_indirect_command_buffer_struct_ids)
      (String.concat "; " promoted_indirect_command_buffer_struct_ids);
  let promoted_argument_table_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id expected_promoted_argument_table_struct_ids
         && (String.equal declaration.kind "method"
             || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  if promoted_argument_table_struct_ids
     <> expected_promoted_argument_table_struct_ids then
    fail "promoted ArgumentTable struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_argument_table_struct_ids)
      (String.concat "; " promoted_argument_table_struct_ids);
  let promoted_render_required_struct_ids=declarations|>List.filter(fun d->String.equal d.classification "bound"&&List.mem d.id expected_promoted_render_required_struct_ids&&(String.equal d.kind "method"||String.equal d.kind "property")&&Binding_struct_spec.mechanically_safe_signature d.signature&&List.exists(Binding_struct_spec.contains_type d.signature)Binding_struct_spec.objc_types)|>List.map(fun d->d.id)|>List.sort_uniq String.compare in
  if promoted_render_required_struct_ids<>expected_promoted_render_required_struct_ids then fail "promoted RenderPipeline required-size struct drift: expected [%s], found [%s]"(String.concat "; " expected_promoted_render_required_struct_ids)(String.concat "; " promoted_render_required_struct_ids);
  let promoted_compute_encoder_struct_ids = declarations|>List.filter(fun d->String.equal d.classification "bound"&&List.mem d.id expected_promoted_compute_encoder_struct_ids&&(String.equal d.kind "method"||String.equal d.kind "property")&&Binding_struct_spec.mechanically_safe_signature d.signature&&List.exists(Binding_struct_spec.contains_type d.signature)Binding_struct_spec.objc_types)|>List.map(fun d->d.id)|>List.sort_uniq String.compare in
  if promoted_compute_encoder_struct_ids<>expected_promoted_compute_encoder_struct_ids then fail "promoted ComputeEncoder struct intersection drift: expected [%s], found [%s]"(String.concat "; " expected_promoted_compute_encoder_struct_ids)(String.concat "; " promoted_compute_encoder_struct_ids);
  let promoted_function_handle_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id expected_promoted_function_handle_struct_ids
         && (String.equal declaration.kind "method"
             || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  if promoted_function_handle_struct_ids
     <> expected_promoted_function_handle_struct_ids then
    fail
      "promoted FunctionHandle struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_function_handle_struct_ids)
      (String.concat "; " promoted_function_handle_struct_ids);
  let promoted_tensor_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id Binding_tensor_safe_handoff.safe41_ids
         && (String.equal declaration.kind "method"
             || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  let expected_promoted_tensor_struct_ids =
    List.sort String.compare expected_promoted_tensor_struct_ids
  in
  if promoted_tensor_struct_ids <> expected_promoted_tensor_struct_ids then
    fail "promoted Tensor struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_tensor_struct_ids)
      (String.concat "; " promoted_tensor_struct_ids);
  let promoted_rasterization_rate_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id Binding_rasterization_rate_safe_handoff.callable_ids
         && (String.equal declaration.kind "method" || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  let expected_promoted_rasterization_rate_struct_ids =
    List.sort String.compare expected_promoted_rasterization_rate_struct_ids
  in
  if promoted_rasterization_rate_struct_ids <> expected_promoted_rasterization_rate_struct_ids then
    fail "promoted RasterizationRate struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_rasterization_rate_struct_ids)
      (String.concat "; " promoted_rasterization_rate_struct_ids);
  let promoted_library_struct_ids =
    declarations
    |> List.filter (fun declaration ->
         String.equal declaration.classification "bound"
         && List.mem declaration.id Binding_library_header_handoff.callable_ids
         && (String.equal declaration.kind "method" || String.equal declaration.kind "property")
         && Binding_struct_spec.mechanically_safe_signature declaration.signature
         && List.exists
              (Binding_struct_spec.contains_type declaration.signature)
              Binding_struct_spec.objc_types)
    |> List.map (fun declaration -> declaration.id)
    |> List.sort_uniq String.compare
  in
  let expected_promoted_library_struct_ids =
    List.sort String.compare expected_promoted_library_struct_ids
  in
  if promoted_library_struct_ids <> expected_promoted_library_struct_ids then
    fail "promoted MTLLibrary struct intersection drift: expected [%s], found [%s]"
      (String.concat "; " expected_promoted_library_struct_ids)
      (String.concat "; " promoted_library_struct_ids);
  let declarations = List.filter relevant declarations in
  let ids = List.map (fun declaration -> declaration.id) declarations in
  let sorted_ids = List.sort String.compare ids in
  let rec reject_duplicates = function
    | left :: right :: _ when String.equal left right ->
        fail "duplicate inventory identifier %s" left
    | _ :: rest -> reject_duplicates rest
    | [] -> ()
  in
  reject_duplicates sorted_ids;
  let method_count =
    List.fold_left
      (fun count declaration ->
        count + if String.equal declaration.kind "method" then 1 else 0)
      0 declarations
  in
  let property_count = List.length declarations - method_count in
  let owner_count =
    declarations
    |> List.filter_map (fun declaration -> declaration.owner)
    |> List.sort_uniq String.compare |> List.length
  in
  if method_count <> expected_method_count then
    fail "expected %d methods, found %d" expected_method_count method_count;
  if property_count <> expected_property_count then
    fail "expected %d properties, found %d" expected_property_count property_count;
  if List.length declarations <> expected_declaration_count then
    fail "expected %d declarations, found %d" expected_declaration_count
      (List.length declarations);
  if owner_count <> expected_owner_count then
    fail "expected %d owners, found %d" expected_owner_count owner_count;
  { declarations; method_count; property_count; owner_count }
