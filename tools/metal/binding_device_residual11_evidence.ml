type evidence =
  { id : string
  ; safe_entry : string
  ; conformance : string
  }

let entries =
  [ { id = "method:-[MTLDevice accelerationStructureSizesWithDescriptor:]"
    ; safe_entry = "Metal.Acceleration_structure.sizes"
    ; conformance = "test_metal_acceleration_safe.ml" }
  ; { id = "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithDescriptor:]"
    ; safe_entry = "Metal.Heap.acceleration_structure_size_and_align"
    ; conformance = "test_metal_resource100_safe.ml" }
  ; { id = "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithSize:]"
    ; safe_entry = "Metal.Heap.acceleration_structure_size_and_align_for_size"
    ; conformance = "test_metal_resource100_safe.ml" }
  ; { id = "method:-[MTLDevice newAccelerationStructureWithDescriptor:]"
    ; safe_entry = "Metal.Acceleration_structure.create"
    ; conformance = "test_metal_acceleration_safe.ml" }
  ; { id = "method:-[MTLDevice newAccelerationStructureWithSize:]"
    ; safe_entry = "Metal.Acceleration_structure.create_with_size"
    ; conformance = "test_metal_acceleration_safe.ml" }
  ; { id = "method:-[MTLDevice newCounterHeapWithDescriptor:error:]"
    ; safe_entry = "Metal.Command4.Counter_heap.create"
    ; conformance = "test_metal4_callable_safe.ml" }
  ; { id = "method:-[MTLDevice newCounterSampleBufferWithDescriptor:error:]"
    ; safe_entry = "Metal.Counter_sample_buffer.create"
    ; conformance = "test_metal_io_safe.ml" }
  ; { id = "method:-[MTLDevice newFence]"
    ; safe_entry = "Metal.Fence.create"
    ; conformance = "test_metal_fence6_safe.ml" }
  ; { id = "method:-[MTLDevice newIOFileHandleWithURL:compressionMethod:error:]"
    ; safe_entry = "Metal.IO.File.open_"
    ; conformance = "test_metal_io_safe.ml" }
  ; { id = "method:-[MTLDevice newLogStateWithDescriptor:error:]"
    ; safe_entry = "Metal.Command4.Log_state.create"
    ; conformance = "test_metal_log_state7_safe.ml" }
  ; { id = "method:-[MTLDevice newRasterizationRateMapWithDescriptor:]"
    ; safe_entry = "Metal.Rasterization_rate_map.create"
    ; conformance = "test_metal4_render_pass7_safe.ml" } ]

let validate () =
  let ids = List.map (fun item -> item.id) entries in
  if ids <> Binding_device_residual_safe_package.already_safe_ids then
    invalid_arg "Device residual11 evidence/set mismatch";
  List.iter
    (fun item ->
      if item.safe_entry = "" || item.conformance = "" then
        invalid_arg ("Device residual11 missing evidence for " ^ item.id))
    entries
