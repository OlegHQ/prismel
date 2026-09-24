let ids =
  [ "method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]"
  ; "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]"
  ; "method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]" ]

let existing_callable_symbols =
  [ "caml_prismel_metal4_compute_acceleration"
  ; "caml_prismel_metal4_compute_copy_tensor"
  ; "caml_prismel_metal4_compute_write_compacted" ]

let () =
  if List.length ids <> 5 || List.length (List.sort_uniq String.compare ids) <> 5
     || List.length existing_callable_symbols <> 3
  then invalid_arg "MTL4ComputeEncoder5 native closure drift"
