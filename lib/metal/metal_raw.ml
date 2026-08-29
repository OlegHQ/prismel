type handle
type device_region = int64 * int64 * int64 * int64 * int64 * int64

include Metal_raw_generated.Make (struct
    type nonrec handle = handle
  end)

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

(** Positional native ABI value for one function-constant specialization. *)
type function_constant_value = string * int * int64 * float

(** Name, Metal data-type code, index, and required flag. *)
type function_constant_info = string * int * int64 * bool

type acceleration_triangle_descriptor =
  { vertex_buffer : handle
  ; vertex_offset : int64
  ; vertex_stride : int64
  ; triangle_count : int64
  ; index_buffer : handle option
  ; index_offset : int64
  }

(** Positional native ABI value for one reflected pipeline binding. Keep this
    synchronized with [copy_bindings] in [metal_bridge.mm]. *)
type pipeline_binding_info =
  string * int * int * int64 * bool * bool * int64 * int64 * int * int * int
  * bool * int64 * int64 * int64 * int64 * int64
  * Metal_argument_reflection_snapshot.reflected_type option

type library_compile_descriptor =
  { label : string option
  ; library_type : int
  ; install_name : string option
  ; linked_libraries : handle array
  }

type compute_pipeline_descriptor =
  { label : string option
  ; reflection : bool
  ; linked_functions : handle array
  ; preloaded_libraries : handle array
  ; binary_archives : handle array
  ; fail_on_binary_archive_miss : bool
  ; support_indirect_command_buffers : bool
  ; buffer_mutabilities : int array
  }

(** Library handle and function name used by Metal 4 static linking. *)
type metal4_function_reference = handle * string

type metal4_static_linking_descriptor =
  { functions : metal4_function_reference array
  ; private_functions : metal4_function_reference array
  ; groups : (string * metal4_function_reference array) array
  }

type metal4_stage_dynamic_linking_descriptor =
  { max_call_stack_depth : int64
  ; binary_linked_functions : handle array
  ; preloaded_libraries : handle array
  }

(** Positional native ABI record for synchronous Metal 4 compute compilation. *)
type metal4_compute_descriptor =
  { label : string option
  ; library : handle
  ; function_name : string
  ; reflection : bool
  ; threadgroup_size_multiple : bool
  ; max_total_threads : int64
  ; required_threads_width : int64
  ; required_threads_height : int64
  ; required_threads_depth : int64
  ; support_binary_linking : bool
  ; support_indirect_commands : bool
  ; preloaded_libraries : handle array
  ; max_call_stack_depth : int64
  ; lookup_archives : handle array
  ; binary_linked_functions : handle array
  ; static_linking : metal4_static_linking_descriptor option
  }

type render_pipeline_reflection =
  { vertex_bindings : pipeline_binding_info array
  ; fragment_bindings : pipeline_binding_info array
  ; tile_bindings : pipeline_binding_info array
  ; object_bindings : pipeline_binding_info array
  ; mesh_bindings : pipeline_binding_info array
  }

type metal4_render_color_attachment_descriptor =
  { pixel_format : int
  ; blending_state : int
  ; source_rgb_blend_factor : int
  ; destination_rgb_blend_factor : int
  ; rgb_blend_operation : int
  ; source_alpha_blend_factor : int
  ; destination_alpha_blend_factor : int
  ; alpha_blend_operation : int
  ; write_mask : int
  }

type metal4_vertex_attribute_descriptor =
  { attribute_index : int
  ; vertex_format : int
  ; offset : int64
  ; buffer_index : int
  }

type metal4_vertex_layout_descriptor =
  { buffer_index : int
  ; stride : int64 option
  ; step_function : int
  ; step_rate : int64
  }

type metal4_vertex_descriptor =
  { attributes : metal4_vertex_attribute_descriptor array
  ; layouts : metal4_vertex_layout_descriptor array
  }

type metal4_render_descriptor =
  { label : string option
  ; library : handle
  ; vertex_function : string
  ; fragment_function : string option
  ; reflection : bool
  ; raster_sample_count : int64
  ; color_attachments : metal4_render_color_attachment_descriptor array
  ; rasterization_enabled : bool
  ; primitive_topology : int
  ; support_indirect_commands : bool
  ; lookup_archives : handle array
  ; vertex_descriptor : metal4_vertex_descriptor option
  ; support_vertex_binary_linking : bool
  ; support_fragment_binary_linking : bool
  ; vertex_dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  ; fragment_dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  ; vertex_static_linking : metal4_static_linking_descriptor option
  ; fragment_static_linking : metal4_static_linking_descriptor option
  ; alpha_to_coverage : bool
  ; alpha_to_one : bool
  ; max_vertex_amplification_count : int64
  ; color_attachment_mapping : int
  }

type metal4_mesh_descriptor =
  { label : string option
  ; library : handle
  ; object_function : string option
  ; mesh_function : string
  ; fragment_function : string option
  ; reflection : bool
  ; max_total_object_threads : int64
  ; max_total_mesh_threads : int64
  ; required_object_width : int64
  ; required_object_height : int64
  ; required_object_depth : int64
  ; required_mesh_width : int64
  ; required_mesh_height : int64
  ; required_mesh_depth : int64
  ; object_threadgroup_size_multiple : bool
  ; mesh_threadgroup_size_multiple : bool
  ; payload_memory_length : int64
  ; max_total_threadgroups_per_mesh_grid : int64
  ; raster_sample_count : int64
  ; color_attachments : metal4_render_color_attachment_descriptor array
  ; rasterization_enabled : bool
  ; support_indirect_commands : bool
  ; lookup_archives : handle array
  ; support_object_binary_linking : bool
  ; support_mesh_binary_linking : bool
  ; support_fragment_binary_linking : bool
  ; object_dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  ; mesh_dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  ; fragment_dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  ; object_static_linking : metal4_static_linking_descriptor option
  ; mesh_static_linking : metal4_static_linking_descriptor option
  ; fragment_static_linking : metal4_static_linking_descriptor option
  ; alpha_to_coverage : bool
  ; alpha_to_one : bool
  ; max_vertex_amplification_count : int64
  ; color_attachment_mapping : int
  }

type metal4_tile_descriptor =
  { label : string option
  ; library : handle
  ; tile_function : string
  ; reflection : bool
  ; raster_sample_count : int64
  ; color_formats : int array
  ; threadgroup_size_matches_tile_size : bool
  ; max_total_threads : int64
  ; required_threads_width : int64
  ; required_threads_height : int64
  ; required_threads_depth : int64
  ; support_binary_linking : bool
  ; static_linking : metal4_static_linking_descriptor option
  ; lookup_archives : handle array
  ; dynamic_linking : metal4_stage_dynamic_linking_descriptor option
  }

(** Positional native ABI record for one base-level Metal 4 render-pass color
    attachment and its optional single-sample resolve target. *)
type metal4_render_attachment =
  { texture : handle
  ; resolve_texture : handle option
  ; load_action : int
  ; store_action : int
  ; clear_red : float
  ; clear_green : float
  ; clear_blue : float
  ; clear_alpha : float
  }

(** Positional native ABI record for one base-level Metal 4 render-pass depth
    attachment. *)
type metal4_render_depth_attachment =
  { texture : handle
  ; load_action : int
  ; store_action : int
  ; clear_depth : float
  }

(** Positional native ABI record for one base-level Metal 4 render-pass stencil
    attachment. *)
type metal4_render_stencil_attachment =
  { texture : handle
  ; load_action : int
  ; store_action : int
  ; clear_stencil : int32
  }

(** Positional native ABI record for a Metal 4 render pass. *)
type metal4_render_pass_descriptor =
  { color_attachments : metal4_render_attachment array
  ; depth_attachment : metal4_render_depth_attachment option
  ; stencil_attachment : metal4_render_stencil_attachment option
  ; width : int
  ; height : int
  ; sample_count : int
  ; label : string option
  ; support_color_attachment_mapping : bool
  ; visibility_result_buffer : handle option
  ; visibility_result_type : int
  }

(** Positional native ABI record for one amplified vertex view. *)
type metal4_vertex_amplification_view_mapping =
  { viewport_array_index_offset : int64
  ; render_target_array_index_offset : int64
  }

(** Positional native ABI record for one Metal scissor rectangle. *)
type metal4_scissor_rect =
  { x : int64
  ; y : int64
  ; width : int64
  ; height : int64
  }

(** Positional native ABI record for one immutable stencil face. *)
type depth_stencil_face_descriptor =
  { compare_function : int
  ; stencil_failure_operation : int
  ; depth_failure_operation : int
  ; pass_operation : int
  ; read_mask : int32
  ; write_mask : int32
  }

(** Positional native ABI record for immutable depth/stencil state. *)
type depth_stencil_descriptor =
  { depth_compare_function : int
  ; depth_write_enabled : bool
  ; front_face_stencil : depth_stencil_face_descriptor option
  ; back_face_stencil : depth_stencil_face_descriptor option
  ; label : string option
  }

type indirect_command_buffer_descriptor =
  { command_types : int64
  ; inherit_buffers : bool
  ; inherit_pipeline_state : bool
  ; max_vertex_buffer_bind_count : int64
  ; max_fragment_buffer_bind_count : int64
  ; max_kernel_buffer_bind_count : int64
  ; support_ray_tracing : bool
  ; support_dynamic_attribute_stride : bool
  ; max_kernel_threadgroup_memory_bind_count : int64
  ; max_object_buffer_bind_count : int64
  ; max_mesh_buffer_bind_count : int64
  ; max_object_threadgroup_memory_bind_count : int64
  ; inherit_depth_stencil_state : bool
  ; inherit_depth_bias : bool
  ; inherit_depth_clip_mode : bool
  ; inherit_cull_mode : bool
  ; inherit_front_facing_winding : bool
  ; inherit_triangle_fill_mode : bool
  ; support_color_attachment_mapping : bool
  }

(** Positional native ABI record for a Metal 4 argument-table descriptor. *)
type metal4_argument_table_descriptor =
  { max_buffers : int
  ; max_textures : int
  ; max_samplers : int
  ; initialize_bindings : bool
  ; support_attribute_strides : bool
  ; label : string option
  }

(** Positional native ABI record for a Metal 4 binary-function lookup or
    compilation. *)
type metal4_binary_function_descriptor =
  { library : handle
  ; source_function : handle
  ; binary_name : string
  ; pipeline_independent : bool
  ; lookup_archives : handle array
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
external placement_mapping_operations : unit -> int64 =
  "caml_prismel_metal_placement_mapping_operations"
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

external device_supports_function_pointers_from_render : handle -> bool =
  "caml_prismel_metal_device_supports_function_pointers_from_render"

external device_supports_vertex_amplification_count : handle -> int -> bool =
  "caml_prismel_metal_device_supports_vertex_amplification_count"

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

external xpc_connect : int -> string -> int -> (handle, string) result =
  "caml_prismel_metal_xpc_connect"

external xpc_call :
  handle -> string -> handle -> bytes -> bytes -> int ->
  (handle * bytes * bytes, string) result
  = "caml_prismel_metal_xpc_call_bytecode" "caml_prismel_metal_xpc_call"

external xpc_service_create : int -> int -> int -> (handle, string) result =
  "caml_prismel_metal_xpc_service_create"

external xpc_service_serve :
  handle -> (handle -> string -> handle -> bytes -> bytes -> unit) ->
  (unit, string) result
  = "caml_prismel_metal_xpc_service_serve"

external xpc_request_reply :
  handle -> handle -> bytes -> bytes -> (unit, string) result
  = "caml_prismel_metal_xpc_request_reply"

external xpc_request_reject :
  handle -> string -> (unit, string) result
  = "caml_prismel_metal_xpc_request_reject"

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

external texture_read_into :
  handle ->
  ((int * int * int * int * int * int) * int * int * int * int * int) ->
  bytes -> (unit, string) result
  = "caml_prismel_metal_texture_read_into"

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

external depth_stencil_create :
  handle -> depth_stencil_descriptor -> (handle, string) result =
  "caml_prismel_metal_depth_stencil_create"

external depth_stencil_label : handle -> string option =
  "caml_prismel_metal_depth_stencil_label"

external indirect_command_buffer_create :
  handle -> indirect_command_buffer_descriptor -> int64 -> int64 ->
  (handle, string) result = "caml_prismel_metal_indirect_command_buffer_create"

external indirect_command_buffer_size : handle -> int64 =
  "caml_prismel_metal_indirect_command_buffer_size"
external indirect_command_buffer_gpu_resource_id : handle -> (int64,string) result =
  "caml_prismel_metal_indirect_command_buffer_gpu_resource_id"

external indirect_command_buffer_reset : handle -> int64 -> int64 ->
  (unit, string) result = "caml_prismel_metal_indirect_command_buffer_reset"

external indirect_render_command : handle -> int64 -> (handle, string) result =
  "caml_prismel_metal_indirect_render_command"

external indirect_compute_command : handle -> int64 -> (handle, string) result =
  "caml_prismel_metal_indirect_compute_command"

external indirect_render_command_reset : handle -> (unit, string) result =
  "caml_prismel_metal_indirect_render_command_reset"

external indirect_render_command_set_pipeline : handle -> handle ->
  (unit, string) result = "caml_prismel_metal_indirect_render_command_set_pipeline"

external indirect_render_command_set_vertex_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_indirect_render_command_set_vertex_buffer"

external indirect_render_command_set_fragment_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_indirect_render_command_set_fragment_buffer"

external indirect_render_command_draw_primitives :
  handle -> int -> int64 -> int64 -> int64 -> int64 -> (unit, string) result =
  "caml_prismel_metal_indirect_render_command_draw_primitives_bytecode"
  "caml_prismel_metal_indirect_render_command_draw_primitives"

external indirect_compute_command_reset : handle -> (unit, string) result =
  "caml_prismel_metal_indirect_compute_command_reset"

external indirect_compute_command_set_pipeline : handle -> handle ->
  (unit, string) result = "caml_prismel_metal_indirect_compute_command_set_pipeline"

external indirect_compute_command_set_kernel_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_indirect_compute_command_set_kernel_buffer"

external indirect_compute_command_dispatch_threads :
  handle -> (int * int * int) -> (int * int * int) -> (unit, string) result =
  "caml_prismel_metal_indirect_compute_command_dispatch_threads"

external compute_encoder_execute_indirect_commands :
  handle -> handle -> int64 -> int64 -> (unit, string) result =
  "caml_prismel_metal_compute_encoder_execute_indirect_commands"

external library_compile :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_library_compile"

external library_compile_descriptor :
  handle -> string -> library_compile_descriptor -> (handle, string) result =
  "caml_prismel_metal_library_compile_descriptor"

external library_load_file :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_library_load_file"

external library_label : handle -> string option =
  "caml_prismel_metal_library_label"

external library_kind : handle -> int = "caml_prismel_metal_library_kind"

external library_install_name : handle -> string option =
  "caml_prismel_metal_library_install_name"

external library_function_names : handle -> string array =
  "caml_prismel_metal_library_function_names"

external function_find : handle -> string -> (handle, string) result =
  "caml_prismel_metal_function_find"

external function_name : handle -> string = "caml_prismel_metal_function_name"

external function_label : handle -> string option =
  "caml_prismel_metal_function_label"

external function_kind : handle -> int = "caml_prismel_metal_function_kind"

external function_constants : handle -> function_constant_info array =
  "caml_prismel_metal_function_constants"

external function_specialize :
  handle -> string -> function_constant_value array -> string option ->
  (handle, string) result
  = "caml_prismel_metal_function_specialize"

external function_create_descriptor :
  handle -> string -> string option -> function_constant_value array -> int ->
  handle array -> bool ->
  (handle, string) result
  = "caml_prismel_metal_function_create_descriptor_bytecode"
    "caml_prismel_metal_function_create_descriptor"

external dynamic_library_create :
  handle -> handle -> string option -> (handle, string) result =
  "caml_prismel_metal_dynamic_library_create"

external dynamic_library_load_file :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_dynamic_library_load_file"

external dynamic_library_label : handle -> string option =
  "caml_prismel_metal_dynamic_library_label"

external dynamic_library_install_name : handle -> string =
  "caml_prismel_metal_dynamic_library_install_name"

external dynamic_library_serialize :
  handle -> string -> (unit, string) result =
  "caml_prismel_metal_dynamic_library_serialize"

external binary_archive_create :
  handle -> string option -> string option -> (handle, string) result =
  "caml_prismel_metal_binary_archive_create"

external binary_archive_label : handle -> string option =
  "caml_prismel_metal_binary_archive_label"

external binary_archive_add_compute :
  handle -> handle -> handle array -> handle array -> (unit, string) result =
  "caml_prismel_metal_binary_archive_add_compute"

external binary_archive_serialize :
  handle -> string -> (unit, string) result =
  "caml_prismel_metal_binary_archive_serialize"

external pipeline_dataset_create :
  handle -> int -> (handle, string) result =
  "caml_prismel_metal_pipeline_dataset_create"

external pipeline_dataset_serialize_script :
  handle -> (bytes, string) result =
  "caml_prismel_metal_pipeline_dataset_serialize_script"

external pipeline_dataset_serialize_archive :
  handle -> string -> (unit, string) result =
  "caml_prismel_metal_pipeline_dataset_serialize_archive"

external pipeline_archive_load_file :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_pipeline_archive_load_file"

external pipeline_archive_label : handle -> string option =
  "caml_prismel_metal_pipeline_archive_label"

external pipeline_archive_load_binary_function :
  handle -> metal4_binary_function_descriptor -> (handle, string) result =
  "caml_prismel_metal_pipeline_archive_load_binary_function"

external pipeline_archive_compute :
  handle -> metal4_compute_descriptor -> bool -> (handle, string) result =
  "caml_prismel_metal_pipeline_archive_compute"
external pipeline_archive_render :
  handle -> metal4_render_descriptor -> bool -> (handle, string) result =
  "caml_prismel_metal_pipeline_archive_render"

external compiler_create :
  handle -> handle option -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_create"

external compiler_label : handle -> string option =
  "caml_prismel_metal_compiler_label"

external compiler_compile_library :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_compile_library"

external compiler_compile_library_async :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_compile_library_async"

external compiler_task_id : handle -> int64 =
  "caml_prismel_metal_compiler_task_id"

external compiler_task_status : handle -> int =
  "caml_prismel_metal_compiler_task_status"

external compiler_task_wait : handle -> unit =
  "caml_prismel_metal_compiler_task_wait"

external compiler_task_take_library :
  handle -> (((handle, string) result option, string) result) =
  "caml_prismel_metal_compiler_task_take_library"

external compiler_create_dynamic_library :
  handle -> handle -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_create_dynamic_library"

external compiler_load_dynamic_library :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_load_dynamic_library"

external compiler_create_dynamic_library_async :
  handle -> handle -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_create_dynamic_library_async"

external compiler_load_dynamic_library_async :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_load_dynamic_library_async"

external compiler_task_take_dynamic_library :
  handle -> (((handle, string) result option, string) result) =
  "caml_prismel_metal_compiler_task_take_dynamic_library"

external compiler_completion_drain : int -> int64 array =
  "caml_prismel_metal_compiler_completion_drain"

external compiler_completion_dropped : unit -> int64 =
  "caml_prismel_metal_compiler_completion_dropped"

external compiler_completion_pending : unit -> int =
  "caml_prismel_metal_compiler_completion_pending"

external compiler_completion_capacity : unit -> int =
  "caml_prismel_metal_compiler_completion_capacity"

external compiler_create_binary_function :
  handle -> metal4_binary_function_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_binary_function"

external compiler_create_binary_function_async :
  handle -> metal4_binary_function_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_binary_function_async"

external compiler_task_take_binary_function :
  handle -> (((handle, string) result option, string) result) =
  "caml_prismel_metal_compiler_task_take_binary_function"

external compiler_create_compute_pipeline :
  handle -> metal4_compute_descriptor ->
  ((handle * pipeline_binding_info array), string) result =
  "caml_prismel_metal_compiler_create_compute_pipeline"

external compiler_create_compute_pipeline_async :
  handle -> metal4_compute_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_compute_pipeline_async"

external compiler_task_take_compute_pipeline :
  handle ->
  ((((handle * pipeline_binding_info array), string) result option, string)
    result) =
  "caml_prismel_metal_compiler_task_take_compute_pipeline"

external compiler_create_render_pipeline :
  handle -> metal4_render_descriptor ->
  ((handle * render_pipeline_reflection), string) result =
  "caml_prismel_metal_compiler_create_render_pipeline"

external compiler_create_render_pipeline_async :
  handle -> metal4_render_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_render_pipeline_async"

external compiler_specialize_render_pipeline :
  handle -> metal4_render_descriptor -> handle ->
  ((handle * render_pipeline_reflection), string) result =
  "caml_prismel_metal_compiler_specialize_render_pipeline"

external compiler_specialize_render_pipeline_async :
  handle -> metal4_render_descriptor -> handle -> (handle, string) result =
  "caml_prismel_metal_compiler_specialize_render_pipeline_async"

external compiler_create_mesh_pipeline :
  handle -> metal4_mesh_descriptor ->
  ((handle * render_pipeline_reflection), string) result =
  "caml_prismel_metal_compiler_create_mesh_pipeline"

external compiler_create_mesh_pipeline_async :
  handle -> metal4_mesh_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_mesh_pipeline_async"

external compiler_create_tile_pipeline :
  handle -> metal4_tile_descriptor ->
  ((handle * render_pipeline_reflection), string) result =
  "caml_prismel_metal_compiler_create_tile_pipeline"

external compiler_create_tile_pipeline_async :
  handle -> metal4_tile_descriptor -> (handle, string) result =
  "caml_prismel_metal_compiler_create_tile_pipeline_async"

external compiler_task_take_render_pipeline :
  handle ->
  ((((handle * render_pipeline_reflection), string) result option, string)
    result) =
  "caml_prismel_metal_compiler_task_take_render_pipeline"

external render_pipeline_label : handle -> string option =
  "caml_prismel_metal_render_pipeline_label"

external render_pipeline_mesh_limits :
  handle -> ((int * int * int * int * int), string) result =
  "caml_prismel_metal_render_pipeline_mesh_limits"

external render_pipeline_tile_limits :
  handle -> ((int * bool), string) result =
  "caml_prismel_metal_render_pipeline_tile_limits"

external command4_allocator_create :
  handle -> string option -> (handle, string) result =
  "caml_prismel_metal_command4_allocator_create"

external command4_allocator_label : handle -> string option =
  "caml_prismel_metal_command4_allocator_label"

external command4_allocator_allocated_size : handle -> int64 =
  "caml_prismel_metal_command4_allocator_allocated_size"

external command4_allocator_reset : handle -> (unit, string) result =
  "caml_prismel_metal_command4_allocator_reset"

external command4_queue_create :
  handle -> string option -> (handle, string) result =
  "caml_prismel_metal_command4_queue_create"

external command4_queue_label : handle -> string option =
  "caml_prismel_metal_command4_queue_label"

external command4_argument_table_create :
  handle -> metal4_argument_table_descriptor -> (handle, string) result =
  "caml_prismel_metal_command4_argument_table_create"

external command4_argument_table_label : handle -> string option =
  "caml_prismel_metal_command4_argument_table_label"

external command4_argument_table_set_buffer :
  handle -> handle option -> (int * int64 * int option) ->
  (unit, string) result =
  "caml_prismel_metal_command4_argument_table_set_buffer"

external command4_argument_table_set_texture :
  handle -> handle option -> int -> (unit, string) result =
  "caml_prismel_metal_command4_argument_table_set_texture"

external command4_argument_table_set_sampler :
  handle -> handle option -> int -> (unit, string) result =
  "caml_prismel_metal_command4_argument_table_set_sampler"

external metal4_argument_table_set_resource :
  handle -> handle -> int -> int64 -> (unit, string) result =
  "caml_prismel_metal4_argument_table_set_resource"

external command4_buffer_create :
  handle -> string option -> (handle, string) result =
  "caml_prismel_metal_command4_buffer_create"
external metal4_command_buffer_options_create : handle -> (handle,string) result =
  "caml_prismel_metal4_command_buffer_options_create"
external metal4_command_buffer_options_log_state : handle -> handle option -> (unit,string) result =
  "caml_prismel_metal4_command_buffer_options_log_state"
external metal4_command_buffer_create_options : handle -> string option -> handle -> (handle,string) result =
  "caml_prismel_metal4_command_buffer_create_options"

external command4_buffer_label : handle -> string option =
  "caml_prismel_metal_command4_buffer_label"

external command4_buffer_end : handle -> (unit, string) result =
  "caml_prismel_metal_command4_buffer_end"

external command4_compute_encoder_create :
  handle -> string option -> (handle, string) result =
  "caml_prismel_metal_command4_compute_encoder_create"

external command4_compute_encoder_set_pipeline :
  handle -> handle -> handle -> (unit, string) result =
  "caml_prismel_metal_command4_compute_encoder_set_pipeline"

external command4_compute_encoder_set_argument_table :
  handle -> handle -> handle option -> (unit, string) result =
  "caml_prismel_metal_command4_compute_encoder_set_argument_table"

external command4_compute_encoder_dispatch :
  handle -> handle -> handle option ->
  (int * int * int * int * int * int) -> (unit, string) result =
  "caml_prismel_metal_command4_compute_encoder_dispatch"

external command4_compute_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_command4_compute_encoder_end"

external command4_render_encoder_create :
  handle -> metal4_render_pass_descriptor ->
  ((handle * int * int), string) result =
  "caml_prismel_metal_command4_render_encoder_create"

external command4_render_encoder_set_pipeline :
  handle -> handle -> handle -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_pipeline"

external command4_render_encoder_set_vertex_amplification_count :
  handle -> handle -> int ->
  metal4_vertex_amplification_view_mapping array option ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_vertex_amplification_count"

external command4_render_encoder_set_color_attachment_map :
  handle -> handle -> int array option -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_color_attachment_map"

external command4_render_encoder_set_depth_stencil :
  handle -> handle -> handle option -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_depth_stencil"

external command4_render_encoder_set_stencil_reference :
  handle -> handle -> int32 -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_stencil_reference"

external command4_render_encoder_set_stencil_references :
  handle -> handle -> int32 -> int32 -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_stencil_references"

external command4_render_encoder_set_blend_color :
  handle -> handle -> (float * float * float * float) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_blend_color"

external command4_render_encoder_set_argument_table :
  handle -> handle -> handle option -> int -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_argument_table"

external command4_render_encoder_set_viewport :
  handle -> (float * float * float * float * float * float) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_viewport"

external command4_render_encoder_set_viewports :
  handle -> (float * float * float * float * float * float) array ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_viewports"

external command4_render_encoder_set_depth_bias :
  handle -> (float * float * float) -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_depth_bias"

external command4_render_encoder_set_depth_test_bounds :
  handle -> (float * float) -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_depth_test_bounds"

external command4_render_encoder_set_scissor_rect :
  handle -> metal4_scissor_rect -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_scissor_rect"

external command4_render_encoder_set_scissor_rects :
  handle -> metal4_scissor_rect array -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_scissor_rects"

external command4_render_encoder_set_color_store_action :
  handle -> int -> int -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_color_store_action"

external command4_render_encoder_set_depth_store_action :
  handle -> int -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_depth_store_action"

external command4_render_encoder_set_stencil_store_action :
  handle -> int -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_stencil_store_action"

external command4_render_encoder_set_visibility_result_mode :
  handle -> int -> int64 -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_set_visibility_result_mode"

external command4_render_encoder_draw_primitives :
  handle -> handle -> handle array -> (int * int * int) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_primitives"

external command4_render_encoder_draw_primitives_instanced :
  handle -> handle -> handle array -> (int * int * int * int * int) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_primitives_instanced"

external command4_render_encoder_draw_indexed_primitives :
  handle -> handle -> handle array -> handle -> (int * int * int * int64) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_indexed_primitives"

external command4_render_encoder_draw_indexed_primitives_instanced :
  handle -> handle -> handle array -> handle ->
  (int * int * int * int64 * int * int * int) -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_indexed_primitives_instanced"

external command4_render_encoder_draw_primitives_indirect :
  handle -> handle -> handle array -> handle -> (int * int64) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_primitives_indirect"

external command4_render_encoder_draw_indexed_primitives_indirect :
  handle -> handle -> handle array -> (handle * handle) ->
  (int * int * int64 * int64 * int64) -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_indexed_primitives_indirect"

external command4_render_encoder_draw_mesh_threadgroups :
  handle -> handle -> handle array ->
  (int * int * int * int * int * int * int * int * int) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_draw_mesh_threadgroups"

external command4_render_encoder_dispatch_threads_per_tile :
  handle -> handle -> handle array -> (int * int * int) ->
  (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_dispatch_threads_per_tile"

external command4_render_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_command4_render_encoder_end"

external command4_queue_commit :
  handle -> handle array -> (handle, string) result =
  "caml_prismel_metal_command4_queue_commit"

external command4_submission_wait : handle -> (unit, string) result =
  "caml_prismel_metal_command4_submission_wait"
external command4_submission_times : handle -> ((float * float), string) result =
  "caml_prismel_metal_command4_submission_times"

external compute_pipeline_create : handle -> handle -> (handle, string) result =
  "caml_prismel_metal_compute_pipeline_create"

external compute_pipeline_create_descriptor :
  handle -> handle -> compute_pipeline_descriptor ->
  ((handle * pipeline_binding_info array), string) result
  = "caml_prismel_metal_compute_pipeline_create_descriptor"

external render93_buffer_at :
  handle -> int -> int -> int64 -> handle option -> (unit, string) result =
  "caml_prismel_metal_render93_buffer_at"

external compute_pipeline_label : handle -> string option =
  "caml_prismel_metal_compute_pipeline_label"

external compute_pipeline_thread_execution_width : handle -> int =
  "caml_prismel_metal_compute_pipeline_thread_execution_width"

external compute_pipeline_max_total_threads : handle -> int =
  "caml_prismel_metal_compute_pipeline_max_total_threads"

external placement_mapping_queue_create :
  handle -> string option -> (handle, string) result
  = "caml_prismel_metal_placement_mapping_queue_create"

external placement_mapping_queue_label : handle -> string option =
  "caml_prismel_metal_placement_mapping_queue_label"

external placement_mapping_update_buffer :
  handle -> handle -> handle option -> int ->
  (int64 * int64 * int64 * int) -> (unit, string) result
  = "caml_prismel_metal_placement_mapping_update_buffer"

external placement_mapping_update_texture :
  handle -> handle -> handle option ->
  (int * (int * int * int * int * int * int) * int * int * int64 * int) ->
  (unit, string) result
  = "caml_prismel_metal_placement_mapping_update_texture"

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

external acceleration_structure_sizes :
  handle -> acceleration_triangle_descriptor ->
  ((int64 * int64 * int64), string) result
  = "caml_prismel_metal_acceleration_structure_sizes"

external acceleration_structure_create :
  handle -> int64 -> (handle, string) result
  = "caml_prismel_metal_acceleration_structure_create"

external command_buffer_acceleration_encoder :
  handle -> (handle, string) result
  = "caml_prismel_metal_command_buffer_acceleration_encoder"

external acceleration_encoder_build :
  handle -> handle -> acceleration_triangle_descriptor -> handle -> int64 ->
  (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_build"

external acceleration_encoder_refit :
  handle -> handle -> handle -> acceleration_triangle_descriptor -> handle ->
  int64 -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_refit_bytecode"
    "caml_prismel_metal_acceleration_encoder_refit"

external acceleration_encoder_copy :
  handle -> handle -> handle -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_copy"

external acceleration_encoder_write_compacted_size :
  handle -> handle -> handle -> int64 -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_write_compacted_size"

external acceleration_encoder_copy_and_compact :
  handle -> handle -> handle -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_copy_and_compact"

external acceleration_encoder_end : handle -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_end"

external compute_pipeline_function_handle :
  handle -> handle -> (handle, string) result
  = "caml_prismel_metal_compute_pipeline_function_handle"
external compute_pipeline11_named : handle -> string -> (handle option,string) result =
  "caml_prismel_metal_compute_pipeline11_named"
external compute_pipeline11_relink : handle -> bool -> (handle,string) result =
  "caml_prismel_metal_compute_pipeline11_relink"
external compute_pipeline_visible_function_table :
  handle -> int64 -> (handle, string) result
  = "caml_prismel_metal_compute_pipeline_visible_function_table"
external compute_pipeline_intersection_function_table :
  handle -> int64 -> (handle, string) result
  = "caml_prismel_metal_compute_pipeline_intersection_function_table"
external visible_function_table_set_function :
  handle -> handle option -> int -> (unit, string) result
  = "caml_prismel_metal_visible_function_table_set_function"
external intersection_function_table_set_function :
  handle -> handle option -> int -> (unit, string) result
  = "caml_prismel_metal_intersection_function_table_set_function"
external intersection_function_table_set_buffer :
  handle -> handle option -> int64 -> int -> (unit, string) result
  = "caml_prismel_metal_intersection_function_table_set_buffer"
external intersection_function_table_set_visible_table :
  handle -> handle option -> int -> (unit, string) result
  = "caml_prismel_metal_intersection_function_table_set_visible_table"
external function_table_resource_id : handle -> int64
  = "caml_prismel_metal_function_table_resource_id"

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
external command_buffer_render_encoder :
  handle -> handle -> float * float * float * float -> (handle, string) result =
  "caml_prismel_metal_command_buffer_render_encoder"
external command_buffer_render_encoder_attachments :
  handle -> handle -> handle option -> handle option ->
  float * float * float * float -> (handle,string) result =
  "caml_prismel_metal_command_buffer_render_encoder_attachments_bytecode"
  "caml_prismel_metal_command_buffer_render_encoder_attachments"
external device_create_fence : handle -> (handle, string) result =
  "caml_prismel_metal_device_create_fence"
external fence_snapshot : handle -> (int64 * string option,string) result =
  "caml_prismel_metal_fence_snapshot"
external fence_set_label : handle -> string option -> (unit,string) result =
  "caml_prismel_metal_fence_set_label"
external layer_create : handle -> (handle,string) result = "caml_prismel_metal_layer_create"
external layer_adopt_borrowed : handle -> Native_layer_token.t -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_layer_adopt_borrowed"
external layer_configure : handle -> int -> int -> int -> (bool*int*bool*bool*bool) -> (unit,string) result = "caml_prismel_metal_layer_configure"
external layer_next_drawable : handle -> (handle option,string) result = "caml_prismel_metal_layer_next_drawable"
external layer10_snapshot : handle -> ((int64 option * (string * string) list * bool),string) result = "caml_prismel_metal_layer10_snapshot"
external layer10_set_hud : handle -> (string * string) list -> (unit,string) result = "caml_prismel_metal_layer10_set_hud"
type presentation_layer_snapshot = int64 * float * float * int64 * bool * int64 * bool * bool * bool * bool
external layer_native_snapshot : handle -> (presentation_layer_snapshot,string) result = "caml_prismel_metal_layer_native_snapshot"
external layer_set_extended_range : handle -> bool -> (unit,string) result = "caml_prismel_metal_layer_set_extended_range"
external layer_colorspace_name : handle -> (string option,string) result = "caml_prismel_metal_layer_colorspace_name"
external layer_set_colorspace_name : handle -> string option -> (unit,string) result = "caml_prismel_metal_layer_set_colorspace_name"
external layer_set_edr : handle -> int -> (float * float * float) -> (unit,string) result = "caml_prismel_metal_layer_set_edr"
external layer_has_edr : handle -> bool = "caml_prismel_metal_layer_has_edr"
external drawable_native_layer : handle -> (handle,string) result = "caml_prismel_metal_drawable_native_layer"
external drawable_texture : handle -> ((handle * int * int * int),string) result = "caml_prismel_metal_drawable_texture"
external command_buffer_present_drawable : handle -> handle -> int -> float -> (unit,string) result = "caml_prismel_metal_command_buffer_present_drawable"
type presentation_command_snapshot = int64 * int64 * int64 * float * float * float * float * bool
external presentation_command_snapshot : handle -> (presentation_command_snapshot,string) result = "caml_prismel_metal_presentation_command_snapshot"
external presentation_command_schedule : handle -> bool -> (unit,string) result = "caml_prismel_metal_presentation_command_schedule"
external presentation_command_debug : handle -> string -> bool -> (unit,string) result = "caml_prismel_metal_presentation_command_debug"
external presentation_command_event : handle -> handle -> int64 -> bool -> (unit,string) result = "caml_prismel_metal_presentation_command_event"
external presentation_compute_encoder : handle -> int -> (handle,string) result = "caml_prismel_metal_presentation_compute_encoder"
external presentation_acceleration_encoder : handle -> (handle,string) result = "caml_prismel_metal_presentation_acceleration_encoder"
external presentation_command_logs : handle -> (string option,string) result = "caml_prismel_metal_presentation_command_logs"
external presentation_descriptor_encoder : handle -> int -> (handle,string) result = "caml_prismel_metal_presentation_descriptor_encoder"
external presentation_parallel_encoder_from_pass : handle -> handle -> (handle,string) result = "caml_prismel_metal_presentation_parallel_encoder_from_pass"
external presentation_parallel_encoder_end : handle -> (unit,string) result = "caml_prismel_metal_presentation_parallel_encoder_end"
external command_buffer_add_handler : handle -> (unit -> unit) -> bool -> (nativeint,string) result = "caml_prismel_metal_command_buffer_add_handler"
external command_buffer_cancel_handler : nativeint -> unit = "caml_prismel_metal_command_buffer_cancel_handler"
external render_pass_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_render_pass_descriptor_create"
external render_pass_descriptor_set_sizes : handle -> int -> int -> int -> int -> (unit,string) result = "caml_prismel_metal_render_pass_descriptor_set_sizes"
type presentation_render_pass_advanced = int64 * int64 * int64 * int64 * int64 * bool * (float * float) array
external render_pass_advanced_set : handle -> presentation_render_pass_advanced -> (unit,string) result = "caml_prismel_metal_render_pass_advanced_set"
external render_pass_advanced_get : handle -> (presentation_render_pass_advanced,string) result = "caml_prismel_metal_render_pass_advanced_get"
external render_pass_reset_depth_stencil : handle -> (unit,string) result = "caml_prismel_metal_render_pass_reset_depth_stencil"
external render_pass_sample_attachments : handle -> (handle,string) result = "caml_prismel_metal_render_pass_sample_attachments"
external render_pass_sample_set : handle -> int64 -> handle option -> int64 -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_pass_sample_set_bytecode" "caml_prismel_metal_render_pass_sample_set"
external render_pass_resolve_texture : handle -> handle option -> bool -> (handle option,string) result = "caml_prismel_metal_render_pass_resolve_texture"
external render_pass_color_store_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_pass_color_store_action"
external render_pass_color_load_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_pass_color_load_action"
external render_pass_set_rate_map : handle -> handle option -> (unit,string) result = "caml_prismel_metal_render_pass_set_rate_map"
external render_pass_sizes : handle -> ((int64 * int64 * int64 * int64),string) result = "caml_prismel_metal_render_pass_sizes"
external render_pass_descriptor_set_attachments :
  handle -> handle -> handle option -> handle option -> handle option ->
  float * float * float * float -> (unit,string) result =
  "caml_prismel_metal_render_pass_descriptor_set_attachments_bytecode"
  "caml_prismel_metal_render_pass_descriptor_set_attachments"
external command_buffer_render_encoder_from_pass :
  handle -> handle -> (handle,string) result =
  "caml_prismel_metal_command_buffer_render_encoder_from_pass"
external render_encoder_memory_barrier_scope : handle -> int -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_memory_barrier_scope"
external render_encoder_memory_barrier_resources : handle -> handle array -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_memory_barrier_resources"
external render_encoder_update_fence : handle -> handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_update_fence"
external render_encoder_wait_fence : handle -> handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_wait_fence"
external render_encoder_set_depth_store_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_set_depth_store_action"
external render_encoder_set_depth_store_options : handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_set_depth_store_options"
external render_encoder_set_stencil_store_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_set_stencil_store_action"
external render_encoder_set_stencil_store_options : handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_set_stencil_store_options"
external render_encoder_use_heaps : handle -> handle array -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_use_heaps"
external render_encoder_use_resources : handle -> handle array -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_use_resources"
external render_encoder_execute_icb_range : handle -> handle -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_execute_icb_range"
external render_encoder_execute_icb_indirect_range : handle -> handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_encoder_execute_icb_indirect_range"
external render_encoder_set_pipeline : handle -> handle -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_pipeline"
external render_encoder_set_vertex_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_buffer"
external render_encoder_set_fragment_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_buffer"
external render_encoder_set_vertex_texture :
  handle -> handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_texture"
external render_encoder_set_fragment_texture :
  handle -> handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_texture"
external render_encoder_set_vertex_bytes :
  handle -> bytes -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_bytes"
external render_encoder_set_fragment_bytes :
  handle -> bytes -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_bytes"
external render_encoder_set_vertex_sampler :
  handle -> handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_sampler"
external render_encoder_set_fragment_sampler :
  handle -> handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_sampler"
external render_encoder_set_vertex_sampler_lod :
  handle -> handle -> float * float -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_sampler_lod"
external render_encoder_set_fragment_sampler_lod :
  handle -> handle -> float * float -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_sampler_lod"

(* Render-command102 raw ABI. High-arity calls name bytecode and native
   companions explicitly; keep these declarations synchronized with the four
   audited render-command native shards. *)
external render_command_draw : handle -> int -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_draw"
external render_command_draw_instances : handle -> int -> int64 -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_draw_instances_bytecode" "caml_prismel_metal_render_command_draw_instances"
external render_command_depth_clip : handle -> int -> (unit,string) result = "caml_prismel_metal_render_command_depth_clip"
external render_command_depth_bounds : handle -> float -> float -> (unit,string) result = "caml_prismel_metal_render_command_depth_bounds"
external render_command_fragment_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_fragment_buffer_offset"
external render_command_mesh_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_mesh_buffer_offset"
external render_command_object_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_object_buffer_offset"
external render_command_object_threadgroup_memory : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_object_threadgroup_memory"
external render_command_stencil_reference : handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_stencil_reference"
external render_command_tessellation_scale : handle -> float -> (unit,string) result = "caml_prismel_metal_render_command_tessellation_scale"
external render_command_threadgroup_memory : handle -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_threadgroup_memory"
external render_command_tile_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_tile_buffer_offset"
external render_command_vertex_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_vertex_buffer_offset"
external render_command_vertex_buffer_offset_stride : handle -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_command_vertex_buffer_offset_stride"

external render_sample_attachment_create : unit -> (handle,string) result = "caml_prismel_metal_render_sample_attachment_create"
external render_sample_start_vertex : handle -> (int64,string) result = "caml_prismel_metal_render_sample_start_vertex"
external render_sample_set_start_vertex : handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_sample_set_start_vertex"
external render_sample_end_vertex : handle -> (int64,string) result = "caml_prismel_metal_render_sample_end_vertex"
external render_sample_set_end_vertex : handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_sample_set_end_vertex"
external render_sample_start_fragment : handle -> (int64,string) result = "caml_prismel_metal_render_sample_start_fragment"
external render_sample_set_start_fragment : handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_sample_set_start_fragment"
external render_sample_end_fragment : handle -> (int64,string) result = "caml_prismel_metal_render_sample_end_fragment"
external render_sample_set_end_fragment : handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_sample_set_end_fragment"
external render_sample_buffer : handle -> (handle option,string) result = "caml_prismel_metal_render_sample_buffer"
external render_sample_set_buffer : handle -> handle option -> (unit,string) result = "caml_prismel_metal_render_sample_set_buffer"
external render_sample_array_get : handle -> int64 -> (handle option,string) result = "caml_prismel_metal_render_sample_array_get"
external render_sample_array_set : handle -> int64 -> handle option -> (unit,string) result = "caml_prismel_metal_render_sample_array_set"

external render_stage_buffer : handle -> int -> handle option -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_buffer_bytecode" "caml_prismel_metal_render_stage_buffer"
external render_stage_buffers : handle -> int -> handle option array -> int64 array -> int64 array -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_buffers_bytecode" "caml_prismel_metal_render_stage_buffers"
external render_stage_bytes : handle -> int -> bytes -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_bytes_bytecode" "caml_prismel_metal_render_stage_bytes"
external render_stage_sampler : handle -> int -> handle option -> bool -> (float*float) -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_sampler_bytecode" "caml_prismel_metal_render_stage_sampler"
external render_stage_samplers : handle -> int -> handle option array -> bool -> float array -> float array -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_samplers_bytecode" "caml_prismel_metal_render_stage_samplers"
external render_stage_texture : handle -> int -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_texture"
external render_stage_textures : handle -> int -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_textures"
external render_stage_acceleration : handle -> int -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_acceleration"
external render_stage_intersection : handle -> int -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_intersection"
external render_stage_intersections : handle -> int -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_intersections"
external render_stage_visible : handle -> int -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_visible"
external render_stage_visibles : handle -> int -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_visibles"

type render_command_scissor = int64 * int64 * int64 * int64
type render_command_viewport = float * float * float * float * float * float
type render_command_view_mapping = int64 * int64
external render_draw_indexed_patches_indirect : handle -> int64 -> handle -> int64 -> handle -> int64 -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_patches_indirect_bytecode" "caml_prismel_metal_render_draw_indexed_patches_indirect"
external render_draw_indexed_patches : handle -> int64 -> int64 -> int64 -> handle -> int64 -> handle -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_patches_bytecode" "caml_prismel_metal_render_draw_indexed_patches"
external render_draw_indexed : handle -> int -> int64 -> int -> handle -> int64 -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_bytecode" "caml_prismel_metal_render_draw_indexed"
external render_draw_indexed_instances : handle -> int -> int64 -> int -> handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_instances_bytecode" "caml_prismel_metal_render_draw_indexed_instances"
external render_draw_indexed_basic : handle -> int -> int64 -> int -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_basic_bytecode" "caml_prismel_metal_render_draw_indexed_basic"
external render_draw_indexed_indirect : handle -> int -> int -> handle -> int64 -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_indirect_bytecode" "caml_prismel_metal_render_draw_indexed_indirect"
external render_draw_patches_indirect : handle -> int64 -> handle -> int64 -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_patches_indirect_bytecode" "caml_prismel_metal_render_draw_patches_indirect"
external render_draw_patches : handle -> int64 -> int64 -> int64 -> handle -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_patches_bytecode" "caml_prismel_metal_render_draw_patches"
external render_draw_indirect : handle -> int -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indirect"
external render_sample_counters : handle -> handle -> int64 -> bool -> (unit,string) result = "caml_prismel_metal_render_sample_counters"
external render_color_attachment_map : handle -> handle option -> (unit,string) result = "caml_prismel_metal_render_color_attachment_map"
external render_depth_stencil : handle -> handle option -> (unit,string) result = "caml_prismel_metal_render_depth_stencil"
external render_scissors : handle -> render_command_scissor array -> (unit,string) result = "caml_prismel_metal_render_scissors"
external render_tessellation_buffer : handle -> handle option -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_tessellation_buffer"
external render_vertex_amplification : handle -> render_command_view_mapping array -> (unit,string) result = "caml_prismel_metal_render_vertex_amplification"
external render_viewports : handle -> render_command_viewport array -> (unit,string) result = "caml_prismel_metal_render_viewports"
external render_encoder_draw :
  handle -> int -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_draw"
external render_encoder_end : handle -> (unit, string) result =
  "caml_prismel_metal_render_encoder_end"
external render_encoder_set_viewport :
  handle -> float * float * float * float * float * float -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_viewport"
external render_encoder_set_scissor :
  handle -> int * int * int * int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_scissor"
external render_encoder_set_cull_mode : handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_cull_mode"
external render_encoder_set_winding : handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_winding"
external render_encoder_set_fill_mode : handle -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fill_mode"
external render_encoder_set_blend_color :
  handle -> float * float * float * float -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_blend_color"
external render_encoder_set_depth_bias :
  handle -> float * float * float -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_depth_bias"
external render_encoder_set_stencil_reference :
  handle -> int32 -> int32 -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_stencil_reference"
external render_encoder_set_visibility :
  handle -> int -> int64 -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_visibility"
external render_encoder_tile_width : handle -> int =
  "caml_prismel_metal_render_encoder_tile_width"
external render_encoder_tile_height : handle -> int =
  "caml_prismel_metal_render_encoder_tile_height"
external render_encoder_set_color_store_action :
  handle -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_color_store_action"
external render_encoder_set_color_store_options :
  handle -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_color_store_options"

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

external compute35_buffer_stride : handle -> handle option -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_buffer_stride"
external compute35_buffer_offset : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_buffer_offset"
external compute35_buffer_offset_stride : handle -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_buffer_offset_stride"
external compute35_buffers : handle -> handle option array -> int64 array -> int64 array -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_buffers_bytecode" "caml_prismel_metal_compute35_buffers"
external compute35_bytes : handle -> bytes -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_bytes"
external compute35_textures : handle -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_textures"
external compute35_sampler : handle -> handle option -> (float*float) option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_sampler"
external compute35_samplers : handle -> handle option array -> float array option -> float array option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_samplers_bytecode" "caml_prismel_metal_compute35_samplers"
external compute35_acceleration : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_acceleration"
external compute35_visible : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_visible"
external compute35_visibles : handle -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_visibles"
external compute35_intersection : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_intersection"
external compute35_intersections : handle -> handle option array -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_intersections"
external compute35_dispatch_groups : handle -> int*int*int -> int*int*int -> (unit,string) result = "caml_prismel_metal_compute35_dispatch_groups"
external compute35_dispatch_indirect : handle -> handle -> int64 -> int*int*int -> (unit,string) result = "caml_prismel_metal_compute35_dispatch_indirect"
external compute35_dispatch_type : handle -> (int,string) result = "caml_prismel_metal_compute35_dispatch_type"
external compute35_execute_indirect : handle -> handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_execute_indirect"
external compute35_barrier_resources : handle -> handle array -> bool array -> (unit,string) result = "caml_prismel_metal_compute35_barrier_resources"
external compute35_barrier_scope : handle -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_barrier_scope"
external compute35_sample_counters : handle -> handle -> int64 -> bool -> (unit,string) result = "caml_prismel_metal_compute35_sample_counters"
external compute35_supports_stage_counters : handle -> (bool,string) result = "caml_prismel_metal_compute35_supports_stage_counters"
external compute35_bytes_plain : handle -> bytes -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_bytes_plain"
external compute35_imageblock : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_imageblock"
external compute35_stage_region : handle -> int64*int64*int64*int64*int64*int64 -> (unit,string) result = "caml_prismel_metal_compute35_stage_region"
external compute35_stage_indirect : handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_stage_indirect"
external compute35_threadgroup_memory : handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_threadgroup_memory"
external compute35_update_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_compute35_update_fence"
external compute35_wait_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_compute35_wait_fence"
external compute35_heaps : handle -> handle array -> (unit,string) result = "caml_prismel_metal_compute35_heaps"
external compute35_resources : handle -> handle array -> bool array -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_resources"

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


(** Resource100 generated raw integration. Internal handles only. *)
type resource_buffer_snapshot = handle * int64 * int * int * int
type resource_texture_snapshot =
  handle * int64 * int64 * int64 * int64 * int64 * int64 * int * int * int
  * int * int * int64
type resource_root_snapshot =
  | Resource_buffer_root of resource_buffer_snapshot
  | Resource_texture_root of resource_texture_snapshot
external resource_buffer_remote_view : handle -> handle -> (resource_buffer_snapshot option,string) result = "caml_prismel_metal_resource_buffer_remote_view"
external resource_buffer_remote_storage : handle -> (resource_buffer_snapshot option,string) result = "caml_prismel_metal_resource_buffer_remote_storage"
external resource_texture_remote_view : handle -> handle -> (resource_texture_snapshot option,string) result = "caml_prismel_metal_resource_texture_remote_view"
external resource_texture_view : handle -> int64 -> (resource_texture_snapshot option,string) result = "caml_prismel_metal_resource_texture_view"
external resource_texture_remote_storage : handle -> (resource_texture_snapshot option,string) result = "caml_prismel_metal_resource_texture_remote_storage"
external resource_texture_root : handle -> (resource_root_snapshot option,string) result = "caml_prismel_metal_resource_texture_root"
external resource_texture_buffer_graph : handle -> ((resource_buffer_snapshot * int64 * int64) option,string) result = "caml_prismel_metal_resource_texture_buffer_graph"
external resource_heap_device : handle -> (int64,string) result = "caml_prismel_metal_resource_heap_device"
external resource_resource_device : handle -> (int64,string) result = "caml_prismel_metal_resource_resource_device"
external resource_resource_heap : handle -> (handle option,string) result = "caml_prismel_metal_resource_resource_heap"
external resource_buffer_add_debug_marker : handle -> string -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_resource_buffer_add_debug_marker"
external resource_buffer_new_tensor : handle -> handle -> int64 -> (handle,string) result = "caml_prismel_metal_resource_buffer_new_tensor"
external resource_layout_array_get : handle -> int64 -> (handle option,string) result = "caml_prismel_metal_resource_layout_array_get"
external resource_layout_array_set : handle -> int64 -> handle option -> (unit,string) result = "caml_prismel_metal_resource_layout_array_set"
external resource_command_buffer_state_encoder : handle -> handle -> (handle,string) result = "caml_prismel_metal_resource_command_buffer_state_encoder"
external resource_device_new_view_pool : handle -> handle -> (handle,string) result = "caml_prismel_metal_resource_device_new_view_pool"
external resource_heap_acceleration_descriptor : handle -> handle -> (handle,string) result = "caml_prismel_metal_resource_heap_acceleration_descriptor"
external resource_heap_acceleration_descriptor_offset : handle -> handle -> int64 -> (handle,string) result = "caml_prismel_metal_resource_heap_acceleration_descriptor_offset"
external resource_heap_acceleration_size : handle -> int64 -> (handle,string) result = "caml_prismel_metal_resource_heap_acceleration_size"
external resource_heap_acceleration_size_offset : handle -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_resource_heap_acceleration_size_offset"
external resource_set_owner : handle -> bytes -> (unit,string) result = "caml_prismel_metal_resource_set_owner"
external resource_set_current_owner : handle -> (unit,string) result = "caml_prismel_metal_resource_set_current_owner"
external resource_encoder_move_texture : handle -> handle -> int64 -> int64 -> (int64 * int64 * int64) -> (int64 * int64 * int64) -> handle -> int64 -> int64 -> (int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal_resource_encoder_move_texture_bytecode" "caml_prismel_metal_resource_encoder_move_texture"
external resource_encoder_update_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_resource_encoder_update_fence"
external resource_encoder_indirect_mapping : handle -> handle -> int64 -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_encoder_indirect_mapping"
external resource_encoder_mappings : handle -> handle -> int64 -> (int64 * int64 * int64 * int64 * int64 * int64) array -> int64 array -> int64 array -> int64 -> (unit,string) result = "caml_prismel_metal_resource_encoder_mappings_bytecode" "caml_prismel_metal_resource_encoder_mappings"
external resource_encoder_wait_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_resource_encoder_wait_fence"
external resource_pass_sample_attachments : handle -> (handle option,string) result = "caml_prismel_metal_resource_pass_sample_attachments"
external resource_sample_attachment_buffer : handle -> (handle option,string) result = "caml_prismel_metal_resource_sample_attachment_buffer"
external resource_sample_attachment_set_buffer : handle -> handle option -> (unit,string) result = "caml_prismel_metal_resource_sample_attachment_set_buffer"
external resource_sample_array_get : handle -> int64 -> (handle option,string) result = "caml_prismel_metal_resource_sample_array_get"
external resource_sample_array_set : handle -> int64 -> handle option -> (unit,string) result = "caml_prismel_metal_resource_sample_array_set"
external resource_pool_base_id : handle -> (int64,string) result = "caml_prismel_metal_resource_pool_base_id"
external resource_pool_copy : handle -> handle -> int64 -> int64 -> int64 -> (int64,string) result = "caml_prismel_metal_resource_pool_copy"
external resource_pool_device : handle -> (handle option,string) result = "caml_prismel_metal_resource_pool_device"
external resource_pool_label : handle -> (string option,string) result = "caml_prismel_metal_resource_pool_label"
external resource_pool_count : handle -> (int64,string) result = "caml_prismel_metal_resource_pool_count"
external resource_texture_get_bytes : handle -> bytes -> int64 -> (int64 * int64 * int64 * int64 * int64 * int64) -> int64 -> (unit,string) result = "caml_prismel_metal_resource_texture_get_bytes"
external resource_texture_replace : handle -> (int64 * int64 * int64 * int64 * int64 * int64) -> int64 -> bytes -> int64 -> (unit,string) result = "caml_prismel_metal_resource_texture_replace"
external resource_texture_pool_set : handle -> handle -> int64 -> (int64,string) result = "caml_prismel_metal_resource_texture_pool_set"
external resource_texture_pool_set_descriptor : handle -> handle -> handle -> int64 -> (int64,string) result = "caml_prismel_metal_resource_texture_pool_set_descriptor"
external resource_texture_pool_set_buffer : handle -> handle -> handle -> int64 -> int64 -> int64 -> (int64,string) result = "caml_prismel_metal_resource_texture_pool_set_buffer_bytecode" "caml_prismel_metal_resource_texture_pool_set_buffer"
external resource_pass_create : unit -> (handle,string) result = "caml_prismel_metal_resource_pass_create"
external resource_texture_descriptor_2d : int64 -> int64 -> int64 -> bool -> (handle,string) result = "caml_prismel_metal_resource_texture_descriptor_2d"
external resource_texture_descriptor_buffer : int64 -> int64 -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_resource_texture_descriptor_buffer"
external resource_texture_descriptor_cube : int64 -> int64 -> bool -> (handle,string) result = "caml_prismel_metal_resource_texture_descriptor_cube"
external resource_buffer_remove_all_debug_markers : handle -> (unit,string) result = "caml_prismel_metal_generated_buffer_remove_all_debug_markers"
external resource_device_sparse_tile_size : handle -> int64 -> int64 -> int64 -> ((int64*int64*int64),string) result = "caml_prismel_metal_generated_device_sparse_tile_size"
external resource_heap_resource_options : handle -> (int64,string) result = "caml_prismel_metal_generated_heap_resource_options"
external resource_resource_allocated_size : handle -> (int64,string) result = "caml_prismel_metal_generated_resource_allocated_size"
external resource_resource_options : handle -> (int64,string) result = "caml_prismel_metal_generated_resource_options"
external resource_texture_framebuffer_only : handle -> (bool,string) result = "caml_prismel_metal_generated_texture_framebuffer_only"

external resource_buffer_layout_create : unit -> (handle,string) result = "caml_prismel_metal_resource_buffer_layout_create"
external resource_buffer_layout_stride : handle -> (int64,string) result = "caml_prismel_metal_resource_buffer_layout_stride"
external resource_buffer_layout_set_stride : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_buffer_layout_set_stride"
external resource_buffer_layout_step_rate : handle -> (int64,string) result = "caml_prismel_metal_resource_buffer_layout_step_rate"
external resource_buffer_layout_set_step_rate : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_buffer_layout_set_step_rate"
external resource_buffer_layout_step_function : handle -> (int64,string) result = "caml_prismel_metal_resource_buffer_layout_step_function"
external resource_buffer_layout_set_step_function : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_buffer_layout_set_step_function"
external resource_sample_attachment_create : unit -> (handle,string) result = "caml_prismel_metal_resource_sample_attachment_create"
external resource_sample_attachment_start : handle -> (int64,string) result = "caml_prismel_metal_resource_sample_attachment_start"
external resource_sample_attachment_set_start : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_sample_attachment_set_start"
external resource_sample_attachment_end : handle -> (int64,string) result = "caml_prismel_metal_resource_sample_attachment_end"
external resource_sample_attachment_set_end : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_sample_attachment_set_end"
external resource_view_pool_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_resource_view_pool_descriptor_create"
external resource_view_pool_descriptor_count : handle -> (int64,string) result = "caml_prismel_metal_resource_view_pool_descriptor_count"
external resource_view_pool_descriptor_set_count : handle -> int64 -> (unit,string) result = "caml_prismel_metal_resource_view_pool_descriptor_set_count"
external resource_view_pool_descriptor_label : handle -> (string option,string) result = "caml_prismel_metal_resource_view_pool_descriptor_label"
external resource_view_pool_descriptor_set_label : handle -> string option -> (unit,string) result = "caml_prismel_metal_resource_view_pool_descriptor_set_label"

(** Pipeline113 safe state-query subset. *)
external pipeline_compute_resource_id : handle -> (int64,string) result = "caml_prismel_metal_pipeline_compute_resource_id"
external pipeline_compute_required_threads : handle -> ((int64*int64*int64),string) result = "caml_prismel_metal_pipeline_compute_required_threads"
external pipeline_compute_shader_validation : handle -> (int64,string) result = "caml_prismel_metal_pipeline_compute_shader_validation"
external pipeline_compute_indirect : handle -> (bool,string) result = "caml_prismel_metal_pipeline_compute_indirect"
external pipeline_compute_imageblock_length : handle -> (int64*int64*int64) -> (int64,string) result = "caml_prismel_metal_pipeline_compute_imageblock_length"
external pipeline_render_resource_id : handle -> (int64,string) result = "caml_prismel_metal_pipeline_render_resource_id"
external pipeline_render_imageblock_sample_length : handle -> (int64,string) result = "caml_prismel_metal_pipeline_render_imageblock_sample_length"
external pipeline_render_mesh_threads : handle -> ((int64*int64*int64),string) result = "caml_prismel_metal_pipeline_render_mesh_threads"
external pipeline_render_object_threads : handle -> ((int64*int64*int64),string) result = "caml_prismel_metal_pipeline_render_object_threads"
external pipeline_render_tile_threads : handle -> ((int64*int64*int64),string) result = "caml_prismel_metal_pipeline_render_tile_threads"
external pipeline_render_shader_validation : handle -> (int64,string) result = "caml_prismel_metal_pipeline_render_shader_validation"
external pipeline_render_indirect : handle -> (bool,string) result = "caml_prismel_metal_pipeline_render_indirect"
external pipeline_render_imageblock_length : handle -> (int64*int64*int64) -> (int64,string) result = "caml_prismel_metal_pipeline_render_imageblock_length"

(** Mesh/tile105 owned descriptor inputs. Field order is the native positional
    ABI consumed by [prismel_mesh_tile_objects_from_value]. *)
type mesh_pipeline_descriptor_inputs =
  { object_function : handle option
  ; mesh_function : handle
  ; fragment_function : handle option
  ; binary_archives : handle array
  ; object_linked_functions : handle option
  ; mesh_linked_functions : handle option
  ; fragment_linked_functions : handle option
  }

type tile_pipeline_descriptor_inputs =
  { tile_function : handle
  ; binary_archives : handle array
  ; preloaded_libraries : handle array
  ; linked_functions : handle option
  }

external mesh_pipeline_descriptor_owned :
  mesh_pipeline_descriptor_inputs -> (handle,string) result =
  "caml_prismel_mesh_pipeline_descriptor"

external tile_pipeline_descriptor_owned :
  tile_pipeline_descriptor_inputs -> (handle,string) result =
  "caml_prismel_tile_pipeline_descriptor"

(** IO/counter111 callable ownership ABI. *)
external io_counter_descriptor_create :
  handle -> int -> string option -> (handle,string) result =
  "caml_prismel_counter_descriptor"
external io_load_buffer :
  handle -> handle -> int64 -> int64 -> handle -> int64 ->
  (unit,string) result =
  "caml_prismel_io_load_buffer_bytecode" "caml_prismel_io_load_buffer"
external io_queue_create :
  handle -> int -> int64 -> int64 -> string option ->
  ((handle * int64),string) result =
  "caml_prismel_metal_io_queue_create"
external io_file_create :
  handle -> string -> string option -> ((handle * int64),string) result =
  "caml_prismel_metal_io_file_create"
external io_command_create :
  handle -> string option -> (handle,string) result =
  "caml_prismel_metal_io_command_create"
external io_command_commit_wait : handle -> (int,string) result =
  "caml_prismel_metal_io_command_commit_wait"
external counter_sets : handle -> (((handle * string) array),string) result = "caml_prismel_metal_counter_sets"
external counter_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_counter_descriptor_create"
external counter_set_counters : handle -> (((handle * string) array),string) result = "caml_prismel_metal_counter_set_counters"
external counter_descriptor_snapshot : handle -> ((handle * string option * int64 * int64),string) result = "caml_prismel_metal_counter_descriptor_snapshot"
external counter_descriptor_set : handle -> handle -> string option -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_counter_descriptor_set"
external counter_sample_buffer_create : handle -> handle -> (handle,string) result = "caml_prismel_metal_counter_sample_buffer_create"
external counter_sample_snapshot : handle -> ((int64 * string option * int64),string) result = "caml_prismel_metal_counter_sample_snapshot"
external counter_sample_resolve : handle -> int64 -> int64 -> (bytes,string) result = "caml_prismel_metal_counter_sample_resolve"
external counter_supports_sampling : handle -> int -> (bool,string) result = "caml_prismel_metal_counter_supports_sampling"
external blit_pass_create : unit -> (handle,string) result = "caml_prismel_metal_blit_pass_create"
external blit_pass_attachments : handle -> (handle,string) result = "caml_prismel_metal_blit_pass_attachments"
external blit_attachment : handle -> int64 -> handle option -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_blit_attachment"
external io_queue_snapshot : handle -> (string option,string) result = "caml_prismel_metal_io_queue_snapshot"
external io_queue_set_label : handle -> string option -> (unit,string) result = "caml_prismel_metal_io_queue_set_label"
external io_queue_barrier : handle -> (unit,string) result = "caml_prismel_metal_io_queue_barrier"
external io_queue_unretained : handle -> (handle,string) result = "caml_prismel_metal_io_queue_unretained"
external io_command_snapshot : handle -> ((string option * string option * int),string) result = "caml_prismel_metal_io_command_snapshot"
external io_command_simple : handle -> int -> string option -> (unit,string) result = "caml_prismel_metal_io_command_simple"
external io_command_event : handle -> handle -> int64 -> bool -> (unit,string) result = "caml_prismel_metal_io_command_event"
external io_command_handler : handle -> (unit -> unit) -> (nativeint,string) result = "caml_prismel_metal_io_command_handler"
external io_file_snapshot : handle -> (string option,string) result = "caml_prismel_metal_io_file_snapshot"
external io_file_set_label : handle -> string option -> (unit,string) result = "caml_prismel_metal_io_file_set_label"
external io_command_copy_status : handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_io_command_copy_status"
external io_command_load_texture : handle -> handle -> (int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * handle * int64) -> (unit,string) result = "caml_prismel_metal_io_command_load_texture"
type io_compression_context
external io_compression_default_chunk : unit -> (int64,string) result = "caml_prismel_metal_io_compression_default_chunk"
external io_compression_create : string -> int -> int64 -> (io_compression_context,string) result = "caml_prismel_metal_io_compression_create"
external io_compression_append : io_compression_context -> bytes -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_io_compression_append"
external io_compression_finish : io_compression_context -> (int,string) result = "caml_prismel_metal_io_compression_finish"
external io_scratch_allocator_create : handle -> (handle,string) result = "caml_prismel_metal_io_scratch_allocator_create"
external io_scratch_allocate : handle -> int64 -> ((handle * handle),string) result = "caml_prismel_metal_io_scratch_allocate"
external io_queue_create_scratch : handle -> handle -> (handle,string) result = "caml_prismel_metal_io_queue_create_scratch"
external io_command_load_bytes : handle -> int64 -> handle -> int64 -> ((bytes,string) result -> unit) -> (nativeint,string) result = "caml_prismel_metal_io_command_load_bytes"
external io_load_bytes_cancel : nativeint -> unit = "caml_prismel_metal_io_load_bytes_cancel"

(** RasterizationRate55 exact descriptor graph ABI. *)
external raster_rate_layer_create : (int64 * int64 * int64) -> float array -> float array -> (handle,string) result = "caml_prismel_metal_rate_layer_create"
external raster_rate_layer_snapshot : handle -> (((int64 * int64 * int64) * (int64 * int64 * int64) * float array * float array),string) result = "caml_prismel_metal_rate_layer_snapshot"
external raster_rate_layer_set_count : handle -> (int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal_rate_layer_set_count"
external raster_rate_sample : handle -> bool -> int64 -> bool -> float -> (float,string) result = "caml_prismel_metal_rate_sample"
external raster_rate_descriptor_create : (int64 * int64 * int64) -> handle array -> string option -> (handle,string) result = "caml_prismel_metal_rate_descriptor_create"
external raster_rate_descriptor_snapshot : handle -> (((int64 * int64 * int64) * string option * handle array),string) result = "caml_prismel_metal_rate_descriptor_snapshot"
external raster_rate_descriptor_set : handle -> (int64 * int64 * int64) -> string option -> (unit,string) result = "caml_prismel_metal_rate_descriptor_set"
external raster_rate_descriptor_layer : handle -> int64 -> handle option -> (handle option,string) result = "caml_prismel_metal_rate_descriptor_layer"
external raster_rate_map_create : handle -> handle -> (handle,string) result = "caml_prismel_metal_rate_map_create"
external raster_rate_map_snapshot : handle -> (((int64 * int64 * int64) * (int64 * int64 * int64) * int64 * (int64 * int64) * string option * int64),string) result = "caml_prismel_metal_rate_map_snapshot"
external raster_rate_map_physical_size : handle -> int64 -> ((int64 * int64 * int64),string) result = "caml_prismel_metal_rate_map_physical_size"
external raster_rate_map_coordinate : handle -> int64 -> bool -> (float * float) -> ((float * float),string) result = "caml_prismel_metal_rate_map_coordinate"
external raster_rate_map_copy_parameters : handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_rate_map_copy_parameters"

(** FunctionStitching43 exact ownership graph ABI. *)
external stitch_function_create : string -> handle array -> handle array -> (handle,string) result = "caml_prismel_metal_stitch_function_create"
external stitch_function_snapshot : handle -> ((string * handle array * handle array),string) result = "caml_prismel_metal_stitch_function_snapshot"
external stitch_function_set : handle -> string -> handle array -> handle array -> (unit,string) result = "caml_prismel_metal_stitch_function_set"
external stitch_graph_create : string -> handle array -> handle option -> bool -> (handle,string) result = "caml_prismel_metal_stitch_graph_create"
external stitch_graph_snapshot : handle -> ((string * handle array * handle option * bool),string) result = "caml_prismel_metal_stitch_graph_snapshot"
external stitch_graph_set : handle -> string -> handle array -> handle option -> bool -> (unit,string) result = "caml_prismel_metal_stitch_graph_set"
external stitched_descriptor_create : handle array -> handle array -> handle array -> int64 -> (handle,string) result = "caml_prismel_metal_stitched_descriptor_create"
external stitched_descriptor_snapshot : handle -> ((handle array * handle array * handle array * int64),string) result = "caml_prismel_metal_stitched_descriptor_snapshot"

(** MTLLibrary42 remaining callable ABI. *)
external compile_options_create : (string * string) array -> (int64 * int64 * int64) -> (handle,string) result = "caml_prismel_metal_compile_options_create"
external compile_options_snapshot : handle -> (((string * string) array * (int64 * int64 * int64)),string) result = "caml_prismel_metal_compile_options_snapshot"
external compile_options_required_threads_available : unit -> bool = "caml_prismel_metal_compile_options_required_threads_available"
external function_argument_encoder_reflection : handle -> int64 -> ((handle * bool),string) result = "caml_prismel_metal_function_argument_encoder_reflection"
external library_function_reflection : handle -> string -> (((pipeline_binding_info array * string option) option),string) result = "caml_prismel_metal_library_function_reflection"
external library_function_async : handle -> string -> int -> ((handle,string) result -> unit) -> (nativeint,string) result = "caml_prismel_metal_library_function_async"
external library_callback_cancel : nativeint -> unit = "caml_prismel_metal_library_callback_cancel"
external library_intersection_function : handle -> string -> (handle,string) result = "caml_prismel_metal_library_intersection_function"
external device_default_library : handle -> (handle,string) result =
  "caml_prismel_metal_device_default_library"
external device_default_library_bundle : handle -> string -> (handle,string) result =
  "caml_prismel_metal_device_default_library_bundle"
external device_library_data : handle -> string -> (handle,string) result =
  "caml_prismel_metal_device_library_data"
external device_library_file : handle -> string -> (handle,string) result =
  "caml_prismel_metal_device_library_file"
external device_library_stitched : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_device_library_stitched"
external device_queue_descriptor : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_device_queue_descriptor"
external device_queue_maximum : handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_queue_maximum"
external device_queue4_default : handle -> (handle,string) result =
  "caml_prismel_metal_device_queue4_default"
external device_io_handle_legacy : handle -> string -> ((handle*int64),string) result =
  "caml_prismel_metal_device_io_handle_legacy"
external device_io_handle_compressed_legacy : handle -> string -> int -> ((handle*int64),string) result =
  "caml_prismel_metal_device_io_handle_compressed_legacy"
external device_function_handle : handle -> handle -> bool -> (handle option,string) result =
  "caml_prismel_metal_device_function_handle"
external device_argument_encoder :
  handle -> (int64 * int64 * int64 * int64 * int64 * int64) array ->
  ((handle * int64 * int64 * int64),string) result =
  "caml_prismel_metal_device_argument_encoder"
external device_render_pipeline_simple : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_device_render_pipeline_simple"
external device_async_compute_function : handle -> handle -> bool -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_async_compute_function"
external device_async_compute_descriptor : handle -> handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_async_compute_descriptor"
external device_async_library_source : handle -> string -> handle option -> (handle,string) result =
  "caml_prismel_metal_device_async_library_source"
external device_async_library_stitched : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_device_async_library_stitched"
external device_async_render_descriptor : handle -> handle -> bool -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_async_render_descriptor"
external device_async_mesh_pipeline : handle -> handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_async_mesh_pipeline"
external device_async_tile_pipeline : handle -> handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_device_async_tile_pipeline"
external device_compute_reflection_pipeline : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_device_compute_reflection_pipeline"
external device_argument_encoder_binding : handle -> handle -> int64 -> ((handle*int64*int64*int64),string) result =
  "caml_prismel_metal_device_argument_encoder_binding"
external device_shared_event_handle : handle -> handle -> ((handle*int64),string) result =
  "caml_prismel_metal_device_shared_event_handle"

(** Authoritative Metal4 lifecycle190 prepared CAML subset. The resource and
    compute-owner shards currently contain typed native helpers only, not OCaml
    primitives, so they are intentionally absent here. *)
external metal4_command_buffer_begin :
  handle -> handle -> string option -> (unit,string) result =
  "caml_prismel_metal4_begin"

external metal4_queue_wait_event :
  handle -> handle -> int64 -> (unit,string) result =
  "caml_prismel_metal4_wait_event"

external metal4_encoder_debug : handle -> handle -> string -> int -> (unit,string) result =
  "caml_prismel_metal4_encoder_debug"
external metal4_encoder_pop_debug : handle -> handle -> (unit,string) result =
  "caml_prismel_metal4_encoder_pop_debug"
external metal4_encoder_barrier :
  handle -> handle -> int64 -> int64 -> int64 -> int -> (unit,string) result =
  "caml_prismel_metal4_encoder_barrier_bytecode" "caml_prismel_metal4_encoder_barrier"
external metal4_encoder_update_fence : handle -> handle -> handle -> int64 -> (unit,string) result =
  "caml_prismel_metal4_encoder_update_fence"
external metal4_encoder_wait_fence : handle -> handle -> handle -> int64 -> (unit,string) result =
  "caml_prismel_metal4_encoder_wait_fence"
external metal4_queue_add_residencies : handle -> handle array -> (unit,string) result =
  "caml_prismel_metal4_queue_add_residencies"
external metal4_queue_remove_residency : handle -> handle -> (unit,string) result =
  "caml_prismel_metal4_queue_remove_residency"
external metal4_queue_remove_residencies : handle -> handle array -> (unit,string) result =
  "caml_prismel_metal4_queue_remove_residencies"
external metal4_counter_create : handle -> int -> int64 -> string option -> (handle,string) result =
  "caml_prismel_metal4_counter_create"
external metal4_counter_info : handle -> ((int64 * int * string option),string) result =
  "caml_prismel_metal4_counter_info"
external metal4_counter_set_label : handle -> string option -> (unit,string) result =
  "caml_prismel_metal4_counter_set_label"
external metal4_counter_invalidate : handle -> (int64 * int64) -> (unit,string) result =
  "caml_prismel_metal4_counter_invalidate"
external metal4_counter_resolve : handle -> (int64 * int64) -> (bytes,string) result =
  "caml_prismel_metal4_counter_resolve"
external metal4_counter_descriptor_roundtrip : int -> int64 -> ((int * int64),string) result =
  "caml_prismel_metal4_counter_descriptor_roundtrip"

type metal4_size = int64 * int64 * int64
type metal4_origin = int64 * int64 * int64
type metal4_range = int64 * int64
external metal4_compute_dispatch_groups : handle -> handle -> (metal4_size * metal4_size) -> (unit,string) result = "caml_prismel_metal4_compute_dispatch_groups"
external metal4_compute_dispatch_indirect_groups : handle -> handle -> ((handle * int64 * int64) * metal4_size) -> (unit,string) result = "caml_prismel_metal4_compute_dispatch_indirect_groups"
external metal4_compute_dispatch_indirect_threads : handle -> handle -> (handle * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_dispatch_indirect_threads"
external metal4_compute_set_imageblock : handle -> handle -> (int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_set_imageblock"
external metal4_compute_stages : handle -> handle -> (int64,string) result = "caml_prismel_metal4_compute_stages"
external metal4_compute_fill_buffer : handle -> handle -> (handle * metal4_range * int) -> (unit,string) result = "caml_prismel_metal4_compute_fill_buffer"
external metal4_compute_generate_mipmaps : handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal4_compute_generate_mipmaps"
external metal4_compute_optimize_cpu : handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal4_compute_optimize_cpu"
external metal4_compute_optimize_gpu : handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal4_compute_optimize_gpu"
external metal4_compute_optimize_cpu_level : handle -> handle -> (handle * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_optimize_cpu_level"
external metal4_compute_optimize_gpu_level : handle -> handle -> (handle * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_optimize_gpu_level"
external metal4_compute_copy_buffer : handle -> handle -> (handle * int64 * handle * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_copy_buffer"
external metal4_compute_copy_texture : handle -> handle -> (handle * handle) -> (unit,string) result = "caml_prismel_metal4_compute_copy_texture"
external metal4_compute_copy_texture_slices : handle -> handle -> (handle * int64 * int64 * handle * int64 * int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_copy_texture_slices"
external metal4_compute_copy_texture_region : handle -> handle -> (handle * int64 * int64 * metal4_origin * metal4_size * handle * int64 * int64 * metal4_origin) -> (unit,string) result = "caml_prismel_metal4_compute_copy_texture_region"
type metal4_buffer_texture_copy = handle * int64 * int64 * int64 * metal4_size * handle * int64 * int64 * metal4_origin
external metal4_compute_buffer_to_texture : handle -> handle -> metal4_buffer_texture_copy -> (unit,string) result = "caml_prismel_metal4_compute_buffer_to_texture"
external metal4_compute_buffer_to_texture_options : handle -> handle -> (handle * int64 * int64 * int64 * metal4_size * handle * int64 * int64 * metal4_origin * int64) -> (unit,string) result = "caml_prismel_metal4_compute_buffer_to_texture_options"
type metal4_texture_buffer_copy = handle * int64 * int64 * metal4_origin * metal4_size * handle * int64 * int64 * int64
external metal4_compute_texture_to_buffer : handle -> handle -> metal4_texture_buffer_copy -> (unit,string) result = "caml_prismel_metal4_compute_texture_to_buffer"
external metal4_compute_texture_to_buffer_options : handle -> handle -> (handle * int64 * int64 * metal4_origin * metal4_size * handle * int64 * int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_compute_texture_to_buffer_options"
external metal4_compute_execute_icb_range : handle -> handle -> (handle * metal4_range) -> (unit,string) result = "caml_prismel_metal4_compute_execute_icb_range"
external metal4_compute_execute_icb_indirect : handle -> handle -> (handle * (handle * int64 * int64)) -> (unit,string) result = "caml_prismel_metal4_compute_execute_icb_indirect"
external metal4_compute_optimize_icb : handle -> handle -> (handle * metal4_range) -> (unit,string) result = "caml_prismel_metal4_compute_optimize_icb"
external metal4_compute_reset_icb : handle -> handle -> (handle * metal4_range) -> (unit,string) result = "caml_prismel_metal4_compute_reset_icb"
external metal4_compute_copy_icb : handle -> handle -> (handle * metal4_range * handle * int64) -> (unit,string) result = "caml_prismel_metal4_compute_copy_icb"
external metal4_compute_copy_acceleration : handle -> handle -> (handle * handle * bool) -> (unit,string) result = "caml_prismel_metal4_compute_copy_acceleration"
external metal4_compute_timestamp : handle -> handle -> (int * handle * int64) -> (unit,string) result = "caml_prismel_metal4_compute_timestamp"
external metal4_compute_copy_tensor : handle -> handle -> (handle * int64 array * int64 array * handle * int64 array * int64 array) -> (unit,string) result = "caml_prismel_metal4_compute_copy_tensor"
external metal4_acceleration_descriptor_triangles : handle -> int64 -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal4_acceleration_descriptor_triangles"
external metal4_acceleration_structure11_create : int -> (handle,string) result =
  "caml_prismel_metal4_acceleration_structure11_create"
type metal4_owned_buffer_range = handle * int64 * int64
external metal4_compute_acceleration : handle -> handle -> (handle * handle * int * metal4_owned_buffer_range * handle option * int64) -> (unit,string) result = "caml_prismel_metal4_compute_acceleration"
external metal4_compute_write_compacted : handle -> handle -> (handle * metal4_owned_buffer_range) -> (unit,string) result = "caml_prismel_metal4_compute_write_compacted"
external metal4_binary_functions_create : unit -> (handle,string) result = "caml_prismel_metal4_binary_functions_create"
external metal4_binary_functions_get : handle -> int -> (handle array,string) result = "caml_prismel_metal4_binary_functions_get"
external metal4_binary_functions_set : handle -> int -> handle array -> (unit,string) result = "caml_prismel_metal4_binary_functions_set"
external metal4_binary_functions_reset : handle -> (unit,string) result = "caml_prismel_metal4_binary_functions_reset"
external metal4_binary_function_info : handle -> ((string option * int),string) result = "caml_prismel_metal4_binary_function_info"
external metal4_buffer_debug : handle -> string -> bool -> (unit,string) result = "caml_prismel_metal4_buffer_debug"
external metal4_buffer_use_residencies : handle -> handle array -> (unit,string) result = "caml_prismel_metal4_buffer_use_residencies"
external metal4_buffer_timestamp : handle -> handle -> int64 -> (unit,string) result = "caml_prismel_metal4_buffer_timestamp"
external metal4_buffer_resolve_counter : handle -> (handle * metal4_range * metal4_owned_buffer_range * handle option * handle option) -> (unit,string) result = "caml_prismel_metal4_buffer_resolve_counter"
external metal4_render_draw : handle -> handle -> (int * int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_render_draw"
external metal4_render_draw_indexed : handle -> handle -> (int * int64 * int * handle * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_render_draw_indexed"
external metal4_render_mesh_threads : handle -> handle -> (metal4_size * metal4_size * metal4_size) -> (unit,string) result = "caml_prismel_metal4_render_mesh_threads"
external metal4_render_mesh_indirect : handle -> handle -> (metal4_owned_buffer_range * metal4_size * metal4_size) -> (unit,string) result = "caml_prismel_metal4_render_mesh_indirect"
external metal4_render_execute_icb_range : handle -> handle -> (handle * metal4_range) -> (unit,string) result = "caml_prismel_metal4_render_execute_icb_range"
external metal4_render_execute_icb_indirect : handle -> handle -> (handle * metal4_owned_buffer_range) -> (unit,string) result = "caml_prismel_metal4_render_execute_icb_indirect"
external metal4_render_memory : handle -> handle -> (bool * int64 * int64 * int64) -> (unit,string) result = "caml_prismel_metal4_render_memory"
external metal4_render_timestamp : handle -> handle -> (int * int64 * handle * int64) -> (unit,string) result = "caml_prismel_metal4_render_timestamp"
external metal4_ml_descriptor_create : handle -> string -> string option -> (handle,string) result = "caml_prismel_metal4_ml_descriptor_create"
external metal4_ml_descriptor_label : handle -> string option -> (string option,string) result = "caml_prismel_metal4_ml_descriptor_label"
external metal4_ml_descriptor_function : handle -> ((handle * string),string) result = "caml_prismel_metal4_ml_descriptor_function"
external metal4_ml_descriptor_input : handle -> int64 -> int64 array option -> (int64 array option,string) result = "caml_prismel_metal4_ml_descriptor_input"
external metal4_ml_descriptor_inputs : handle -> int64 -> int64 array option array -> (unit,string) result = "caml_prismel_metal4_ml_descriptor_inputs"
external metal4_ml_descriptor_reset : handle -> (unit,string) result = "caml_prismel_metal4_ml_descriptor_reset"
external metal4_ml_compile : handle -> handle -> ((handle * (string option * int64 * int64 * pipeline_binding_info array)),string) result = "caml_prismel_metal4_ml_compile"
external metal4_ml_compile_async : handle -> handle -> (handle,string) result = "caml_prismel_metal4_ml_compile_async"
external metal4_ml_task_take : handle -> ((((handle * (string option * int64 * int64 * pipeline_binding_info array)),string) result option,string) result) = "caml_prismel_metal4_ml_task_take"
external metal4_ml_encoder_create : handle -> (handle,string) result = "caml_prismel_metal4_ml_encoder_create"
external metal4_ml_encoder_pipeline : handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal4_ml_encoder_pipeline"
external metal4_ml_encoder_table : handle -> handle -> handle option -> (unit,string) result = "caml_prismel_metal4_ml_encoder_table"
external metal4_ml_encoder_dispatch : handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal4_ml_encoder_dispatch"
external metal4_function_descriptor : handle -> string -> (handle,string) result = "caml_prismel_metal4_function_descriptor"
external metal4_function_constants : unit -> (handle,string) result = "caml_prismel_metal4_function_constants"
external metal4_specialized_create : handle option -> string option -> handle option -> (handle,string) result = "caml_prismel_metal4_specialized_create"
external metal4_specialized_get : handle -> ((handle option * string option * handle option),string) result = "caml_prismel_metal4_specialized_get"
external metal4_specialized_set : handle -> handle option -> string option -> handle option -> (unit,string) result = "caml_prismel_metal4_specialized_set"

(** Shader157 exact callable raw subset. Descriptor graphs, reflection,
    preprocessor dictionaries and callback compilation remain blocked. *)
external shader_function_options :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_function_options"
external shader_function_patch_control_point_count :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_function_patch_control_point_count"
external shader_function_patch_type :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_function_patch_type"
external shader_function_attributes :
  handle -> bool -> (handle array,string) result =
  "caml_prismel_metal_shader_function_attributes"
external shader_function_argument_encoder :
  handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_shader_function_argument_encoder"

external shader_attribute_name :
  handle -> bool -> (string option,string) result =
  "caml_prismel_metal_shader_attribute_name"
external shader_attribute_index :
  handle -> bool -> (int64,string) result =
  "caml_prismel_metal_shader_attribute_index"
external shader_attribute_type :
  handle -> bool -> (int64,string) result =
  "caml_prismel_metal_shader_attribute_type"
external shader_attribute_active :
  handle -> bool -> (bool,string) result =
  "caml_prismel_metal_shader_attribute_active"
external shader_attribute_patch_control_point :
  handle -> bool -> (bool,string) result =
  "caml_prismel_metal_shader_attribute_patch_control_point"
external shader_attribute_patch_data :
  handle -> bool -> (bool,string) result =
  "caml_prismel_metal_shader_attribute_patch_data"

external shader_attribute_descriptor_buffer_index :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_buffer_index"
external shader_attribute_descriptor_offset :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_offset"
external shader_attribute_descriptor_format :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_format"
external shader_attribute_descriptor_set_buffer_index :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_set_buffer_index"
external shader_attribute_descriptor_set_offset :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_set_offset"
external shader_attribute_descriptor_set_format :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_set_format"
external shader_attribute_descriptor_at :
  handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_at"
external shader_attribute_descriptor_set_at :
  handle -> int64 -> handle -> (unit,string) result =
  "caml_prismel_metal_shader_attribute_descriptor_set_at"

external shader_stage_descriptor_create :
  unit -> (handle,string) result =
  "caml_prismel_metal_shader_stage_descriptor_create"
external shader_stage_descriptor_index_buffer_index :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_stage_descriptor_index_buffer_index"
external shader_stage_descriptor_index_type :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_stage_descriptor_index_type"
external shader_stage_descriptor_set_index_buffer_index :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_stage_descriptor_set_index_buffer_index"
external shader_stage_descriptor_set_index_type :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_stage_descriptor_set_index_type"
external shader_stage_descriptor_reset :
  handle -> (unit,string) result =
  "caml_prismel_metal_shader_stage_descriptor_reset"
external shader_stage_descriptor_child :
  handle -> bool -> (handle,string) result =
  "caml_prismel_metal_shader_stage_descriptor_child"

external shader_stitching_input_create :
  int64 -> (handle,string) result =
  "caml_prismel_metal_shader_stitching_input_create"
external shader_stitching_input_index :
  handle -> (int64,string) result =
  "caml_prismel_metal_shader_stitching_input_index"
external shader_stitching_input_set_index :
  handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shader_stitching_input_set_index"
(* Corrected Command-support121 exact native subset (18 mechanical / 103
   handwritten partition). Callback and complex-copy families remain absent. *)
external command_capture_set_destination : handle -> int -> (unit,string) result =
  "caml_prismel_metal_capture_set_destination"
external command_capture_is_capturing : handle -> (bool,string) result =
  "caml_prismel_metal_capture_is_capturing"
external command_function_log_type : handle -> (int64,string) result =
  "caml_prismel_metal_function_log_type"
external command_function_log_column : handle -> (int64,string) result =
  "caml_prismel_metal_function_log_column"
external command_function_log_line : handle -> (int64,string) result =
  "caml_prismel_metal_function_log_line"
external command_shared_event_value : handle -> (int64,string) result =
  "caml_prismel_metal_shared_event_value"
external command_shared_event_set_value : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shared_event_set_value"

external command_capture_manager_shared : unit -> (handle,string) result =
  "caml_prismel_metal_capture_manager_shared"
external command_capture_descriptor_create : unit -> (handle,string) result =
  "caml_prismel_metal_capture_descriptor_create"
external command_capture_supports_destination : handle -> int -> (bool,string) result =
  "caml_prismel_metal_capture_supports_destination"
external command_capture_start : handle -> handle -> (unit,string) result =
  "caml_prismel_metal_capture_start"
external command_capture_stop : handle -> (unit,string) result =
  "caml_prismel_metal_capture_stop"
external command_event_label : handle -> (string option,string) result =
  "caml_prismel_metal_event_label"
external command_event_set_label : handle -> string option -> (unit,string) result =
  "caml_prismel_metal_event_set_label"
external command_event_device_id : handle -> (int64,string) result =
  "caml_prismel_metal_event_device_id"

external command_indirect_compute_clear_barrier : handle -> (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_clear_barrier"
external command_indirect_compute_set_barrier : handle -> (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_set_barrier"
external command_indirect_compute_imageblock :
  handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_imageblock"
external command_indirect_compute_stage_region :
  handle -> (int64 * int64 * int64 * int64 * int64 * int64) ->
  (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_stage_region"
external command_indirect_compute_memory :
  handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_memory"
external command_indirect_compute_dispatch_groups :
  handle -> (int64 * int64 * int64) -> (int64 * int64 * int64) ->
  (unit,string) result =
  "caml_prismel_metal_support_indirect_compute_dispatch_groups"

external command_indirect_render_clear_barrier : handle -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_clear_barrier"
external command_indirect_render_set_barrier : handle -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_set_barrier"
external command_indirect_render_set_cull : handle -> int -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_set_cull"
external command_indirect_render_set_depth_clip : handle -> int -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_set_depth_clip"
external command_indirect_render_set_front_winding : handle -> int -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_set_front_winding"
external command_indirect_render_set_fill : handle -> int -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_set_fill"
external command_indirect_render_depth_bias :
  handle -> float -> float -> float -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_depth_bias"
external command_indirect_render_depth_stencil :
  handle -> handle -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_depth_stencil"
external command_indirect_render_object_memory :
  handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_object_memory"
external command_indirect_render_mesh_groups :
  handle -> (int64 * int64 * int64) -> (int64 * int64 * int64) ->
  (int64 * int64 * int64) -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_mesh_groups"
external command_indirect_render_mesh_threads :
  handle -> (int64 * int64 * int64) -> (int64 * int64 * int64) ->
  (int64 * int64 * int64) -> (unit,string) result =
  "caml_prismel_metal_support_indirect_render_mesh_threads"
(* Mesh/tile105 exact mechanical ABI: 16 properties and 32 companions. *)
type mesh_tile_threadgroup_size = int64 * int64 * int64

type mesh_color_attachment_mechanical =
  { pixel_format : int64
  ; source_rgb_blend_factor : int
  ; destination_rgb_blend_factor : int
  ; rgb_blend_operation : int
  ; source_alpha_blend_factor : int
  ; destination_alpha_blend_factor : int
  ; alpha_blend_operation : int
  ; write_mask : int64
  }

type mesh_descriptor_mechanical =
  { label : string option
  ; depth_attachment_pixel_format : int64
  ; stencil_attachment_pixel_format : int64
  ; required_threads_per_mesh_threadgroup : mesh_tile_threadgroup_size
  ; required_threads_per_object_threadgroup : mesh_tile_threadgroup_size
  }

type tile_descriptor_mechanical =
  { label : string option
  ; required_threads_per_threadgroup : mesh_tile_threadgroup_size
  }

external mesh_buffer_descriptor_create : unit -> (handle,string) result =
  "caml_prismel_metal_mesh_buffer_descriptor_create"
external mesh_buffer_set_mutability : handle -> int -> (unit,string) result =
  "caml_prismel_metal_mesh_buffer_set_mutability"
external mesh_color_attachment_create : unit -> (handle,string) result =
  "caml_prismel_metal_mesh_color_attachment_create"
external mesh_color_attachment_set :
  handle -> int64 -> int -> int -> int -> int -> int -> int -> int64 ->
  (unit,string) result =
  "caml_prismel_metal_mesh_color_attachment_set_bytecode"
  "caml_prismel_metal_mesh_color_attachment_set"
external mesh_descriptor_set_mechanical :
  handle -> string option -> int64 -> int64 -> mesh_tile_threadgroup_size ->
  mesh_tile_threadgroup_size -> (unit,string) result =
  "caml_prismel_metal_mesh_descriptor_set_mechanical_bytecode"
  "caml_prismel_metal_mesh_descriptor_set_mechanical"
external tile_descriptor_set_mechanical :
  handle -> string option -> mesh_tile_threadgroup_size -> (unit,string) result =
  "caml_prismel_metal_tile_descriptor_set_mechanical"

(* Constructible Command-support event handles carry authoritative source
   device identity because a shared event may expose a nil native device. *)
external command_event_create :
  handle -> ((handle * int64),string) result =
  "caml_prismel_metal_command_event_create"
external command_shared_event_create :
  handle -> ((handle * int64),string) result =
  "caml_prismel_metal_command_shared_event_create"

(* Exact synchronous Mesh/tile105 descriptor compilation selectors. *)
external mesh_pipeline_compile :
  handle -> handle -> int64 ->
  ((handle * render_pipeline_reflection),string) result =
  "caml_prismel_metal_mesh_pipeline_compile"
external tile_pipeline_compile :
  handle -> handle -> int64 ->
  ((handle * render_pipeline_reflection),string) result =
  "caml_prismel_metal_tile_pipeline_compile"

type pipeline_render_ownership =
  { vertex_function : handle
  ; fragment_function : handle option
  ; binary_archives : handle array
  ; vertex_preloaded_libraries : handle array
  ; fragment_preloaded_libraries : handle array
  ; vertex_linked_functions : handle option
  ; fragment_linked_functions : handle option
  }

type pipeline_compute_ownership =
  { compute_function : handle
  ; preloaded_libraries : handle array
  ; stage_input_descriptor : handle option
  }

external pipeline_render_descriptor :
  handle -> pipeline_render_ownership -> (handle,string) result =
  "caml_prismel_metal_pipeline_render_descriptor"
external pipeline_compute_descriptor :
  handle -> pipeline_compute_ownership -> (handle,string) result =
  "caml_prismel_metal_pipeline_compute_descriptor"
external pipeline_compute_descriptor_required_threads :
  handle -> (mesh_tile_threadgroup_size,string) result =
  "caml_prismel_metal_pipeline_compute_descriptor_required_threads"
external pipeline_compute_descriptor_set_required_threads :
  handle -> mesh_tile_threadgroup_size -> (unit,string) result =
  "caml_prismel_metal_pipeline_compute_descriptor_set_required_threads"
external pipeline_compute_descriptor_reset : handle -> (unit,string) result =
  "caml_prismel_metal_pipeline_compute_descriptor_reset"
external pipeline_render_descriptor_depth_format : handle -> (int64,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_depth_format"
external pipeline_render_descriptor_set_depth_format : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_set_depth_format"
external pipeline_render_descriptor_input_topology : handle -> (int64,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_input_topology"
external pipeline_render_descriptor_set_input_topology : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_set_input_topology"
external pipeline_render_descriptor_sample_count : handle -> (int64,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_sample_count"
external pipeline_render_descriptor_set_sample_count : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_set_sample_count"
external pipeline_render_descriptor_stencil_format : handle -> (int64,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_stencil_format"
external pipeline_render_descriptor_set_stencil_format : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_set_stencil_format"
external pipeline_render_descriptor_tessellation_winding : handle -> (int64,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_tessellation_winding"
external pipeline_render_descriptor_set_tessellation_winding : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_set_tessellation_winding"
external pipeline_render_descriptor_reset : handle -> (unit,string) result =
  "caml_prismel_metal_pipeline_render_descriptor_reset"
external pipeline_render_compile :
  handle -> handle -> int64 ->
  ((handle * render_pipeline_reflection),string) result =
  "caml_prismel_metal_pipeline_render_compile"
external pipeline_compute_compile :
  handle -> handle -> int64 ->
  ((handle * pipeline_binding_info array),string) result =
  "caml_prismel_metal_pipeline_compute_compile"

(* Metal4 render-pass owned descriptor graph. *)
external metal4_render_pass_descriptor : unit -> (handle,string) result =
  "caml_prismel_metal4_render_pass_descriptor"
external metal4_render_pass_sample_positions :
  handle -> (float * float) array -> ((float * float) array,string) result =
  "caml_prismel_metal4_render_pass_sample_positions"
external metal4_render_pass_rate_map : handle -> handle option -> (unit,string) result =
  "caml_prismel_metal4_render_pass_rate_map"
external metal4_render_pass_depth_attachment :
  handle -> handle option -> (int * int * float) -> (unit,string) result =
  "caml_prismel_metal4_render_pass_depth_attachment"
external metal4_render_pass_stencil_attachment :
  handle -> handle option -> (int * int * int32) -> (unit,string) result =
  "caml_prismel_metal4_render_pass_stencil_attachment"

external metal4_stitched_descriptor : handle array -> (handle,string) result =
  "caml_prismel_metal4_stitched_descriptor"
external metal4_stitched_get : handle -> (handle array,string) result =
  "caml_prismel_metal4_stitched_get"
external metal4_stitched_set : handle -> handle array -> (unit,string) result =
  "caml_prismel_metal4_stitched_set"
(* Exact MTLTensor.h mechanical18 raw closure. *)
external tensor_buffer_offset : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_buffer_offset"
external tensor_data_type : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_data_type"
external tensor_gpu_resource_id : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_gpu_resource_id"
external tensor_usage : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_usage"
external tensor_descriptor_cpu_cache_mode : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_cpu_cache_mode"
external tensor_descriptor_data_type : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_data_type"
external tensor_descriptor_hazard_tracking_mode : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_hazard_tracking_mode"
external tensor_descriptor_resource_options : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_resource_options"
external tensor_descriptor_storage_mode : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_storage_mode"
external tensor_descriptor_usage : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_descriptor_usage"
external tensor_descriptor_set_cpu_cache_mode : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_cpu_cache_mode"
external tensor_descriptor_set_data_type : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_data_type"
external tensor_descriptor_set_hazard_tracking_mode : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_hazard_tracking_mode"
external tensor_descriptor_set_resource_options : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_resource_options"
external tensor_descriptor_set_storage_mode : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_storage_mode"
external tensor_descriptor_set_usage : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_usage"
external tensor_extents_extent : handle -> int64 -> (int64,string) result =
  "caml_prismel_metal_tensor_extents_extent"
external tensor_extents_rank : handle -> (int64,string) result =
  "caml_prismel_metal_tensor_extents_rank"
external tensor_extents_create : int64 array -> (handle,string) result =
  "caml_prismel_metal_tensor_extents_create"
external tensor_descriptor_create : unit -> (handle,string) result =
  "caml_prismel_metal_tensor_descriptor_create"
external tensor_buffer : handle -> (handle option,string) result =
  "caml_prismel_metal_tensor_buffer"
external tensor_dimensions : handle -> (handle option,string) result =
  "caml_prismel_metal_tensor_dimensions"
external tensor_strides : handle -> (handle option,string) result =
  "caml_prismel_metal_tensor_strides"
external tensor_descriptor_dimensions : handle -> (handle option,string) result =
  "caml_prismel_metal_tensor_descriptor_dimensions"
external tensor_descriptor_strides : handle -> (handle option,string) result =
  "caml_prismel_metal_tensor_descriptor_strides"
external tensor_descriptor_set_dimensions : handle -> handle -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_dimensions"
external tensor_descriptor_set_strides : handle -> handle -> (unit,string) result =
  "caml_prismel_metal_tensor_descriptor_set_strides"
external tensor_get_bytes : handle -> bytes -> handle -> handle -> handle -> (unit,string) result =
  "caml_prismel_metal_tensor_get_bytes_bytecode" "caml_prismel_metal_tensor_get_bytes"
external tensor_replace_bytes : handle -> bytes -> handle -> handle -> handle -> (unit,string) result =
  "caml_prismel_metal_tensor_replace_bytes_bytecode" "caml_prismel_metal_tensor_replace_bytes"
external tensor_device_create : handle -> handle -> (handle,string) result =
  "caml_prismel_metal_tensor_device_create"
external tensor_device_size_align : handle -> handle -> ((int64*int64),string) result =
  "caml_prismel_metal_tensor_device_size_align"
external resource_layout_array_create : unit -> (handle,string) result =
  "caml_prismel_metal_resource_layout_array_create"
external resource_texture_view_descriptor_create :
  int64 -> int64 -> int64 -> int64 -> int64 -> int64 -> (handle,string) result =
  "caml_prismel_metal_resource_texture_view_descriptor_create_bytecode"
  "caml_prismel_metal_resource_texture_view_descriptor_create"
external resource_heap_acceleration_triangle :
  handle -> acceleration_triangle_descriptor -> int64 option -> (handle,string) result =
  "caml_prismel_metal_resource_heap_acceleration_triangle"
external resource_heap_acceleration_size_align :
  handle -> int64 -> ((int64*int64),string) result =
  "caml_prismel_metal_resource_heap_acceleration_size_align"
external resource_heap_acceleration_triangle_size_align :
  handle -> acceleration_triangle_descriptor -> ((int64*int64),string) result =
  "caml_prismel_metal_resource_heap_acceleration_triangle_size_align"

(* Exact callable ABI for ArgumentEncoder34. *)
external argument_encoder_snapshot :
  handle -> ((string option * int64 * int64 * int64),string) result =
  "caml_prismel_metal_argument_encoder_snapshot"
external argument_encoder_set_label :
  handle -> string option -> (unit,string) result =
  "caml_prismel_metal_argument_encoder_set_label"
external argument_encoder_set_buffer :
  handle -> handle -> int64 -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_argument_encoder_set_buffer"
external argument_encoder_nested : handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_argument_encoder_nested"
external argument_encoder_constant_available :
  handle -> int64 -> (bool,string) result =
  "caml_prismel_metal_argument_encoder_constant_available"
external argument_encoder_single :
  handle -> int -> handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_argument_encoder_single"
external argument_encoder_array :
  handle -> int -> handle array -> int64 array -> (int64 * int64) ->
  (unit,string) result =
  "caml_prismel_metal_argument_encoder_array"

(* Exact callable tail for AccelerationCommand32. *)
external acceleration_pass_create : unit -> (handle,string) result =
  "caml_prismel_metal_acceleration_pass_create"
external acceleration_pass_attachments : handle -> (handle,string) result =
  "caml_prismel_metal_acceleration_pass_attachments"
external acceleration_pass_attachment :
  handle -> int64 -> handle option -> int64 -> int64 -> (handle,string) result =
  "caml_prismel_metal_acceleration_pass_attachment"
external acceleration_pass_attachment_snapshot :
  handle -> ((handle option * int64 * int64),string) result =
  "caml_prismel_metal_acceleration_pass_attachment_snapshot"
external acceleration_pass_attachment_set :
  handle -> int64 -> handle option -> (unit,string) result =
  "caml_prismel_metal_acceleration_pass_attachment_set"
external acceleration_encoder_fence :
  handle -> handle -> bool -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_fence"
external acceleration_encoder_sample :
  handle -> handle -> int64 -> bool -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_sample"
external acceleration_encoder_use :
  handle -> handle array -> (int * handle) array -> int64 -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_use"
external acceleration_encoder_refit_options :
  handle -> handle -> handle -> acceleration_triangle_descriptor -> handle ->
  int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_refit_options_bytecode"
  "caml_prismel_metal_acceleration_encoder_refit_options"
external acceleration_encoder_write_type :
  handle -> handle -> handle -> int64 -> int -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_write_type"
external acceleration_encoder_with_pass :
  handle -> handle -> (handle,string) result =
  "caml_prismel_metal_acceleration_encoder_with_pass"
external acceleration_supports_counters : handle -> (bool,string) result =
  "caml_prismel_metal_acceleration_supports_counters"

type blit_copy_spec =
  | Blit_buffer_to_texture of int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64
  | Blit_buffer_to_buffer of int64 * int64 * int64
  | Blit_tensor_to_tensor of handle * handle * handle * handle
  | Blit_texture_to_buffer of int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64
  | Blit_texture_region of int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64
  | Blit_texture_levels of int64 * int64 * int64 * int64 * int64 * int64
  | Blit_texture_whole
  | Blit_indirect_commands of int64 * int64 * int64

external blit_copy :
  handle -> int -> handle -> handle -> blit_copy_spec -> (unit,string) result =
  "caml_prismel_metal_blit_copy"
external blit_fill_mipmap :
  handle -> handle -> bool -> (int64 * int64 * int64) -> (unit,string) result =
  "caml_prismel_metal_blit_fill_mipmap"
external blit_fence : handle -> handle -> bool -> (unit,string) result =
  "caml_prismel_metal_blit_fence"
external blit_counter :
  handle -> handle -> int64 -> int64 -> handle -> int64 -> bool ->
  (unit,string) result =
  "caml_prismel_metal_blit_counter_bytecode"
  "caml_prismel_metal_blit_counter"
external blit_texture_aux :
  handle -> handle -> int -> int64 array -> (unit,string) result =
  "caml_prismel_metal_blit_texture_aux"
external blit_indirect :
  handle -> handle -> bool -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_blit_indirect"
external blit_access_counters : handle -> handle -> (int64*int64*int64*int64*int64*int64) -> int64 -> int64 -> bool -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_blit_access_counters_bytecode" "caml_prismel_metal_blit_access_counters"

external capture_descriptor_snapshot :
  handle -> ((handle option * int option * int * string option),string) result =
  "caml_prismel_metal_capture_descriptor_snapshot"
external capture_descriptor_set :
  handle -> handle option -> int -> int -> string option -> (unit,string) result =
  "caml_prismel_metal_capture_descriptor_set"
external capture_scope_create : handle -> handle -> int -> (handle,string) result =
  "caml_prismel_metal_capture_scope_create"
external capture_default_scope :
  handle -> handle option -> bool -> (handle option,string) result =
  "caml_prismel_metal_capture_default_scope"
external capture_lifecycle :
  handle -> handle -> int -> bool -> (unit,string) result =
  "caml_prismel_metal_capture_lifecycle"
external capture_start_descriptor_checked :
  handle -> handle -> (unit,string) result =
  "caml_prismel_metal_capture_start_descriptor_checked"

external compute_pass_create : int -> (handle,string) result =
  "caml_prismel_metal_compute_pass_create"
external compute_pass_snapshot :
  handle -> ((int * handle),string) result =
  "caml_prismel_metal_compute_pass_snapshot"
external compute_pass_set_dispatch : handle -> int -> (unit,string) result =
  "caml_prismel_metal_compute_pass_set_dispatch"
external compute_pass_attachment :
  handle -> int64 -> handle option -> int64 -> int64 -> (handle,string) result =
  "caml_prismel_metal_compute_pass_attachment"
external compute_pass_attachment_snapshot :
  handle -> ((handle option * int64 * int64),string) result =
  "caml_prismel_metal_compute_pass_attachment_snapshot"

external function_log_location : handle -> (handle option,string) result =
  "caml_prismel_metal_function_log_location"
external command_function_logs : handle -> (handle array,string) result =
  "caml_prismel_metal_command_function_logs"
external command_buffer_encoder_infos :
  handle -> ((string option * string array * int) array, string) result =
  "caml_prismel_metal_command_buffer_encoder_infos"
external function_log_encoder_label : handle -> (string option,string) result =
  "caml_prismel_metal_function_log_encoder_label"
external function_log_function : handle -> (handle option,string) result =
  "caml_prismel_metal_function_log_function"
external function_log_location_url : handle -> (string option,string) result =
  "caml_prismel_metal_function_log_location_url"
external function_log_location_function_name :
  handle -> (string option,string) result =
  "caml_prismel_metal_function_log_location_function_name"

external command_encoder_barrier :
  handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_command_encoder_barrier"
external command_encoder_device_id : handle -> (int64,string) result =
  "caml_prismel_metal_command_encoder_device_id"
external command_encoder_label : handle -> (string option,string) result =
  "caml_prismel_metal_command_encoder_label"
external command_encoder_set_label :
  handle -> string option -> (unit,string) result =
  "caml_prismel_metal_command_encoder_set_label"
external command_encoder_debug :
  handle -> int -> string option -> int64 -> (int64,string) result =
  "caml_prismel_metal_command_encoder_debug"

external command_queue_descriptor_create :
  int64 -> handle option -> (handle, string) result =
  "caml_prismel_metal_command_queue_descriptor_create"
external command_queue_descriptor_snapshot :
  handle -> ((int64 * handle option), string) result =
  "caml_prismel_metal_command_queue_descriptor_snapshot"
external command_queue_descriptor_set :
  handle -> int64 -> handle option -> (unit, string) result =
  "caml_prismel_metal_command_queue_descriptor_set"
external command_queue_command_buffer :
  handle -> int -> bool -> int64 -> handle option -> (handle, string) result =
  "caml_prismel_metal_command_queue_command_buffer"
external command_queue_snapshot :
  handle -> ((string option * int64), string) result =
  "caml_prismel_metal_command_queue_snapshot"
external command_queue_set_label :
  handle -> string option -> (unit, string) result =
  "caml_prismel_metal_command_queue_set_label"
external command_queue_capture_boundary : handle -> (unit, string) result =
  "caml_prismel_metal_command_queue_capture_boundary"

external indirect_command_set_buffer_stride :
  handle -> handle -> int64 -> int64 -> int64 -> int -> int64 ->
  (unit, string) result =
  "caml_prismel_metal_indirect_command_set_buffer_stride_bytecode"
  "caml_prismel_metal_indirect_command_set_buffer_stride"
external indirect_render_set_stage_buffer :
  handle -> handle -> int64 -> int64 -> int -> int64 -> (unit, string) result =
  "caml_prismel_metal_indirect_render_set_stage_buffer_bytecode"
  "caml_prismel_metal_indirect_render_set_stage_buffer"
external indirect_render_draw_indexed :
  handle -> int -> int64 -> int -> handle -> int64 -> int64 -> int64 -> int64 ->
  int64 -> (unit, string) result =
  "caml_prismel_metal_indirect_render_draw_indexed_bytecode"
  "caml_prismel_metal_indirect_render_draw_indexed"
external indirect_render_draw_patches :
  handle -> handle option -> handle -> handle ->
  (int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64) ->
  int64 -> (unit, string) result =
  "caml_prismel_metal_indirect_render_draw_patches_bytecode"
  "caml_prismel_metal_indirect_render_draw_patches"

external capture_scope_snapshot :
  handle -> ((string option * int64 * handle option * handle option), string) result =
  "caml_prismel_metal_capture_scope_snapshot"
external capture_scope_set_label :
  handle -> string option -> (unit, string) result =
  "caml_prismel_metal_capture_scope_set_label"
external capture_scope_transition :
  handle -> bool -> (unit, string) result =
  "caml_prismel_metal_capture_scope_transition"
external capture_scope_queue_identity :
  handle -> bool -> (handle option, string) result =
  "caml_prismel_metal_capture_scope_queue_identity"

external event_listener_create :
  int -> string option -> (handle, string) result =
  "caml_prismel_metal_event_listener_create"
external event_listener_queue :
  handle -> ((handle * string), string) result =
  "caml_prismel_metal_event_listener_queue"
external shared_event_export_handle : handle -> (handle, string) result =
  "caml_prismel_metal_shared_event_export_handle"
external shared_event_handle_label :
  handle -> (string option, string) result =
  "caml_prismel_metal_shared_event_handle_label"
external shared_event_notify :
  handle -> handle -> int64 -> (int64 -> unit) -> (nativeint, string) result =
  "caml_prismel_metal_shared_event_notify"
external shared_event_notify_cancel : nativeint -> unit =
  "caml_prismel_metal_shared_event_notify_cancel"

external acceleration_descriptor_create : int -> (handle, string) result =
  "caml_prismel_metal_acceleration_descriptor_create"

external log_state_descriptor_create : int -> int64 -> (handle, string) result =
  "caml_prismel_metal_log_state_descriptor_create"
external log_state_descriptor_snapshot :
  handle -> ((int * int64), string) result =
  "caml_prismel_metal_log_state_descriptor_snapshot"
external log_state_descriptor_set :
  handle -> int -> int64 -> (unit, string) result =
  "caml_prismel_metal_log_state_descriptor_set"
external log_state_create :
  handle -> handle -> ((handle * int64), string) result =
  "caml_prismel_metal_log_state_create"
external log_state_add_handler :
  handle -> (string option * string option * int * string -> unit) ->
  (nativeint, string) result =
  "caml_prismel_metal_log_state_add_handler"
external log_state_handler_cancel : nativeint -> unit =
  "caml_prismel_metal_log_state_handler_cancel"

external parallel_render_child :
  handle -> bool -> ((handle * int64), string) result =
  "caml_prismel_metal_parallel_render_child"
external parallel_render_store :
  handle -> int -> int64 -> int64 -> bool -> int64 -> (unit, string) result =
  "caml_prismel_metal_parallel_render_store_bytecode"
  "caml_prismel_metal_parallel_render_store"

external function_handle_snapshot :
  handle -> ((int * int64 * int64 * string), string) result =
  "caml_prismel_metal_function_handle_snapshot"

external linked_functions_array :
  handle -> int -> (handle array option, string) result =
  "caml_prismel_metal_linked_functions_array"
external linked_functions_create : unit -> (handle,string) result =
  "caml_prismel_metal_linked_functions_create"
external linked_functions_set_array :
  handle -> int -> handle array option -> int64 -> (unit, string) result =
  "caml_prismel_metal_linked_functions_set_array"
external linked_functions_groups :
  handle -> ((string * handle array) array option, string) result =
  "caml_prismel_metal_linked_functions_groups"
external linked_functions_set_groups :
  handle -> (string * handle array) array option -> int64 -> (unit, string) result =
  "caml_prismel_metal_linked_functions_set_groups"

external metal4_queue_copy_buffer_mappings :
  handle -> handle -> handle -> (int64 * int64 * int64) array -> bool ->
  (unit, string) result =
  "caml_prismel_metal4_queue_copy_buffer_mappings"
external metal4_queue_copy_texture_mappings :
  handle -> handle -> handle ->
  (int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 * int64 *
   int64 * int64 * int64 * int64) array -> bool -> (unit, string) result =
  "caml_prismel_metal4_queue_copy_texture_mappings"
external metal4_queue_synchronize :
  handle -> int -> handle -> int64 -> bool -> bool -> (unit, string) result =
  "caml_prismel_metal4_queue_synchronize_bytecode"
  "caml_prismel_metal4_queue_synchronize"

external render93_descriptor_create : int -> (handle,string) result =
  "caml_prismel_metal_render93_descriptor_create"
external render93_descriptor_label : handle -> int -> bool -> string option -> (string option,string) result =
  "caml_prismel_metal_render93_descriptor_label"
external render93_descriptor_reset : handle -> int -> (unit,string) result =
  "caml_prismel_metal_render93_descriptor_reset"
external render93_color_at : handle -> int64 -> bool -> handle option -> (handle option,string) result =
  "caml_prismel_metal_render93_color_at"
external render93_mesh_graph : handle -> int -> bool -> handle array -> (unit,string) result =
  "caml_prismel_metal_render93_mesh_graph"
external render93_tile_graph : handle -> int -> bool -> handle array -> (unit,string) result =
  "caml_prismel_metal_render93_tile_graph"
external render93_array_snapshot : handle -> int -> int -> (int64 array,string) result =
  "caml_prismel_metal_render93_array_snapshot"
external render93_mesh_linked : handle -> int -> bool -> handle option -> (handle option,string) result = "caml_prismel_metal_render93_mesh_linked"
external render93_tile_linked : handle -> bool -> handle option -> (handle option,string) result = "caml_prismel_metal_render93_tile_linked"
external render93_function_handle : handle -> int -> handle -> int64 -> (handle option,string) result = "caml_prismel_metal_render93_function_handle"
external render93_function_handle_name : handle -> int -> string -> int64 -> (handle option,string) result = "caml_prismel_metal_render93_function_handle"
external render93_function_table : handle -> int -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_render93_function_table"
external render93_functions_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_render93_functions_descriptor_create"
external render93_functions_descriptor_array : handle -> int -> bool -> handle array -> (handle array,string) result = "caml_prismel_metal_render93_functions_descriptor_array"
external render93_specialization_descriptor : handle -> (handle,string) result = "caml_prismel_metal_render93_specialization_descriptor"
external render93_relink : handle -> int -> handle -> (handle,string) result = "caml_prismel_metal_render93_relink"
external render93_vertex_descriptor : handle -> bool -> handle option -> (handle option,string) result = "caml_prismel_metal_render93_vertex_descriptor"
external render93_vertex_materialize : (int*int*int*int) array -> (int*int64*int*int64) array -> (handle,string) result = "caml_prismel_metal_render93_vertex_materialize"
external render93_reflection_arguments : handle -> int -> ((string*int64*int*int*bool*int64) array,string) result = "caml_prismel_metal_render93_reflection_arguments"

external intersection_table_array :
  handle -> int -> handle option array -> int64 array -> int64 array ->
  (int64 * int64) -> int64 -> int64 -> (unit, string) result =
  "caml_prismel_metal_intersection_table_array_bytecode"
  "caml_prismel_metal_intersection_table_array"
external intersection_table_signature :
  handle -> int -> int64 -> (int64 * int64) -> int64 -> (unit, string) result =
  "caml_prismel_metal_intersection_table_signature"

external stage_io_attribute_at :
  handle -> int64 -> (handle option, string) result =
  "caml_prismel_metal_stage_io_attribute_at"
external stage_io_attribute_set :
  handle -> int64 -> handle option -> (unit, string) result =
  "caml_prismel_metal_stage_io_attribute_set"
external stage_io_children :
  handle -> ((handle * handle), string) result =
  "caml_prismel_metal_stage_io_children"
external stage_io_reset : handle -> (unit, string) result =
  "caml_prismel_metal_stage_io_reset"

external blit_pass10_attachment_at :
  handle -> int64 -> (handle option, string) result =
  "caml_prismel_metal_blit_pass10_attachment_at"
external blit_pass10_attachment_set :
  handle -> int64 -> handle option -> (unit, string) result =
  "caml_prismel_metal_blit_pass10_attachment_set"
external blit_pass10_sample_buffer :
  handle -> (handle option, string) result =
  "caml_prismel_metal_blit_pass10_sample_buffer"
external blit_pass10_set_sample_buffer :
  handle -> handle option -> int64 -> (unit, string) result =
  "caml_prismel_metal_blit_pass10_set_sample_buffer"

external drawable10_snapshot :
  handle -> ((int64 * float), string) result =
  "caml_prismel_metal_drawable10_snapshot"
external drawable10_present :
  handle -> int -> float -> bool -> (unit, string) result =
  "caml_prismel_metal_drawable10_present"
external drawable10_add_handler :
  handle -> (int64 * float -> unit) -> (nativeint, string) result =
  "caml_prismel_metal_drawable10_add_handler"
external drawable10_handler_cancel : nativeint -> unit =
  "caml_prismel_metal_drawable10_handler_cancel"

external function_constants3_create : unit -> (handle, string) result =
  "caml_prismel_metal_function_constants3_create"
external function_constants3_reset : handle -> (unit, string) result =
  "caml_prismel_metal_function_constants3_reset"
external function_constants3_set_index :
  handle -> int -> int64 -> string -> (unit, string) result =
  "caml_prismel_metal_function_constants3_set_index"
external function_constants3_set_range :
  handle -> int -> (int64 * int64) -> string -> (unit, string) result =
  "caml_prismel_metal_function_constants3_set_range"
external function_constants3_specialize :
  handle -> handle -> string -> (handle, string) result =
  "caml_prismel_metal_function_constants3_specialize"

external metal4_stitched_graph_pair :
  handle -> handle array option -> handle option -> int64 array -> int64 option ->
  int64 -> bool -> (unit, string) result =
  "caml_prismel_metal4_stitched_graph_pair_bytecode"
  "caml_prismel_metal4_stitched_graph_pair"
external metal4_stitched_graph_snapshot :
  handle -> ((handle array * handle option), string) result =
  "caml_prismel_metal4_stitched_graph_snapshot"

external metal4_render_pipeline3_create : int -> (handle, string) result =
  "caml_prismel_metal4_render_pipeline3_create"
external metal4_render_pipeline3_reset :
  handle -> int -> bool -> (unit, string) result =
  "caml_prismel_metal4_render_pipeline3_reset"

external metal4_compute_pipeline_reset1_create : unit -> (handle,string) result =
  "caml_prismel_metal4_compute_pipeline_reset1_create"
external metal4_compute_pipeline_reset1_configure :
  handle -> handle option -> int64 -> bool -> (unit,string) result =
  "caml_prismel_metal4_compute_pipeline_reset1_configure"
external metal4_compute_pipeline_reset1_reset : handle -> (unit,string) result =
  "caml_prismel_metal4_compute_pipeline_reset1_reset"

external binary_archive5_descriptor_create : int -> (handle, string) result =
  "caml_prismel_metal_binary_archive5_descriptor_create"
external binary_archive5_configured_descriptor :
  int -> handle -> handle option -> int64 -> (handle,string) result =
  "caml_prismel_metal_binary_archive5_configured_descriptor"
external binary_archive5_add :
  handle -> int -> handle -> handle option -> int64 -> int64 -> int64 option ->
  (unit, string) result =
  "caml_prismel_metal_binary_archive5_add_bytecode"
  "caml_prismel_metal_binary_archive5_add"

external metal4_ml_pipeline5_label :
  handle -> (string option, string) result =
  "caml_prismel_metal4_ml_pipeline5_label"

external device_architecture_name : handle -> (string,string) result =
  "caml_prismel_metal_device_architecture_name"
external device_observer_create : (handle * string option -> unit) -> ((handle array * nativeint),string) result = "caml_prismel_metal_device_observer_create"
external device_observer_cancel : nativeint -> (unit,string) result = "caml_prismel_metal_device_observer_cancel"
external device_capability_snapshot : handle -> ((bool*int64*int64*int64*bool*bool*int),string) result = "caml_prismel_metal_device_capability_snapshot"
external device_set_maximize_compilation : handle -> bool -> (unit,string) result = "caml_prismel_metal_device_set_maximize_compilation"
external device_supports_counter_sampling_exact : handle -> int64 -> (bool,string) result = "caml_prismel_metal_device_supports_counter_sampling_exact"
external device_supports_feature_set_exact : handle -> int64 -> (bool,string) result = "caml_prismel_metal_device_supports_feature_set_exact"
external device_supports_rate_layers : handle -> int64 -> (bool,string) result = "caml_prismel_metal_device_supports_rate_layers"
external device_convert_sparse_regions : handle -> device_region array -> (int64*int64*int64) -> int -> bool -> (device_region array,string) result = "caml_prismel_metal_device_convert_sparse_regions"
external device_default_sample_positions : handle -> int64 -> ((float*float) array,string) result = "caml_prismel_metal_device_default_sample_positions"
external device_sample_timestamps : handle -> ((int64*int64),string) result = "caml_prismel_metal_device_sample_timestamps"
external device_timestamp_frequency : handle -> (int64,string) result = "caml_prismel_metal_device_timestamp_frequency"
external device_counter_heap_entry_size : handle -> (int64,string) result = "caml_prismel_metal_device_counter_heap_entry_size"
