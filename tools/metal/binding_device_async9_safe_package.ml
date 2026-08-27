let ids = Binding_device_tail38_plan.async9

let core6 =
  [ "method:-[MTLDevice newComputePipelineStateWithDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:completionHandler:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:options:completionHandler:]"
  ; "method:-[MTLDevice newLibraryWithSource:options:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:options:completionHandler:]" ]

let capability3 =
  [ "method:-[MTLDevice newLibraryWithStitchedDescriptor:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithMeshDescriptor:options:completionHandler:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithTileDescriptor:options:completionHandler:]" ]

let validate () =
  let union = List.sort_uniq String.compare (core6 @ capability3) in
  if List.length ids <> 9 || List.sort String.compare ids <> union then
    invalid_arg "Device async9 safe partition drift"
