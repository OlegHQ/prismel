let ids = Binding_device_tail38_plan.metadata_ids
let owned_metadata_ids =
  [ "class:MTLTilePipelineColorAttachmentDescriptor"
  ; "protocol:MTLIndirectComputeCommandEncoder"
  ; "protocol:MTLIndirectRenderCommandEncoder" ]
let observer_ids =
  [ "function:MTLCopyAllDevicesWithObserver"
  ; "function:MTLRemoveDeviceObserver"
  ; "typedef:MTLDeviceNotificationHandler"
  ; "typedef:MTLDeviceNotificationName" ]
let validate () =
  if List.length ids<>7 || List.length owned_metadata_ids<>3 ||
     List.length observer_ids<>4 ||
     List.sort String.compare ids <> List.sort String.compare
       (owned_metadata_ids@observer_ids)
  then invalid_arg "Device metadata7 exact partition drift"
