type status = Pending_safe_native | Blocked
type item =
  { id : string
  ; safe_operation : string
  ; safe_fixture : string
  ; native_fixture : string
  ; status : status
  }

let items =
  [ { id = "method:-[MTLDevice newRenderPipelineStateWithMeshDescriptor:options:reflection:error:]"
    ; safe_operation = "Metal.Mesh_tile_pipeline.compile_mesh"
    ; safe_fixture = "lib/metal/test_metal_mesh_tile105_safe.ml"
    ; native_fixture = "tools/metal/test_mesh_tile_pipeline_native.mm"
    ; status = Pending_safe_native }
  ; { id = "method:-[MTLDevice newRenderPipelineStateWithTileDescriptor:options:reflection:error:]"
    ; safe_operation = "Metal.Mesh_tile_pipeline.compile_tile"
    ; safe_fixture = "lib/metal/test_metal_mesh_tile105_safe.ml"
    ; native_fixture = "tools/metal/test_mesh_tile_pipeline_native.mm"
    ; status = Pending_safe_native } ]

let pending_ids = List.map (fun item -> item.id) items
let validate () =
  if List.length items <> 2 || List.length (List.sort_uniq String.compare pending_ids) <> 2
     || List.exists (fun item -> item.safe_operation = "" || item.safe_fixture = "" || item.native_fixture = "") items
  then failwith "Mesh/tile synchronous compilation reachability drift"
let () = validate ()
