let fail message = raise (Failure message)

let () =
  let actual =
    List.sort String.compare
      Binding_device_spatial_timestamp6_safe_closure.callable_ids
  in
  let expected =
    [ "method:-[MTLDevice convertSparsePixelRegions:toTileRegions:withTileSize:alignmentMode:numRegions:]"
    ; "method:-[MTLDevice convertSparseTileRegions:toPixelRegions:withTileSize:numRegions:]"
    ; "method:-[MTLDevice getDefaultSamplePositions:count:]"
    ; "method:-[MTLDevice queryTimestampFrequency]"
    ; "method:-[MTLDevice sampleTimestamps:gpuTimestamp:]"
    ; "method:-[MTLDevice sizeOfCounterHeapEntry:]" ]
    |> List.sort String.compare
  in
  if actual <> expected then fail "Device spatial/timestamp exact-six drift";
  print_endline "Device spatial/timestamp: exact six-selector closure"
