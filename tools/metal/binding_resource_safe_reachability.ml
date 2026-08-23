type gap =
  | Missing_public_operation
  | Missing_constructor
  | Missing_parent_metadata
  | Missing_completion_retention
  | Missing_capability_test

type status = Promotable | Blocked of gap

type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }

let contains text needle =
  let length = String.length needle in
  let rec loop offset =
    offset + length <= String.length text
    && (String.sub text offset length = needle || loop (offset + 1))
  in
  loop 0

let mem id values = List.exists (String.equal id) values

(* This is deliberately an audit of the public safe surface, not of whether a
   native trampoline exists.  The descriptor24 and callable10 partitions have
   executable safe adapters.  The pool core below is the exact portion exposed
   by [Metal.Resource100.Texture_view_pool]. *)
let pool_core =
  [ "method:-[MTLDevice newTextureViewPoolWithDescriptor:error:]"
  ; "method:-[MTLResourceViewPool copyResourceViewsFromPool:sourceRange:destinationIndex:]"
  ; "method:-[MTLResourceViewPool device]"
  ; "method:-[MTLResourceViewPool resourceViewCount]"
  ; "method:-[MTLTextureViewPool setTextureView:atIndex:]"
  ; "property:MTLResourceViewPool:device"
  ; "property:MTLResourceViewPool:resourceViewCount"
  ]

let has_public_operation id =
  mem id Binding_resource_integration_partition.descriptor_owned
  || mem id Binding_resource_integration_partition.already_callable
  || mem id Binding_resource_integration_partition.graph_gated_scalars
  || mem id Binding_resource_integration_partition.safe_ownership_tail
  || mem id pool_core

let public_operation id =
  if contains id "MTLBufferLayoutDescriptor" then
    "Metal.Resource100.Buffer_layout.create/get/set/destroy"
  else if contains id "MTLResourceStatePassSampleBufferAttachmentDescriptor"
  then "Metal.Resource100.Sample_attachment.create/set_range/destroy"
  else if contains id "MTLResourceViewPoolDescriptor" then
    "Metal.Resource100.View_pool_descriptor.create/get/destroy"
  else if contains id "newTextureViewPoolWithDescriptor" then
    "Metal.Resource100.Texture_view_pool.create"
  else if contains id "copyResourceViewsFromPool" then
    "Metal.Resource100.Texture_view_pool.copy"
  else if contains id "setTextureView:atIndex:" then
    "Metal.Resource100.Texture_view_pool.set"
  else if contains id "addDebugMarker" then
    "Metal.Resource100.Buffer_ops.add_debug_marker"
  else if contains id "newTextureViewWithPixelFormat" then
    "Metal.Resource100.Texture_ops.view"
  else if contains id "getBytes" then
    "Metal.Resource100.Texture_ops.get_bytes"
  else if contains id "replaceRegion" then
    "Metal.Resource100.Texture_ops.replace_region"
  else if contains id "MTLResourceStatePassDescriptor" then
    "Metal.Resource100.Resource_state_pass.create"
  else if contains id "resourceStateCommandEncoderWithDescriptor" then
    "Metal.Resource100.Resource_state_pass.create_encoder"
  else if contains id "updateFence" then
    "Metal.Resource_state_encoder.update_fence"
  else if contains id "waitForFence" then
    "Metal.Resource_state_encoder.wait_for_fence"
  else if contains id "MTLResourceViewPool device"
       || contains id "MTLResourceViewPool:device" then
    "Metal.Resource100.Texture_view_pool.device"
  else if contains id "resourceViewCount" then
    "Metal.Resource100.Texture_view_pool.count"
  else if contains id "MTLBuffer newRemoteBufferViewForDevice" then
    "Metal.Resource100.Buffer_ops.remote_view"
  else if contains id "MTLBuffer remoteStorageBuffer"
       || contains id "MTLBuffer:remoteStorageBuffer" then
    "Metal.Resource100.Buffer_ops.remote_storage"
  else if contains id "MTLTexture newRemoteTextureViewForDevice" then
    "Metal.Resource100.Texture_ops.remote_view"
  else if contains id "MTLTexture remoteStorageTexture"
       || contains id "MTLTexture:remoteStorageTexture" then
    "Metal.Resource100.Texture_ops.remote_storage"
  else if contains id "MTLTexture rootResource"
       || contains id "MTLTexture:rootResource" then
    "Metal.Resource100.Texture_ops.root_resource"
  else if contains id "setTextureViewFromBuffer" then
    "Metal.Resource100.Texture_view_pool.set_from_buffer"
  else if contains id "newAccelerationStructureWithSize:" then
    "Metal.Resource100.Heap_ops.create_acceleration_structure"
  else if contains id "MTLResourceViewPool baseResourceID"
       || contains id "MTLResourceViewPool:baseResourceID" then
    "Metal.Resource100.Texture_view_pool.base_resource_id"
  else if contains id "MTLResourceViewPool label"
       || contains id "MTLResourceViewPool:label" then
    "Metal.Resource100.Texture_view_pool.label"
  else if contains id "MTLResource device" || contains id "MTLResource:device" then
    "Metal.Resource100.Resource_ops.device"
  else if contains id "MTLResource heap" || contains id "MTLResource:heap" then
    "Metal.Resource100.Resource_ops.heap"
  else if mem id Binding_resource_integration_partition.graph_gated_scalars then
    "Metal.Resource100.Texture_ops.buffer_backing"
  else if mem id Binding_resource_integration_partition.already_callable then
    "existing Metal Device/Buffer/Texture/Heap/Resource safe operation"
  else "missing public Resource100 operation"

let required_test id =
  if String.starts_with ~prefix:"class:" id then
    "native construction, handle-kind rejection, destroy idempotence"
  else if String.starts_with ~prefix:"enum-case:" id then
    "exact numeric mapping and exhaustive round trip"
  else if contains id "Descriptor" then
    "default, setter/getter round trip, invalid range, zero handle delta"
  else if contains id "resourceStateCommandEncoder"
       || contains id "TextureMapping" || contains id "updateFence"
       || contains id "waitForFence" then
    "wrong-device rejection, exact command behavior, completion retention"
  else if contains id "new" || contains id "objectAtIndexedSubscript"
       || contains id "remoteStorage" || contains id "rootResource"
       || contains id "sampleBuffer" || contains id "device"
       || contains id "heap" then
    "nullable result, exact handle kind, parent graph, failure unwind"
  else if contains id "getBytes" || contains id "replaceRegion" then
    "malformed region/stride rejection and exact byte round trip"
  else "getter/setter exactness, destroyed rejection, zero handle delta"

let blocked_gap id =
  if contains id "sampleBuffer" || contains id "SampleBuffer" then
    Missing_constructor
  else if contains id "resourceStateCommandEncoder" || contains id "TextureMapping"
       || contains id "updateFence" || contains id "waitForFence" then
    Missing_completion_retention
  else if contains id "remote" || contains id "rootResource"
       || contains id " new" || contains id "objectAtIndexedSubscript"
       || contains id "setObject:atIndexedSubscript" then
    Missing_parent_metadata
  else if contains id "ViewPool" || contains id "setTextureView" then
    Missing_capability_test
  else Missing_public_operation

let item id =
  { id
  ; public_operation = public_operation id
  ; required_test = required_test id
  ; status = if has_public_operation id then Promotable else Blocked (blocked_gap id)
  }

let items = List.map item Binding_resource_manifest.ids
let promotable_ids =
  List.filter_map
    (fun item -> match item.status with Promotable -> Some item.id | Blocked _ -> None)
    items |> List.sort String.compare
let blocked =
  List.filter
    (fun item -> match item.status with Promotable -> false | Blocked _ -> true)
    items

let find id = List.find (fun item -> String.equal item.id id) items

let validate () =
  if List.length items <> 100 then failwith "Resource100 audit count drift";
  let ids = List.map (fun item -> item.id) items in
  if List.sort_uniq String.compare ids <> List.sort String.compare ids then
    failwith "Resource100 audit contains duplicate IDs";
  if List.sort String.compare ids
     <> List.sort String.compare Binding_resource_manifest.ids then
    failwith "Resource100 audit does not close the exact manifest";
  if List.exists (fun item -> item.public_operation = "" || item.required_test = "") items
  then failwith "Resource100 audit has an empty operation or test mapping";
  if List.exists (fun id -> not (List.mem id Binding_resource_manifest.ids))
       promotable_ids then
    failwith "Resource100 promotable closure escaped its manifest"

let () = validate ()
