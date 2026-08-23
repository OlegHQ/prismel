let resource100_overlap =
 ["method:-[MTLDevice newTextureViewPoolWithDescriptor:error:]";
  "method:-[MTLDevice sparseTileSizeWithTextureType:pixelFormat:sampleCount:]"]
let acceleration115_overlap =
 ["method:-[MTLDevice accelerationStructureSizesWithDescriptor:]";
  "method:-[MTLDevice functionHandleWithBinaryFunction:]";
  "method:-[MTLDevice functionHandleWithFunction:]";
  "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithDescriptor:]";
  "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithSize:]";
  "method:-[MTLDevice newAccelerationStructureWithDescriptor:]";
  "method:-[MTLDevice newAccelerationStructureWithSize:]"]
let zero_overlap_batches = ["presentation125";"mesh_tile105";"render_resource19";"render_encoder106"]
let all_exclusions = resource100_overlap @ acceleration115_overlap
let () =
 if List.sort String.compare all_exclusions <>
    List.sort String.compare Binding_device_header_plan.excluded_ids then
  invalid_arg"Device/type overlap exclusions drift";
 if 103-List.length all_exclusions+25<>119 then invalid_arg"Device/type net count drift"
