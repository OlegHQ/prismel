type handle
type device_region = int64 * int64 * int64 * int64 * int64 * int64

module Registry = Metal_gen.Make (struct
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

type acceleration_instance_descriptor =
  { instance_buffer : handle; instance_count : int64; primitives : handle array
  ; instance_offset : int64 }

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

external destroy : handle -> bool = "caml_prismel_metal_destroy"

external drain_releases : unit -> int = "caml_prismel_metal_drain_releases"
external pending_releases : unit -> int = "caml_prismel_metal_pending_releases"
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

external buffer_create : handle -> int64 -> int -> (handle, string) result =
  "caml_prismel_metal_buffer_create"

external buffer_info : handle -> int64 * int * int * int * int64 =
  "caml_prismel_metal_buffer_info"

external buffer_set_label : handle -> string -> (unit, string) result =
  "caml_prismel_metal_buffer_set_label"

external buffer_write :
  handle -> int64 -> bytes -> int -> int -> (unit, string) result
  = "caml_prismel_metal_buffer_write"

external buffer_read : handle -> int64 -> int -> (bytes, string) result =
  "caml_prismel_metal_buffer_read"

external resource_make_aliasable : handle -> (unit, string) result =
  "caml_prismel_metal_resource_make_aliasable"

external resource_is_aliasable : handle -> bool =
  "caml_prismel_metal_resource_is_aliasable"




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


external texture_create :
  handle ->
  texture_descriptor ->
  string option -> (handle, string) result
  = "caml_prismel_metal_texture_create"

external texture_info : handle -> int array = "caml_prismel_metal_texture_info"

external texture_is_sparse : handle -> bool =
  "caml_prismel_metal_texture_is_sparse"

external texture_sparse_info :
  handle -> handle -> int -> (int64 array, string) result
  = "caml_prismel_metal_texture_sparse_info"

external texture_is_shareable : handle -> bool =
  "caml_prismel_metal_texture_is_shareable"

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

external depth_stencil_create :
  handle -> depth_stencil_descriptor -> (handle, string) result =
  "caml_prismel_metal_depth_stencil_create"

external indirect_command_buffer_create :
  handle -> indirect_command_buffer_descriptor -> int64 -> int64 ->
  (handle, string) result = "caml_prismel_metal_indirect_command_buffer_create"

external indirect_command_buffer_reset : handle -> int64 -> int64 ->
  (unit, string) result = "caml_prismel_metal_indirect_command_buffer_reset"

external indirect_render_command : handle -> int64 -> (handle, string) result =
  "caml_prismel_metal_indirect_render_command"

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

external library_compile :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_library_compile"

external library_compile_descriptor :
  handle -> string -> library_compile_descriptor -> (handle, string) result =
  "caml_prismel_metal_library_compile_descriptor"

external library_kind : handle -> int = "caml_prismel_metal_library_kind"

external library_function_names : handle -> string array =
  "caml_prismel_metal_library_function_names"

external function_find : handle -> string -> (handle, string) result =
  "caml_prismel_metal_function_find"

external function_name : handle -> string = "caml_prismel_metal_function_name"

external function_kind : handle -> int = "caml_prismel_metal_function_kind"

external function_specialize :
  handle -> string -> function_constant_value array -> string option ->
  (handle, string) result
  = "caml_prismel_metal_function_specialize"

external dynamic_library_create :
  handle -> handle -> string option -> (handle, string) result =
  "caml_prismel_metal_dynamic_library_create"

external dynamic_library_load_file :
  handle -> string -> string option -> (handle, string) result =
  "caml_prismel_metal_dynamic_library_load_file"

external dynamic_library_install_name : handle -> string =
  "caml_prismel_metal_dynamic_library_install_name"

external dynamic_library_serialize :
  handle -> string -> (unit, string) result =
  "caml_prismel_metal_dynamic_library_serialize"

external binary_archive_create :
  handle -> string option -> string option -> (handle, string) result =
  "caml_prismel_metal_binary_archive_create"

external binary_archive_add_compute :
  handle -> handle -> handle array -> handle array -> (unit, string) result =
  "caml_prismel_metal_binary_archive_add_compute"

external binary_archive_serialize :
  handle -> string -> (unit, string) result =
  "caml_prismel_metal_binary_archive_serialize"

external compiler_create :
  handle -> handle option -> string option -> (handle, string) result =
  "caml_prismel_metal_compiler_create"

external compiler_create_render_pipeline :
  handle -> metal4_render_descriptor ->
  ((handle * render_pipeline_reflection), string) result =
  "caml_prismel_metal_compiler_create_render_pipeline"

external compute_pipeline_create : handle -> handle -> (handle, string) result =
  "caml_prismel_metal_compute_pipeline_create"

external compute_pipeline_create_descriptor :
  handle -> handle -> compute_pipeline_descriptor ->
  ((handle * pipeline_binding_info array), string) result
  = "caml_prismel_metal_compute_pipeline_create_descriptor"

external compute_pipeline_max_total_threads : handle -> int =
  "caml_prismel_metal_compute_pipeline_max_total_threads"



external command_queue_add_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_queue_add_residency_sets"


external command_queue_remove_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_queue_remove_residency_sets"


(* Generic acceleration build descriptors (plan G5); field order is read
   positionally by metal_bridge.mm. *)
type accel_keyframe = { keyframe_buffer : handle; keyframe_offset : int64 }
type accel_geometry_raw =
  | Raw_triangles of
      { vertex : handle; vertex_offset : int64; vertex_stride : int64; triangle_count : int64
      ; index : handle option; index_offset : int64; index_uint16 : bool
      ; keyframes : accel_keyframe array; opaque : bool; allow_duplicate : bool
      ; table_offset : int64 }
  | Raw_boxes of
      { boxes : handle; box_offset : int64; box_stride : int64; box_count : int64
      ; box_keyframes : accel_keyframe array; box_opaque : bool; box_allow_duplicate : bool
      ; box_table_offset : int64 }
  | Raw_curves of
      { control : handle; control_offset : int64; control_stride : int64; control_count : int64
      ; radius : handle; radius_offset : int64; radius_stride : int64
      ; curve_index : handle; curve_index_offset : int64; curve_index_uint16 : bool
      ; segment_count : int64; segment_control_points : int64
      ; curve_type : int; curve_basis : int; end_caps : int
      ; control_keyframes : accel_keyframe array; radius_keyframes : accel_keyframe array
      ; curve_opaque : bool; curve_allow_duplicate : bool; curve_table_offset : int64 }
type accel_motion_raw =
  { keyframe_count : int64; start_time : float; end_time : float
  ; start_border : int; end_border : int }
type accel_primitive_raw =
  { geometries : accel_geometry_raw array; motion : accel_motion_raw option
  ; primitive_refit : bool; fast_build : bool }
type accel_instances_raw =
  { instances_buffer : handle; instances_offset : int64; instances_stride : int64
  ; instances_count : int64; instance_kind : int; instanced : handle array
  ; motion_transforms : handle option; motion_transform_offset : int64
  ; motion_transform_count : int64; instances_refit : bool }
external accel_descriptor_primitive : accel_primitive_raw -> (handle, string) result
  = "caml_prismel_metal_accel_descriptor_primitive"
external accel_descriptor_instances : accel_instances_raw -> (handle, string) result
  = "caml_prismel_metal_accel_descriptor_instances"
external accel_descriptor_sizes : handle -> handle -> ((int64 * int64 * int64), string) result
  = "caml_prismel_metal_accel_descriptor_sizes"
external accel_encoder_build_descriptor :
  handle -> handle -> handle -> handle -> int64 -> (unit, string) result
  = "caml_prismel_metal_accel_encoder_build_descriptor"
external accel_encoder_refit_descriptor :
  handle -> handle -> handle -> handle -> handle -> int64 -> (unit, string) result
  = "caml_prismel_metal_accel_encoder_refit_descriptor_bytecode"
    "caml_prismel_metal_accel_encoder_refit_descriptor"
external accel_instance_layout : int -> int array = "caml_prismel_metal_accel_instance_layout"

external acceleration_structure_create :
  handle -> int64 -> (handle, string) result
  = "caml_prismel_metal_acceleration_structure_create"


external acceleration_encoder_copy :
  handle -> handle -> handle -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_copy"

external acceleration_encoder_copy_and_compact :
  handle -> handle -> handle -> (unit, string) result
  = "caml_prismel_metal_acceleration_encoder_copy_and_compact"


external compute_pipeline_function_handle :
  handle -> handle -> (handle, string) result
  = "caml_prismel_metal_compute_pipeline_function_handle"
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



external command_buffer_use_residency_sets :
  handle -> handle array -> (unit, string) result
  = "caml_prismel_metal_command_buffer_use_residency_sets"


external command_buffer_render_encoder_attachments :
  handle -> handle -> handle option -> handle option ->
  float * float * float * float -> (handle,string) result =
  "caml_prismel_metal_command_buffer_render_encoder_attachments_bytecode"
  "caml_prismel_metal_command_buffer_render_encoder_attachments"
external layer_create : handle -> (handle,string) result = "caml_prismel_metal_layer_create"
external layer_adopt_borrowed : handle -> Native_layer_token.t -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_layer_adopt_borrowed"
external layer_configure : handle -> int -> int -> int -> (bool*int*bool*bool*bool) -> (unit,string) result = "caml_prismel_metal_layer_configure"
external layer_next_drawable : handle -> (handle option,string) result = "caml_prismel_metal_layer_next_drawable"
type presentation_layer_snapshot = int64 * float * float * int64 * bool * int64 * bool * bool * bool * bool
external drawable_texture : handle -> ((handle * int * int * int),string) result = "caml_prismel_metal_drawable_texture"
external command_buffer_present_drawable : handle -> handle -> int -> float -> (unit,string) result = "caml_prismel_metal_command_buffer_present_drawable"
type presentation_command_snapshot = int64 * int64 * int64 * float * float * float * float * bool
external presentation_command_snapshot : handle -> (presentation_command_snapshot,string) result = "caml_prismel_metal_presentation_command_snapshot"
external command_buffer_cancel_handler : nativeint -> unit = "caml_prismel_metal_command_buffer_cancel_handler"
external render_pass_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_render_pass_descriptor_create"
external render_pass_descriptor_set_sizes : handle -> int -> int -> int -> int -> (unit,string) result = "caml_prismel_metal_render_pass_descriptor_set_sizes"
type presentation_render_pass_advanced = int64 * int64 * int64 * int64 * int64 * bool * (float * float) array
external render_pass_sample_set : handle -> int64 -> handle option -> int64 -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_pass_sample_set_bytecode" "caml_prismel_metal_render_pass_sample_set"
external render_pass_resolve_texture : handle -> handle option -> bool -> (handle option,string) result = "caml_prismel_metal_render_pass_resolve_texture"
external render_pass_color_store_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_pass_color_store_action"
external render_pass_color_load_action : handle -> int -> (unit,string) result = "caml_prismel_metal_render_pass_color_load_action"
external render_pass_descriptor_set_attachments :
  handle -> handle -> handle option -> handle option -> handle option ->
  float * float * float * float -> (unit,string) result =
  "caml_prismel_metal_render_pass_descriptor_set_attachments_bytecode"
  "caml_prismel_metal_render_pass_descriptor_set_attachments"
external render_encoder_update_fence : handle -> handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_update_fence"
external render_encoder_wait_fence : handle -> handle -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_wait_fence"
external render_encoder_use_heaps : handle -> handle array -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_use_heaps"
external render_encoder_use_resources : handle -> handle array -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_use_resources"
external render_encoder_execute_icb_range : handle -> handle -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_execute_icb_range"
external render_encoder_set_pipeline : handle -> handle -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_pipeline"
external render_encoder_set_vertex_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_vertex_buffer"
external render_encoder_set_fragment_buffer :
  handle -> handle -> int64 -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_fragment_buffer"
external render_encoder_execute_indexed_draws :
  handle -> handle array -> handle array array -> int array array ->
  int64 array array -> int array array -> int array -> int64 array ->
  int array -> handle array -> int64 array -> (unit,string) result =
  "caml_prismel_metal_render_encoder_execute_indexed_draws_bytecode"
  "caml_prismel_metal_render_encoder_execute_indexed_draws"
type prepared_render_pass_state =
  int * handle option * (int32 * int32) option *
  (float * float * float * float * float * float) *
  (int * int * int * int)
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

external render_stage_buffer : handle -> int -> handle option -> int64 -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_buffer_bytecode" "caml_prismel_metal_render_stage_buffer"

external render_stage_bytes : handle -> int -> bytes -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_bytes_bytecode" "caml_prismel_metal_render_stage_bytes"
external render_stage_sampler : handle -> int -> handle option -> bool -> (float*float) -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_sampler_bytecode" "caml_prismel_metal_render_stage_sampler"
external render_stage_texture : handle -> int -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_render_stage_texture"

type render_command_scissor = int64 * int64 * int64 * int64
type render_command_viewport = float * float * float * float * float * float
type render_command_view_mapping = int64 * int64

external render_draw_indexed_instances : handle -> int -> int64 -> int -> handle -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_instances_bytecode" "caml_prismel_metal_render_draw_indexed_instances"
external render_draw_indexed_basic : handle -> int -> int64 -> int -> handle -> int64 -> (unit,string) result = "caml_prismel_metal_render_draw_indexed_basic_bytecode" "caml_prismel_metal_render_draw_indexed_basic"

external render_depth_stencil : handle -> handle option -> (unit,string) result = "caml_prismel_metal_render_depth_stencil"
external render_encoder_draw :
  handle -> int -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_draw"
external render_encoder_draw_primitives :
  handle -> int -> int -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_encoder_draw_primitives"
external render_pass_depth_stencil_actions :
  handle -> int -> int -> float -> int -> int -> int -> (unit, string) result =
  "caml_prismel_metal_render_pass_depth_stencil_actions_bytecode"
  "caml_prismel_metal_render_pass_depth_stencil_actions"
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
external render_encoder_set_stencil_reference :
  handle -> int32 -> int32 -> (unit, string) result =
  "caml_prismel_metal_render_encoder_set_stencil_reference"
external render_encoder_tile_width : handle -> int =
  "caml_prismel_metal_render_encoder_tile_width"
external render_encoder_tile_height : handle -> int =
  "caml_prismel_metal_render_encoder_tile_height"



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

external compute35_acceleration : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_acceleration"
external compute35_visible : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_visible"
external compute35_intersection : handle -> handle option -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_intersection"
external compute35_dispatch_groups : handle -> int*int*int -> int*int*int -> (unit,string) result = "caml_prismel_metal_compute35_dispatch_groups"
external compute35_bytes_plain : handle -> bytes -> int64 -> (unit,string) result = "caml_prismel_metal_compute35_bytes_plain"
external compute35_update_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_compute35_update_fence"
external compute35_wait_fence : handle -> handle -> (unit,string) result = "caml_prismel_metal_compute35_wait_fence"
external compute35_heaps : handle -> handle array -> (unit,string) result = "caml_prismel_metal_compute35_heaps"


external resource_state_encoder_update_texture_mapping :
  handle -> handle -> int -> (int * int * int * int * int * int) -> int -> int ->
  (unit, string) result
  = "caml_prismel_metal_resource_state_encoder_update_texture_mapping_bytecode"
    "caml_prismel_metal_resource_state_encoder_update_texture_mapping"


external blit_encoder_copy_buffer_to_texture :
  handle -> handle -> handle ->
  (int64 * int * int * (int * int * int) * int * int * (int * int * int)) ->
  (unit, string) result
  = "caml_prismel_metal_blit_encoder_copy_buffer_to_texture"



external command_buffer_wait : handle -> unit =
  "caml_prismel_metal_command_buffer_wait"


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

external pipeline_render_indirect : handle -> (bool,string) result = "caml_prismel_metal_pipeline_render_indirect"

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

(** Counter and blit-pass bindings. *)
external counter_sets : handle -> (((handle * string) array),string) result = "caml_prismel_metal_counter_sets"
external counter_descriptor_create : unit -> (handle,string) result = "caml_prismel_metal_counter_descriptor_create"
external counter_set_counters : handle -> (((handle * string) array),string) result = "caml_prismel_metal_counter_set_counters"

external counter_descriptor_set : handle -> handle -> string option -> int64 -> int64 -> (unit,string) result = "caml_prismel_metal_counter_descriptor_set"
external counter_sample_buffer_create : handle -> handle -> (handle,string) result = "caml_prismel_metal_counter_sample_buffer_create"

external counter_sample_resolve : handle -> int64 -> int64 -> (bytes,string) result = "caml_prismel_metal_counter_sample_resolve"
external counter_supports_sampling : handle -> int -> (bool,string) result = "caml_prismel_metal_counter_supports_sampling"
external blit_pass_create : unit -> (handle,string) result = "caml_prismel_metal_blit_pass_create"
external blit_pass_attachments : handle -> (handle,string) result = "caml_prismel_metal_blit_pass_attachments"
external blit_attachment : handle -> int64 -> handle option -> int64 -> int64 -> (handle,string) result = "caml_prismel_metal_blit_attachment"

external device_library_data : handle -> string -> (handle,string) result =
  "caml_prismel_metal_device_library_data"

(** Authoritative Metal4 lifecycle190 prepared CAML subset. The resource and
    compute-owner shards currently contain typed native helpers only, not OCaml
    primitives, so they are intentionally absent here. *)

type metal4_size = int64 * int64 * int64
type metal4_origin = int64 * int64 * int64
type metal4_range = int64 * int64

type metal4_buffer_texture_copy = handle * int64 * int64 * int64 * metal4_size * handle * int64 * int64 * metal4_origin

type metal4_texture_buffer_copy = handle * int64 * int64 * metal4_origin * metal4_size * handle * int64 * int64 * int64

type metal4_owned_buffer_range = handle * int64 * int64

external shader_function_argument_encoder :
  handle -> int64 -> (handle,string) result =
  "caml_prismel_metal_shader_function_argument_encoder"

(* Corrected Command-support121 exact native subset (18 mechanical / 103
   handwritten partition). Callback and complex-copy families remain absent. *)
external command_shared_event_value : handle -> (int64,string) result =
  "caml_prismel_metal_shared_event_value"
external command_shared_event_set_value : handle -> int64 -> (unit,string) result =
  "caml_prismel_metal_shared_event_set_value"

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

(* Metal4 render-pass owned descriptor graph. *)

(* Exact MTLTensor.h mechanical18 raw closure. *)

(* Exact callable ABI for ArgumentEncoder34. *)
external argument_encoder_snapshot :
  handle -> ((string option * int64 * int64 * int64),string) result =
  "caml_prismel_metal_argument_encoder_snapshot"
external argument_encoder_set_buffer :
  handle -> handle -> int64 -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_argument_encoder_set_buffer"
external argument_encoder_single :
  handle -> int -> handle -> int64 -> int64 -> (unit,string) result =
  "caml_prismel_metal_argument_encoder_single"

(* Exact callable tail for AccelerationCommand32. *)
external acceleration_encoder_write_type :
  handle -> handle -> handle -> int64 -> int -> (unit,string) result =
  "caml_prismel_metal_acceleration_encoder_write_type"

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

external compute_pass_create : int -> (handle,string) result =
  "caml_prismel_metal_compute_pass_create"
external compute_pass_snapshot :
  handle -> ((int * handle),string) result =
  "caml_prismel_metal_compute_pass_snapshot"
external compute_pass_attachment :
  handle -> int64 -> handle option -> int64 -> int64 -> (handle,string) result =
  "caml_prismel_metal_compute_pass_attachment"
external compute_pass_attachment_snapshot :
  handle -> ((handle option * int64 * int64),string) result =
  "caml_prismel_metal_compute_pass_attachment_snapshot"

external indirect_render_draw_indexed :
  handle -> int -> int64 -> int -> handle -> int64 -> int64 -> int64 -> int64 ->
  int64 -> (unit, string) result =
  "caml_prismel_metal_indirect_render_draw_indexed_bytecode"
  "caml_prismel_metal_indirect_render_draw_indexed"

external render93_array_snapshot : handle -> int -> int -> (int64 array,string) result =
  "caml_prismel_metal_render93_array_snapshot"

external blit_pass10_attachment_at :
  handle -> int64 -> (handle option, string) result =
  "caml_prismel_metal_blit_pass10_attachment_at"
external blit_pass10_set_sample_buffer :
  handle -> handle option -> int64 -> (unit, string) result =
  "caml_prismel_metal_blit_pass10_set_sample_buffer"

external drawable10_snapshot :
  handle -> ((int64 * float), string) result =
  "caml_prismel_metal_drawable10_snapshot"

external binary_archive5_configured_descriptor :
  int -> handle -> handle option -> int64 -> (handle,string) result =
  "caml_prismel_metal_binary_archive5_configured_descriptor"
external binary_archive5_add :
  handle -> int -> handle -> handle option -> int64 -> int64 -> int64 option ->
  (unit, string) result =
  "caml_prismel_metal_binary_archive5_add_bytecode"
  "caml_prismel_metal_binary_archive5_add"

external device_sample_timestamps : handle -> ((int64*int64),string) result = "caml_prismel_metal_device_sample_timestamps"
external device_timestamp_frequency : handle -> (int64,string) result = "caml_prismel_metal_device_timestamp_frequency"
external shared_event_wait : handle -> int64 -> int64 -> (bool,string) result = "caml_prismel_metal_shared_event_wait"
external render_encoder_draw_mesh_threadgroups : handle -> (int*int*int*int*int*int*int*int*int) -> (unit,string) result = "caml_prismel_metal_render_encoder_draw_mesh_threadgroups"
external render_encoder_dispatch_threads_per_tile : handle -> int -> int -> int -> (unit,string) result = "caml_prismel_metal_render_encoder_dispatch_threads_per_tile"
external mesh_tile_descriptor_set_color_format : handle -> bool -> int -> int -> (unit,string) result = "caml_prismel_metal_mesh_tile_descriptor_set_color_format"
external fx_spatial_supported : handle -> (bool,string) result = "caml_prismel_metal_fx_spatial_supported"
external fx_spatial_create : handle -> (int*int*int*int*int*int) -> (handle,string) result = "caml_prismel_metal_fx_spatial_create"
external fx_spatial_encode : handle -> handle -> handle -> handle -> (unit,string) result = "caml_prismel_metal_fx_spatial_encode"
