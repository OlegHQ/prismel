open Support

let fail format = Printf.ksprintf failwith format
let string name value =
  match member_string name value with Some value -> value | None -> fail "missing %s" name

let declaration value =
  let declaration : Binding_pipeline_header_plan.declaration =
    { id = string "id" value
    ; header = string "header" value
    ; kind = string "kind" value
    ; owner = member_string "owner" value
    ; name = string "name" value
    ; signature = string "signature" value
    }
  in
  declaration, string "classification" value

let prior_bound_ids =
  [ "method:-[MTLRenderPipelineState maxTotalThreadsPerMeshThreadgroup]"
  ; "method:-[MTLRenderPipelineState maxTotalThreadsPerObjectThreadgroup]"
  ; "property:MTLRenderPipelineState:maxTotalThreadsPerMeshThreadgroup"
  ; "property:MTLRenderPipelineState:maxTotalThreadsPerObjectThreadgroup"
  ]

let post_plan_ids =
  [ "class:MTLComputePipelineDescriptor"
  ; "method:-[MTLComputePipelineDescriptor computeFunction]"
  ; "method:-[MTLComputePipelineDescriptor preloadedLibraries]"
  ; "method:-[MTLComputePipelineDescriptor setComputeFunction:]"
  ; "method:-[MTLComputePipelineDescriptor setPreloadedLibraries:]"
  ; "property:MTLComputePipelineDescriptor:computeFunction"
  ; "property:MTLComputePipelineDescriptor:preloadedLibraries" ]

let historical_bound_ids =
  [ "enum-case:MTLBlendFactor:MTLBlendFactorUnspecialized"
  ; "enum-case:MTLBlendOperation:MTLBlendOperationUnspecialized"
  ; "enum-case:MTLColorWriteMask:MTLColorWriteMaskUnspecialized"
  ; "enum-case:MTLPrimitiveTopologyClass:MTLPrimitiveTopologyClassUnspecified" ]

let promoted_plan_ids =
  Binding_pipeline_expanded_reachability.promotable_ids
  @ Binding_pipeline_state_safe_reachability.promotable_ids
  @ historical_bound_ids
  |> List.filter (fun id -> not (List.mem id (prior_bound_ids @ post_plan_ids)))

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let json = read_file Sys.argv.(1) |> Yojson.Safe.from_string in
  let declarations =
    match member_list "symbols" json with
    | Some values ->
        List.map declaration values
        |> List.filter_map (fun (declaration, classification) ->
             if classification = "unreviewed"
                || List.mem declaration.Binding_pipeline_header_plan.id promoted_plan_ids
             then Some declaration else None)
    | None -> fail "inventory symbols are absent"
  in
  let entries = Binding_pipeline_header_plan.select declarations in
  Binding_pipeline_header_plan.validate entries;
  let items =
    List.map
      (fun (entry : Binding_pipeline_header_plan.entry) ->
        Binding_pipeline_state_safe_reachability.item entry.declaration.id)
      entries
  in
  let promotable =
    List.filter_map
      (fun item ->
        match item.Binding_pipeline_state_safe_reachability.status with
        | Promotable -> Some item.id
        | Blocked _ -> None)
      items |> List.sort String.compare
  in
  let expected =
    List.filter
      (fun id -> not (List.mem id prior_bound_ids))
      Binding_pipeline_state_safe_reachability.promotable_ids
  in
  if promotable <> expected then
    fail "Pipeline113 promotable closure escaped the qualified manifest";
  if List.length Binding_pipeline_state_safe_reachability.promotable_ids <> 24
     || List.length promotable <> 20 || List.length items - List.length promotable <> 93
  then
    fail "Pipeline113 safe/gap cardinality drift";
  Printf.printf
    "Pipeline113 public audit: 24 safe IDs (20 newly promotable, 4 prior bound), 93 blocked; exact113 closed\n"
