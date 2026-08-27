let ids =
  [ "class:MTLFunctionStitchingAttributeAlwaysInline"
  ; "class:MTLFunctionStitchingFunctionNode"
  ; "class:MTLFunctionStitchingGraph"
  ; "class:MTLFunctionStitchingInputNode"
  ; "class:MTLStitchedLibraryDescriptor"
  ; "protocol:MTLFunctionStitchingAttribute"
  ; "protocol:MTLFunctionStitchingNode" ]
let validate () =
  if List.length ids<>7 || List.length(List.sort_uniq String.compare ids)<>7
  then invalid_arg "FunctionStitching7 safe closure drift"
