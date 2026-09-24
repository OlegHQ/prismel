type buffer = private Buffer of nativeint
type texture = private Texture of nativeint
type heap = private Heap of nativeint
type sampler = private Sampler of nativeint
type resource = private Resource of nativeint
type view_pool = private View_pool of nativeint
type resource_state_encoder = private Resource_state_encoder of nativeint

type capability = Sparse | Texture_views | Resource_view_pool | Hazard_tracking
type access = Read_only | Read_write | Write_only
type lifecycle = Owned | Borrowed_parent of resource | Completion_retained

type operation =
  | Buffer_contents | Buffer_gpu_address | Buffer_texture_view
  | Texture_view | Texture_replace_region | Texture_read_region
  | Heap_buffer | Heap_texture | Heap_make_aliasable
  | Resource_purgeable_state | Resource_label | Resource_view
  | Resource_state_encoder | Sparse_mapping | Sampler_metadata

val capability_for : operation -> capability option
val lifecycle_for : operation -> lifecycle
val native_selector_contract : string list
val failure_policies : string list
