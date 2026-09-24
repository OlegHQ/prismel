let ids =
  [ "class:MTL4AccelerationStructureBoundingBoxGeometryDescriptor"
  ; "class:MTL4AccelerationStructureCurveGeometryDescriptor"
  ; "class:MTL4AccelerationStructureDescriptor"
  ; "class:MTL4AccelerationStructureGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionCurveGeometryDescriptor"
  ; "class:MTL4AccelerationStructureMotionTriangleGeometryDescriptor"
  ; "class:MTL4AccelerationStructureTriangleGeometryDescriptor"
  ; "class:MTL4IndirectInstanceAccelerationStructureDescriptor"
  ; "class:MTL4InstanceAccelerationStructureDescriptor"
  ; "class:MTL4PrimitiveAccelerationStructureDescriptor" ]

let concrete_constructor_count = 9
let abstract_metadata_count = 2

let () =
  if List.length ids <> 11 || List.length (List.sort_uniq String.compare ids) <> 11
     || concrete_constructor_count + abstract_metadata_count <> 11
  then invalid_arg "MTL4AccelerationStructure11 native closure drift"
