type work_package = Mechanical_native | Handwritten_safe_native | Public_metadata

let mechanical_ids =
  [ "method:-[MTLRasterizationRateLayerDescriptor maxSampleCount]"
  ; "method:-[MTLRasterizationRateLayerDescriptor sampleCount]"
  ; "method:-[MTLRasterizationRateLayerDescriptor setSampleCount:]"
  ; "method:-[MTLRasterizationRateMap layerCount]"
  ; "method:-[MTLRasterizationRateMap mapPhysicalToScreenCoordinates:forLayer:]"
  ; "method:-[MTLRasterizationRateMap mapScreenToPhysicalCoordinates:forLayer:]"
  ; "method:-[MTLRasterizationRateMap physicalGranularity]"
  ; "method:-[MTLRasterizationRateMap physicalSizeForLayer:]"
  ; "method:-[MTLRasterizationRateMap screenSize]"
  ; "method:-[MTLRasterizationRateMapDescriptor layerCount]"
  ; "method:-[MTLRasterizationRateMapDescriptor screenSize]"
  ; "method:-[MTLRasterizationRateMapDescriptor setScreenSize:]"
  ; "property:MTLRasterizationRateLayerDescriptor:maxSampleCount"
  ; "property:MTLRasterizationRateLayerDescriptor:sampleCount"
  ; "property:MTLRasterizationRateMap:layerCount"
  ; "property:MTLRasterizationRateMap:physicalGranularity"
  ; "property:MTLRasterizationRateMap:screenSize"
  ; "property:MTLRasterizationRateMapDescriptor:layerCount"
  ; "property:MTLRasterizationRateMapDescriptor:screenSize"
  ]

let descriptor_constructors =
  [ "method:+[MTLRasterizationRateMapDescriptor rasterizationRateMapDescriptorWithScreenSize:]"
  ; "method:+[MTLRasterizationRateMapDescriptor rasterizationRateMapDescriptorWithScreenSize:layer:]"
  ; "method:+[MTLRasterizationRateMapDescriptor rasterizationRateMapDescriptorWithScreenSize:layerCount:layers:]"
  ; "method:-[MTLRasterizationRateLayerDescriptor initWithSampleCount:]"
  ; "method:-[MTLRasterizationRateLayerDescriptor initWithSampleCount:horizontal:vertical:]"
  ]

let array_access =
  [ "method:-[MTLRasterizationRateLayerArray objectAtIndexedSubscript:]"
  ; "method:-[MTLRasterizationRateLayerArray setObject:atIndexedSubscript:]"
  ; "method:-[MTLRasterizationRateSampleArray objectAtIndexedSubscript:]"
  ; "method:-[MTLRasterizationRateSampleArray setObject:atIndexedSubscript:]"
  ]

let layer_storage =
  [ "method:-[MTLRasterizationRateLayerDescriptor horizontalSampleStorage]"
  ; "method:-[MTLRasterizationRateLayerDescriptor horizontal]"
  ; "method:-[MTLRasterizationRateLayerDescriptor verticalSampleStorage]"
  ; "method:-[MTLRasterizationRateLayerDescriptor vertical]"
  ; "property:MTLRasterizationRateLayerDescriptor:horizontal"
  ; "property:MTLRasterizationRateLayerDescriptor:horizontalSampleStorage"
  ; "property:MTLRasterizationRateLayerDescriptor:vertical"
  ; "property:MTLRasterizationRateLayerDescriptor:verticalSampleStorage"
  ]

let map_ownership =
  [ "method:-[MTLRasterizationRateMap copyParameterDataToBuffer:offset:]"
  ; "method:-[MTLRasterizationRateMap device]"
  ; "method:-[MTLRasterizationRateMap label]"
  ; "method:-[MTLRasterizationRateMap parameterBufferSizeAndAlign]"
  ; "property:MTLRasterizationRateMap:device"
  ; "property:MTLRasterizationRateMap:label"
  ; "property:MTLRasterizationRateMap:parameterBufferSizeAndAlign"
  ]

let descriptor_graph =
  [ "method:-[MTLRasterizationRateMapDescriptor label]"
  ; "method:-[MTLRasterizationRateMapDescriptor layerAtIndex:]"
  ; "method:-[MTLRasterizationRateMapDescriptor layers]"
  ; "method:-[MTLRasterizationRateMapDescriptor setLabel:]"
  ; "method:-[MTLRasterizationRateMapDescriptor setLayer:atIndex:]"
  ; "property:MTLRasterizationRateMapDescriptor:label"
  ; "property:MTLRasterizationRateMapDescriptor:layers"
  ]

let ownership_ids =
  descriptor_constructors @ array_access @ layer_storage @ map_ownership
  @ descriptor_graph

let metadata_ids =
  [ "class:MTLRasterizationRateLayerArray"
  ; "class:MTLRasterizationRateLayerDescriptor"
  ; "class:MTLRasterizationRateMapDescriptor"
  ; "class:MTLRasterizationRateSampleArray"
  ; "protocol:MTLRasterizationRateMap"
  ]

let all_ids = mechanical_ids @ ownership_ids @ metadata_ids

let package id =
  if List.mem id mechanical_ids then Mechanical_native
  else if List.mem id ownership_ids then Handwritten_safe_native
  else if List.mem id metadata_ids then Public_metadata
  else invalid_arg ("unknown rasterization-rate ID: " ^ id)

let validate () =
  if List.length mechanical_ids <> 19 || List.length ownership_ids <> 31
     || List.length metadata_ids <> 5 || List.length all_ids <> 55
     || List.length (List.sort_uniq String.compare all_ids) <> 55
  then failwith "rasterization-rate55 work-package drift"

let () = validate ()
