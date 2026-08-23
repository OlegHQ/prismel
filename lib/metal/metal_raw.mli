type handle

(** Positional native ABI record. Keep field order synchronized with
    [texture_descriptor] in [metal_bridge.mm]. *)
type texture_descriptor =
  { texture_type : int
  ; pixel_format : int
  ; width : int
  ; height : int
  ; depth : int
  ; mip_levels : int
  ; sample_count : int
  ; array_length : int
  ; storage_mode : int
  ; cpu_cache_mode : int
  ; hazard_tracking_mode : int
  ; usage : int
  ; allow_gpu_optimized_contents : bool
  ; compression_type : int
  ; swizzle_red : int
  ; swizzle_green : int
  ; swizzle_blue : int
  ; swizzle_alpha : int
  }

(** Positional native ABI record for texture-view construction. *)
type texture_view_descriptor =
  { pixel_format : int
  ; texture_type : int
  ; base_mip : int
  ; mip_count : int
  ; base_slice : int
  ; slice_count : int
  ; requested_swizzle_red : int
  ; requested_swizzle_green : int
  ; requested_swizzle_blue : int
  ; requested_swizzle_alpha : int
  ; effective_swizzle_red : int
  ; effective_swizzle_green : int
  ; effective_swizzle_blue : int
  ; effective_swizzle_alpha : int
  }

external is_main_thread : unit -> bool = "caml_prismel_metal_is_main_thread"
external generation : handle -> int64 = "caml_prismel_metal_generation"
external destroyed : handle -> bool = "caml_prismel_metal_destroyed"
external destroy : handle -> bool = "caml_prismel_metal_destroy"

external drain_releases : unit -> int = "caml_prismel_metal_drain_releases"
external pending_releases : unit -> int = "caml_prismel_metal_pending_releases"
external dropped_releases : unit -> int = "caml_prismel_metal_dropped_releases"
external live_handles : unit -> int = "caml_prismel_metal_live_handles"
external total_created : unit -> int64 = "caml_prismel_metal_total_created"
external total_released : unit -> int64 = "caml_prismel_metal_total_released"
external external_deallocations : unit -> int64 =
  "caml_prismel_metal_external_deallocations"
external external_deallocation_mismatches : unit -> int64 =
  "caml_prismel_metal_external_deallocation_mismatches"
external resident_bytes : unit -> int64 = "caml_prismel_metal_resident_bytes"

external default_device : unit -> (handle, string) result =
  "caml_prismel_metal_default_device"

external all_devices : unit -> (handle array, string) result =
  "caml_prismel_metal_all_devices"

external device_name : handle -> string = "caml_prismel_metal_device_name"
external device_registry_id : handle -> int64 =
  "caml_prismel_metal_device_registry_id"

external device_is_low_power : handle -> bool =
  "caml_prismel_metal_device_is_low_power"

external device_is_removable : handle -> bool =
  "caml_prismel_metal_device_is_removable"

external device_is_headless : handle -> bool =
  "caml_prismel_metal_device_is_headless"

external device_has_unified_memory : handle -> bool =
  "caml_prismel_metal_device_has_unified_memory"

external device_recommended_max_working_set_size : handle -> int64 =
  "caml_prismel_metal_device_recommended_max_working_set_size"

external device_current_allocated_size : handle -> int64 =
  "caml_prismel_metal_device_current_allocated_size"

external device_max_buffer_length : handle -> int64 =
  "caml_prismel_metal_device_max_buffer_length"

external device_supports_family : handle -> int -> bool =
  "caml_prismel_metal_device_supports_family"

external device_supports_raytracing : handle -> bool =
  "caml_prismel_metal_device_supports_raytracing"

external device_supports_raytracing_from_render : handle -> bool =
  "caml_prismel_metal_device_supports_raytracing_from_render"

external device_supports_dynamic_libraries : handle -> bool =
  "caml_prismel_metal_device_supports_dynamic_libraries"

external device_supports_function_pointers : handle -> bool =
  "caml_prismel_metal_device_supports_function_pointers"

external device_supports_residency_sets : handle -> bool =
  "caml_prismel_metal_device_supports_residency_sets"

external device_supports_sparse_textures : handle -> bool =
  "caml_prismel_metal_device_supports_sparse_textures"

external device_supports_placement_sparse : handle -> bool =
  "caml_prismel_metal_device_supports_placement_sparse"

external device_supports_sampler_reduction : handle -> bool =
  "caml_prismel_metal_device_supports_sampler_reduction"

external device_supports_lossy_texture_compression : handle -> bool =
  "caml_prismel_metal_device_supports_lossy_texture_compression"

external device_sparse_tile_size_in_bytes :
  handle -> int -> (int64, string) result
  = "caml_prismel_metal_device_sparse_tile_size_in_bytes"

external device_sparse_texture_tile_size :
  handle -> int -> int -> int -> int -> ((int * int * int), string) result
  = "caml_prismel_metal_device_sparse_texture_tile_size"

external device_minimum_texture_alignment :
  handle -> int -> int -> (int64, string) result
  = "caml_prismel_metal_device_minimum_texture_alignment"

external buffer_create : handle -> int64 -> int -> (handle, string) result =
  "caml_prismel_metal_buffer_create"

external buffer_placement_sparse_create :
  handle -> int64 -> int -> int -> (handle, string) result
  = "caml_prismel_metal_buffer_placement_sparse_create"

external buffer_sparse_tier : handle -> int =
  "caml_prismel_metal_buffer_sparse_tier"

external buffer_create_copy :
  handle -> bytes -> int -> int -> int -> (handle, string) result
  = "caml_prismel_metal_buffer_create_copy"

external external_memory_page_size : unit -> int =
  "caml_prismel_metal_external_memory_page_size"

external external_memory_create : int64 -> (handle, string) result =
  "caml_prismel_metal_external_memory_create"

external external_memory_info : handle -> int64 * int64 =
  "caml_prismel_metal_external_memory_info"

external external_memory_write :
  handle -> int64 -> bytes -> int -> int -> (unit, string) result
  = "caml_prismel_metal_external_memory_write"

external external_memory_read :
  handle -> int64 -> int -> (bytes, string) result
  = "caml_prismel_metal_external_memory_read"

external buffer_create_no_copy :
  handle -> handle -> int -> (handle, string) result
  = "caml_prismel_metal_buffer_create_no_copy"

external buffer_texture_create :
  handle ->
  texture_descriptor ->
  int64 -> int -> string option -> (handle, string) result
  = "caml_prismel_metal_buffer_texture_create"

external buffer_info : handle -> int64 * int * int * int * int64 =
  "caml_prismel_metal_buffer_info"

external buffer_set_label : handle -> string -> (unit, string) result =
  "caml_prismel_metal_buffer_set_label"

external buffer_label : handle -> string option =
  "caml_prismel_metal_buffer_label"

external buffer_write :
  handle -> int64 -> bytes -> int -> int -> (unit, string) result
  = "caml_prismel_metal_buffer_write"

external buffer_read : handle -> int64 -> int -> (bytes, string) result =
  "caml_prismel_metal_buffer_read"

external resource_set_purgeable_state : handle -> int -> (int, string) result =
  "caml_prismel_metal_resource_set_purgeable_state"

external resource_make_aliasable : handle -> (unit, string) result =
  "caml_prismel_metal_resource_make_aliasable"

external resource_is_aliasable : handle -> bool =
  "caml_prismel_metal_resource_is_aliasable"

external device_supports_texture_sample_count : handle -> int -> bool =
  "caml_prismel_metal_device_supports_texture_sample_count"

external device_supports_depth24_stencil8 : handle -> bool =
  "caml_prismel_metal_device_supports_depth24_stencil8"

external device_supports_bc_texture_compression : handle -> bool =
  "caml_prismel_metal_device_supports_bc_texture_compression"

external heap_buffer_size_and_align : handle -> int64 -> int -> int64 * int64 =
  "caml_prismel_metal_heap_buffer_size_and_align"

external heap_texture_size_and_align :
  handle ->
  texture_descriptor ->
  int64 * int64
  = "caml_prismel_metal_heap_texture_size_and_align"

external heap_create :
  handle -> (int64 * int * int * int * int * int) -> string option ->
  (handle, string) result
  = "caml_prismel_metal_heap_create"

external heap_info : handle -> int64 array = "caml_prismel_metal_heap_info"
external heap_max_available_size : handle -> int64 -> int64 =
  "caml_prismel_metal_heap_max_available_size"

external heap_set_label : handle -> string -> (unit, string) result =
  "caml_prismel_metal_heap_set_label"

external heap_label : handle -> string option = "caml_prismel_metal_heap_label"

external heap_set_purgeable_state : handle -> int -> (int, string) result =
  "caml_prismel_metal_heap_set_purgeable_state"

external heap_buffer_create :
  handle -> int64 -> int -> int64 option -> (handle, string) result
  = "caml_prismel_metal_heap_buffer_create"

external heap_texture_create :
  handle ->
  texture_descriptor ->
  int64 option -> string option -> (handle, string) result
  = "caml_prismel_metal_heap_texture_create"

external residency_set_create :
  handle -> int -> string option -> (handle, string) result
  = "caml_prismel_metal_residency_set_create"

external residency_set_label : handle -> (string option, string) result =
  "caml_prismel_metal_residency_set_label"

external residency_set_allocated_size : handle -> (int64, string) result =
  "caml_prismel_metal_residency_set_allocated_size"

external allocation_allocated_size : handle -> (int64, string) result =
  "caml_prismel_metal_allocation_allocated_size"

external residency_set_counts :
  handle -> (int64 * int64, string) result
  = "caml_prismel_metal_residency_set_counts"

external residency_set_add_allocation :
  handle -> handle -> (unit, string) result
  = "caml_prismel_metal_residency_set_add_allocation"

external residency_set_add_allocations :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_residency_set_add_allocations"

external residency_set_remove_allocation :
  handle -> handle -> (unit, string) result
  = "caml_prismel_metal_residency_set_remove_allocation"

external residency_set_remove_allocations :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_residency_set_remove_allocations"

external residency_set_remove_all : handle -> (unit, string) result =
  "caml_prismel_metal_residency_set_remove_all"

external residency_set_contains : handle -> handle -> (bool, string) result =
  "caml_prismel_metal_residency_set_contains"

external residency_set_commit : handle -> (unit, string) result =
  "caml_prismel_metal_residency_set_commit"

external residency_set_request : handle -> (unit, string) result =
  "caml_prismel_metal_residency_set_request"

external residency_set_end : handle -> (unit, string) result =
  "caml_prismel_metal_residency_set_end"

external texture_create :
  handle ->
  texture_descriptor ->
  string option -> (handle, string) result
  = "caml_prismel_metal_texture_create"

external texture_placement_sparse_create :
  handle ->
  texture_descriptor ->
  int -> (handle, string) result
  = "caml_prismel_metal_texture_placement_sparse_create"

external texture_shared_create :
  handle ->
  texture_descriptor ->
  string option -> (handle, string) result
  = "caml_prismel_metal_texture_shared_create"

external texture_info : handle -> int array = "caml_prismel_metal_texture_info"

external texture_is_sparse : handle -> bool =
  "caml_prismel_metal_texture_is_sparse"

external texture_sparse_tier : handle -> int =
  "caml_prismel_metal_texture_sparse_tier"

external texture_sparse_info :
  handle -> handle -> int -> (int64 array, string) result
  = "caml_prismel_metal_texture_sparse_info"

external texture_is_shareable : handle -> bool =
  "caml_prismel_metal_texture_is_shareable"

external texture_shared_handle_create :
  handle -> (handle, string) result
  = "caml_prismel_metal_texture_shared_handle_create"

external shared_texture_handle_info : handle -> int64 * string option =
  "caml_prismel_metal_shared_texture_handle_info"

external texture_shared_import :
  handle -> handle -> (handle, string) result
  = "caml_prismel_metal_texture_shared_import"

external shared_texture_xpc_connect :
  string -> int -> (handle, string) result
  = "caml_prismel_metal_shared_texture_xpc_connect"

external shared_texture_xpc_call :
  handle -> string -> handle -> bytes -> bytes -> int ->
  (handle * bytes * bytes, string) result
  = "caml_prismel_metal_shared_texture_xpc_call_bytecode"
    "caml_prismel_metal_shared_texture_xpc_call"

external shared_texture_xpc_service_create :
  int -> int -> (handle, string) result
  = "caml_prismel_metal_shared_texture_xpc_service_create"

external shared_texture_xpc_service_serve :
  handle -> (handle -> string -> handle -> bytes -> bytes -> unit) ->
  (unit, string) result
  = "caml_prismel_metal_shared_texture_xpc_service_serve"

external shared_texture_xpc_request_reply :
  handle -> handle -> bytes -> bytes -> (unit, string) result
  = "caml_prismel_metal_shared_texture_xpc_request_reply"

external shared_texture_xpc_request_reject :
  handle -> string -> (unit, string) result
  = "caml_prismel_metal_shared_texture_xpc_request_reject"

external io_surface_create :
  bool -> int array -> string option -> (handle, string) result
  = "caml_prismel_metal_io_surface_create"

external io_surface_info : handle -> int64 * int64 * bool * int array =
  "caml_prismel_metal_io_surface_info"

external io_surface_write :
  handle -> int -> int64 -> bytes -> int -> (unit, string) result
  = "caml_prismel_metal_io_surface_write"

external io_surface_read :
  handle -> int -> int64 -> int -> (bytes, string) result
  = "caml_prismel_metal_io_surface_read"

external texture_io_surface_create :
  handle -> handle -> int ->
  texture_descriptor ->
  string option -> (handle, string) result
  = "caml_prismel_metal_texture_io_surface_create"

external texture_set_label : handle -> string -> (unit, string) result =
  "caml_prismel_metal_texture_set_label"

external texture_label : handle -> string option =
  "caml_prismel_metal_texture_label"

external texture_write :
  handle ->
  ((int * int * int * int * int * int) * int * int * int * int * int) ->
  bytes -> (unit, string) result
  = "caml_prismel_metal_texture_write"

external texture_read :
  handle ->
  ((int * int * int * int * int * int) * int * int * int * int * int) ->
  (bytes, string) result
  = "caml_prismel_metal_texture_read"

external texture_create_view :
  handle -> texture_view_descriptor -> string option ->
  (handle, string) result
  = "caml_prismel_metal_texture_create_view"

external sampler_create :
  handle ->
  (int * int * int * int * int * int * int * int * int * bool * float * float * bool * float * int * bool) ->
  string option -> (handle, string) result
  = "caml_prismel_metal_sampler_create"

external sampler_label : handle -> string option =
  "caml_prismel_metal_sampler_label"

external library_compile : handle -> string -> (handle, string) result =
  "caml_prismel_metal_library_compile"

external function_find : handle -> string -> (handle, string) result =
  "caml_prismel_metal_function_find"

external function_name : handle -> string = "caml_prismel_metal_function_name"

external compute_pipeline_create : handle -> handle -> (handle, string) result =
  "caml_prismel_metal_compute_pipeline_create"

external compute_pipeline_thread_execution_width : handle -> int =
  "caml_prismel_metal_compute_pipeline_thread_execution_width"

external compute_pipeline_max_total_threads : handle -> int =
  "caml_prismel_metal_compute_pipeline_max_total_threads"

external command_queue_create : handle -> (handle, string) result =
  "caml_prismel_metal_command_queue_create"

external command_queue_add_residency_set :
  handle -> handle -> (unit, string) result
  = "caml_prismel_metal_command_queue_add_residency_set"

external command_queue_add_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_queue_add_residency_sets"

external command_queue_remove_residency_set :
  handle -> handle -> (unit, string) result
  = "caml_prismel_metal_command_queue_remove_residency_set"

external command_queue_remove_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_queue_remove_residency_sets"

external command_buffer_create : handle -> (handle, string) result =
  "caml_prismel_metal_command_buffer_create"

external command_buffer_set_label : handle -> string -> (unit, string) result =
  "caml_prismel_metal_command_buffer_set_label"

external command_buffer_use_residency_set :
  handle -> handle -> (unit, string) result
  = "caml_prismel_metal_command_buffer_use_residency_set"

external command_buffer_use_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_buffer_use_residency_sets"

external command_buffer_compute_encoder : handle -> (handle, string) result =
  "caml_prismel_metal_command_buffer_compute_encoder"

external command_buffer_resource_state_encoder :
  handle -> (handle, string) result
  = "caml_prismel_metal_command_buffer_resource_state_encoder"

external command_buffer_blit_encoder : handle -> (handle, string) result =
  "caml_prismel_metal_command_buffer_blit_encoder"

external compute_encoder_set_pipeline : handle -> handle -> (unit, string) result =
  "caml_prismel_metal_compute_encoder_set_pipeline"

external compute_encoder_set_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result
  = "caml_prismel_metal_compute_encoder_set_buffer"

external compute_encoder_set_texture :
  handle -> handle -> int -> (unit, string) result
  = "caml_prismel_metal_compute_encoder_set_texture"

external compute_encoder_dispatch :
  handle -> (int * int * int) -> (int * int * int) -> (unit, string) result
  = "caml_prismel_metal_compute_encoder_dispatch"

external compute_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_compute_encoder_end"

external resource_state_encoder_update_texture_mapping :
  handle -> handle -> int -> (int * int * int * int * int * int) -> int -> int ->
  (unit, string) result
  = "caml_prismel_metal_resource_state_encoder_update_texture_mapping_bytecode"
    "caml_prismel_metal_resource_state_encoder_update_texture_mapping"

external resource_state_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_resource_state_encoder_end"

external blit_encoder_copy_buffer_to_texture :
  handle -> handle -> handle ->
  (int64 * int * int * (int * int * int) * int * int * (int * int * int)) ->
  (unit, string) result
  = "caml_prismel_metal_blit_encoder_copy_buffer_to_texture"

external blit_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_blit_encoder_end"

external command_buffer_commit : handle -> (unit, string) result =
  "caml_prismel_metal_command_buffer_commit"

external command_buffer_wait : handle -> unit =
  "caml_prismel_metal_command_buffer_wait"

external command_buffer_status : handle -> int =
  "caml_prismel_metal_command_buffer_status"

external command_buffer_error : handle -> string option =
  "caml_prismel_metal_command_buffer_error"
