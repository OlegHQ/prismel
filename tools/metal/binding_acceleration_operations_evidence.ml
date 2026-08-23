let validate (selection : Binding_acceleration_operations_plan.selection) =
  if selection.method_count < 80 then
    invalid_arg "Metal acceleration operations: insufficient executable method closure";
  let required =
    [ "MTLAccelerationStructureCommandEncoder"; "MTLIntersectionFunctionTable"
    ; "MTLVisibleFunctionTable"; "MTLDevice"; "MTLComputePipelineState"
    ; "MTLRenderPipelineState" ]
  in
  List.iter
    (fun owner ->
      if not (List.mem owner selection.owners) then
        invalid_arg ("Metal acceleration operations: missing owner " ^ owner))
    required;
  let contract = Binding_acceleration_operations_codegen.render_contract selection in
  let safe = Binding_acceleration_operations_codegen.render_safe_model selection in
  if String.length contract < 15_000 || String.length safe < 12_000 then
    invalid_arg "Metal acceleration operations: generated evidence too small";
  if String.contains contract '\000' || String.contains safe '\000' then
    invalid_arg "Metal acceleration operations: invalid generated evidence"
