type representation =
  | Layer_array
  | Layer_descriptor
  | Map_descriptor
  | Sample_array
  | Map_protocol

type item = { id : string; public_type : string; representation : representation }

let items =
  [ { id = "class:MTLRasterizationRateLayerArray"
    ; public_type = "Metal.Rasterization_rate_descriptor.t layer storage"
    ; representation = Layer_array }
  ; { id = "class:MTLRasterizationRateLayerDescriptor"
    ; public_type = "Metal.Rasterization_rate_layer.t"
    ; representation = Layer_descriptor }
  ; { id = "class:MTLRasterizationRateMapDescriptor"
    ; public_type = "Metal.Rasterization_rate_descriptor.t"
    ; representation = Map_descriptor }
  ; { id = "class:MTLRasterizationRateSampleArray"
    ; public_type = "float array snapshots in Metal.Rasterization_rate_layer"
    ; representation = Sample_array }
  ; { id = "protocol:MTLRasterizationRateMap"
    ; public_type = "Metal.Rasterization_rate_map.t"
    ; representation = Map_protocol } ]

let promotable_ids = List.map (fun item -> item.id) items

let validate () =
  if List.length items <> 5
     || List.length (List.sort_uniq String.compare promotable_ids) <> 5
     || List.exists (fun item -> item.public_type = "") items
  then failwith "RasterizationRate residual exact5 drift"

let () = validate ()
