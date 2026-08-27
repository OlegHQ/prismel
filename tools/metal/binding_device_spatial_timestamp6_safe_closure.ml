let callable_ids =
  [ "method:-[MTLDevice convertSparsePixelRegions:toTileRegions:withTileSize:alignmentMode:numRegions:]"
  ; "method:-[MTLDevice convertSparseTileRegions:toPixelRegions:withTileSize:numRegions:]"
  ; "method:-[MTLDevice getDefaultSamplePositions:count:]"
  ; "method:-[MTLDevice queryTimestampFrequency]"
  ; "method:-[MTLDevice sampleTimestamps:gpuTimestamp:]"
  ; "method:-[MTLDevice sizeOfCounterHeapEntry:]" ]

let expected_count = 6

let () =
  if List.length callable_ids <> expected_count then
    invalid_arg "Device spatial/timestamp closure must contain exactly six IDs";
  let sorted = List.sort_uniq String.compare callable_ids in
  if List.length sorted <> expected_count then
    invalid_arg "Device spatial/timestamp closure contains duplicate IDs"
