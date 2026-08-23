type buffer = Buffer of nativeint
type texture = Texture of nativeint
type heap = Heap of nativeint
type sampler = Sampler of nativeint
type resource = Resource of nativeint
type view_pool = View_pool of nativeint
type resource_state_encoder = Resource_state_encoder of nativeint
type capability = Sparse | Texture_views | Resource_view_pool | Hazard_tracking
type access = Read_only | Read_write | Write_only
type lifecycle = Owned | Borrowed_parent of resource | Completion_retained
type operation =
  | Buffer_contents | Buffer_gpu_address | Buffer_texture_view
  | Texture_view | Texture_replace_region | Texture_read_region
  | Heap_buffer | Heap_texture | Heap_make_aliasable
  | Resource_purgeable_state | Resource_label | Resource_view
  | Resource_state_encoder | Sparse_mapping | Sampler_metadata

let capability_for = function
  | Buffer_texture_view | Texture_view -> Some Texture_views
  | Resource_view -> Some Resource_view_pool
  | Sparse_mapping -> Some Sparse
  | Resource_state_encoder -> Some Hazard_tracking
  | _ -> None

let lifecycle_for = function
  | Buffer_contents | Buffer_gpu_address | Texture_replace_region | Texture_read_region
  | Resource_purgeable_state | Resource_label | Heap_make_aliasable | Sampler_metadata -> Owned
  | Buffer_texture_view | Texture_view | Resource_view -> Borrowed_parent (Resource Nativeint.zero)
  | Heap_buffer | Heap_texture | Resource_state_encoder | Sparse_mapping -> Completion_retained

let native_selector_contract =
  [ "[buffer contents] -> borrowed bytes bounded by buffer.length"
  ; "[buffer gpuAddress] -> scalar, unavailable after destruction"
  ; "[texture newTextureViewWithPixelFormat:*] -> owned child retaining parent"
  ; "[texture getBytes:*] / [texture replaceRegion:*] -> checked exact subresource"
  ; "[heap newBufferWithLength:options:] -> owned resource retaining heap relationship"
  ; "[heap newTextureWithDescriptor:] -> owned resource retaining heap relationship"
  ; "[resource setPurgeableState:] -> serialized state transition"
  ; "[resource makeAliasable] -> invalidates safe use until replacement allocation"
  ; "[commandBuffer resourceStateCommandEncoder*] -> completion-owned child"
  ; "[device newTextureViewPoolWithDescriptor:error:] -> owned error-returning constructor" ]

let failure_policies =
  [ "reject cross-device heap/resource/command combinations"
  ; "reject integer overflow before NSRange/MTLRegion construction"
  ; "reject unaligned offsets before native entry"
  ; "reject unsupported pixel-format views through capability and usage checks"
  ; "preserve source resource state when a view or pool constructor fails"
  ; "unwind every retained descriptor, pool, resource, and encoder on NSError/exception" ]
