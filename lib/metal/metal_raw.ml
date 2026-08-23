type handle

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

(** Positional native ABI value for one reflected pipeline binding. Keep this
    synchronized with [copy_bindings] in [metal_bridge.mm]. *)
type pipeline_binding_info =
  string * int * int * int64 * bool * bool * int64 * int64 * int * int * int
  * bool * int64 * int64 * int64 * int64 * int64

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

(** Positional native ABI record for one base-level, single-sample Metal 4
    render-pass color attachment. *)
type metal4_render_attachment =
  { texture : handle
  ; load_action : int
  ; store_action : int
  ; clear_red : float
  ; clear_green : float
  ; clear_blue : float
  ; clear_alpha : float
  }

(** Positional native ABI record for one base-level, single-sample Metal 4
    render-pass depth attachment. *)
type metal4_render_depth_attachment =
  { texture : handle
  ; load_action : int
  ; store_action : int
  ; clear_depth : float
  }

(** Positional native ABI record for one base-level, single-sample Metal 4
    render-pass stencil attachment. *)
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
  (handle, string) result
  = "caml_prismel_metal_function_create_descriptor"

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

external command4_buffer_create :
  handle -> string option -> (handle, string) result =
  "caml_prismel_metal_command4_buffer_create"

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

external compute_pipeline_create : handle -> handle -> (handle, string) result =
  "caml_prismel_metal_compute_pipeline_create"

external compute_pipeline_create_descriptor :
  handle -> handle -> compute_pipeline_descriptor ->
  ((handle * pipeline_binding_info array), string) result
  = "caml_prismel_metal_compute_pipeline_create_descriptor"

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
