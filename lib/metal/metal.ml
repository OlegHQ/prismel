module Enum = Metal_gen.Enum
module Data_type = Metal_gen.Enum.Mtl_data_type
module Feature_set = Metal_gen.Enum.Mtl_feature_set

type error_kind =
  | Native_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Invalid_state
  | Unsupported
  | Device_mismatch

type error = { operation : string; kind : error_kind; message : string }

let pp_error formatter error = Format.fprintf formatter "%s: %s" error.operation error.message
let error operation kind message = Error { operation; kind; message }
let native_error operation message = error operation Native_error message

(* Adapters for generated [Metal_raw.Registry] calls, which return
   [(_, string) result]: [native] types the failure, [probe] reads an
   internal capability bit whose native failure means "unsupported". *)
let native operation = function Ok value -> Ok value | Error message -> native_error operation message
let probe = function Ok value -> value | Error _ -> false

let contains_nul value = String.contains value '\000'
let option_exists predicate = function Some value -> predicate value | None -> false

let validate_absolute_path operation path =
  if path = "" then error operation Invalid_argument "path is empty"
  else if contains_nul path then error operation Invalid_argument "path contains a NUL byte"
  else if Filename.is_relative path then error operation Invalid_argument "path must be absolute"
  else Ok ()

module Vertex_descriptor = struct
  type format =
    | Uchar2
    | Uchar3
    | Uchar4
    | Char2
    | Char3
    | Char4
    | Uchar2_normalized
    | Uchar3_normalized
    | Uchar4_normalized
    | Char2_normalized
    | Char3_normalized
    | Char4_normalized
    | Ushort2
    | Ushort3
    | Ushort4
    | Short2
    | Short3
    | Short4
    | Ushort2_normalized
    | Ushort3_normalized
    | Ushort4_normalized
    | Short2_normalized
    | Short3_normalized
    | Short4_normalized
    | Half2
    | Half3
    | Half4
    | Float
    | Float2
    | Float3
    | Float4
    | Int
    | Int2
    | Int3
    | Int4
    | Uint
    | Uint2
    | Uint3
    | Uint4
    | Int1010102_normalized
    | Uint1010102_normalized
    | Uchar4_normalized_bgra
    | Uchar
    | Char
    | Uchar_normalized
    | Char_normalized
    | Ushort
    | Short
    | Ushort_normalized
    | Short_normalized
    | Half
    | Float_rg11b10
    | Float_rgb9e5

  type step_function = Constant | Per_vertex | Per_instance | Per_patch | Per_patch_control_point
  type stride = Static of int | Dynamic
  type attribute = { index : int; format : format; offset : int; buffer_index : int }

  type layout = {
    buffer_index : int;
    stride : stride;
    step_function : step_function;
    step_rate : int;
  }

  type t = { attributes : attribute list; layouts : layout list }

  let format_code = function
    | Uchar2 -> 1
    | Uchar3 -> 2
    | Uchar4 -> 3
    | Char2 -> 4
    | Char3 -> 5
    | Char4 -> 6
    | Uchar2_normalized -> 7
    | Uchar3_normalized -> 8
    | Uchar4_normalized -> 9
    | Char2_normalized -> 10
    | Char3_normalized -> 11
    | Char4_normalized -> 12
    | Ushort2 -> 13
    | Ushort3 -> 14
    | Ushort4 -> 15
    | Short2 -> 16
    | Short3 -> 17
    | Short4 -> 18
    | Ushort2_normalized -> 19
    | Ushort3_normalized -> 20
    | Ushort4_normalized -> 21
    | Short2_normalized -> 22
    | Short3_normalized -> 23
    | Short4_normalized -> 24
    | Half2 -> 25
    | Half3 -> 26
    | Half4 -> 27
    | Float -> 28
    | Float2 -> 29
    | Float3 -> 30
    | Float4 -> 31
    | Int -> 32
    | Int2 -> 33
    | Int3 -> 34
    | Int4 -> 35
    | Uint -> 36
    | Uint2 -> 37
    | Uint3 -> 38
    | Uint4 -> 39
    | Int1010102_normalized -> 40
    | Uint1010102_normalized -> 41
    | Uchar4_normalized_bgra -> 42
    | Uchar -> 45
    | Char -> 46
    | Uchar_normalized -> 47
    | Char_normalized -> 48
    | Ushort -> 49
    | Short -> 50
    | Ushort_normalized -> 51
    | Short_normalized -> 52
    | Half -> 53
    | Float_rg11b10 -> 54
    | Float_rgb9e5 -> 55

  let step_function_code = function
    | Constant -> 0
    | Per_vertex -> 1
    | Per_instance -> 2
    | Per_patch -> 3
    | Per_patch_control_point -> 4

  let raw_attribute (value : attribute) =
    ({
       Metal_raw.attribute_index = value.index;
       vertex_format = format_code value.format;
       offset = Int64.of_int value.offset;
       buffer_index = value.buffer_index;
     }
      : Metal_raw.metal4_vertex_attribute_descriptor)

  let raw_layout (value : layout) =
    ({
       Metal_raw.buffer_index = value.buffer_index;
       stride =
         (match value.stride with Static stride -> Some (Int64.of_int stride) | Dynamic -> None);
       step_function = step_function_code value.step_function;
       step_rate = Int64.of_int value.step_rate;
     }
      : Metal_raw.metal4_vertex_layout_descriptor)

  let raw value =
    ({
       Metal_raw.attributes = Array.of_list (List.map raw_attribute value.attributes);
       layouts = Array.of_list (List.map raw_layout value.layouts);
     }
      : Metal_raw.metal4_vertex_descriptor)
end

module Thread = struct
  let is_initial_domain = Domain.is_main_domain
  let is_platform_main_thread = Metal_raw.is_main_thread

  let require operation =
    if not (is_initial_domain ()) then
      error operation Wrong_domain "Metal operation must run on the initial OCaml domain"
    else if not (is_platform_main_thread ()) then
      error operation Wrong_domain "Metal operation must run on the platform main thread"
    else Ok ()
end

let before_main operation =
  match Thread.require operation with
  | Error _ as failure -> failure
  | Ok () ->
      ignore (Metal_raw.drain_releases ());
      Ok ()

let on_main operation callback =
  match before_main operation with Error _ as failure -> failure | Ok () -> callback ()

module Release_queue = struct
  type stats = {
    pending : int;
    live_handles : int;
    total_created : int64;
    total_released : int64;
    external_deallocations : int64;
    external_deallocation_mismatches : int64;
    resident_bytes : int64;
  }

  let drain () =
    match Thread.require "Metal.Release_queue.drain" with
    | Error _ as failure -> failure
    | Ok () ->
        Ok (Metal_raw.drain_releases ())

  let stats () =
    match Thread.require "Metal.Release_queue.stats" with
    | Error _ as failure -> failure
    | Ok () ->
        let resident_bytes = Metal_raw.resident_bytes () in
        if resident_bytes < 0L then
          native_error "Metal.Release_queue.stats" "mach task_info could not read resident memory"
        else
          Ok
            {
              pending = Metal_raw.pending_releases ();
              live_handles = Metal_raw.live_handles ();
              total_created = Metal_raw.total_created ();
              total_released = Metal_raw.total_released ();
              external_deallocations = Metal_raw.external_deallocations ();
              external_deallocation_mismatches = Metal_raw.external_deallocation_mismatches ();
              resident_bytes;
            }
end

type lifetime = { identity : int; destroyed : bool Atomic.t; dependents : int Atomic.t }

let lifetime_identity_counter = Atomic.make 0

let rec next_lifetime_identity () =
  let identity = Atomic.get lifetime_identity_counter in
  if identity = Stdlib.max_int then failwith "Metal lifetime identity space exhausted"
  else if Atomic.compare_and_set lifetime_identity_counter identity (identity + 1) then identity
  else next_lifetime_identity ()

let lifetime () =
  {
    identity = next_lifetime_identity ();
    destroyed = Atomic.make false;
    dependents = Atomic.make 0;
  }

let is_destroyed lifetime = Atomic.get lifetime.destroyed
let dependent_count lifetime = Atomic.get lifetime.dependents
let attach lifetime = Atomic.incr lifetime.dependents
let detach lifetime = Atomic.decr lifetime.dependents

let finalize_child lifetime parent on_finalize =
  if Atomic.compare_and_set lifetime.destroyed false true then begin
    on_finalize ();
    detach parent
  end

let ensure_live operation lifetime =
  if is_destroyed lifetime then error operation Destroyed "handle is destroyed" else Ok ()

let destroy_leaf operation lifetime raw detach_parent =
  on_main operation (fun () ->
      if Atomic.compare_and_set lifetime.destroyed false true then begin
        ignore (Metal_raw.destroy raw);
        detach_parent ()
      end;
      Ok ())

let destroy_parent operation lifetime raw detach_parent =
  on_main operation (fun () ->
      if is_destroyed lifetime then Ok ()
      else
        let dependents = dependent_count lifetime in
        if dependents <> 0 then
          error operation Parent_has_dependents
            (Printf.sprintf "handle still owns %d live dependent(s)" dependents)
        else begin
          Atomic.set lifetime.destroyed true;
          ignore (Metal_raw.destroy raw);
          detach_parent ();
          Ok ()
        end)

type device = { raw : Metal_raw.handle; lifetime : lifetime; registry_id : int64 }

type command_shared_event = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  registry_id : int64;
  mutable value : int64;
}

type buffer_storage_mode = Shared | Managed | Private

type texture_kind =
  | Texture_1d
  | Texture_1d_array
  | Texture_2d
  | Texture_2d_array
  | Texture_2d_multisample
  | Texture_cube
  | Texture_cube_array
  | Texture_3d
  | Texture_2d_multisample_array
  | Texture_buffer

type shader_scalar_type =
  | Float
  | Half
  | Int
  | Uint
  | Short
  | Ushort
  | Char
  | Uchar
  | Bool
  | Long
  | Ulong
  | Bfloat

type shader_data_type =
  | No_type
  | Struct
  | Array
  | Scalar of shader_scalar_type
  | Vector of shader_scalar_type * int
  | Matrix of shader_scalar_type * int * int
  | Texture_type
  | Sampler_type
  | Pointer
  | Other_data_type of int

type shader_binding_access = Read_only | Read_write | Write_only | Unknown_access of int
type buffer_binding_layout = { alignment : int64; data_size : int64; data_type : shader_data_type }

type texture_binding_layout = {
  texture_kind : texture_kind;
  data_type : shader_data_type;
  depth : bool;
  array_length : int64;
}

type sized_binding_layout = { alignment : int64; data_size : int64 }

type shader_binding_kind =
  | Buffer_binding of buffer_binding_layout
  | Threadgroup_memory_binding of sized_binding_layout
  | Texture_binding of texture_binding_layout
  | Sampler_binding
  | Imageblock_data_binding
  | Imageblock_binding
  | Visible_function_table_binding
  | Primitive_acceleration_structure_binding
  | Instance_acceleration_structure_binding
  | Intersection_function_table_binding
  | Object_payload_binding of sized_binding_layout
  | Tensor_binding
  | Unknown_binding of int

type shader_binding = {
  name : string;
  index : int64;
  access : shader_binding_access;
  used : bool;
  argument : bool;
  kind : shader_binding_kind;
  reflection : Metal_argument_reflection_snapshot.reflected_type option;
}

type shader_binding_layout_kind =
  | Buffer_layout
  | Threadgroup_memory_layout
  | Texture_layout
  | Sampler_layout
  | Imageblock_data_layout
  | Imageblock_layout
  | Visible_function_table_layout
  | Primitive_acceleration_structure_layout
  | Instance_acceleration_structure_layout
  | Intersection_function_table_layout
  | Object_payload_layout
  | Tensor_layout
  | Other_binding_layout of int

type shader_binding_layout = {
  name : string;
  index : int64;
  access : shader_binding_access;
  kind : shader_binding_layout_kind;
  data_type : shader_data_type option;
}

type function_kind =
  | Vertex
  | Fragment
  | Kernel
  | Visible
  | Intersection
  | Mesh
  | Object
  | Unknown_function_kind of int

type function_constant_value =
  | Bool_constant of bool
  | Int8_constant of int
  | Uint8_constant of int
  | Int16_constant of int
  | Uint16_constant of int
  | Int32_constant of int32
  | Uint32_constant of int64
  | Int64_constant of int64
  | Uint64_bits_constant of int64
  | Float16_constant of float
  | Float32_constant of float

type function_constant = {
  name : string;
  data_type : shader_data_type;
  index : int64;
  required : bool;
}

type library_kind = Executable_library | Dynamic_library_source | Unknown_library_kind of int
type pixel_format = Metal_format.t
type resource_cpu_cache_mode = Default_cache | Write_combined
type resource_hazard_tracking_mode = Default_hazard_tracking | Untracked | Tracked
type purgeable_state = Nonvolatile | Volatile | Empty
type sparse_page_size = Page_16_kib | Page_64_kib | Page_256_kib
type resource_state = { relinquished : bool Atomic.t; purgeable : purgeable_state Atomic.t }

type texture_usage =
  | Shader_read
  | Shader_write
  | Render_target
  | Pixel_format_view
  | Shader_atomic

type texture_compression_type = Lossless | Lossy
type texture_swizzle_channel = Zero | One | Red | Green | Blue | Alpha

type texture_swizzle = {
  red : texture_swizzle_channel;
  green : texture_swizzle_channel;
  blue : texture_swizzle_channel;
  alpha : texture_swizzle_channel;
}

type texture_descriptor = {
  kind : texture_kind;
  format : pixel_format;
  width : int;
  height : int;
  depth : int;
  mip_levels : int;
  sample_count : int;
  array_length : int;
  storage : buffer_storage_mode;
  cpu_cache : resource_cpu_cache_mode;
  hazard_tracking : resource_hazard_tracking_mode;
  usage : texture_usage list;
  allow_gpu_optimized_contents : bool;
  compression : texture_compression_type;
  swizzle : texture_swizzle;
  label : string option;
}

type heap_kind = Automatic | Placement | Sparse

type heap_descriptor = {
  size : int64;
  storage : buffer_storage_mode;
  cpu_cache : resource_cpu_cache_mode;
  hazard_tracking : resource_hazard_tracking_mode;
  kind : heap_kind;
  sparse_page_size : sparse_page_size option;
  label : string option;
}

type heap_allocation = { offset : int64; size : int64; active : bool Atomic.t }

type metal_layer_edr_metadata =
  | Standard
  | Hlg
  | Hdr10 of { minimum_luminance : float; maximum_luminance : float; optical_output_scale : float }

type heap = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  descriptor : heap_descriptor;
  allocations : heap_allocation list ref;
  purgeable : purgeable_state Atomic.t;
  active_uses : int Atomic.t;
}

and fence = { raw : Metal_raw.handle; lifetime : lifetime; device : device }

and metal_layer = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  mutable layer_width : int;
  mutable layer_height : int;
  mutable layer_format : pixel_format;
  mutable framebuffer_only : bool;
  mutable maximum_drawables : int;
  mutable allows_timeout : bool;
  mutable display_sync : bool;
  mutable presents_with_transaction : bool;

  mutable drawable_descriptor : texture_descriptor option;
}

and metal_drawable = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  layer : metal_layer;
  mutable drawable_texture : texture option;

  mutable presentation_scheduled : bool;
}

and render_pass_descriptor = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  pass_width : int;
  pass_height : int;
  pass_array_length : int;
  pass_sample_count : int;
  mutable pass_color : texture option;
  mutable pass_depth : texture option;
  mutable pass_stencil : texture option;
  mutable pass_visibility : buffer option;
  mutable pass_resolve : texture option;
  pass_samples : render_pass_sample_state option array;
}

and render_pass_sample_state = { sample_buffer : resource100_sample_buffer }

and resource100_sample_buffer = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  sample_count : int64;

}

and resource_parent =
  | Device_resource of device
  | Heap_resource of heap

and buffer = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  length : int64;
  storage : buffer_storage_mode;

  parent : resource_parent;

  placement_sparse_page_size : sparse_page_size option;
  allocation : heap_allocation option;
  state : resource_state;

}

and acceleration_structure = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  size : int64;
  heap : heap option;
  allocation : heap_allocation option;
}

and texture = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  descriptor : texture_descriptor;
  parent : texture_parent;
  heap_offset : int64 option;
  placement_sparse_page_size : sparse_page_size option;
  allocation : heap_allocation option;
  state : resource_state;
}

and buffer_texture_backing = { buffer : buffer; offset : int64; bytes_per_row : int }
and texture_parent =
  | Texture_resource of resource_parent
  | Texture_drawable_resource of metal_drawable

  | Texture_view of texture


type sampler_filter = Nearest | Linear
type sampler_mip_filter = Not_mipmapped | Mip_nearest | Mip_linear

type sampler_address_mode =
  | Clamp_to_edge
  | Mirror_clamp_to_edge
  | Repeat
  | Mirror_repeat
  | Clamp_to_zero
  | Clamp_to_border_color

type sampler_border_color = Transparent_black | Opaque_black | Opaque_white
type sampler_reduction_mode = Weighted_average | Minimum | Maximum

type sampler_compare_function =
  | Never
  | Less
  | Equal
  | Less_equal
  | Greater
  | Not_equal
  | Greater_equal
  | Always

type stencil_operation =
  | Keep
  | Zero
  | Replace
  | Increment_clamp
  | Decrement_clamp
  | Invert
  | Increment_wrap
  | Decrement_wrap

type stencil_face = {
  compare : sampler_compare_function;
  stencil_fail : stencil_operation;
  depth_fail : stencil_operation;
  pass : stencil_operation;
  read_mask : int32;
  write_mask : int32;
}

type sampler_descriptor = {
  min_filter : sampler_filter;
  mag_filter : sampler_filter;
  mip_filter : sampler_mip_filter;
  max_anisotropy : int;
  s_address : sampler_address_mode;
  t_address : sampler_address_mode;
  r_address : sampler_address_mode;
  border_color : sampler_border_color;
  reduction_mode : sampler_reduction_mode;
  normalized_coordinates : bool;
  lod_min_clamp : float;
  lod_max_clamp : float;
  lod_average : bool;
  lod_bias : float;
  compare_function : sampler_compare_function;
  support_argument_buffers : bool;
  label : string option;
}

type sampler = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;

}

type depth_stencil = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;

}

type library = { raw : Metal_raw.handle; lifetime : lifetime; device : device }
type function_handle = { raw : Metal_raw.handle; lifetime : lifetime; library : library }

type linked_functions = {

  lifetime : lifetime;

}

type shader_argument_encoder = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  function_ : function_handle option;

  device : device;

  encoded_length : int64;
  alignment : int64;
  retained : (int64, lifetime) Hashtbl.t;
  parent_encoder : shader_argument_encoder option;
}

type dynamic_library = { raw : Metal_raw.handle; lifetime : lifetime; device : device }

type binary_archive = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  archive_edges : lifetime list ref;
}

type pipeline_dataset = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;

}

type pipeline_archive = { raw : Metal_raw.handle; lifetime : lifetime; device : device }

type binary_function = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;

  name : string;

}

type binary_functions_descriptor = {

  descriptor_device : device option;

} [@@warning "-69"]

type compiler = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  dataset : pipeline_dataset option;
}

type compute_pipeline = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  bindings : shader_binding array option;

  max_total_threads : int;
}

type linked_function_handle = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  pipeline : compute_pipeline;
  function_ : function_handle;
}

type visible_function_table = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  pipeline : compute_pipeline;
  capacity : int;
  functions : linked_function_handle option array;
}

type intersection_function_table = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  pipeline : compute_pipeline;
  capacity : int;
  functions : linked_function_handle option array;
  buffers : buffer option array;
  visible_tables : visible_function_table option array;
}

type render_pipeline_kind = Render | Tile | Mesh
type render_color_attachment_mapping = Identity | Inherited
type render_blend_state = Blend_disabled | Blend_enabled

type render_blend_factor =
  | Blend_zero
  | Blend_one
  | Blend_source_color
  | Blend_one_minus_source_color
  | Blend_source_alpha
  | Blend_one_minus_source_alpha
  | Blend_destination_color
  | Blend_one_minus_destination_color
  | Blend_destination_alpha
  | Blend_one_minus_destination_alpha
  | Blend_source_alpha_saturated
  | Blend_color
  | Blend_one_minus_color
  | Blend_alpha
  | Blend_one_minus_alpha
  | Blend_source1_color
  | Blend_one_minus_source1_color
  | Blend_source1_alpha
  | Blend_one_minus_source1_alpha

type render_blend_operation =
  | Blend_add
  | Blend_subtract
  | Blend_reverse_subtract
  | Blend_min
  | Blend_max

type render_color_write = Write_red | Write_green | Write_blue | Write_alpha

type render_color_attachment = {
  format : pixel_format;
  blending : render_blend_state;
  source_rgb : render_blend_factor;
  destination_rgb : render_blend_factor;
  rgb_operation : render_blend_operation;
  source_alpha : render_blend_factor;
  destination_alpha : render_blend_factor;
  alpha_operation : render_blend_operation;
  write_mask : render_color_write list;
}

type render_pipeline_reflection = {
  vertex_bindings : shader_binding array;
  fragment_bindings : shader_binding array;
  tile_bindings : shader_binding array;
  object_bindings : shader_binding array;
  mesh_bindings : shader_binding array;
}

type mesh_pipeline_constraints = {
  has_object_stage : bool;
  required_object_threads : (int * int * int) option;
  required_mesh_threads : (int * int * int) option;
}

type tile_pipeline_constraints = {
  required_tile_threads : (int * int * int) option;
}

type render_pipeline = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  kind : render_pipeline_kind;
  raster_sample_count : int;

  color_formats : pixel_format list;
  color_attachments : render_color_attachment list;

  reflection : render_pipeline_reflection option;
  mesh_constraints : mesh_pipeline_constraints option;
  tile_constraints : tile_pipeline_constraints option;
}

type residency_allocation = Buffer of buffer | Texture of texture | Heap of heap
type residency_member = { allocation : residency_allocation; mutable present : bool }
type residency_descriptor = { label : string option; initial_capacity : int }

type residency_set = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  members : (int64, residency_member) Hashtbl.t;
}

type command_queue = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  residency_sets : residency_set list ref;
}

type command_phase = Recording | Submitted | Failed

type indirect_command_kind =
  | Indirect_draw
  | Indirect_draw_indexed
  | Indirect_concurrent_dispatch
  | Indirect_concurrent_dispatch_threads

type indirect_command_buffer_descriptor = {
  command_types : indirect_command_kind list;
  inherit_buffers : bool;
  inherit_pipeline_state : bool;
  max_vertex_buffer_bind_count : int;
  max_fragment_buffer_bind_count : int;
  max_kernel_buffer_bind_count : int;
  support_ray_tracing : bool;
  support_dynamic_attribute_stride : bool;
  max_kernel_threadgroup_memory_bind_count : int;
  max_object_buffer_bind_count : int;
  max_mesh_buffer_bind_count : int;
  max_object_threadgroup_memory_bind_count : int;
  inherit_depth_stencil_state : bool;
  inherit_depth_bias : bool;
  inherit_depth_clip_mode : bool;
  inherit_cull_mode : bool;
  inherit_front_facing_winding : bool;
  inherit_triangle_fill_mode : bool;
  support_color_attachment_mapping : bool;
}

type indirect_retained =
  | Indirect_buffer of buffer

  | Indirect_render_pipeline of render_pipeline

type indirect_command_buffer = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  max_command_count : int;
  command_types : indirect_command_kind list;

  retained : indirect_retained list ref;
}

type indirect_command_buffer_handle = indirect_command_buffer

type indirect_render_command = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  parent : indirect_command_buffer;
}

type render_encoder_prepared_resources = {

  lifetime : lifetime;
  prepared_buffers : buffer array;
  prepared_textures : texture array;

}

type prepared_command_resources = {
  prepared_pipeline_roots : render_pipeline array;
  prepared_buffer_roots : buffer array;
  prepared_texture_roots : texture array;
  prepared_depth_stencil_roots : depth_stencil array;
  prepared_sample_roots : resource100_sample_buffer array;
  prepared_indirect_roots : indirect_command_buffer array;
  prepared_resource_roots : render_encoder_prepared_resources array;
}

let empty_prepared_command_resources =
  {
    prepared_pipeline_roots = [||];
    prepared_buffer_roots = [||];
    prepared_texture_roots = [||];
    prepared_depth_stencil_roots = [||];
    prepared_sample_roots = [||];
    prepared_indirect_roots = [||];
    prepared_resource_roots = [||];
  }

type command_resource =
  | Command_buffer_buffer of buffer

  | Command_buffer_acceleration_structure of acceleration_structure
  | Command_buffer_texture of texture
  | Command_buffer_sampler of sampler
  | Command_buffer_depth_stencil of depth_stencil
  | Command_buffer_visible_table of visible_function_table
  | Command_buffer_intersection_table of intersection_function_table
  | Command_buffer_render_pipeline of render_pipeline
  | Command_residency_set of residency_set
  | Command_buffer_indirect of indirect_command_buffer
  | Command_buffer_fence of fence
  | Command_buffer_heap of heap
  | Command_buffer_drawable of metal_drawable
  | Command_buffer_prepared_command of prepared_command_resources

type prepared_resource_slot = {
  mutable prepared_active : bool;
  prepared_lifetime : lifetime;
}

type prepared_command_slot = {
  mutable prepared_command_active : bool;
  mutable prepared_command : prepared_command_resources;
}

type command_buffer = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  queue : command_queue;

  mutable phase : command_phase;
  resources : command_resource list ref;
  (* Lifetime identities already in [resources]: dedup in O(1) per bind. *)
  retained_identities : (int, unit) Hashtbl.t;
  prepared_resource : prepared_resource_slot option;
  prepared_command_slot : prepared_command_slot;
  mutable scoped_prepared_active : bool;
  scoped_prepared_lifetime : lifetime;
  callback_tokens : nativeint list ref;
  presentation_events : lifetime list ref;

}

type compute_encoder = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  command_buffer : command_buffer;
  mutable pipeline : compute_pipeline option;
}

type render_encoder = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  command_buffer : command_buffer;
  target : texture;

  mutable pipeline : render_pipeline option;
}

type resource_state_encoder = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  command_buffer : command_buffer;
}

type counter_sample_buffer = resource100_sample_buffer

type blit_pass_descriptor = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;
  mutable blit_attachments : blit_pass_attachment_array option;
}

and blit_pass_attachment_array = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  parent : blit_pass_descriptor;
  slots : blit_pass_attachment option array;
}

and blit_pass_attachment = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  parent : blit_pass_attachment_array;
  index : int;
  mutable blit_sample_buffer : counter_sample_buffer option;

}

type compute_pass_descriptor = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  device : device;

  compute_attachments : (resource100_sample_buffer * int64 * int64) option array;
}

type resource100_tensor = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  buffer : buffer;

  dimensions : int64 array;

  data_type : Data_type.t;
} [@@warning "-69"]

type blit_encoder = { raw : Metal_raw.handle; lifetime : lifetime; command_buffer : command_buffer }

type acceleration_encoder = {
  raw : Metal_raw.handle;
  lifetime : lifetime;
  command_buffer : command_buffer;
}

(* MTLCommandBufferStatus, or -1 when Metal cannot report it *)
let command_buffer_status raw =
  match Metal_raw.Registry.command_buffer_status raw with Ok status -> Int64.to_int status | Error _ -> -1

let make_device raw =
  match Metal_raw.Registry.device_registry_id raw with
  | Ok registry_id -> Ok ({ raw; lifetime = lifetime (); registry_id } : device)
  | Error message -> native_error "Metal.Device.system_default" message

let attach_finalizer ?(on_finalize = fun () -> ()) value lifetime parent =
  Gc.finalise (fun _ -> finalize_child lifetime parent on_finalize) value

let attach_lifetime_finalizer ?(on_finalize = fun () -> ()) lifetime parent =
  Gc.finalise (fun lifetime -> finalize_child lifetime parent on_finalize) lifetime

let command_resource_lifetime = function
  | Command_buffer_buffer buffer -> buffer.lifetime

  | Command_buffer_acceleration_structure value -> value.lifetime
  | Command_buffer_texture texture -> texture.lifetime
  | Command_buffer_sampler sampler -> sampler.lifetime
  | Command_buffer_depth_stencil value -> value.lifetime
  | Command_buffer_visible_table value -> value.lifetime
  | Command_buffer_intersection_table value -> value.lifetime
  | Command_buffer_render_pipeline pipeline -> pipeline.lifetime
  | Command_residency_set residency_set -> residency_set.lifetime
  | Command_buffer_indirect value -> value.lifetime
  | Command_buffer_fence value -> value.lifetime
  | Command_buffer_heap value -> value.lifetime
  | Command_buffer_drawable value -> value.lifetime
  | Command_buffer_prepared_command _ ->
      invalid_arg "prepared command has multiple resource lifetimes"

let rec command_texture_heap (value : texture) =
  match value.parent with
  | Texture_resource (Heap_resource heap) -> Some heap
  | Texture_resource (Device_resource _ )  ->
      None
  | Texture_drawable_resource _ -> None

  | Texture_view parent -> command_texture_heap parent

let command_resource_heap = function
  | Command_buffer_buffer { parent = Heap_resource heap; _ } -> Some heap
  | Command_buffer_buffer { parent = Device_resource _ ; _ } -> None

  | Command_buffer_acceleration_structure _ -> None
  | Command_buffer_texture texture -> command_texture_heap texture
  | Command_buffer_sampler _ -> None
  | Command_buffer_depth_stencil _ | Command_buffer_visible_table _
  | Command_buffer_intersection_table _ ->
      None
  | Command_buffer_render_pipeline _ | Command_residency_set _ | Command_buffer_indirect _
  | Command_buffer_fence _ ->
      None
  | Command_buffer_heap heap -> Some heap
  | Command_buffer_drawable _ -> None
  | Command_buffer_prepared_command _ -> None

let release_prepared_command_resources prepared =
  for index = 0 to Array.length prepared.prepared_pipeline_roots - 1 do
    detach (Array.unsafe_get prepared.prepared_pipeline_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_buffer_roots - 1 do
    let buffer = Array.unsafe_get prepared.prepared_buffer_roots index in
    detach buffer.lifetime;
    match buffer.parent with
    | Device_resource _  -> ()
    | Heap_resource heap -> Atomic.decr heap.active_uses
  done;
  for index = 0 to Array.length prepared.prepared_texture_roots - 1 do
    let texture = Array.unsafe_get prepared.prepared_texture_roots index in
    detach texture.lifetime;
    Option.iter (fun heap -> Atomic.decr heap.active_uses) (command_texture_heap texture)
  done;
  for index = 0 to Array.length prepared.prepared_depth_stencil_roots - 1 do
    detach (Array.unsafe_get prepared.prepared_depth_stencil_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_sample_roots - 1 do
    detach (Array.unsafe_get prepared.prepared_sample_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_indirect_roots - 1 do
    detach (Array.unsafe_get prepared.prepared_indirect_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_resource_roots - 1 do
    let resources = Array.unsafe_get prepared.prepared_resource_roots index in
    for buffer_index = 0 to Array.length resources.prepared_buffers - 1 do
      match (Array.unsafe_get resources.prepared_buffers buffer_index).parent with
      | Device_resource _  -> ()
      | Heap_resource heap -> Atomic.decr heap.active_uses
    done;
    for texture_index = 0 to Array.length resources.prepared_textures - 1 do
      Option.iter
        (fun heap -> Atomic.decr heap.active_uses)
        (command_texture_heap (Array.unsafe_get resources.prepared_textures texture_index))
    done;
    detach resources.lifetime
  done

let release_command_resources resources identities =
  let retained = !resources in
  resources := [];
  Hashtbl.reset identities;
  List.iter
    (function
      | Command_buffer_prepared_command prepared -> release_prepared_command_resources prepared
      | resource ->
          detach (command_resource_lifetime resource);
          Option.iter (fun heap -> Atomic.decr heap.active_uses) (command_resource_heap resource))
    retained

let release_prepared_resource slot =
  if slot.prepared_active then begin
    slot.prepared_active <- false;
    detach slot.prepared_lifetime
  end

let release_prepared_command_slot slot =
  if slot.prepared_command_active then begin
    let prepared = slot.prepared_command in
    slot.prepared_command_active <- false;
    slot.prepared_command <- empty_prepared_command_resources;
    release_prepared_command_resources prepared
  end

let release_finalized_command_buffer_resources resources identities prepared_resource
    prepared_command_slot =
  release_command_resources resources identities;
  release_prepared_resource prepared_resource;
  release_prepared_command_slot prepared_command_slot

let release_command_buffer_resources command_buffer =
  release_command_resources command_buffer.resources command_buffer.retained_identities;
  (match command_buffer.prepared_resource with
  | Some slot -> release_prepared_resource slot
  | None when command_buffer.scoped_prepared_active ->
      command_buffer.scoped_prepared_active <- false;
      detach command_buffer.scoped_prepared_lifetime
  | None -> ());
  release_prepared_command_slot command_buffer.prepared_command_slot

(* True when [lifetime] is already retained by this command buffer; otherwise
   records it and returns false. Every retain below goes through this table, so
   binding the same resources in thousands of draws costs O(1) each instead of
   rescanning the retained list. *)
let already_retained (command_buffer : command_buffer) (lifetime : lifetime) =
  Hashtbl.mem command_buffer.retained_identities lifetime.identity
  || (Hashtbl.add command_buffer.retained_identities lifetime.identity (); false)

let retain_command_buffer_buffer (command_buffer : command_buffer) (buffer : buffer) =
  if not (already_retained command_buffer buffer.lifetime) then begin
    attach buffer.lifetime;
    Option.iter
      (fun heap -> Atomic.incr heap.active_uses)
      (match buffer.parent with
      | Device_resource _  -> None
      | Heap_resource heap -> Some heap);
    command_buffer.resources := Command_buffer_buffer buffer :: !(command_buffer.resources)
  end

let rec command_resources_retain_prepared_command prepared = function
  | [] -> false
  | Command_buffer_prepared_command candidate :: _ -> candidate == prepared
  | _ :: rest -> command_resources_retain_prepared_command prepared rest

let retain_prepared_command_resources prepared =
  for index = 0 to Array.length prepared.prepared_pipeline_roots - 1 do
    attach (Array.unsafe_get prepared.prepared_pipeline_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_buffer_roots - 1 do
    let buffer = Array.unsafe_get prepared.prepared_buffer_roots index in
    attach buffer.lifetime;
    match buffer.parent with
    | Device_resource _  -> ()
    | Heap_resource heap -> Atomic.incr heap.active_uses
  done;
  for index = 0 to Array.length prepared.prepared_texture_roots - 1 do
    let texture = Array.unsafe_get prepared.prepared_texture_roots index in
    attach texture.lifetime;
    Option.iter (fun heap -> Atomic.incr heap.active_uses) (command_texture_heap texture)
  done;
  for index = 0 to Array.length prepared.prepared_depth_stencil_roots - 1 do
    attach (Array.unsafe_get prepared.prepared_depth_stencil_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_sample_roots - 1 do
    attach (Array.unsafe_get prepared.prepared_sample_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_indirect_roots - 1 do
    attach (Array.unsafe_get prepared.prepared_indirect_roots index).lifetime
  done;
  for index = 0 to Array.length prepared.prepared_resource_roots - 1 do
    let resources = Array.unsafe_get prepared.prepared_resource_roots index in
    attach resources.lifetime;
    for buffer_index = 0 to Array.length resources.prepared_buffers - 1 do
      match (Array.unsafe_get resources.prepared_buffers buffer_index).parent with
      | Device_resource _  -> ()
      | Heap_resource heap -> Atomic.incr heap.active_uses
    done;
    for texture_index = 0 to Array.length resources.prepared_textures - 1 do
      Option.iter
        (fun heap -> Atomic.incr heap.active_uses)
        (command_texture_heap (Array.unsafe_get resources.prepared_textures texture_index))
    done
  done

let retain_command_buffer_prepared_command_overflow command_buffer prepared =
  if not (command_resources_retain_prepared_command prepared !(command_buffer.resources)) then begin
    retain_prepared_command_resources prepared;
    command_buffer.resources :=
      Command_buffer_prepared_command prepared :: !(command_buffer.resources)
  end

let retain_command_buffer_prepared_command command_buffer prepared =
  let primary = command_buffer.prepared_command_slot in
  if primary.prepared_command_active then
    begin if primary.prepared_command != prepared then
      retain_command_buffer_prepared_command_overflow command_buffer prepared
    end
  else begin
    retain_prepared_command_resources prepared;
    primary.prepared_command <- prepared;
    primary.prepared_command_active <- true
  end

let retain_command_buffer_acceleration_structure (command_buffer : command_buffer)
    (value : acceleration_structure) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources :=
      Command_buffer_acceleration_structure value :: !(command_buffer.resources)
  end

let retain_command_buffer_texture (command_buffer : command_buffer) (texture : texture) =
  if not (already_retained command_buffer texture.lifetime) then begin
    attach texture.lifetime;
    Option.iter (fun heap -> Atomic.incr heap.active_uses) (command_texture_heap texture);
    command_buffer.resources := Command_buffer_texture texture :: !(command_buffer.resources)
  end

let retain_command_buffer_sampler (command_buffer : command_buffer) (sampler : sampler) =
  if not (already_retained command_buffer sampler.lifetime) then begin
    attach sampler.lifetime;
    command_buffer.resources := Command_buffer_sampler sampler :: !(command_buffer.resources)
  end

let retain_command_buffer_depth_stencil command_buffer (value : depth_stencil) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources := Command_buffer_depth_stencil value :: !(command_buffer.resources)
  end

let retain_command_buffer_visible_table command_buffer (value : visible_function_table) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources := Command_buffer_visible_table value :: !(command_buffer.resources)
  end

let retain_command_buffer_intersection_table command_buffer (value : intersection_function_table) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources :=
      Command_buffer_intersection_table value :: !(command_buffer.resources)
  end

let retain_command_buffer_residency_set (command_buffer : command_buffer)
    (residency_set : residency_set) =
  if not (already_retained command_buffer residency_set.lifetime) then begin
    attach residency_set.lifetime;
    command_buffer.resources := Command_residency_set residency_set :: !(command_buffer.resources)
  end

let retain_command_buffer_indirect (command_buffer : command_buffer)
    (value : indirect_command_buffer) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources := Command_buffer_indirect value :: !(command_buffer.resources)
  end

let retain_command_buffer_render_pipeline (command_buffer : command_buffer)
    (pipeline : render_pipeline) =
  if not (already_retained command_buffer pipeline.lifetime) then begin
    attach pipeline.lifetime;
    command_buffer.resources :=
      Command_buffer_render_pipeline pipeline :: !(command_buffer.resources)
  end

let retain_command_buffer_fence (command_buffer : command_buffer) (value : fence) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources := Command_buffer_fence value :: !(command_buffer.resources)
  end

let retain_command_buffer_heap (command_buffer : command_buffer) (value : heap) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    Atomic.incr value.active_uses;
    command_buffer.resources := Command_buffer_heap value :: !(command_buffer.resources)
  end

let retain_command_buffer_drawable (command_buffer : command_buffer) (value : metal_drawable) =
  if not (already_retained command_buffer value.lifetime) then begin
    attach value.lifetime;
    command_buffer.resources := Command_buffer_drawable value :: !(command_buffer.resources)
  end

let release_queue_residency_sets residency_sets =
  let retained = !residency_sets in
  residency_sets := [];
  List.iter (fun (value : residency_set) -> detach value.lifetime) retained

let deactivate_allocation (value : heap_allocation option) =
  match value with None -> () | Some allocation -> Atomic.set allocation.active false

let resource_parent_lifetime = function
  | Device_resource device -> device.lifetime
  | Heap_resource heap -> heap.lifetime

let resource_parent_extra_device (_device : device) = function

  | Device_resource _ | Heap_resource _ -> None

let texture_parent_lifetime = function
  | Texture_resource parent -> resource_parent_lifetime parent
  | Texture_drawable_resource drawable -> drawable.lifetime

  | Texture_view texture -> texture.lifetime

let texture_parent_extra_device (device : device) = function
  | Texture_resource parent -> resource_parent_extra_device device parent

   | Texture_view _ | Texture_drawable_resource _ -> None

let resource_state () = { relinquished = Atomic.make false; purgeable = Atomic.make Nonvolatile }

let parent_heap = function
  | Device_resource _  -> None
  | Heap_resource heap -> Some heap

let rec texture_heap (value : texture) =
  match value.parent with
  | Texture_resource parent -> parent_heap parent

  | Texture_drawable_resource _ -> None
  | Texture_view parent -> texture_heap parent

let ensure_heap_nonvolatile operation = function
  | Some heap when Atomic.get heap.purgeable <> Nonvolatile ->
      error operation Invalid_state "resource heap must be nonvolatile"
  | None | Some _ -> Ok ()

let ensure_resource_usable operation state heap =
  if Atomic.get state.relinquished then
    error operation Invalid_state "resource has relinquished its storage for aliasing"
  else
    match Atomic.get state.purgeable with
    | Volatile ->
        error operation Invalid_state "resource is volatile and must be restored before access"
    | Empty ->
        error operation Invalid_state
          "resource contents are empty and must be restored before access"
    | Nonvolatile -> (
        match ensure_heap_nonvolatile operation heap with
        | Error _ as failure -> failure
        | Ok () -> Ok ())

let ensure_buffer_usable operation (value : buffer) =
  match ensure_live operation value.lifetime with
  | Error _ as failure -> failure
  | Ok () -> ensure_resource_usable operation value.state (parent_heap value.parent)

let ensure_texture_usable operation (value : texture) =
  match ensure_live operation value.lifetime with
  | Error _ as failure -> failure
  | Ok () -> ensure_resource_usable operation value.state (texture_heap value)

let same_device (left : device) (right : device) = Int64.equal left.registry_id right.registry_id

let ensure_same_device operation expected actual =
  if same_device expected actual then Ok ()
  else error operation Device_mismatch "resources belong to different Metal devices"

let storage_code = function Shared -> 0 | Managed -> 1 | Private -> 2
let cache_code = function Default_cache -> 0 | Write_combined -> 1
let hazard_code = function Default_hazard_tracking -> 0 | Untracked -> 1 | Tracked -> 2

let resource_options_code ~storage ~cpu_cache ~hazard_tracking =
  cache_code cpu_cache lor (storage_code storage lsl 4) lor (hazard_code hazard_tracking lsl 8)

let concrete_hazard_tracking ~heap = function
  | Default_hazard_tracking -> if heap then Untracked else Tracked
  | (Untracked | Tracked) as mode -> mode

let cache_mode_of_code operation = function
  | 0 -> Ok Default_cache
  | 1 -> Ok Write_combined
  | code -> native_error operation (Printf.sprintf "unknown CPU cache mode %d" code)

let hazard_mode_of_code operation = function
  | 0 -> Ok Default_hazard_tracking
  | 1 -> Ok Untracked
  | 2 -> Ok Tracked
  | code -> native_error operation (Printf.sprintf "unknown hazard tracking mode %d" code)

module Sparse_page_size = struct
  type t = sparse_page_size = Page_16_kib | Page_64_kib | Page_256_kib

  let bytes = function Page_16_kib -> 16_384L | Page_64_kib -> 65_536L | Page_256_kib -> 262_144L
end

let sparse_page_size_code = function Page_16_kib -> 101 | Page_64_kib -> 102 | Page_256_kib -> 103

module Shared_event = struct
  type t = command_shared_event

  let signaled_value (value : t) =
    let operation = "Metal.Shared_event.signaled_value" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.command_shared_event_value value.raw with
            | Error m -> native_error operation m
            | Ok x ->
                value.value <- x;
                Ok x))

  let set_signaled_value (value : t) next =
    let operation = "Metal.Shared_event.set_signaled_value" in
    if next < 0L then error operation Invalid_argument "shared-event value must be nonnegative"
    else
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () when next < value.value ->
              error operation Invalid_argument "shared-event value must not decrease"
          | Ok () -> (
              match Metal_raw.command_shared_event_set_value value.raw next with
              | Error m -> native_error operation m
              | Ok () ->
                  value.value <- next;
                  Ok ()))

  let wait_until_signaled (value : t) ~value:target ~timeout_ms =
    let operation = "Metal.Shared_event.wait_until_signaled" in
    if target < 0L || timeout_ms < 0L then
      error operation Invalid_argument "shared-event wait value and timeout must be nonnegative"
    else
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match Metal_raw.shared_event_wait value.raw target timeout_ms with
              | Error m -> native_error operation m
              | Ok reached ->
                  if reached && target > value.value then value.value <- target;
                  Ok reached))

  let destroy (value : t) =
    destroy_parent "Metal.Shared_event.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Device = struct
  type t = device
  type counter_sampling_point = Stage_boundary | Draw_boundary | Dispatch_boundary | Blit_boundary

  type capability_snapshot = {
    barycentric_coordinates : bool;
    max_threads : int64 * int64 * int64;
    maximize_concurrent_compilation : bool;
    bc_texture_compression : bool;
    counter_set_count : int;
  }

  let new_fence (value : t) =
    let operation = "Metal.Device.new_fence" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.device_create_fence value.raw with
            | Error message -> native_error operation message
            | Ok raw ->
                let fence : fence = { raw; lifetime = lifetime (); device = value } in
                attach value.lifetime;
                attach_finalizer fence fence.lifetime value.lifetime;
                Ok fence))

  let new_shared_event (value : t) =
    let operation = "Metal.Device.new_shared_event" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.command_shared_event_create value.raw with
            | Error m -> native_error operation m
            | Ok (raw, registry_id) when registry_id <> value.registry_id ->
                ignore (Metal_raw.destroy raw);
                error operation Device_mismatch
                  "shared-event constructor returned another device identity"
            | Ok (raw, registry_id) -> (
                match Metal_raw.command_shared_event_value raw with
                | Error m ->
                    ignore (Metal_raw.destroy raw);
                    native_error operation m
                | Ok current ->
                    let event : command_shared_event =
                      { raw; lifetime = lifetime (); device = value; registry_id; value = current }
                    in
                    attach value.lifetime;
                    attach_finalizer event event.lifetime value.lifetime;
                    Ok event)))

  type family =
    | Apple1
    | Apple2
    | Apple3
    | Apple4
    | Apple5
    | Apple6
    | Apple7
    | Apple8
    | Apple9
    | Apple10
    | Mac2
    | Common1
    | Common2
    | Common3
    | Metal3
    | Metal4

  type info = {
    name : string;
    registry_id : int64;
    low_power : bool;
    removable : bool;
    headless : bool;
    unified_memory : bool;
    recommended_max_working_set_size : int64;
    current_allocated_size : int64;
    max_buffer_length : int64;
    max_threadgroup_memory_length : int64;
    raytracing : bool;
    raytracing_from_render : bool;
    dynamic_libraries : bool;
    function_pointers : bool;
  }

  let system_default () =
    on_main "Metal.Device.system_default" (fun () ->
        match Metal_raw.default_device () with
        | Ok raw -> make_device raw
        | Error message -> native_error "Metal.Device.system_default" message)

  let same = same_device

  let info (value : t) =
    let operation = "Metal.Device.info" in
    on_main operation (fun () ->
        let ( let* ) value callback = Result.bind value callback in
        let* () = ensure_live operation value.lifetime in
        let* max_threadgroup_memory_length = native operation (Metal_raw.Registry.device_max_threadgroup_memory_length value.raw) in
        let* name = native operation (Metal_raw.Registry.device_name value.raw) in
        let* low_power = native operation (Metal_raw.Registry.device_is_low_power value.raw) in
        let* removable = native operation (Metal_raw.Registry.device_is_removable value.raw) in
        let* headless = native operation (Metal_raw.Registry.device_is_headless value.raw) in
        let* unified_memory = native operation (Metal_raw.Registry.device_has_unified_memory value.raw) in
        let* recommended_max_working_set_size =
          native operation (Metal_raw.Registry.device_recommended_max_working_set_size value.raw) in
        let* current_allocated_size = native operation (Metal_raw.Registry.device_current_allocated_size value.raw) in
        let* max_buffer_length = native operation (Metal_raw.Registry.device_max_buffer_length value.raw) in
        let* raytracing = native operation (Metal_raw.Registry.device_supports_raytracing value.raw) in
        let* raytracing_from_render = native operation (Metal_raw.Registry.device_supports_raytracing_from_render value.raw) in
        let* dynamic_libraries = native operation (Metal_raw.Registry.device_supports_dynamic_libraries value.raw) in
        let* function_pointers = native operation (Metal_raw.Registry.device_supports_function_pointers value.raw) in
        Ok
          {
            name = (if name = "" then "Unnamed Metal device" else name);
            registry_id = value.registry_id;
            low_power;
            removable;
            headless;
            unified_memory;
            recommended_max_working_set_size;
            current_allocated_size;
            max_buffer_length;
            max_threadgroup_memory_length;
            raytracing;
            raytracing_from_render;
            dynamic_libraries;
            function_pointers;
          })

  let family_code = function
    | Apple1 -> 1001
    | Apple2 -> 1002
    | Apple3 -> 1003
    | Apple4 -> 1004
    | Apple5 -> 1005
    | Apple6 -> 1006
    | Apple7 -> 1007
    | Apple8 -> 1008
    | Apple9 -> 1009
    | Apple10 -> 1010
    | Mac2 -> 2002
    | Common1 -> 3001
    | Common2 -> 3002
    | Common3 -> 3003
    | Metal3 -> 5001
    | Metal4 -> 5002

  let supports_family (value : t) family =
    on_main "Metal.Device.supports_family" (fun () ->
        match ensure_live "Metal.Device.supports_family" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.device_supports_family value.raw (Int64.of_int (family_code family)) with
            | Error message -> native_error "Metal.Device.supports_family" message
            | Ok supported -> Ok supported))

  let supports_texture_sample_count (value : t) sample_count =
    on_main "Metal.Device.supports_texture_sample_count" (fun () ->
        match ensure_live "Metal.Device.supports_texture_sample_count" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when sample_count <= 0 ->
            error "Metal.Device.supports_texture_sample_count" Invalid_argument
              "texture sample count must be positive"
        | Ok () -> native "Metal.Device.supports_texture_sample_count"
              (Metal_raw.Registry.device_supports_texture_sample_count value.raw (Int64.of_int sample_count)))

  let supports_residency_sets (value : t) =
    on_main "Metal.Device.supports_residency_sets" (fun () ->
        match ensure_live "Metal.Device.supports_residency_sets" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> Ok (Metal_raw.device_supports_residency_sets value.raw))

  let supports_sparse_textures (value : t) =
    on_main "Metal.Device.supports_sparse_textures" (fun () ->
        match ensure_live "Metal.Device.supports_sparse_textures" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> Ok (Metal_raw.device_supports_sparse_textures value.raw))

  type sparse_region = {
    x : int64;
    y : int64;
    z : int64;
    width : int64;
    height : int64;
    depth : int64;
  }

  type sparse_alignment = Outward | Inward

  let sample_timestamps (value : t) =
    let operation = "Metal.Device.sample_timestamps" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.device_sample_timestamps value.raw with
            | Error m -> native_error operation m
            | Ok (cpu, gpu) when cpu < 0L || gpu < 0L ->
                native_error operation "Metal returned a negative timestamp"
            | Ok pair -> Ok pair))

  let timestamp_frequency (value : t) =
    let operation = "Metal.Device.timestamp_frequency" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.device_timestamp_frequency value.raw with
            | Error m -> error operation Unsupported m
            | Ok n when n <= 0L ->
                native_error operation "Metal returned a zero timestamp frequency"
            | Ok n -> Ok n))

  let destroy (value : t) =
    destroy_parent "Metal.Device.destroy" value.lifetime value.raw (fun () -> ())
end

module Buffer = struct
  type t = buffer
  type storage_mode = buffer_storage_mode = Shared | Managed | Private
  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined

  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type sparse_tier = Not_sparse | Sparse_tier_1

  let validate_create operation (device : Device.t) ~length ~label =
    if length <= 0L then error operation Invalid_argument "buffer length must be positive"
    else if (match Metal_raw.Registry.device_max_buffer_length device.raw with Ok limit -> length > limit | Error _ -> true) then
      error operation Invalid_argument "buffer length exceeds the device limit"
    else if option_exists contains_nul label then
      error operation Invalid_argument "label contains a NUL byte"
    else Ok ()

  let finish_create ?placement_sparse_page_size operation ~(device : Device.t) ~parent ~length
      ~storage ~cpu_cache ~hazard_tracking ~heap_offset ~allocation ~label raw =
    let actual_length, actual_storage, actual_cache, actual_hazard, actual_offset =
      Metal_raw.buffer_info raw
    in
    let expected_hazard =
      concrete_hazard_tracking
        ~heap:
          (match parent with
          | Heap_resource _ -> true
          | Device_resource _  -> false)
        hazard_tracking
    in
    if
      actual_length <> length
      || actual_storage <> storage_code storage
      || actual_cache <> cache_code cpu_cache
      || actual_hazard <> hazard_code expected_hazard
      || option_exists (fun expected -> expected <> actual_offset) heap_offset
    then begin
      ignore (Metal_raw.destroy raw);
      native_error operation "Metal changed checked buffer properties during creation"
    end
    else
      let label_result =
        match label with None -> Ok () | Some label -> Metal_raw.buffer_set_label raw label
      in
      match label_result with
      | Error message ->
          ignore (Metal_raw.destroy raw);
          native_error operation message
      | Ok () ->
          let parent_lifetime = resource_parent_lifetime parent in
          let value : t =
            {
              raw;
              lifetime = lifetime ();
              device;
              length;
              storage;

              parent;

              placement_sparse_page_size;
              allocation;
              state = resource_state ();

            }
          in
          attach parent_lifetime;
          let extra_device = resource_parent_extra_device device parent in
          Option.iter attach extra_device;
          attach_finalizer
            ~on_finalize:(fun () ->
              deactivate_allocation allocation;
              Option.iter detach extra_device)
            value value.lifetime parent_lifetime;
          Ok value

  let create ~(device : Device.t) ~length ~storage ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?label () =
    on_main "Metal.Buffer.create" (fun () ->
        match ensure_live "Metal.Buffer.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_create "Metal.Buffer.create" device ~length ~label with
            | Error _ as failure -> failure
            | Ok () -> (
                let options = resource_options_code ~storage ~cpu_cache ~hazard_tracking in
                match Metal_raw.buffer_create device.raw length options with
                | Error message -> native_error "Metal.Buffer.create" message
                | Ok raw ->
                    finish_create "Metal.Buffer.create" ~device ~parent:(Device_resource device)
                      ~length ~storage ~cpu_cache ~hazard_tracking ~heap_offset:None
                      ~allocation:None ~label raw)))

  let length (value : t) = value.length

  let validate_range operation ~total ~offset ~length =
    if offset < 0L || length < 0 then error operation Invalid_argument "range is negative"
    else
      let length64 = Int64.of_int length in
      if offset > total || length64 > Int64.sub total offset then
        error operation Invalid_argument "range exceeds the buffer"
      else Ok ()

  let write_bytes (value : t) ?(src_offset = 0) ~dst_offset bytes =
    on_main "Metal.Buffer.write_bytes" (fun () ->
        match ensure_buffer_usable "Metal.Buffer.write_bytes" value with
        | Error _ as failure -> failure
        | Ok () when Option.is_some value.placement_sparse_page_size ->
            error "Metal.Buffer.write_bytes" Invalid_state
              "placement sparse buffers have no CPU-visible backing until mapped"
        | Ok () when value.storage = Private ->
            error "Metal.Buffer.write_bytes" Unsupported "private buffers have no CPU mapping"
        | Ok () -> (
            let source_length = Bytes.length bytes in
            if src_offset < 0 || src_offset > source_length then
              error "Metal.Buffer.write_bytes" Invalid_argument
                "source offset is outside the byte buffer"
            else
              let length = source_length - src_offset in
              match
                validate_range "Metal.Buffer.write_bytes" ~total:value.length ~offset:dst_offset
                  ~length
              with
              | Error _ as failure -> failure
              | Ok () -> (
                  match Metal_raw.buffer_write value.raw dst_offset bytes src_offset length with
                  | Ok () -> Ok ()
                  | Error message -> native_error "Metal.Buffer.write_bytes" message)))

  let read_bytes (value : t) ~offset ~length =
    on_main "Metal.Buffer.read_bytes" (fun () ->
        match ensure_buffer_usable "Metal.Buffer.read_bytes" value with
        | Error _ as failure -> failure
        | Ok () when Option.is_some value.placement_sparse_page_size ->
            error "Metal.Buffer.read_bytes" Invalid_state
              "placement sparse buffers have no CPU-visible backing until mapped"
        | Ok () when value.storage = Private ->
            error "Metal.Buffer.read_bytes" Unsupported "private buffers have no CPU mapping"
        | Ok () when length > Sys.max_string_length ->
            error "Metal.Buffer.read_bytes" Invalid_argument
              "read length exceeds the maximum OCaml byte-buffer size"
        | Ok () -> (
            match validate_range "Metal.Buffer.read_bytes" ~total:value.length ~offset ~length with
            | Error _ as failure -> failure
            | Ok () -> (
                match Metal_raw.buffer_read value.raw offset length with
                | Ok bytes -> Ok bytes
                | Error message -> native_error "Metal.Buffer.read_bytes" message)))

  let make_aliasable (value : t) =
    on_main "Metal.Buffer.make_aliasable" (fun () ->
        match ensure_live "Metal.Buffer.make_aliasable" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Option.is_some value.placement_sparse_page_size ->
            error "Metal.Buffer.make_aliasable" Invalid_state
              "placement sparse aliasing is controlled by mapping operations"
        | Ok () when Atomic.get value.state.relinquished -> Ok ()
        | Ok () when Atomic.get value.state.purgeable <> Nonvolatile ->
            error "Metal.Buffer.make_aliasable" Invalid_state
              "buffer must be nonvolatile before becoming aliasable"
        | Ok () when dependent_count value.lifetime <> 0 ->
            error "Metal.Buffer.make_aliasable" Parent_has_dependents
              "buffer has an active mapping, texture, or command dependency"
        | Ok () -> (
            match value.parent with
            | Device_resource _ ->
                error "Metal.Buffer.make_aliasable" Invalid_state
                  "only heap-backed buffers can become aliasable"

            | Heap_resource heap -> (
                match ensure_heap_nonvolatile "Metal.Buffer.make_aliasable" (Some heap) with
                | Error _ as failure -> failure
                | Ok () -> (
                    match Metal_raw.resource_make_aliasable value.raw with
                    | Error message -> native_error "Metal.Buffer.make_aliasable" message
                    | Ok () ->
                        if not (Metal_raw.resource_is_aliasable value.raw) then
                          native_error "Metal.Buffer.make_aliasable"
                            "Metal did not make the heap buffer aliasable"
                        else begin
                          Atomic.set value.state.relinquished true;
                          deactivate_allocation value.allocation;
                          Ok ()
                        end))))

  let destroy (value : t) =
    destroy_parent "Metal.Buffer.destroy" value.lifetime value.raw (fun () ->
        deactivate_allocation value.allocation;
        detach (resource_parent_lifetime value.parent);
        Option.iter detach (resource_parent_extra_device value.device value.parent))
end

module Acceleration_structure = struct
  type t = acceleration_structure
  type structure = t

  type sizes = {
    acceleration_structure_size : int64;
    build_scratch_buffer_size : int64;
    refit_scratch_buffer_size : int64;
  }

  (* Generic build descriptors (plan G5): triangles, bounding boxes, and
     curves, each static or keyframed, under one primitive descriptor; and
     instance descriptors of the default, user-id, or motion record kinds. *)
  module Build = struct
    type keyframe = { buffer : buffer; offset : int64 }
    type border = Clamp | Vanish
    type motion =
      { keyframe_count : int; start_time : float; end_time : float
      ; start_border : border; end_border : border }
    type index = { index_buffer : buffer; index_offset : int64; index_uint16 : bool }
    type common =
      { opaque : bool; allow_duplicate_intersection : bool
      ; intersection_function_table_offset : int }
    let default_common =
      { opaque = true; allow_duplicate_intersection = false
      ; intersection_function_table_offset = 0 }
    type curve_type = Round | Flat
    type curve_basis = Bspline | Catmull_rom | Linear | Bezier
    type end_caps = No_caps | Disk | Sphere
    type geometry =
      | Triangles of
          { vertices : keyframe list; vertex_stride : int64; triangle_count : int64
          ; index : index option; common : common }
      | Bounding_boxes of
          { boxes : keyframe list; stride : int64; count : int64; common : common }
      | Curves of
          { control_points : keyframe list; control_stride : int64; control_point_count : int64
          ; radii : keyframe list; radius_stride : int64; index : index
          ; segment_count : int64; control_points_per_segment : int
          ; curve_type : curve_type; basis : curve_basis; end_caps : end_caps
          ; common : common }
    type usage = Refit | Prefer_fast_build
    type instance_kind = Default_instances | User_id_instances | Motion_instances
    type instance_layout =
      { size : int; transform : int; options : int; mask : int; table_offset : int
      ; structure_index : int; user_id : int; transforms_start : int; transforms_count : int
      ; start_border_offset : int; end_border_offset : int; start_time_offset : int
      ; end_time_offset : int }
    type t =
      { raw : Metal_raw.handle; lifetime : lifetime; device : device; buffers : buffer list
      ; structures : structure list;  kind : instance_kind option }

    let kind_code = function
      | Default_instances -> 0
      | User_id_instances -> 1
      | Motion_instances -> 2

    let instance_layout kind =
      let layout = Metal_raw.accel_instance_layout (kind_code kind) in
      { size = layout.(0); transform = layout.(1); options = layout.(2); mask = layout.(3)
      ; table_offset = layout.(4); structure_index = layout.(5); user_id = layout.(6)
      ; transforms_start = layout.(7); transforms_count = layout.(8)
      ; start_border_offset = layout.(9); end_border_offset = layout.(10)
      ; start_time_offset = layout.(11); end_time_offset = layout.(12) }

    let keyframe_raw (k : keyframe) : Metal_raw.accel_keyframe =
      { keyframe_buffer = k.buffer.raw; keyframe_offset = k.offset }

    let common_raw (c : common) = (c.opaque, c.allow_duplicate_intersection,
      Int64.of_int c.intersection_function_table_offset)

    (* The element at the last index of a strided range must fit its buffer. *)
    let range_fits (buffer : buffer) offset stride count element =
      offset >= 0L && stride >= element && element > 0L && count > 0L
      && offset <= buffer.length
      && Int64.sub count 1L <= Int64.div (Int64.sub (Int64.sub buffer.length offset) element) stride
      && element <= Int64.sub buffer.length offset

    let validate_keyframes operation (device : device) name keyframes ~motion ~check =
      let expected = match motion with None -> 1 | Some m -> m.keyframe_count in
      if List.length keyframes <> expected then
        error operation Invalid_argument
          (name ^ " keyframe count must match the descriptor's motion keyframes (or be one)")
      else
        let rec loop = function
          | [] -> Ok ()
          | (k : keyframe) :: rest -> (
              match ensure_buffer_usable operation k.buffer with
              | Error _ as e -> e
              | Ok () when not (same_device device k.buffer.device) ->
                  error operation Device_mismatch (name ^ " buffer belongs to another device")
              | Ok () when not (check k) ->
                  error operation Invalid_argument (name ^ " range exceeds its buffer")
              | Ok () -> loop rest)
        in
        loop keyframes

    let validate_index operation (device : device) = function
      | None -> Ok ()
      | Some (i : index) -> (
          match ensure_buffer_usable operation i.index_buffer with
          | Error _ as e -> e
          | Ok () when not (same_device device i.index_buffer.device) ->
              error operation Device_mismatch "index buffer belongs to another device"
          | Ok () when i.index_offset < 0L || i.index_offset > i.index_buffer.length ->
              error operation Invalid_argument "index offset exceeds its buffer"
          | Ok () -> Ok ())

    let geometry_raw (g : geometry) : Metal_raw.accel_geometry_raw =
      match g with
      | Triangles { vertices; vertex_stride; triangle_count; index; common } ->
          let opaque, allow_duplicate, table_offset = common_raw common in
          let first = List.hd vertices in
          Raw_triangles
            { vertex = first.buffer.raw; vertex_offset = first.offset; vertex_stride
            ; triangle_count
            ; index = Option.map (fun (i : index) -> i.index_buffer.raw) index
            ; index_offset = Option.fold ~none:0L ~some:(fun (i : index) -> i.index_offset) index
            ; index_uint16 = Option.fold ~none:false ~some:(fun (i : index) -> i.index_uint16) index
            ; keyframes = (match vertices with [ _ ] -> [||] | _ -> Array.of_list (List.map keyframe_raw vertices))
            ; opaque; allow_duplicate; table_offset }
      | Bounding_boxes { boxes; stride; count; common } ->
          let box_opaque, box_allow_duplicate, box_table_offset = common_raw common in
          let first = List.hd boxes in
          Raw_boxes
            { boxes = first.buffer.raw; box_offset = first.offset; box_stride = stride
            ; box_count = count
            ; box_keyframes = (match boxes with [ _ ] -> [||] | _ -> Array.of_list (List.map keyframe_raw boxes))
            ; box_opaque; box_allow_duplicate; box_table_offset }
      | Curves { control_points; control_stride; control_point_count; radii; radius_stride; index
               ; segment_count; control_points_per_segment; curve_type; basis; end_caps; common } ->
          let curve_opaque, curve_allow_duplicate, curve_table_offset = common_raw common in
          let control = List.hd control_points and radius = List.hd radii in
          let motion = match control_points with [ _ ] -> false | _ -> true in
          Raw_curves
            { control = control.buffer.raw; control_offset = control.offset; control_stride
            ; control_count = control_point_count
            ; radius = radius.buffer.raw; radius_offset = radius.offset; radius_stride
            ; curve_index = index.index_buffer.raw; curve_index_offset = index.index_offset
            ; curve_index_uint16 = index.index_uint16
            ; segment_count; segment_control_points = Int64.of_int control_points_per_segment
            ; curve_type = (match curve_type with Round -> 0 | Flat -> 1)
            ; curve_basis = (match basis with Bspline -> 0 | Catmull_rom -> 1 | Linear -> 2 | Bezier -> 3)
            ; end_caps = (match end_caps with No_caps -> 0 | Disk -> 1 | Sphere -> 2)
            ; control_keyframes = (if motion then Array.of_list (List.map keyframe_raw control_points) else [||])
            ; radius_keyframes = (if motion then Array.of_list (List.map keyframe_raw radii) else [||])
            ; curve_opaque; curve_allow_duplicate; curve_table_offset }

    let validate_geometry operation (device : device) ~motion = function
      | Triangles { vertices; vertex_stride; triangle_count; index; _ } ->
          if vertex_stride < 12L || Int64.rem vertex_stride 4L <> 0L || triangle_count <= 0L
             || triangle_count > Int64.div Int64.max_int 3L then
            error operation Invalid_argument
              "triangle stride must be at least 12 and four-byte aligned with a positive count"
          else
            let count = match index with None -> Int64.mul triangle_count 3L | Some _ -> 1L in
            Result.bind
              (validate_keyframes operation device "vertex" vertices ~motion ~check:(fun k ->
                   range_fits k.buffer k.offset vertex_stride count 12L))
              (fun () ->
                validate_index operation device
                  (Option.map (fun (i : index) ->
                       ignore (range_fits i.index_buffer i.index_offset
                         (if i.index_uint16 then 2L else 4L) (Int64.mul triangle_count 3L)
                         (if i.index_uint16 then 2L else 4L)); i) index))
      | Bounding_boxes { boxes; stride; count; _ } ->
          if stride < 24L || Int64.rem stride 4L <> 0L || count <= 0L then
            error operation Invalid_argument
              "bounding box stride must be at least 24 and four-byte aligned with a positive count"
          else
            validate_keyframes operation device "bounding box" boxes ~motion ~check:(fun k ->
                range_fits k.buffer k.offset stride count 24L)
      | Curves { control_points; control_stride; control_point_count; radii; radius_stride; index
               ; segment_count; control_points_per_segment; _ } ->
          if control_stride < 12L || radius_stride < 4L || control_point_count < 2L
             || segment_count <= 0L || control_points_per_segment < 2
             || control_points_per_segment > 4 then
            error operation Invalid_argument "curve strides, counts, or segment shape are invalid"
          else if List.length radii <> List.length control_points then
            error operation Invalid_argument "curve radius keyframes must match control point keyframes"
          else
            Result.bind
              (validate_keyframes operation device "control point" control_points ~motion
                 ~check:(fun k -> range_fits k.buffer k.offset control_stride control_point_count 12L))
              (fun () ->
                Result.bind
                  (validate_keyframes operation device "radius" radii ~motion ~check:(fun k ->
                       range_fits k.buffer k.offset radius_stride control_point_count 4L))
                  (fun () -> validate_index operation device (Some index)))

    let geometry_buffers = function
      | Triangles { vertices; index; _ } ->
          List.map (fun (k : keyframe) -> k.buffer) vertices
          @ Option.fold ~none:[] ~some:(fun (i : index) -> [ i.index_buffer ]) index
      | Bounding_boxes { boxes; _ } -> List.map (fun (k : keyframe) -> k.buffer) boxes
      | Curves { control_points; radii; index; _ } ->
          List.map (fun (k : keyframe) -> k.buffer) (control_points @ radii) @ [ index.index_buffer ]

    (* A descriptor borrows its buffers and structures: like [Triangle.t] it
       pins nothing, and every build revalidates them and retains them on the
       command buffer for the GPU's lifetime of the work. *)
    let finish operation (device : device) raw ~buffers ~structures ~instance_count:_ ~kind =
      attach device.lifetime;
      let value = { raw; lifetime = lifetime (); device; buffers; structures;  kind } in
      Gc.finalise
        (fun (value : t) ->
          if Atomic.compare_and_set value.lifetime.destroyed false true then begin
            ignore (Metal_raw.destroy value.raw);
            detach value.device.lifetime
          end)
        value;
      ignore operation;
      Ok value

    let primitive (device : Device.t) ?motion ?(usage = []) geometries =
      let operation = "Metal.Acceleration_structure.Build.primitive" in
      on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as e -> e
          | Ok () when geometries = [] ->
              error operation Invalid_argument "descriptor requires at least one geometry"
          | Ok ()
            when (match motion with
                  | Some m -> m.keyframe_count < 2 || not (m.start_time < m.end_time)
                                || not (Float.is_finite m.start_time && Float.is_finite m.end_time)
                  | None -> false) ->
              error operation Invalid_argument
                "motion requires at least two keyframes and an increasing finite time range"
          | Ok () -> (
              let rec validate = function
                | [] -> Ok ()
                | g :: rest -> Result.bind (validate_geometry operation device ~motion g) (fun () -> validate rest)
              in
              match validate geometries with
              | Error _ as e -> e
              | Ok () -> (
                  let raw : Metal_raw.accel_primitive_raw =
                    { geometries = Array.of_list (List.map geometry_raw geometries)
                    ; motion = Option.map (fun (m : motion) : Metal_raw.accel_motion_raw ->
                        { keyframe_count = Int64.of_int m.keyframe_count; start_time = m.start_time
                        ; end_time = m.end_time
                        ; start_border = (match m.start_border with Clamp -> 0 | Vanish -> 1)
                        ; end_border = (match m.end_border with Clamp -> 0 | Vanish -> 1) }) motion
                    ; primitive_refit = List.mem Refit usage; fast_build = List.mem Prefer_fast_build usage }
                  in
                  match Metal_raw.accel_descriptor_primitive raw with
                  | Error m -> native_error operation m
                  | Ok raw ->
                      finish operation device raw
                        ~buffers:(List.concat_map geometry_buffers geometries) ~structures:[]
                        ~instance_count:0L ~kind:None)))

    let instances (device : Device.t) ~(buffer : buffer) ?(offset = 0L) ?stride ~count
        ?(kind = Default_instances) ?motion_transforms ?(usage = []) (primitives : structure array) =
      let operation = "Metal.Acceleration_structure.Build.instances" in
      on_main operation (fun () ->
          let layout = instance_layout kind in
          let stride = Option.value stride ~default:(Int64.of_int layout.size) in
          match ensure_live operation device.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_buffer_usable operation buffer with
              | Error _ as e -> e
              | Ok () when not (same_device device buffer.device) ->
                  error operation Device_mismatch "instance buffer belongs to another device"
              | Ok () when Array.length primitives = 0 ->
                  error operation Invalid_argument "instances reference no structures"
              | Ok ()
                when count <= 0L || stride < Int64.of_int layout.size || Int64.rem stride 4L <> 0L
                     || Int64.rem offset 4L <> 0L
                     || not (range_fits buffer offset stride count (Int64.of_int layout.size)) ->
                  error operation Invalid_argument
                    "instance range is invalid, unaligned, or exceeds its buffer"
              | Ok () when kind = Motion_instances && motion_transforms = None ->
                  error operation Invalid_argument "motion instances require a transform buffer"
              | Ok () -> (
                  let rec check index =
                    if index = Array.length primitives then Ok ()
                    else
                      match ensure_live operation primitives.(index).lifetime with
                      | Error _ as e -> e
                      | Ok () when not (same_device device primitives.(index).device) ->
                          error operation Device_mismatch "primitive belongs to another device"
                      | Ok () -> check (index + 1)
                  in
                  match check 0 with
                  | Error _ as e -> e
                  | Ok () -> (
                      let transforms =
                        match motion_transforms with
                        | None -> Ok None
                        | Some ((b : buffer), transform_offset, transform_count) -> (
                            match ensure_buffer_usable operation b with
                            | Error _ as e -> e
                            | Ok () when not (same_device device b.device) ->
                                error operation Device_mismatch
                                  "motion transform buffer belongs to another device"
                            | Ok () when not (range_fits b transform_offset 48L transform_count 48L) ->
                                error operation Invalid_argument
                                  "motion transform range exceeds its buffer"
                            | Ok () -> Ok (Some (b, transform_offset, transform_count)))
                      in
                      match transforms with
                      | Error _ as e -> e
                      | Ok transforms -> (
                          let raw : Metal_raw.accel_instances_raw =
                            { instances_buffer = buffer.raw; instances_offset = offset
                            ; instances_stride = stride; instances_count = count
                            ; instance_kind = kind_code kind
                            ; instanced = Array.map (fun (x : structure) -> x.raw) primitives
                            ; motion_transforms = Option.map (fun ((b : buffer), _, _) -> b.raw) transforms
                            ; motion_transform_offset = Option.fold ~none:0L ~some:(fun (_, o, _) -> o) transforms
                            ; motion_transform_count = Option.fold ~none:0L ~some:(fun (_, _, c) -> c) transforms
                            ; instances_refit = List.mem Refit usage }
                          in
                          match Metal_raw.accel_descriptor_instances raw with
                          | Error m -> native_error operation m
                          | Ok raw ->
                              finish operation device raw
                                ~buffers:(buffer :: Option.fold ~none:[] ~some:(fun (b, _, _) -> [ b ]) transforms)
                                ~structures:(Array.to_list primitives) ~instance_count:count
                                ~kind:(Some kind))))))

    let sizes ~(device : Device.t) (value : t) =
      let operation = "Metal.Acceleration_structure.Build.sizes" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () when not (same_device device value.device) ->
              error operation Device_mismatch "descriptor belongs to another device"
          | Ok () -> (
              match Metal_raw.accel_descriptor_sizes device.raw value.raw with
              | Error m -> native_error operation m
              | Ok (acceleration_structure_size, build_scratch_buffer_size, refit_scratch_buffer_size) ->
                  Ok { acceleration_structure_size; build_scratch_buffer_size; refit_scratch_buffer_size }))

    let instance_kind (value : t) = value.kind

    let destroy (value : t) =
      destroy_parent "Metal.Acceleration_structure.Build.destroy" value.lifetime value.raw (fun () ->
          detach value.device.lifetime)
  end

  let create ~(device : device) ~size =
    let operation = "Metal.Acceleration_structure.create" in
    on_main operation (fun () ->
        if size <= 0L then error operation Invalid_argument "size must be positive"
        else
          match ensure_live operation device.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match Metal_raw.acceleration_structure_create device.raw size with
              | Error message -> native_error operation message
              | Ok raw ->
                  let value =
                    { raw; lifetime = lifetime (); device; size; heap = None; allocation = None }
                  in
                  attach device.lifetime;
                  attach_finalizer value value.lifetime device.lifetime;
                  Ok value))

  let destroy (value : t) =
    destroy_parent "Metal.Acceleration_structure.destroy" value.lifetime value.raw (fun () ->
        match value.heap with
        | None -> detach value.device.lifetime
        | Some heap ->
            deactivate_allocation value.allocation;
            detach heap.lifetime)
end

module Texture = struct
  type t = texture

  type kind = texture_kind =
    | Texture_1d
    | Texture_1d_array
    | Texture_2d
    | Texture_2d_array
    | Texture_2d_multisample
    | Texture_cube
    | Texture_cube_array
    | Texture_3d
    | Texture_2d_multisample_array
    | Texture_buffer

  type format = Metal_format.t =
    | A8_unorm
    | R8_unorm
    | R8_unorm_srgb
    | R8_snorm
    | R8_uint
    | R8_sint
    | R16_unorm
    | R16_snorm
    | R16_uint
    | R16_sint
    | R16_float
    | Rg8_unorm
    | Rg8_unorm_srgb
    | Rg8_snorm
    | Rg8_uint
    | Rg8_sint
    | B5g6r5_unorm
    | A1bgr5_unorm
    | Abgr4_unorm
    | Bgr5a1_unorm
    | R32_uint
    | R32_sint
    | R32_float
    | Rg16_unorm
    | Rg16_snorm
    | Rg16_uint
    | Rg16_sint
    | Rg16_float
    | Rgba8_unorm
    | Rgba8_unorm_srgb
    | Rgba8_snorm
    | Rgba8_uint
    | Rgba8_sint
    | Bgra8_unorm
    | Bgra8_unorm_srgb
    | Rgb10a2_unorm
    | Rgb10a2_uint
    | Rg11b10_float
    | Rgb9e5_float
    | Bgr10a2_unorm
    | Bgr10_xr
    | Bgr10_xr_srgb
    | Rg32_uint
    | Rg32_sint
    | Rg32_float
    | Rgba16_unorm
    | Rgba16_snorm
    | Rgba16_uint
    | Rgba16_sint
    | Rgba16_float
    | Bgra10_xr
    | Bgra10_xr_srgb
    | Rgba32_uint
    | Rgba32_sint
    | Rgba32_float
    | Bc1_rgba
    | Bc1_rgba_srgb
    | Bc2_rgba
    | Bc2_rgba_srgb
    | Bc3_rgba
    | Bc3_rgba_srgb
    | Bc4_r_unorm
    | Bc4_r_snorm
    | Bc5_rg_unorm
    | Bc5_rg_snorm
    | Bc6h_rgb_float
    | Bc6h_rgb_ufloat
    | Bc7_rgba_unorm
    | Bc7_rgba_unorm_srgb
    | Eac_r11_unorm
    | Eac_r11_snorm
    | Eac_rg11_unorm
    | Eac_rg11_snorm
    | Eac_rgba8
    | Eac_rgba8_srgb
    | Etc2_rgb8
    | Etc2_rgb8_srgb
    | Etc2_rgb8a1
    | Etc2_rgb8a1_srgb
    | Astc_4x4_srgb
    | Astc_5x4_srgb
    | Astc_5x5_srgb
    | Astc_6x5_srgb
    | Astc_6x6_srgb
    | Astc_8x5_srgb
    | Astc_8x6_srgb
    | Astc_8x8_srgb
    | Astc_10x5_srgb
    | Astc_10x6_srgb
    | Astc_10x8_srgb
    | Astc_10x10_srgb
    | Astc_12x10_srgb
    | Astc_12x12_srgb
    | Astc_4x4_ldr
    | Astc_5x4_ldr
    | Astc_5x5_ldr
    | Astc_6x5_ldr
    | Astc_6x6_ldr
    | Astc_8x5_ldr
    | Astc_8x6_ldr
    | Astc_8x8_ldr
    | Astc_10x5_ldr
    | Astc_10x6_ldr
    | Astc_10x8_ldr
    | Astc_10x10_ldr
    | Astc_12x10_ldr
    | Astc_12x12_ldr
    | Astc_4x4_hdr
    | Astc_5x4_hdr
    | Astc_5x5_hdr
    | Astc_6x5_hdr
    | Astc_6x6_hdr
    | Astc_8x5_hdr
    | Astc_8x6_hdr
    | Astc_8x8_hdr
    | Astc_10x5_hdr
    | Astc_10x6_hdr
    | Astc_10x8_hdr
    | Astc_10x10_hdr
    | Astc_12x10_hdr
    | Astc_12x12_hdr
    | Gbgr422
    | Bgrg422
    | Depth16_unorm
    | Depth32_float
    | Stencil8
    | Depth24_unorm_stencil8
    | Depth32_float_stencil8
    | X32_stencil8
    | X24_stencil8

  type format_layout = Metal_format.layout = {
    block_width : int;
    block_height : int;
    bytes_per_block : int;
  }

  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined

  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type usage = texture_usage =
    | Shader_read
    | Shader_write
    | Render_target
    | Pixel_format_view
    | Shader_atomic

  type compression_type = texture_compression_type = Lossless | Lossy
  type swizzle_channel = texture_swizzle_channel = Zero | One | Red | Green | Blue | Alpha

  type swizzle = texture_swizzle = {
    red : swizzle_channel;
    green : swizzle_channel;
    blue : swizzle_channel;
    alpha : swizzle_channel;
  }

  type sparse_tier = Not_sparse | Sparse_tier_1 | Sparse_tier_2

  type descriptor = texture_descriptor = {
    kind : kind;
    format : format;
    width : int;
    height : int;
    depth : int;
    mip_levels : int;
    sample_count : int;
    array_length : int;
    storage : Buffer.storage_mode;
    cpu_cache : cpu_cache_mode;
    hazard_tracking : hazard_tracking_mode;
    usage : usage list;
    allow_gpu_optimized_contents : bool;
    compression : compression_type;
    swizzle : swizzle;
    label : string option;
  }

  let compression_code = function Lossless -> 0 | Lossy -> 1

  let swizzle_channel_code = function
    | Zero -> 0
    | One -> 1
    | Red -> 2
    | Green -> 3
    | Blue -> 4
    | Alpha -> 5

  let swizzle_codes (value : swizzle) =
    ( swizzle_channel_code value.red,
      swizzle_channel_code value.green,
      swizzle_channel_code value.blue,
      swizzle_channel_code value.alpha )

  let default_swizzle = { red = Red; green = Green; blue = Blue; alpha = Alpha }

  let has_writable_usage =
    List.exists (function
      | Shader_write | Shader_atomic -> true
      | Shader_read | Render_target | Pixel_format_view -> false)

  let has_lossy_incompatible_usage =
    List.exists (function
      | Pixel_format_view | Shader_write | Shader_atomic -> true
      | Shader_read | Render_target -> false)

  type region = { x : int; y : int; z : int; width : int; height : int; depth : int }

  type sparse_info = {
    page_size : Sparse_page_size.t;
    tile_width : int;
    tile_height : int;
    tile_depth : int;
    tile_size_in_bytes : int64;
    first_mip_in_tail : int option;
    tail_size_in_bytes : int64;
  }

  type buffer_backing = buffer_texture_backing = {
    buffer : Buffer.t;
    offset : int64;
    bytes_per_row : int;
  }

  let descriptor_2d ?(mipmapped = false) ?(storage = Private) ?(usage = [ Shader_read ])
      ?(compression = Lossless) ?(swizzle = default_swizzle) ?label ~format ~width ~height () =
    let max_dimension = max width height in
    let rec mip_count dimension count =
      if dimension <= 1 then count else mip_count (dimension / 2) (count + 1)
    in
    {
      kind = Texture_2d;
      format;
      width;
      height;
      depth = 1;
      mip_levels = (if mipmapped then mip_count max_dimension 1 else 1);
      sample_count = 1;
      array_length = 1;
      storage;
      cpu_cache = Default_cache;
      hazard_tracking = Default_hazard_tracking;
      usage;
      allow_gpu_optimized_contents = true;
      compression;
      swizzle;
      label;
    }

  let kind_code = function
    | Texture_1d -> 0
    | Texture_1d_array -> 1
    | Texture_2d -> 2
    | Texture_2d_array -> 3
    | Texture_2d_multisample -> 4
    | Texture_cube -> 5
    | Texture_cube_array -> 6
    | Texture_3d -> 7
    | Texture_2d_multisample_array -> 8
    | Texture_buffer -> 9

  let format_code = Metal_format.code
  let format_layout = Metal_format.layout

  let supports_family_raw (device : Device.t) family =
    Result.value ~default:false
      (Metal_raw.Registry.device_supports_family device.raw (Int64.of_int (Device.family_code family)))

  let supports_compression_raw (device : Device.t) format =
    match Metal_format.compression_family format with
    | None -> true
    | Some Metal_format.Bc -> probe (Metal_raw.Registry.device_supports_bc_texture_compression device.raw)
    | Some (Metal_format.Eac_etc2 | Metal_format.Astc_ldr) ->
        supports_family_raw device Device.Apple2 || supports_family_raw device Device.Metal4
    | Some Metal_format.Astc_hdr ->
        supports_family_raw device Device.Apple6 || supports_family_raw device Device.Metal4

  let supports_compressed_volume_raw (device : Device.t) =
    supports_family_raw device Device.Apple3
    || supports_family_raw device Device.Mac2
    || supports_family_raw device Device.Metal3
    || supports_family_raw device Device.Metal4

  let usage_bit = function
    | Shader_read -> 0x1
    | Shader_write -> 0x2
    | Render_target -> 0x4
    | Pixel_format_view -> 0x10
    | Shader_atomic -> 0x20

  let usage_bits usages = List.fold_left (fun bits usage -> bits lor usage_bit usage) 0 usages

  let max_mip_levels (descriptor : descriptor) =
    let largest = max descriptor.width (max descriptor.height descriptor.depth) in
    let rec count dimension levels =
      if dimension <= 1 then levels else count (dimension / 2) (levels + 1)
    in
    count largest 1

  let is_array = function
    | Texture_1d_array | Texture_2d_array | Texture_cube_array | Texture_2d_multisample_array ->
        true
    | Texture_1d | Texture_2d | Texture_2d_multisample | Texture_cube | Texture_3d | Texture_buffer
      ->
        false

  let is_multisample = function
    | Texture_2d_multisample | Texture_2d_multisample_array -> true
    | Texture_1d | Texture_1d_array | Texture_2d | Texture_2d_array | Texture_cube
    | Texture_cube_array | Texture_3d | Texture_buffer ->
        false

  let validate_descriptor operation (device : Device.t) (descriptor : descriptor) =
    let invalid message = error operation Invalid_argument message in
    if
      descriptor.width <= 0 || descriptor.height <= 0 || descriptor.depth <= 0
      || descriptor.mip_levels <= 0 || descriptor.sample_count <= 0 || descriptor.array_length <= 0
    then invalid "texture dimensions and counts must be positive"
    else if
      (descriptor.kind = Texture_buffer && descriptor.width > 268_435_456)
      || descriptor.kind <> Texture_buffer
         && (descriptor.width > 16_384 || descriptor.height > 16_384 || descriptor.depth > 2_048)
    then invalid "texture dimensions exceed the binding's checked Metal limits"
    else if descriptor.mip_levels > max_mip_levels descriptor then
      invalid "texture mip count exceeds its dimensions"
    else if descriptor.array_length >= 2_048 then invalid "texture array length must be below 2048"
    else if List.length descriptor.usage <> List.length (List.sort_uniq compare descriptor.usage)
    then invalid "texture usage contains duplicates"
    else if descriptor.swizzle <> default_swizzle && has_writable_usage descriptor.usage then
      invalid "texture swizzling is incompatible with shader-write and shader-atomic usage"
    else if descriptor.compression = Lossy && descriptor.storage <> Private then
      invalid "lossy texture compression requires private storage"
    else if descriptor.compression = Lossy && not descriptor.allow_gpu_optimized_contents then
      invalid "lossy texture compression requires GPU-optimized contents"
    else if descriptor.compression = Lossy && has_lossy_incompatible_usage descriptor.usage then
      invalid
        "lossy texture compression is incompatible with pixel-format views, shader writes, and \
         shader atomics"
    else if
      descriptor.compression = Lossy
      &&
      match descriptor.kind with
      | Texture_1d | Texture_1d_array | Texture_buffer -> true
      | Texture_2d | Texture_2d_array | Texture_2d_multisample | Texture_cube | Texture_cube_array
      | Texture_3d | Texture_2d_multisample_array ->
          false
    then invalid "lossy texture compression is incompatible with 1D and buffer textures"
    else if
      descriptor.compression = Lossy
      && not (Metal_format.supports_lossy_compression descriptor.format)
    then invalid "pixel format does not support lossy texture compression"
    else if
      descriptor.compression = Lossy
      && not (Metal_raw.device_supports_lossy_texture_compression device.raw)
    then error operation Unsupported "device does not support lossy texture compression"
    else if
      descriptor.format = Depth24_unorm_stencil8
      && not (probe (Metal_raw.Registry.device_supports_depth24_stencil8 device.raw))
    then error operation Unsupported "device does not support Depth24Unorm_Stencil8 textures"
    else if not (supports_compression_raw device descriptor.format) then
      error operation Unsupported "device does not support the selected compressed texture format"
    else if Metal_format.is_view_only descriptor.format then
      invalid "stencil-plane formats can only be created as texture views"
    else if
      Metal_format.is_compressed descriptor.format
      &&
      match descriptor.kind with
      | Texture_2d | Texture_2d_array | Texture_cube | Texture_cube_array | Texture_3d -> false
      | Texture_1d | Texture_1d_array | Texture_2d_multisample | Texture_2d_multisample_array
      | Texture_buffer ->
          true
    then invalid "compressed formats require a 2D, 2D-array, cube, cube-array, or 3D texture"
    else if
      Metal_format.is_compressed descriptor.format
      && descriptor.kind = Texture_3d
      && not (supports_compressed_volume_raw device)
    then error operation Unsupported "device does not support compressed volume textures"
    else if
      Metal_format.is_compressed descriptor.format
      && List.exists
           (function
             | Shader_write | Render_target | Shader_atomic -> true
             | Shader_read | Pixel_format_view -> false)
           descriptor.usage
    then invalid "compressed textures support only shader-read and pixel-format-view usage"
    else if
      Metal_format.is_subsampled descriptor.format
      && (descriptor.kind <> Texture_2d
         || descriptor.width mod 2 <> 0
         || descriptor.mip_levels <> 1 || descriptor.sample_count <> 1
         || descriptor.array_length <> 1 || descriptor.depth <> 1)
    then invalid "subsampled 4:2:2 formats require an even-width, single-mip 2D texture"
    else
      match descriptor.label with
      | Some label when contains_nul label -> invalid "texture label contains a NUL byte"
      | _ -> (
          let structural_error =
            match descriptor.kind with
            | (Texture_1d | Texture_buffer) when descriptor.height <> 1 || descriptor.depth <> 1 ->
                Some "1D and buffer textures require height=depth=1"
            | Texture_1d_array when descriptor.height <> 1 || descriptor.depth <> 1 ->
                Some "1D-array textures require height=depth=1"
            | Texture_2d | Texture_2d_array | Texture_2d_multisample | Texture_2d_multisample_array
            | Texture_cube | Texture_cube_array
              when descriptor.depth <> 1 ->
                Some "2D, cube, and multisample textures require depth=1"
            | (Texture_cube | Texture_cube_array) when descriptor.width <> descriptor.height ->
                Some "cube textures must be square"
            | Texture_3d when descriptor.array_length <> 1 -> Some "3D textures cannot be arrays"
            | _ -> None
          in
          match structural_error with
          | Some message -> invalid message
          | None when is_array descriptor.kind && descriptor.array_length < 2 ->
              invalid "array textures require at least two elements"
          | None when (not (is_array descriptor.kind)) && descriptor.array_length <> 1 ->
              invalid "non-array textures require array_length=1"
          | None when is_multisample descriptor.kind && descriptor.mip_levels <> 1 ->
              invalid "multisample textures require exactly one mip level"
          | None when is_multisample descriptor.kind && descriptor.sample_count = 1 ->
              invalid "multisample textures require more than one sample"
          | None when (not (is_multisample descriptor.kind)) && descriptor.sample_count <> 1 ->
              invalid "non-multisample textures require sample_count=1"
          | None when descriptor.kind = Texture_buffer && descriptor.mip_levels <> 1 ->
              invalid "buffer textures require exactly one mip level"
          | None -> (
              if descriptor.sample_count = 1 then Ok ()
              else
                match Device.supports_texture_sample_count device descriptor.sample_count with
                | Error _ as failure -> failure
                | Ok true -> Ok ()
                | Ok false -> invalid "device does not support the texture sample count"))

  let raw_descriptor (descriptor : descriptor) =
    let swizzle_red, swizzle_green, swizzle_blue, swizzle_alpha =
      swizzle_codes descriptor.swizzle
    in
    {
      Metal_raw.texture_type = kind_code descriptor.kind;
      pixel_format = format_code descriptor.format;
      width = descriptor.width;
      height = descriptor.height;
      depth = descriptor.depth;
      mip_levels = descriptor.mip_levels;
      sample_count = descriptor.sample_count;
      array_length = descriptor.array_length;
      storage_mode = storage_code descriptor.storage;
      cpu_cache_mode = cache_code descriptor.cpu_cache;
      hazard_tracking_mode = hazard_code descriptor.hazard_tracking;
      usage = usage_bits descriptor.usage;
      allow_gpu_optimized_contents = descriptor.allow_gpu_optimized_contents;
      compression_type = compression_code descriptor.compression;
      swizzle_red;
      swizzle_green;
      swizzle_blue;
      swizzle_alpha;
    }

  let verify_info operation raw descriptor ~heap =
    let info = Metal_raw.texture_info raw in
    let actual_hazard = concrete_hazard_tracking ~heap descriptor.hazard_tracking in
    if Array.length info <> 18 then
      native_error operation "Metal returned malformed texture properties"
    else
      let swizzle_red, swizzle_green, swizzle_blue, swizzle_alpha =
        swizzle_codes descriptor.swizzle
      in
      let expected =
        [|
          kind_code descriptor.kind;
          format_code descriptor.format;
          descriptor.width;
          descriptor.height;
          descriptor.depth;
          descriptor.mip_levels;
          descriptor.sample_count;
          descriptor.array_length;
          usage_bits descriptor.usage;
          storage_code descriptor.storage;
          cache_code descriptor.cpu_cache;
          hazard_code actual_hazard;
          (if descriptor.allow_gpu_optimized_contents then 1 else 0);
          compression_code descriptor.compression;
          swizzle_red;
          swizzle_green;
          swizzle_blue;
          swizzle_alpha;
        |]
      in
      if info = expected then Ok { descriptor with hazard_tracking = actual_hazard }
      else begin
        let fields =
          [|
            "texture type";
            "pixel format";
            "width";
            "height";
            "depth";
            "mip levels";
            "sample count";
            "array length";
            "usage";
            "storage mode";
            "CPU cache mode";
            "hazard tracking mode";
            "GPU-optimized contents";
            "compression type";
            "red swizzle";
            "green swizzle";
            "blue swizzle";
            "alpha swizzle";
          |]
        in
        let rec mismatch index =
          if index = Array.length expected then None
          else if info.(index) <> expected.(index) then Some index
          else mismatch (index + 1)
        in
        match mismatch 0 with
        | None ->
            native_error operation "Metal changed a checked texture descriptor during creation"
        | Some index ->
            native_error operation
              (Printf.sprintf "Metal changed texture %s from %d to %d" fields.(index)
                 expected.(index) info.(index))
      end

  let finish_create ?expected_shareable ?placement_sparse_page_size operation ~device ~descriptor
      ~parent ~heap_offset ~allocation raw =
    let heap =
      match parent with
      | Texture_resource (Heap_resource _) -> true
      | Texture_resource (Device_resource _ )
       | Texture_view _ | Texture_drawable_resource _ ->
          false

    in
    match verify_info operation raw descriptor ~heap with
    | Error _ as failure ->
        ignore (Metal_raw.destroy raw);
        failure
    | Ok _
      when option_exists
             (fun expected -> expected <> Metal_raw.texture_is_shareable raw)
             expected_shareable ->
        ignore (Metal_raw.destroy raw);
        native_error operation "Metal changed the checked texture sharing mode during creation"
    | Ok descriptor ->
        let parent_lifetime = texture_parent_lifetime parent in
        let placement_sparse_page_size =
          match (placement_sparse_page_size, parent) with
          | Some page_size, _ -> Some page_size
          | None, Texture_view texture -> texture.placement_sparse_page_size
          | ( None,
              ( Texture_resource _
              | Texture_drawable_resource _ ) ) ->
              None
        in
        let state =
          match parent with
          | Texture_resource _ -> resource_state ()

          | Texture_drawable_resource _ -> resource_state ()
          | Texture_view texture -> texture.state
        in
        let value : t =
          {
            raw;
            lifetime = lifetime ();
            device;
            descriptor;
            parent;
            heap_offset;
            placement_sparse_page_size;
            allocation;
            state;
          }
        in
        attach parent_lifetime;
        let extra_device = texture_parent_extra_device device parent in
        Option.iter attach extra_device;
        attach_finalizer
          ~on_finalize:(fun () ->
            deactivate_allocation allocation;
            Option.iter detach extra_device)
          value value.lifetime parent_lifetime;
        Ok value

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Texture.create" (fun () ->
        match ensure_live "Metal.Texture.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_descriptor "Metal.Texture.create" device descriptor with
            | Error _ as failure -> failure
            | Ok () when descriptor.kind = Texture_buffer ->
                error "Metal.Texture.create" Invalid_argument
                  "texture-buffer resources must be created from a buffer"
            | Ok () -> (
                match
                  Metal_raw.texture_create device.raw (raw_descriptor descriptor) descriptor.label
                with
                | Error message -> native_error "Metal.Texture.create" message
                | Ok raw ->
                    finish_create ~expected_shareable:false "Metal.Texture.create" ~device
                      ~descriptor ~parent:(Texture_resource (Device_resource device))
                      ~heap_offset:None ~allocation:None raw)))

  let device (value : t) = value.device
  let descriptor (value : t) = value.descriptor
  let destroyed (value : t) = is_destroyed value.lifetime

  let decode_sparse_info operation page_size values =
    if Array.length values <> 6 then
      native_error operation "Metal returned malformed sparse texture metadata"
    else
      let integer index =
        let value = values.(index) in
        if value <= 0L || value > Int64.of_int max_int then None else Some (Int64.to_int value)
      in
      match (integer 0, integer 1, integer 2) with
      | Some tile_width, Some tile_height, Some tile_depth ->
          let tile_size_in_bytes = values.(3) in
          let first_tail = values.(4) in
          let tail_size_in_bytes = values.(5) in
          if
            tile_size_in_bytes <> Sparse_page_size.bytes page_size
            || tail_size_in_bytes < 0L || first_tail < -1L
            || first_tail > Int64.of_int max_int
          then native_error operation "Metal returned inconsistent sparse texture metadata"
          else
            Ok
              {
                page_size;
                tile_width;
                tile_height;
                tile_depth;
                tile_size_in_bytes;
                first_mip_in_tail =
                  (if first_tail < 0L then None else Some (Int64.to_int first_tail));
                tail_size_in_bytes;
              }
      | None, _, _ | _, None, _ | _, _, None ->
          native_error operation "Metal returned invalid sparse texture tile dimensions"

  let sparse_info_raw operation (value : t) =
    let page_size =
      match value.placement_sparse_page_size with
      | Some _ as page_size -> page_size
      | None -> (
          match texture_heap value with
          | Some { descriptor = { kind = Sparse; sparse_page_size = Some page_size; _ }; _ } ->
              Some page_size
          | Some _ | None -> None)
    in
    match page_size with
    | None ->
        if Metal_raw.texture_is_sparse value.raw then
          native_error operation "sparse texture has no matching typed page-size metadata"
        else Ok None
    | Some page_size -> (
        if not (Metal_raw.texture_is_sparse value.raw) then
          native_error operation "typed sparse texture lost its native identity"
        else
          match
            Metal_raw.texture_sparse_info value.device.raw value.raw
              (sparse_page_size_code page_size)
          with
          | Error message -> native_error operation message
          | Ok values -> (
              match decode_sparse_info operation page_size values with
              | Error _ as failure -> failure
              | Ok info -> Ok (Some info)))

  let sparse_info (value : t) =
    on_main "Metal.Texture.sparse_info" (fun () ->
        match ensure_live "Metal.Texture.sparse_info" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> sparse_info_raw "Metal.Texture.sparse_info" value)

  let mip_dimension dimension level = max 1 (dimension lsr level)

  let total_slices (descriptor : descriptor) =
    match descriptor.kind with
    | Texture_1d_array | Texture_2d_array | Texture_2d_multisample_array -> descriptor.array_length
    | Texture_cube -> 6
    | Texture_cube_array -> descriptor.array_length * 6
    | Texture_1d | Texture_2d | Texture_2d_multisample | Texture_3d | Texture_buffer -> 1

  let checked_mul left right =
    if left = 0 || right = 0 then Some 0
    else if left > max_int / right then None
    else Some (left * right)

  let validate_transfer operation (value : t) ~region ~mip_level ~slice ~bytes_per_row
      ~bytes_per_image =
    let invalid message = error operation Invalid_argument message in
    if Option.is_some value.placement_sparse_page_size then
      error operation Invalid_state
        "placement sparse textures have no CPU-visible backing until mapped"
    else if value.descriptor.storage = Private then
      error operation Unsupported "private textures have no CPU transfer mapping"
    else if is_multisample value.descriptor.kind then
      error operation Unsupported "multisample textures do not support CPU transfer"
    else if mip_level < 0 || mip_level >= value.descriptor.mip_levels then
      invalid "mip level is outside the texture"
    else if slice < 0 || slice >= total_slices value.descriptor then
      invalid "slice is outside the texture"
    else if
      region.x < 0 || region.y < 0 || region.z < 0 || region.width <= 0 || region.height <= 0
      || region.depth <= 0
    then invalid "texture region coordinates and dimensions are invalid"
    else
      let width = mip_dimension value.descriptor.width mip_level in
      let height = mip_dimension value.descriptor.height mip_level in
      let depth = mip_dimension value.descriptor.depth mip_level in
      if
        region.x > width
        || region.width > width - region.x
        || region.y > height
        || region.height > height - region.y
        || region.z > depth
        || region.depth > depth - region.z
      then invalid "texture region exceeds the selected mip level"
      else
        let layout = format_layout value.descriptor.format in
        let aligned origin length limit block =
          origin mod block = 0 && (length mod block = 0 || origin + length = limit)
        in
        if
          not
            (aligned region.x region.width width layout.block_width
            && aligned region.y region.height height layout.block_height)
        then invalid "texture region is not aligned to its format blocks"
        else
          let blocks value block = 1 + ((value - 1) / block) in
          match checked_mul (blocks region.width layout.block_width) layout.bytes_per_block with
          | None -> invalid "texture row cardinality overflows an OCaml integer"
          | Some minimum_row
            when bytes_per_row < minimum_row || bytes_per_row mod layout.bytes_per_block <> 0 ->
              invalid "texture row pitch is too small or not block-aligned"
          | Some _ -> (
              match checked_mul bytes_per_row (blocks region.height layout.block_height) with
              | None -> invalid "texture image cardinality overflows an OCaml integer"
              | Some minimum_image when bytes_per_image < minimum_image ->
                  invalid "texture image pitch is smaller than its rows"
              | Some _ -> (
                  match checked_mul bytes_per_image region.depth with
                  | None -> invalid "texture transfer cardinality overflows an OCaml integer"
                  | Some total when total > Sys.max_string_length ->
                      invalid "texture transfer exceeds the maximum OCaml byte buffer"
                  | Some total -> Ok total))

  let transfer_tuple region ~mip_level ~slice ~source_offset ~bytes_per_row ~bytes_per_image =
    ( (region.x, region.y, region.z, region.width, region.height, region.depth),
      mip_level,
      slice,
      source_offset,
      bytes_per_row,
      bytes_per_image )

  let write_bytes (value : t) ~region ~mip_level ~slice ?(src_offset = 0) ~bytes_per_row
      ~bytes_per_image bytes =
    on_main "Metal.Texture.write_bytes" (fun () ->
        match ensure_texture_usable "Metal.Texture.write_bytes" value with
        | Error _ as failure -> failure
        | Ok () -> (
            match
              validate_transfer "Metal.Texture.write_bytes" value ~region ~mip_level ~slice
                ~bytes_per_row ~bytes_per_image
            with
            | Error _ as failure -> failure
            | Ok total -> (
                if
                  src_offset < 0
                  || src_offset > Bytes.length bytes
                  || total > Bytes.length bytes - src_offset
                then
                  error "Metal.Texture.write_bytes" Invalid_argument
                    "source bytes do not contain the complete pitched region"
                else
                  match
                    Metal_raw.texture_write value.raw
                      (transfer_tuple region ~mip_level ~slice ~source_offset:src_offset
                         ~bytes_per_row ~bytes_per_image)
                      bytes
                  with
                  | Ok () -> Ok ()
                  | Error message -> native_error "Metal.Texture.write_bytes" message)))

  let read_bytes (value : t) ~region ~mip_level ~slice ~bytes_per_row ~bytes_per_image =
    on_main "Metal.Texture.read_bytes" (fun () ->
        match ensure_texture_usable "Metal.Texture.read_bytes" value with
        | Error _ as failure -> failure
        | Ok () -> (
            match
              validate_transfer "Metal.Texture.read_bytes" value ~region ~mip_level ~slice
                ~bytes_per_row ~bytes_per_image
            with
            | Error _ as failure -> failure
            | Ok _ -> (
                match
                  Metal_raw.texture_read value.raw
                    (transfer_tuple region ~mip_level ~slice ~source_offset:0 ~bytes_per_row
                       ~bytes_per_image)
                with
                | Ok bytes -> Ok bytes
                | Error message -> native_error "Metal.Texture.read_bytes" message)))

  let read_bytes_into (value : t) ~region ~mip_level ~slice ~bytes_per_row ~bytes_per_image
      ~destination =
    on_main "Metal.Texture.read_bytes_into" (fun () ->
        match ensure_texture_usable "Metal.Texture.read_bytes_into" value with
        | Error _ as failure -> failure
        | Ok () -> (
            match
              validate_transfer "Metal.Texture.read_bytes_into" value ~region ~mip_level ~slice
                ~bytes_per_row ~bytes_per_image
            with
            | Error _ as failure -> failure
            | Ok total -> (
                if Bytes.length destination <> total then
                  error "Metal.Texture.read_bytes_into" Invalid_argument
                    "destination length does not match the complete pitched region"
                else
                  match
                    Metal_raw.texture_read_into value.raw
                      (transfer_tuple region ~mip_level ~slice ~source_offset:0 ~bytes_per_row
                         ~bytes_per_image)
                      destination
                  with
                  | Ok () -> Ok ()
                  | Error message -> native_error "Metal.Texture.read_bytes_into" message)))

  let compatible_view_format = Metal_format.compatible_view

  let compose_swizzle_channel (parent : swizzle) = function
    | Zero -> Zero
    | One -> One
    | Red -> parent.red
    | Green -> parent.green
    | Blue -> parent.blue
    | Alpha -> parent.alpha

  let compose_swizzle (parent : swizzle) (view : swizzle) =
    {
      red = compose_swizzle_channel parent view.red;
      green = compose_swizzle_channel parent view.green;
      blue = compose_swizzle_channel parent view.blue;
      alpha = compose_swizzle_channel parent view.alpha;
    }

  let create_view (parent : t) ~format ~base_mip ~mip_count ~base_slice ~slice_count
      ?(swizzle = default_swizzle) ?label () =
    on_main "Metal.Texture.create_view" (fun () ->
        match ensure_texture_usable "Metal.Texture.create_view" parent with
        | Error _ as failure -> failure
        | Ok () when swizzle <> default_swizzle && has_writable_usage parent.descriptor.usage ->
            error "Metal.Texture.create_view" Invalid_argument
              "texture-view swizzling is incompatible with writable texture usage"
        | Ok ()
          when (not (List.mem Pixel_format_view parent.descriptor.usage))
               && (format <> parent.descriptor.format || swizzle = default_swizzle) ->
            error "Metal.Texture.create_view" Invalid_argument
              "parent texture usage does not permit this texture view"
        | Ok () when not (compatible_view_format parent.descriptor.format format) ->
            error "Metal.Texture.create_view" Invalid_argument
              "requested texture-view format is not in a compatible format class"
        | Ok ()
          when format = X24_stencil8
               && not (probe (Metal_raw.Registry.device_supports_depth24_stencil8 parent.device.raw)) ->
            error "Metal.Texture.create_view" Unsupported
              "device does not support X24_Stencil8 texture views"
        | Ok ()
          when base_mip < 0 || mip_count <= 0
               || base_mip > parent.descriptor.mip_levels
               || mip_count > parent.descriptor.mip_levels - base_mip ->
            error "Metal.Texture.create_view" Invalid_argument "texture-view mip range is invalid"
        | Ok ()
          when base_slice < 0 || slice_count <= 0
               || base_slice > total_slices parent.descriptor
               || slice_count > total_slices parent.descriptor - base_slice ->
            error "Metal.Texture.create_view" Invalid_argument "texture-view slice range is invalid"
        | Ok () when option_exists contains_nul label ->
            error "Metal.Texture.create_view" Invalid_argument
              "texture-view label contains a NUL byte"
        | Ok () -> (
            let array_length =
              match parent.descriptor.kind with
              | Texture_cube_array -> slice_count / 6
              | kind when is_array kind -> slice_count
              | _ -> 1
            in
            let slice_shape_valid =
              match parent.descriptor.kind with
              | Texture_cube -> base_slice = 0 && slice_count = 6
              | Texture_cube_array -> base_slice mod 6 = 0 && slice_count mod 6 = 0
              | kind when is_array kind -> true
              | _ -> base_slice = 0 && slice_count = 1
            in
            if not slice_shape_valid then
              error "Metal.Texture.create_view" Invalid_argument
                "texture-view slices do not preserve the texture kind"
            else
              let effective_swizzle = compose_swizzle parent.descriptor.swizzle swizzle in
              let descriptor : descriptor =
                {
                  parent.descriptor with
                  format;
                  width = mip_dimension parent.descriptor.width base_mip;
                  height = mip_dimension parent.descriptor.height base_mip;
                  depth = mip_dimension parent.descriptor.depth base_mip;
                  mip_levels = mip_count;
                  array_length;
                  swizzle = effective_swizzle;
                  label;
                }
              in
              let ( requested_swizzle_red,
                    requested_swizzle_green,
                    requested_swizzle_blue,
                    requested_swizzle_alpha ) =
                swizzle_codes swizzle
              in
              let ( effective_swizzle_red,
                    effective_swizzle_green,
                    effective_swizzle_blue,
                    effective_swizzle_alpha ) =
                swizzle_codes effective_swizzle
              in
              match
                Metal_raw.texture_create_view parent.raw
                  {
                    Metal_raw.pixel_format = format_code format;
                    texture_type = kind_code descriptor.kind;
                    base_mip;
                    mip_count;
                    base_slice;
                    slice_count;
                    requested_swizzle_red;
                    requested_swizzle_green;
                    requested_swizzle_blue;
                    requested_swizzle_alpha;
                    effective_swizzle_red;
                    effective_swizzle_green;
                    effective_swizzle_blue;
                    effective_swizzle_alpha;
                  }
                  label
              with
              | Error message -> native_error "Metal.Texture.create_view" message
              | Ok raw ->
                  finish_create "Metal.Texture.create_view" ~device:parent.device ~descriptor
                    ~parent:(Texture_view parent) ~heap_offset:parent.heap_offset ~allocation:None
                    raw))

  let make_aliasable (value : t) =
    on_main "Metal.Texture.make_aliasable" (fun () ->
        match ensure_live "Metal.Texture.make_aliasable" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Option.is_some value.placement_sparse_page_size ->
            error "Metal.Texture.make_aliasable" Invalid_state
              "placement sparse aliasing is controlled by mapping operations"
        | Ok () when Atomic.get value.state.relinquished -> Ok ()
        | Ok () when Atomic.get value.state.purgeable <> Nonvolatile ->
            error "Metal.Texture.make_aliasable" Invalid_state
              "texture must be nonvolatile before becoming aliasable"
        | Ok () when dependent_count value.lifetime <> 0 ->
            error "Metal.Texture.make_aliasable" Parent_has_dependents
              "texture has a live view or command dependency"
        | Ok () -> (
            match value.parent with
            | Texture_view _ ->
                error "Metal.Texture.make_aliasable" Invalid_state
                  "texture views cannot become aliasable"

            | Texture_drawable_resource _ ->
                error "Metal.Texture.make_aliasable" Invalid_state
                  "drawable-backed textures cannot become aliasable"
            | Texture_resource (Device_resource _) ->
                error "Metal.Texture.make_aliasable" Invalid_state
                  "only heap-backed textures can become aliasable"

            | Texture_resource (Heap_resource heap) -> (
                if heap.descriptor.kind = Sparse then
                  error "Metal.Texture.make_aliasable" Invalid_state
                    "sparse texture mappings are released by unmapping tiles"
                else
                  match ensure_heap_nonvolatile "Metal.Texture.make_aliasable" (Some heap) with
                  | Error _ as failure -> failure
                  | Ok () -> (
                      match Metal_raw.resource_make_aliasable value.raw with
                      | Error message -> native_error "Metal.Texture.make_aliasable" message
                      | Ok () ->
                          if not (Metal_raw.resource_is_aliasable value.raw) then
                            native_error "Metal.Texture.make_aliasable"
                              "Metal did not make the heap texture aliasable"
                          else begin
                            Atomic.set value.state.relinquished true;
                            deactivate_allocation value.allocation;
                            Ok ()
                          end))))

  let destroy (value : t) =
    destroy_parent "Metal.Texture.destroy" value.lifetime value.raw (fun () ->
        deactivate_allocation value.allocation;
        detach (texture_parent_lifetime value.parent);
        Option.iter detach (texture_parent_extra_device value.device value.parent))
end

module Metal_layer = struct
  type t = metal_layer

  type edr_metadata = metal_layer_edr_metadata =
    | Standard
    | Hlg
    | Hdr10 of {
        minimum_luminance : float;
        maximum_luminance : float;
        optical_output_scale : float;
      }

  type config = {
    width : int;
    height : int;
    format : Texture.format;
    framebuffer_only : bool;
    maximum_drawables : int;
    allows_timeout : bool;
    display_sync : bool;
    presents_with_transaction : bool;
  }

  let default ~width ~height =
    {
      width;
      height;
      format = Texture.Bgra8_unorm;
      framebuffer_only = false;
      maximum_drawables = 3;
      allows_timeout = true;
      display_sync = false;
      presents_with_transaction = false;
    }

  let create (device : Device.t) config =
    let operation = "Metal.Metal_layer.create" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if
              config.width <= 0 || config.height <= 0 || config.maximum_drawables < 2
              || config.maximum_drawables > 3
            then error operation Invalid_argument "invalid drawable size or maximum count"
            else if
              not
                (List.mem config.format
                   [ Texture.Bgra8_unorm; Texture.Bgra8_unorm_srgb; Texture.Rgba16_float ])
            then error operation Unsupported "pixel format is not supported by CAMetalLayer"
            else
              match Metal_raw.layer_create device.raw with
              | Error m -> native_error operation m
              | Ok raw -> (
                  match
                    Metal_raw.layer_configure raw config.width config.height
                      (Metal_format.code config.format)
                      ( config.framebuffer_only,
                        config.maximum_drawables,
                        config.allows_timeout,
                        config.display_sync,
                        config.presents_with_transaction )
                  with
                  | Error m ->
                      ignore (Metal_raw.destroy raw);
                      native_error operation m
                  | Ok () ->
                      let value : t =
                        {
                          raw;
                          lifetime = lifetime ();
                          device;
                          layer_width = config.width;
                          layer_height = config.height;
                          layer_format = config.format;
                          framebuffer_only = config.framebuffer_only;
                          maximum_drawables = config.maximum_drawables;
                          allows_timeout = config.allows_timeout;
                          display_sync = config.display_sync;
                          presents_with_transaction = config.presents_with_transaction;

                          drawable_descriptor = None;
                        }
                      in
                      attach device.lifetime;
                      attach_finalizer value value.lifetime device.lifetime;
                      Ok value)))

  let adopt_borrowed (device : Device.t) token config =
    let operation = "Metal.Metal_layer.adopt_borrowed" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if not (Native_layer_token.alive token) then
              error operation Destroyed "native layer token is stale"
            else if
              config.width <= 0 || config.height <= 0 || config.maximum_drawables < 2
              || config.maximum_drawables > 3
            then error operation Invalid_argument "invalid drawable size or maximum count"
            else
              match
                Metal_raw.layer_adopt_borrowed device.raw token
                  (Native_layer_token.owner_id token)
                  (Native_layer_token.generation token)
              with
              | Error m -> native_error operation m
              | Ok raw -> (
                  match
                    Metal_raw.layer_configure raw config.width config.height
                      (Metal_format.code config.format)
                      ( config.framebuffer_only,
                        config.maximum_drawables,
                        config.allows_timeout,
                        config.display_sync,
                        config.presents_with_transaction )
                  with
                  | Error m ->
                      ignore (Metal_raw.destroy raw);
                      native_error operation m
                  | Ok () ->
                      let value : t =
                        {
                          raw;
                          lifetime = lifetime ();
                          device;
                          layer_width = config.width;
                          layer_height = config.height;
                          layer_format = config.format;
                          framebuffer_only = config.framebuffer_only;
                          maximum_drawables = config.maximum_drawables;
                          allows_timeout = config.allows_timeout;
                          display_sync = config.display_sync;
                          presents_with_transaction = config.presents_with_transaction;

                          drawable_descriptor = None;
                        }
                      in
                      attach device.lifetime;
                      attach_finalizer value value.lifetime device.lifetime;
                      Ok value)))

  let device (value : t) = value.device

  let config (value : t) =
    {
      width = value.layer_width;
      height = value.layer_height;
      format = value.layer_format;
      framebuffer_only = value.framebuffer_only;
      maximum_drawables = value.maximum_drawables;
      allows_timeout = value.allows_timeout;
      display_sync = value.display_sync;
      presents_with_transaction = value.presents_with_transaction;
    }

  let configure (value : t) config =
    let operation = "Metal.Metal_layer.configure" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if
              config.width <= 0 || config.height <= 0 || config.maximum_drawables < 2
              || config.maximum_drawables > 3
            then error operation Invalid_argument "invalid drawable size or maximum count"
            else if
              not
                (List.mem config.format
                   [ Texture.Bgra8_unorm; Texture.Bgra8_unorm_srgb; Texture.Rgba16_float ])
            then error operation Unsupported "pixel format is not supported by CAMetalLayer"
            else
              match
                Metal_raw.layer_configure value.raw config.width config.height
                  (Metal_format.code config.format)
                  ( config.framebuffer_only,
                    config.maximum_drawables,
                    config.allows_timeout,
                    config.display_sync,
                    config.presents_with_transaction )
              with
              | Error m -> native_error operation m
              | Ok () ->
                  value.layer_width <- config.width;
                  value.layer_height <- config.height;
                  value.layer_format <- config.format;
                  value.framebuffer_only <- config.framebuffer_only;
                  value.maximum_drawables <- config.maximum_drawables;
                  value.allows_timeout <- config.allows_timeout;
                  value.display_sync <- config.display_sync;
                  value.presents_with_transaction <- config.presents_with_transaction;
                  value.drawable_descriptor <- None;
                  Ok ()))

  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_parent "Metal.Metal_layer.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Drawable = struct
  type t = metal_drawable
  type loss = Timeout_or_unavailable
  type present_time = Immediate | At_time of float | After_minimum_duration of float

  let acquire_owned ~finalize (layer : metal_layer) =
    let operation = "Metal.Drawable.acquire" in
    match before_main operation with
    | Error _ as error -> error
    | Ok () -> (
        match ensure_live operation layer.lifetime with
        | Error _ as error -> error
        | Ok () -> (
            match Metal_raw.layer_next_drawable layer.raw with
            | Error message -> native_error operation message
            | Ok None -> Ok (Error Timeout_or_unavailable)
            | Ok (Some raw) -> (
                match Metal_raw.drawable10_snapshot raw with
                | Error message ->
                    ignore (Metal_raw.destroy raw);
                    native_error operation message
                | Ok (_drawable_id, _) ->
                    let value : t =
                      {
                        raw;
                        lifetime = lifetime ();
                        layer;
                        drawable_texture = None;

                        presentation_scheduled = false;
                      }
                    in
                    attach layer.lifetime;
                    if finalize then attach_finalizer value value.lifetime layer.lifetime;
                    Ok (Ok value))))

  let acquire layer = acquire_owned ~finalize:true layer

  let texture_owned ~finalize (value : t) =
    let operation = "Metal.Drawable.texture" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match value.drawable_texture with
            | Some texture -> Ok texture
            | None -> (
                match Metal_raw.drawable_texture value.raw with
                | Error message -> native_error operation message
                | Ok (raw, width, height, format_code) -> (
                    match
                      match format_code with
                      | 80 -> Some Texture.Bgra8_unorm
                      | 81 -> Some Texture.Bgra8_unorm_srgb
                      | 115 -> Some Texture.Rgba16_float
                      | _ -> None
                    with
                    | None ->
                        ignore (Metal_raw.destroy raw);
                        error operation Unsupported "drawable returned an unsupported pixel format"
                    | Some format ->
                        let descriptor =
                          match value.layer.drawable_descriptor with
                          | Some descriptor
                            when descriptor.width = width && descriptor.height = height
                                 && descriptor.format = format ->
                              descriptor
                          | _ ->
                              let descriptor =
                                Texture.descriptor_2d ~storage:Buffer.Private
                                  ~usage:[ Texture.Render_target ] ~format ~width ~height ()
                              in
                              value.layer.drawable_descriptor <- Some descriptor;
                              descriptor
                        in
                        let texture : texture =
                          {
                            raw;
                            lifetime = lifetime ();
                            device = value.layer.device;
                            descriptor;
                            parent = Texture_drawable_resource value;
                            heap_offset = None;
                            placement_sparse_page_size = None;
                            allocation = None;
                            state =
                              {
                                relinquished = Atomic.make false;
                                purgeable = Atomic.make Nonvolatile;
                              };
                          }
                        in
                        attach value.lifetime;
                        if finalize then attach_finalizer texture texture.lifetime value.lifetime;
                        value.drawable_texture <- Some texture;
                        Ok texture))))

  let texture value = texture_owned ~finalize:true value

  module Private = struct
    let acquire_scoped layer = acquire_owned ~finalize:false layer
    let texture_scoped value = texture_owned ~finalize:false value
  end

  let destroy (value : t) =
    destroy_parent "Metal.Drawable.destroy" value.lifetime value.raw (fun () ->
        detach value.layer.lifetime)
end

module Render_pass_descriptor = struct
  type color_load_action = Load_dont_care | Load | Clear
  type t = render_pass_descriptor
  type visibility_result_type = Disabled | Boolean

  type sample_attachment = {
    start_vertex : int64;
    end_vertex : int64;
    start_fragment : int64;
    end_fragment : int64;
    has_sample_buffer : bool;
  }

  type advanced = {
    imageblock_sample_length : int64;
    threadgroup_memory_length : int64;
    tile_width : int64;
    tile_height : int64;
    visibility_result_type : visibility_result_type;
    support_color_attachment_mapping : bool;
    sample_positions : (float * float) array;
  }

  let create ~width ~height ?(array_length = 1) ?(sample_count = 1) () =
    let operation = "Metal.Render_pass_descriptor.create" in
    on_main operation (fun () ->
        if width <= 0 || height <= 0 || array_length <= 0 || sample_count <= 0 then
          error operation Invalid_argument "render pass sizes must be positive"
        else
          match Metal_raw.render_pass_descriptor_create () with
          | Error message -> native_error operation message
          | Ok raw -> (
              match
                Metal_raw.render_pass_descriptor_set_sizes raw width height array_length
                  sample_count
              with
              | Error message ->
                  ignore (Metal_raw.destroy raw);
                  native_error operation message
              | Ok () ->
                  Ok
                    {
                      raw;
                      lifetime = lifetime ();
                      pass_width = width;
                      pass_height = height;
                      pass_array_length = array_length;
                      pass_sample_count = sample_count;
                      pass_color = None;
                      pass_depth = None;
                      pass_stencil = None;
                      pass_visibility = None;
                      pass_resolve = None;
                      pass_samples = Array.make 4 None;
                    }))

  let set_sample_attachment (value : t) ~index (sample : counter_sample_buffer option) ~start_vertex
      ~end_vertex ~start_fragment ~end_fragment =
    let operation = "Metal.Render_pass_descriptor.set_sample_attachment" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when index < 0 || index >= 4 ->
            error operation Invalid_argument "sample attachment index must be in [0,4)"
        | Ok () -> (
            match sample with
            | None -> (
                match
                  Metal_raw.render_pass_sample_set value.raw (Int64.of_int index) None (-1L) (-1L)
                    (-1L) (-1L)
                with
                | Error message -> native_error operation message
                | Ok () ->
                    Option.iter
                      (fun (state : render_pass_sample_state) ->
                        detach state.sample_buffer.lifetime)
                      value.pass_samples.(index);
                    value.pass_samples.(index) <- None;
                    Ok ())
            | Some buffer when is_destroyed buffer.lifetime ->
                error operation Destroyed "counter sample buffer is destroyed"
            | Some buffer
              when option_exists
                     (fun (texture : texture) -> not (same_device texture.device buffer.device))
                     value.pass_color ->
                error operation Device_mismatch "counter sample buffer belongs to another device"
            | Some buffer
              when List.exists
                     (fun x -> x < -1L || x >= buffer.sample_count)
                     [ start_vertex; end_vertex; start_fragment; end_fragment ]
                   || (start_vertex >= 0L && end_vertex >= 0L && start_vertex > end_vertex)
                   || (start_fragment >= 0L && end_fragment >= 0L && start_fragment > end_fragment)
                   || List.for_all (fun x -> x < 0L) [ start_vertex; end_vertex; start_fragment; end_fragment ] ->
                error operation Invalid_argument
                  "counter sample indices are outside the buffer, reversed, or all unsampled"
            | Some buffer -> (
                match
                  Metal_raw.render_pass_sample_set value.raw (Int64.of_int index) (Some buffer.raw)
                    start_vertex end_vertex start_fragment end_fragment
                with
                | Error message -> native_error operation message
                | Ok () ->
                    attach buffer.lifetime;
                    Option.iter
                      (fun (state : render_pass_sample_state) ->
                        detach state.sample_buffer.lifetime)
                      value.pass_samples.(index);
                    value.pass_samples.(index) <- Some { sample_buffer = buffer };
                    Ok ())))

  let set_resolve_texture (value : t) (next : texture option) =
    let operation = "Metal.Render_pass_descriptor.set_resolve_texture" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match next with
            | Some texture when is_destroyed texture.lifetime ->
                error operation Destroyed "resolve texture is destroyed"
            | Some _ when value.pass_sample_count <= 1 ->
                error operation Invalid_argument
                  "resolve texture requires a multisample render pass"
            | Some texture
              when texture.descriptor.width <> value.pass_width
                   || texture.descriptor.height <> value.pass_height
                   || texture.descriptor.sample_count <> 1
                   || not (List.mem Render_target texture.descriptor.usage) ->
                error operation Invalid_argument
                  "resolve texture dimensions, samples, or usage are incompatible"
            | Some texture
              when option_exists
                     (fun (color : texture) -> not (same_device color.device texture.device))
                     value.pass_color ->
                error operation Device_mismatch "resolve texture belongs to another device"
            | _ -> (
                match
                  Metal_raw.render_pass_resolve_texture value.raw
                    (Option.map (fun (texture : texture) -> texture.raw) next)
                    true
                with
                | Error message -> native_error operation message
                | Ok actual ->
                    Option.iter (fun raw -> ignore (Metal_raw.destroy raw)) actual;
                    if Option.is_some actual <> Option.is_some next then
                      error operation Native_error "resolve texture round-trip changed nullability"
                    else begin
                      Option.iter (fun (texture : texture) -> attach texture.lifetime) next;
                      Option.iter
                        (fun (texture : texture) -> detach texture.lifetime)
                        value.pass_resolve;
                      value.pass_resolve <- next;
                      Ok ()
                    end)))

  let set_color_store_action (value : t) ~resolve =
    let operation = "Metal.Render_pass_descriptor.set_color_store_action" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            let code = if resolve then 2 else 1 in
            if resolve && value.pass_sample_count = 1 then
              error operation Invalid_argument "resolve store actions require multisampling"
            else
              match Metal_raw.render_pass_color_store_action value.raw code with
              | Ok () -> Ok ()
              | Error message -> native_error operation message))

  type store_action = Store_dont_care | Store

  let set_depth_stencil_actions (value : t) ~depth:(depth_load, depth_store, clear_depth)
      ~stencil:(stencil_load, stencil_store, clear_stencil) =
    let operation = "Metal.Render_pass_descriptor.set_depth_stencil_actions" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () when not (Float.is_finite clear_depth) || clear_depth < 0. || clear_depth > 1.
                     || clear_stencil < 0 || clear_stencil > 255 ->
            error operation Invalid_argument "depth clear must be in [0,1] and stencil clear in [0,255]"
        | Ok () -> (
            let load = function Load_dont_care -> 0 | Load -> 1 | Clear -> 2
            and store = function Store_dont_care -> 0 | Store -> 1 in
            match
              Metal_raw.render_pass_depth_stencil_actions value.raw (load depth_load)
                (store depth_store) clear_depth (load stencil_load) (store stencil_store)
                clear_stencil
            with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let set_color_load_action (value : t) action =
    let operation = "Metal.Render_pass_descriptor.set_color_load_action" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            let code = match action with Load_dont_care -> 0 | Load -> 1 | Clear -> 2 in
            match Metal_raw.render_pass_color_load_action value.raw code with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let detach_option get = Option.iter (fun value -> detach (get value))

  let depth_capable = function
    | Texture.Depth16_unorm | Texture.Depth32_float | Texture.Depth24_unorm_stencil8
    | Texture.Depth32_float_stencil8 ->
        true
    | _ -> false

  let stencil_capable = function
    | Texture.Stencil8 | Texture.Depth24_unorm_stencil8 | Texture.Depth32_float_stencil8
    | Texture.X32_stencil8 | Texture.X24_stencil8 ->
        true
    | _ -> false

  let set_attachments (value : t) ~(color : texture) ?(clear = (0., 0., 0., 1.))
      ?(depth : texture option) ?(stencil : texture option) ?(visibility_result : buffer option) ()
      =
    let operation = "Metal.Render_pass_descriptor.set_attachments" in
    on_main operation (fun () ->
        let textures = color :: List.filter_map Fun.id [ depth; stencil ] in
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when value.pass_array_length <> 1 ->
            error operation Unsupported
              "classic attachment configuration supports one render-target slice"
        | Ok () -> (
            match
              List.find_opt (fun (texture : texture) -> is_destroyed texture.lifetime) textures
            with
            | Some _ -> error operation Destroyed "render pass attachment is destroyed"
            | None -> (
                let device = color.device in
                if
                  List.exists
                    (fun (texture : texture) -> not (same_device device texture.device))
                    textures
                then
                  error operation Device_mismatch
                    "render pass attachments belong to different devices"
                else if
                  option_exists
                    (fun (texture : texture) -> not (same_device device texture.device))
                    value.pass_resolve
                  || Array.exists
                       (function
                         | None -> false
                         | Some (state : render_pass_sample_state) ->
                             not (same_device device state.sample_buffer.device))
                       value.pass_samples
                then
                  error operation Device_mismatch
                    "retained resolve/counter attachments belong to another device"
                else
                  match visibility_result with
                  | Some buffer when is_destroyed buffer.lifetime ->
                      error operation Destroyed "visibility buffer is destroyed"
                  | Some buffer when not (same_device device buffer.device) ->
                      error operation Device_mismatch "visibility buffer belongs to another device"
                  | Some buffer when buffer.length < 8L ->
                      error operation Invalid_argument
                        "visibility buffer must contain at least eight bytes"
                  | _ -> (
                      let compatible (texture : texture) =
                        texture.descriptor.width = value.pass_width
                        && texture.descriptor.height = value.pass_height
                        && texture.descriptor.sample_count = value.pass_sample_count
                        && List.mem Render_target texture.descriptor.usage
                      in
                      let r, g, b, a = clear in
                      if not (compatible color) then
                        error operation Invalid_argument
                          "color attachment dimensions, samples, or usage are incompatible"
                      else if
                        depth_capable color.descriptor.format
                        || stencil_capable color.descriptor.format
                      then
                        error operation Invalid_argument
                          "color attachment uses a depth/stencil pixel format"
                      else if
                        option_exists
                          (fun texture ->
                            (not (compatible texture))
                            || not (depth_capable texture.descriptor.format))
                          depth
                      then
                        error operation Invalid_argument
                          "depth attachment format or geometry is incompatible"
                      else if
                        option_exists
                          (fun texture ->
                            (not (compatible texture))
                            || not (stencil_capable texture.descriptor.format))
                          stencil
                      then
                        error operation Invalid_argument
                          "stencil attachment format or geometry is incompatible"
                      else if not (List.for_all Float.is_finite [ r; g; b; a ]) then
                        error operation Invalid_argument "clear color must be finite"
                      else
                        match
                          Metal_raw.render_pass_descriptor_set_attachments value.raw color.raw
                            (Option.map (fun (texture : texture) -> texture.raw) depth)
                            (Option.map (fun (texture : texture) -> texture.raw) stencil)
                            (Option.map (fun (buffer : buffer) -> buffer.raw) visibility_result)
                            clear
                        with
                        | Error message -> native_error operation message
                        | Ok () ->
                            Option.iter
                              (fun (texture : texture) -> attach texture.lifetime)
                              (Some color);
                            Option.iter (fun (texture : texture) -> attach texture.lifetime) depth;
                            Option.iter (fun (texture : texture) -> attach texture.lifetime) stencil;
                            Option.iter
                              (fun (buffer : buffer) -> attach buffer.lifetime)
                              visibility_result;
                            detach_option
                              (fun (texture : texture) -> texture.lifetime)
                              value.pass_color;
                            detach_option
                              (fun (texture : texture) -> texture.lifetime)
                              value.pass_depth;
                            detach_option
                              (fun (texture : texture) -> texture.lifetime)
                              value.pass_stencil;
                            detach_option
                              (fun (buffer : buffer) -> buffer.lifetime)
                              value.pass_visibility;
                            value.pass_color <- Some color;
                            value.pass_depth <- depth;
                            value.pass_stencil <- stencil;
                            value.pass_visibility <- visibility_result;
                            Ok ()))))

  let destroy (value : t) =
    destroy_parent "Metal.Render_pass_descriptor.destroy" value.lifetime value.raw (fun () ->
        detach_option (fun (texture : texture) -> texture.lifetime) value.pass_color;
        detach_option (fun (texture : texture) -> texture.lifetime) value.pass_depth;
        detach_option (fun (texture : texture) -> texture.lifetime) value.pass_stencil;
        detach_option (fun (buffer : buffer) -> buffer.lifetime) value.pass_visibility;
        detach_option (fun (texture : texture) -> texture.lifetime) value.pass_resolve;
        Array.iter
          (Option.iter (fun (state : render_pass_sample_state) ->
               detach state.sample_buffer.lifetime))
          value.pass_samples)
end

module Fence = struct
  type t = fence

  let create = Device.new_fence

  let destroy (value : t) =
    destroy_parent "Metal.Fence.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Heap = struct
  type t = heap
  type kind = heap_kind = Automatic | Placement | Sparse
  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined

  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type descriptor = heap_descriptor = {
    size : int64;
    storage : Buffer.storage_mode;
    cpu_cache : cpu_cache_mode;
    hazard_tracking : hazard_tracking_mode;
    kind : kind;
    sparse_page_size : Sparse_page_size.t option;
    label : string option;
  }

  type size_and_align = { size : int64; alignment : int64 }

  type info = {
    size : int64;
    used_size : int64;
    current_allocated_size : int64;
    storage : Buffer.storage_mode;
    cpu_cache : cpu_cache_mode;
    hazard_tracking : hazard_tracking_mode;
    kind : kind;
  }

  let make_descriptor ?(storage = Private) ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?(kind = Automatic) ?sparse_page_size ?label
      ~size () =
    { size; storage; cpu_cache; hazard_tracking; kind; sparse_page_size; label }

  let kind_code = function Automatic -> 0 | Placement -> 1 | Sparse -> 2

  let kind_of_code operation = function
    | 0 -> Ok Automatic
    | 1 -> Ok Placement
    | 2 -> Ok Sparse
    | code -> native_error operation (Printf.sprintf "unknown heap kind %d" code)

  let storage_of_code operation = function
    | 0 -> Ok Shared
    | 1 -> Ok Managed
    | 2 -> Ok Private
    | code -> native_error operation (Printf.sprintf "unknown storage mode %d" code)

  let sparse_tile_size_in_bytes_raw operation (device : Device.t) page_size =
    if not (Metal_raw.device_supports_sparse_textures device.raw) then
      error operation Unsupported "device does not support sparse textures"
    else
      match
        Metal_raw.device_sparse_tile_size_in_bytes device.raw (sparse_page_size_code page_size)
      with
      | Error message -> error operation Unsupported message
      | Ok bytes when bytes <> Sparse_page_size.bytes page_size ->
          native_error operation "Metal changed the selected sparse page's byte cardinality"
      | Ok bytes -> Ok bytes

  let validate_descriptor operation (device : Device.t) (descriptor : descriptor) =
    if descriptor.size <= 0L then error operation Invalid_argument "heap size must be positive"
    else if descriptor.storage = Managed then
      error operation Unsupported "Metal heaps do not support managed storage"
    else if option_exists contains_nul descriptor.label then
      error operation Invalid_argument "heap label contains a NUL byte"
    else
      match (descriptor.kind, descriptor.sparse_page_size) with
      | Automatic, Some _ ->
          error operation Invalid_argument "automatic heaps do not accept a sparse page size"
      | Sparse, None ->
          error operation Invalid_argument "sparse heaps require an explicit sparse page size"
      | Sparse, Some _ when descriptor.storage <> Private || descriptor.cpu_cache <> Default_cache
        ->
          error operation Invalid_argument "sparse heaps require private default-cache storage"
      | (Automatic | Placement), None -> Ok ()
      | Placement, Some _ when not (Metal_raw.device_supports_placement_sparse device.raw) ->
          error operation Unsupported "device does not support placement sparse resources"
      | Placement, Some page_size ->
          let page_bytes = Sparse_page_size.bytes page_size in
          if Int64.rem descriptor.size page_bytes <> 0L then
            error operation Invalid_argument
              "placement heap size must be a whole number of sparse pages"
          else Ok ()
      | Sparse, Some page_size -> (
          match sparse_tile_size_in_bytes_raw operation device page_size with
          | Error _ as failure -> failure
          | Ok page_bytes when Int64.rem descriptor.size page_bytes <> 0L ->
              error operation Invalid_argument
                "sparse heap size must be a whole number of sparse pages"
          | Ok _ -> Ok ())

  let descriptor_tuple (descriptor : descriptor) =
    ( descriptor.size,
      storage_code descriptor.storage,
      cache_code descriptor.cpu_cache,
      hazard_code descriptor.hazard_tracking,
      kind_code descriptor.kind,
      Option.fold ~none:0 ~some:sparse_page_size_code descriptor.sparse_page_size )

  let decode_info operation raw =
    let values = Metal_raw.heap_info raw in
    if Array.length values <> 7 then
      native_error operation "Metal returned malformed heap properties"
    else
      match
        ( storage_of_code operation (Int64.to_int values.(3)),
          cache_mode_of_code operation (Int64.to_int values.(4)),
          hazard_mode_of_code operation (Int64.to_int values.(5)),
          kind_of_code operation (Int64.to_int values.(6)) )
      with
      | Ok storage, Ok cpu_cache, Ok hazard_tracking, Ok kind ->
          Ok
            {
              size = values.(0);
              used_size = values.(1);
              current_allocated_size = values.(2);
              storage;
              cpu_cache;
              hazard_tracking;
              kind;
            }
      | (Error _ as failure), _, _, _
      | _, (Error _ as failure), _, _
      | _, _, (Error _ as failure), _
      | _, _, _, (Error _ as failure) ->
          failure

  let validate_size_and_align operation ~minimum (size, alignment) =
    if size < minimum || alignment <= 0L || Int64.logand alignment (Int64.pred alignment) <> 0L then
      native_error operation "Metal returned an invalid heap resource size or alignment"
    else Ok { size; alignment }

  let buffer_size_and_align ~(device : Device.t) ~length ~storage ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) () =
    on_main "Metal.Heap.buffer_size_and_align" (fun () ->
        match ensure_live "Metal.Heap.buffer_size_and_align" device.lifetime with
        | Error _ as failure -> failure
        | Ok () when storage = Managed ->
            error "Metal.Heap.buffer_size_and_align" Unsupported
              "Metal heaps do not support managed storage"
        | Ok () -> (
            match
              Buffer.validate_create "Metal.Heap.buffer_size_and_align" device ~length ~label:None
            with
            | Error _ as failure -> failure
            | Ok () ->
                let options = resource_options_code ~storage ~cpu_cache ~hazard_tracking in
                Metal_raw.heap_buffer_size_and_align device.raw length options
                |> validate_size_and_align "Metal.Heap.buffer_size_and_align" ~minimum:length))

  let texture_size_and_align ~(device : Device.t) (descriptor : Texture.descriptor) =
    on_main "Metal.Heap.texture_size_and_align" (fun () ->
        match ensure_live "Metal.Heap.texture_size_and_align" device.lifetime with
        | Error _ as failure -> failure
        | Ok () when descriptor.storage = Managed ->
            error "Metal.Heap.texture_size_and_align" Unsupported
              "Metal heaps do not support managed storage"
        | Ok () -> (
            match
              Texture.validate_descriptor "Metal.Heap.texture_size_and_align" device descriptor
            with
            | Error _ as failure -> failure
            | Ok () when descriptor.kind = Texture.Texture_buffer ->
                error "Metal.Heap.texture_size_and_align" Invalid_argument
                  "texture-buffer resources must be created from a buffer"
            | Ok () ->
                Metal_raw.heap_texture_size_and_align device.raw (Texture.raw_descriptor descriptor)
                |> validate_size_and_align "Metal.Heap.texture_size_and_align" ~minimum:1L))

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Heap.create" (fun () ->
        match ensure_live "Metal.Heap.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_descriptor "Metal.Heap.create" device descriptor with
            | Error _ as failure -> failure
            | Ok () -> (
                match
                  Metal_raw.heap_create device.raw (descriptor_tuple descriptor) descriptor.label
                with
                | Error message -> native_error "Metal.Heap.create" message
                | Ok raw -> (
                    match decode_info "Metal.Heap.create" raw with
                    | Error _ as failure ->
                        ignore (Metal_raw.destroy raw);
                        failure
                    | Ok info ->
                        let expected_hazard =
                          concrete_hazard_tracking ~heap:true descriptor.hazard_tracking
                        in
                        if
                          info.size < descriptor.size
                          || info.storage <> descriptor.storage
                          || info.cpu_cache <> descriptor.cpu_cache
                          || info.hazard_tracking <> expected_hazard
                          || info.kind <> descriptor.kind
                        then begin
                          ignore (Metal_raw.destroy raw);
                          native_error "Metal.Heap.create"
                            "Metal changed checked heap properties during creation"
                        end
                        else
                          let descriptor =
                            {
                              descriptor with
                              size = info.size;
                              hazard_tracking = info.hazard_tracking;
                            }
                          in
                          let value : t =
                            {
                              raw;
                              lifetime = lifetime ();
                              device;
                              descriptor;
                              allocations = ref [];
                              purgeable = Atomic.make Nonvolatile;
                              active_uses = Atomic.make 0;
                            }
                          in
                          attach device.lifetime;
                          attach_finalizer value value.lifetime device.lifetime;
                          Ok value))))

  let descriptor (value : t) = value.descriptor

  let validate_placement operation (value : t) offset required =
    match (value.descriptor.kind, offset) with
    | Automatic, None ->
        let available = Metal_raw.heap_max_available_size value.raw required.alignment in
        if required.size > available then
          error operation Invalid_state "automatic heap has insufficient unfragmented capacity"
        else Ok ()
    | Automatic, Some _ ->
        error operation Invalid_argument "automatic heaps do not accept placement offsets"
    | Placement, None ->
        error operation Invalid_argument "placement heaps require an explicit offset"
    | Placement, Some offset when offset < 0L ->
        error operation Invalid_argument "heap placement offset is negative"
    | Placement, Some offset when Int64.rem offset required.alignment <> 0L ->
        error operation Invalid_argument "heap placement offset does not meet resource alignment"
    | Placement, Some offset
      when offset > value.descriptor.size || required.size > Int64.sub value.descriptor.size offset
      ->
        error operation Invalid_argument "heap placement exceeds the heap"
    | Placement, Some offset ->
        let active =
          List.filter
            (fun (allocation : heap_allocation) -> Atomic.get allocation.active)
            !(value.allocations)
        in
        value.allocations := active;
        let limit = Int64.add offset required.size in
        if
          List.exists
            (fun (allocation : heap_allocation) ->
              offset < Int64.add allocation.offset allocation.size && allocation.offset < limit)
            active
        then error operation Invalid_state "heap placement overlaps a live non-aliasable resource"
        else Ok ()
    | Sparse, None -> Ok ()
    | Sparse, Some _ ->
        error operation Invalid_argument "sparse heaps do not accept placement offsets"

  let make_allocation offset (required : size_and_align) =
    Option.map
      (fun offset ->
        ({ offset; size = required.size; active = Atomic.make true } : heap_allocation))
      offset

  let register_allocation value allocation result =
    match result with
    | Error _ as failure -> failure
    | Ok resource ->
        Option.iter
          (fun allocation -> value.allocations := allocation :: !(value.allocations))
          allocation;
        Ok resource

  let create_buffer (value : t) ?offset ~length ?label () =
    on_main "Metal.Heap.create_buffer" (fun () ->
        match ensure_live "Metal.Heap.create_buffer" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
            error "Metal.Heap.create_buffer" Invalid_state
              "heap must be nonvolatile before allocating resources"
        | Ok () when value.descriptor.kind = Sparse ->
            error "Metal.Heap.create_buffer" Unsupported
              "legacy sparse heaps allocate textures, not buffers"
        | Ok () -> (
            match Buffer.validate_create "Metal.Heap.create_buffer" value.device ~length ~label with
            | Error _ as failure -> failure
            | Ok () -> (
                let descriptor = value.descriptor in
                let options =
                  resource_options_code ~storage:descriptor.storage ~cpu_cache:descriptor.cpu_cache
                    ~hazard_tracking:descriptor.hazard_tracking
                in
                match
                  Metal_raw.heap_buffer_size_and_align value.device.raw length options
                  |> validate_size_and_align "Metal.Heap.create_buffer" ~minimum:length
                with
                | Error _ as failure -> failure
                | Ok required -> (
                    match validate_placement "Metal.Heap.create_buffer" value offset required with
                    | Error _ as failure -> failure
                    | Ok () ->
                        let allocation = make_allocation offset required in
                        let result =
                          match Metal_raw.heap_buffer_create value.raw length options offset with
                          | Error message -> native_error "Metal.Heap.create_buffer" message
                          | Ok raw ->
                              Buffer.finish_create "Metal.Heap.create_buffer" ~device:value.device
                                ~parent:(Heap_resource value) ~length ~storage:descriptor.storage
                                ~cpu_cache:descriptor.cpu_cache
                                ~hazard_tracking:descriptor.hazard_tracking ~heap_offset:offset
                                ~allocation ~label raw
                        in
                        register_allocation value allocation result))))

  let create_texture (value : t) ?offset (descriptor : Texture.descriptor) =
    on_main "Metal.Heap.create_texture" (fun () ->
        match ensure_live "Metal.Heap.create_texture" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
            error "Metal.Heap.create_texture" Invalid_state
              "heap must be nonvolatile before allocating resources"
        | Ok () -> (
            let expected_hazard = concrete_hazard_tracking ~heap:true descriptor.hazard_tracking in
            if
              descriptor.storage <> value.descriptor.storage
              || descriptor.cpu_cache <> value.descriptor.cpu_cache
              || expected_hazard <> value.descriptor.hazard_tracking
            then
              error "Metal.Heap.create_texture" Invalid_argument
                "texture storage, cache, and hazard modes must match the heap"
            else
              match
                Texture.validate_descriptor "Metal.Heap.create_texture" value.device descriptor
              with
              | Error _ as failure -> failure
              | Ok () when descriptor.kind = Texture.Texture_buffer ->
                  error "Metal.Heap.create_texture" Invalid_argument
                    "texture-buffer resources must be created from a buffer"
              | Ok () -> (
                  let descriptor = { descriptor with hazard_tracking = expected_hazard } in
                  match value.descriptor.kind with
                  | Sparse -> (
                      match (offset, value.descriptor.sparse_page_size) with
                      | Some _, _ ->
                          error "Metal.Heap.create_texture" Invalid_argument
                            "sparse heaps do not accept placement offsets"
                      | None, None ->
                          native_error "Metal.Heap.create_texture"
                            "sparse heap lost its checked page size"
                      | None, Some page_size -> (
                          let sparse_kind_supported =
                            match descriptor.kind with
                            | Texture.Texture_2d | Texture.Texture_2d_array | Texture.Texture_cube
                            | Texture.Texture_cube_array | Texture.Texture_3d ->
                                true
                            | Texture.Texture_1d | Texture.Texture_1d_array
                            | Texture.Texture_2d_multisample | Texture.Texture_2d_multisample_array
                            | Texture.Texture_buffer ->
                                false
                          in
                          if not sparse_kind_supported then
                            error "Metal.Heap.create_texture" Unsupported
                              "sparse heaps support reviewed 2D, cube, and 3D texture kinds"
                          else if Metal_format.is_subsampled descriptor.format then
                            error "Metal.Heap.create_texture" Unsupported
                              "sparse subsampled textures are not in the reviewed format matrix"
                          else
                            match
                              Metal_raw.device_sparse_texture_tile_size value.device.raw
                                (Texture.kind_code descriptor.kind)
                                (Texture.format_code descriptor.format)
                                descriptor.sample_count (sparse_page_size_code page_size)
                            with
                            | Error message -> error "Metal.Heap.create_texture" Unsupported message
                            | Ok (width, height, depth) when width <= 0 || height <= 0 || depth <= 0
                              ->
                                native_error "Metal.Heap.create_texture"
                                  "Metal returned invalid sparse tile dimensions"
                            | Ok _ -> (
                                match
                                  Metal_raw.heap_texture_create value.raw
                                    (Texture.raw_descriptor descriptor)
                                    None descriptor.label
                                with
                                | Error message -> native_error "Metal.Heap.create_texture" message
                                | Ok raw ->
                                    Texture.finish_create "Metal.Heap.create_texture"
                                      ~device:value.device ~descriptor
                                      ~parent:(Texture_resource (Heap_resource value))
                                      ~heap_offset:None ~allocation:None raw)))
                  | Automatic | Placement -> (
                      match
                        Metal_raw.heap_texture_size_and_align value.device.raw
                          (Texture.raw_descriptor descriptor)
                        |> validate_size_and_align "Metal.Heap.create_texture" ~minimum:1L
                      with
                      | Error _ as failure -> failure
                      | Ok required -> (
                          match
                            validate_placement "Metal.Heap.create_texture" value offset required
                          with
                          | Error _ as failure -> failure
                          | Ok () ->
                              let allocation = make_allocation offset required in
                              let result =
                                match
                                  Metal_raw.heap_texture_create value.raw
                                    (Texture.raw_descriptor descriptor)
                                    offset descriptor.label
                                with
                                | Error message -> native_error "Metal.Heap.create_texture" message
                                | Ok raw ->
                                    Texture.finish_create "Metal.Heap.create_texture"
                                      ~device:value.device ~descriptor
                                      ~parent:(Texture_resource (Heap_resource value))
                                      ~heap_offset:offset ~allocation raw
                              in
                              register_allocation value allocation result)))))

  let destroy (value : t) =
    destroy_parent "Metal.Heap.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Residency_set = struct
  type t = residency_set

  type allocation = residency_allocation =
    | Buffer of Buffer.t
    | Texture of Texture.t
    | Heap of Heap.t

  type descriptor = residency_descriptor = { label : string option; initial_capacity : int }

  let make_descriptor ?label ?(initial_capacity = 0) () = { label; initial_capacity }

  let allocation_lifetime = function
    | Buffer value -> value.lifetime
    | Texture value -> value.lifetime
    | Heap value -> value.lifetime

  let allocation_device = function
    | Buffer value -> value.device
    | Texture value -> value.device
    | Heap value -> value.device

  let allocation_raw = function
    | Buffer value -> value.raw
    | Texture value -> value.raw
    | Heap value -> value.raw

  let allocation_generation allocation = Metal_raw.generation (allocation_raw allocation)

  let allocation_heap = function
    | Buffer value -> parent_heap value.parent
    | Texture value -> texture_heap value
    | Heap value -> Some value

  let attach_allocation allocation =
    attach (allocation_lifetime allocation);
    Option.iter (fun heap -> Atomic.incr heap.active_uses) (allocation_heap allocation)

  let detach_allocation allocation =
    detach (allocation_lifetime allocation);
    Option.iter (fun heap -> Atomic.decr heap.active_uses) (allocation_heap allocation)

  let release_members members =
    Hashtbl.iter (fun _ (member : residency_member) -> detach_allocation member.allocation) members;
    Hashtbl.clear members

  let ensure_allocation_live operation = function
    | Buffer value -> ensure_live operation value.lifetime
    | Texture value -> ensure_live operation value.lifetime
    | Heap value -> ensure_live operation value.lifetime

  let ensure_allocation_usable operation = function
    | Buffer value -> ensure_buffer_usable operation value
    | Texture value -> ensure_texture_usable operation value
    | Heap value -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
            error operation Invalid_state "heap must be nonvolatile before entering a residency set"
        | Ok () -> Ok ())

  let validate_unique operation allocations =
    let seen = Hashtbl.create (List.length allocations) in
    let rec loop = function
      | [] -> Ok ()
      | allocation :: rest ->
          let generation = allocation_generation allocation in
          if Hashtbl.mem seen generation then
            error operation Invalid_argument "residency allocation list contains a duplicate handle"
          else begin
            Hashtbl.add seen generation ();
            loop rest
          end
    in
    loop allocations

  let validate_allocations operation (value : t) ~usable allocations =
    match validate_unique operation allocations with
    | Error _ as failure -> failure
    | Ok () ->
        let rec loop = function
          | [] -> Ok ()
          | allocation :: rest -> (
              let live =
                if usable then ensure_allocation_usable operation allocation
                else ensure_allocation_live operation allocation
              in
              match live with
              | Error _ as failure -> failure
              | Ok () -> (
                  match
                    ensure_same_device operation value.device (allocation_device allocation)
                  with
                  | Error _ as failure -> failure
                  | Ok () -> loop rest))
        in
        loop allocations

  let find_member (value : t) allocation =
    Hashtbl.find_opt value.members (allocation_generation allocation)

  let present_count (value : t) =
    Hashtbl.fold
      (fun _ (member : residency_member) count -> if member.present then count + 1 else count)
      value.members 0

  let validate_native_count operation (value : t) =
    match Metal_raw.residency_set_counts value.raw with
    | Error message -> native_error operation message
    | Ok (count, all_count) ->
        let expected = Int64.of_int (present_count value) in
        let retained = Int64.of_int (Hashtbl.length value.members) in
        if count < 0L || all_count < 0L then
          native_error operation
            (Printf.sprintf
               "Metal returned negative residency allocation counts (count=%Ld all=%Ld)" count
               all_count)
        else if all_count <> expected then
          native_error operation
            (Printf.sprintf
               "Metal residency membership diverged from the safe ownership ledger (all=%Ld \
                expected=%Ld)"
               all_count expected)
        else if count <> expected && count <> retained then
          native_error operation
            (Printf.sprintf
               "Metal returned an unexplained residency allocation count (count=%Ld present=%Ld \
                retained=%Ld)"
               count expected retained)
        else if all_count > Int64.of_int max_int then
          native_error operation "Metal residency allocation count exceeds an OCaml integer"
        else Ok (Int64.to_int all_count)

  let validate_descriptor operation (descriptor : descriptor) =
    if descriptor.initial_capacity < 0 then
      error operation Invalid_argument "residency-set initial capacity must be nonnegative"
    else if option_exists contains_nul descriptor.label then
      error operation Invalid_argument "residency-set label contains a NUL byte"
    else Ok ()

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Residency_set.create" (fun () ->
        match ensure_live "Metal.Residency_set.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_descriptor "Metal.Residency_set.create" descriptor with
            | Error _ as failure -> failure
            | Ok () when not (Metal_raw.device_supports_residency_sets device.raw) ->
                error "Metal.Residency_set.create" Unsupported
                  "residency sets require macOS 15 and device API support"
            | Ok () -> (
                match
                  Metal_raw.residency_set_create device.raw descriptor.initial_capacity
                    descriptor.label
                with
                | Error message -> native_error "Metal.Residency_set.create" message
                | Ok raw -> (
                    let members = Hashtbl.create descriptor.initial_capacity in
                    let value : t = { raw; lifetime = lifetime (); device; members } in
                    match validate_native_count "Metal.Residency_set.create" value with
                    | Error _ as failure ->
                        ignore (Metal_raw.destroy raw);
                        failure
                    | Ok _ ->
                        attach device.lifetime;
                        attach_finalizer
                          ~on_finalize:(fun () -> release_members members)
                          value value.lifetime device.lifetime;
                        Ok value))))

  let allocated_size (value : t) =
    on_main "Metal.Residency_set.allocated_size" (fun () ->
        match ensure_live "Metal.Residency_set.allocated_size" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.residency_set_allocated_size value.raw with
            | Error message -> native_error "Metal.Residency_set.allocated_size" message
            | Ok size -> Ok size))

  let add operation ~bulk (value : t) allocations =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () -> (
        match validate_allocations operation value ~usable:true allocations with
        | Error _ as failure -> failure
        | Ok () -> (
            let changes =
              List.filter
                (fun allocation ->
                  match find_member value allocation with
                  | Some member -> not member.present
                  | None -> true)
                allocations
            in
            if changes = [] then Ok ()
            else
              let raw_result =
                match (bulk, changes) with
                | false, [ allocation ] ->
                    Metal_raw.residency_set_add_allocation value.raw (allocation_raw allocation)
                | false, _ -> assert false
                | true, _ ->
                    Metal_raw.residency_set_add_allocations value.raw
                      (Array.of_list (List.map allocation_raw changes))
              in
              match raw_result with
              | Error message -> native_error operation message
              | Ok () -> (
                  List.iter
                    (fun allocation ->
                      match find_member value allocation with
                      | Some member -> member.present <- true
                      | None ->
                          attach_allocation allocation;
                          Hashtbl.add value.members
                            (allocation_generation allocation)
                            { allocation; present = true })
                    changes;
                  match validate_native_count operation value with
                  | Error _ as failure -> failure
                  | Ok _ -> Ok ())))

  let add_allocation (value : t) allocation =
    on_main "Metal.Residency_set.add_allocation" (fun () ->
        add "Metal.Residency_set.add_allocation" ~bulk:false value [ allocation ])

  let remove operation ~bulk (value : t) allocations =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () -> (
        match validate_allocations operation value ~usable:false allocations with
        | Error _ as failure -> failure
        | Ok () -> (
            let changes =
              List.filter
                (fun allocation ->
                  match find_member value allocation with
                  | Some member -> member.present
                  | None -> false)
                allocations
            in
            if changes = [] then Ok ()
            else
              let raw_result =
                match (bulk, changes) with
                | false, [ allocation ] ->
                    Metal_raw.residency_set_remove_allocation value.raw (allocation_raw allocation)
                | false, _ -> assert false
                | true, _ ->
                    Metal_raw.residency_set_remove_allocations value.raw
                      (Array.of_list (List.map allocation_raw changes))
              in
              match raw_result with
              | Error message -> native_error operation message
              | Ok () -> (
                  List.iter
                    (fun allocation ->
                      match find_member value allocation with
                      | Some member -> member.present <- false
                      | None -> assert false)
                    changes;
                  match validate_native_count operation value with
                  | Error _ as failure -> failure
                  | Ok _ -> Ok ())))

  let remove_allocation (value : t) allocation =
    on_main "Metal.Residency_set.remove_allocation" (fun () ->
        remove "Metal.Residency_set.remove_allocation" ~bulk:false value [ allocation ])

  let commit (value : t) =
    on_main "Metal.Residency_set.commit" (fun () ->
        match ensure_live "Metal.Residency_set.commit" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.residency_set_commit value.raw with
            | Error message -> native_error "Metal.Residency_set.commit" message
            | Ok () -> (
                let removed =
                  Hashtbl.fold
                    (fun generation (member : residency_member) removed ->
                      if member.present then removed else (generation, member) :: removed)
                    value.members []
                in
                List.iter
                  (fun (generation, (member : residency_member)) ->
                    Hashtbl.remove value.members generation;
                    detach_allocation member.allocation)
                  removed;
                match validate_native_count "Metal.Residency_set.commit" value with
                | Error _ as failure -> failure
                | Ok _ -> Ok ())))

  let destroy (value : t) =
    destroy_parent "Metal.Residency_set.destroy" value.lifetime value.raw (fun () ->
        release_members value.members;
        detach value.device.lifetime)
end

module Sampler = struct
  type t = sampler
  type filter = sampler_filter = Nearest | Linear
  type mip_filter = sampler_mip_filter = Not_mipmapped | Mip_nearest | Mip_linear

  type address_mode = sampler_address_mode =
    | Clamp_to_edge
    | Mirror_clamp_to_edge
    | Repeat
    | Mirror_repeat
    | Clamp_to_zero
    | Clamp_to_border_color

  type border_color = sampler_border_color = Transparent_black | Opaque_black | Opaque_white
  type reduction_mode = sampler_reduction_mode = Weighted_average | Minimum | Maximum

  type compare_function = sampler_compare_function =
    | Never
    | Less
    | Equal
    | Less_equal
    | Greater
    | Not_equal
    | Greater_equal
    | Always

  type descriptor = sampler_descriptor = {
    min_filter : filter;
    mag_filter : filter;
    mip_filter : mip_filter;
    max_anisotropy : int;
    s_address : address_mode;
    t_address : address_mode;
    r_address : address_mode;
    border_color : border_color;
    reduction_mode : reduction_mode;
    normalized_coordinates : bool;
    lod_min_clamp : float;
    lod_max_clamp : float;
    lod_average : bool;
    lod_bias : float;
    compare_function : compare_function;
    support_argument_buffers : bool;
    label : string option;
  }

  let default ?label () =
    {
      min_filter = Nearest;
      mag_filter = Nearest;
      mip_filter = Not_mipmapped;
      max_anisotropy = 1;
      s_address = Clamp_to_edge;
      t_address = Clamp_to_edge;
      r_address = Clamp_to_edge;
      border_color = Transparent_black;
      reduction_mode = Weighted_average;
      normalized_coordinates = true;
      lod_min_clamp = 0.;
      lod_max_clamp = 3.402823466e38;
      lod_average = false;
      lod_bias = 0.;
      compare_function = Never;
      support_argument_buffers = false;
      label;
    }

  let filter_code = function Nearest -> 0 | Linear -> 1
  let mip_code = function Not_mipmapped -> 0 | Mip_nearest -> 1 | Mip_linear -> 2

  let address_code = function
    | Clamp_to_edge -> 0
    | Mirror_clamp_to_edge -> 1
    | Repeat -> 2
    | Mirror_repeat -> 3
    | Clamp_to_zero -> 4
    | Clamp_to_border_color -> 5

  let border_code = function Transparent_black -> 0 | Opaque_black -> 1 | Opaque_white -> 2
  let reduction_code = function Weighted_average -> 0 | Minimum -> 1 | Maximum -> 2

  let compare_code = function
    | Never -> 0
    | Less -> 1
    | Equal -> 2
    | Less_equal -> 3
    | Greater -> 4
    | Not_equal -> 5
    | Greater_equal -> 6
    | Always -> 7

  let validate descriptor =
    let invalid message = error "Metal.Sampler.create" Invalid_argument message in
    if descriptor.max_anisotropy < 1 || descriptor.max_anisotropy > 16 then
      invalid "sampler anisotropy must be in [1, 16]"
    else if
      (not (Float.is_finite descriptor.lod_min_clamp))
      || (not (Float.is_finite descriptor.lod_max_clamp))
      || descriptor.lod_min_clamp < 0.
      || descriptor.lod_max_clamp < descriptor.lod_min_clamp
      || descriptor.lod_max_clamp > 3.402823466e38
    then invalid "sampler LOD clamps are invalid or exceed float32 range"
    else if
      (not (Float.is_finite descriptor.lod_bias))
      || descriptor.lod_bias < -16. || descriptor.lod_bias > 15.999
    then invalid "sampler LOD bias must be finite and in [-16, 15.999]"
    else if option_exists contains_nul descriptor.label then
      invalid "sampler label contains a NUL byte"
    else if
      (not descriptor.normalized_coordinates)
      && (descriptor.s_address <> Clamp_to_edge
         || descriptor.t_address <> Clamp_to_edge
         || descriptor.r_address <> Clamp_to_edge
         || descriptor.mip_filter <> Not_mipmapped
         || descriptor.max_anisotropy <> 1)
    then invalid "unnormalized coordinates require clamp-to-edge, no mip filter, and anisotropy=1"
    else Ok ()

  let descriptor_tuple descriptor =
    ( filter_code descriptor.min_filter,
      filter_code descriptor.mag_filter,
      mip_code descriptor.mip_filter,
      descriptor.max_anisotropy,
      address_code descriptor.s_address,
      address_code descriptor.t_address,
      address_code descriptor.r_address,
      border_code descriptor.border_color,
      reduction_code descriptor.reduction_mode,
      descriptor.normalized_coordinates,
      descriptor.lod_min_clamp,
      descriptor.lod_max_clamp,
      descriptor.lod_average,
      descriptor.lod_bias,
      compare_code descriptor.compare_function,
      descriptor.support_argument_buffers )

  let requires_sampler_reduction descriptor =
    descriptor.reduction_mode <> Weighted_average || descriptor.lod_bias <> 0.

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Sampler.create" (fun () ->
        match ensure_live "Metal.Sampler.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate descriptor with
            | Error _ as failure -> failure
            | Ok ()
              when requires_sampler_reduction descriptor
                   && not (Metal_raw.device_supports_sampler_reduction device.raw) ->
                error "Metal.Sampler.create" Unsupported
                  "sampler reduction modes and LOD bias require macOS 26 and Apple GPU family 10"
            | Ok () -> (
                match
                  Metal_raw.sampler_create device.raw (descriptor_tuple descriptor) descriptor.label
                with
                | Error message -> native_error "Metal.Sampler.create" message
                | Ok raw ->
                    let value : t = { raw; lifetime = lifetime (); device } in
                    attach device.lifetime;
                    attach_finalizer value value.lifetime device.lifetime;
                    Ok value)))

  let destroy (value : t) =
    destroy_parent "Metal.Sampler.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Depth_stencil = struct
  type t = depth_stencil

  type compare_function = sampler_compare_function =
    | Never
    | Less
    | Equal
    | Less_equal
    | Greater
    | Not_equal
    | Greater_equal
    | Always

  type operation = stencil_operation =
    | Keep
    | Zero
    | Replace
    | Increment_clamp
    | Decrement_clamp
    | Invert
    | Increment_wrap
    | Decrement_wrap

  type face = stencil_face = {
    compare : compare_function;
    stencil_fail : operation;
    depth_fail : operation;
    pass : operation;
    read_mask : int32;
    write_mask : int32;
  }

  let face ?(compare = Always) ?(stencil_fail = Keep) ?(depth_fail = Keep) ?(pass = Keep)
      ?(read_mask = Int32.minus_one) ?(write_mask = Int32.minus_one) () =
    { compare; stencil_fail; depth_fail; pass; read_mask; write_mask }

  let operation_code = function
    | Keep -> 0
    | Zero -> 1
    | Replace -> 2
    | Increment_clamp -> 3
    | Decrement_clamp -> 4
    | Invert -> 5
    | Increment_wrap -> 6
    | Decrement_wrap -> 7

  let raw_face (value : face) =
    ({
       Metal_raw.compare_function = Sampler.compare_code value.compare;
       stencil_failure_operation = operation_code value.stencil_fail;
       depth_failure_operation = operation_code value.depth_fail;
       pass_operation = operation_code value.pass;
       read_mask = value.read_mask;
       write_mask = value.write_mask;
     }
      : Metal_raw.depth_stencil_face_descriptor)

  let create_owned ~finalize ?label ?(depth_compare = Always) ?(depth_write = false) ?front_face
      ?back_face (device : Device.t) () =
    let operation = "Metal.Depth_stencil.create" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () when option_exists contains_nul label ->
            error operation Invalid_argument "depth/stencil label contains a NUL byte"
        | Ok () -> (
            let descriptor : Metal_raw.depth_stencil_descriptor =
              {
                depth_compare_function = Sampler.compare_code depth_compare;
                depth_write_enabled = depth_write;
                front_face_stencil = Option.map raw_face front_face;
                back_face_stencil = Option.map raw_face back_face;
                label;
              }
            in
            match Metal_raw.depth_stencil_create device.raw descriptor with
            | Error message -> native_error operation message
            | Ok raw ->
                let value : t =
                  {
                    raw;
                    lifetime = lifetime ();
                    device;

                  }
                in
                attach device.lifetime;
                if finalize then attach_finalizer value value.lifetime device.lifetime;
                Ok value))

  let create ?label ?depth_compare ?depth_write ?front_face ?back_face device () =
    create_owned ~finalize:true ?label ?depth_compare ?depth_write ?front_face ?back_face device ()

  module Private = struct
  end

  let destroy (value : t) =
    destroy_parent "Metal.Depth_stencil.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Shader_type = struct
  type scalar = shader_scalar_type =
    | Float
    | Half
    | Int
    | Uint
    | Short
    | Ushort
    | Char
    | Uchar
    | Bool
    | Long
    | Ulong
    | Bfloat

  type t = shader_data_type =
    | No_type
    | Struct
    | Array
    | Scalar of scalar
    | Vector of scalar * int
    | Matrix of scalar * int * int
    | Texture_type
    | Sampler_type
    | Pointer
    | Other_data_type of int

  let of_code = function
    | 0 -> No_type
    | 1 -> Struct
    | 2 -> Array
    | 3 -> Scalar Float
    | 4 -> Vector (Float, 2)
    | 5 -> Vector (Float, 3)
    | 6 -> Vector (Float, 4)
    | 7 -> Matrix (Float, 2, 2)
    | 8 -> Matrix (Float, 2, 3)
    | 9 -> Matrix (Float, 2, 4)
    | 10 -> Matrix (Float, 3, 2)
    | 11 -> Matrix (Float, 3, 3)
    | 12 -> Matrix (Float, 3, 4)
    | 13 -> Matrix (Float, 4, 2)
    | 14 -> Matrix (Float, 4, 3)
    | 15 -> Matrix (Float, 4, 4)
    | 16 -> Scalar Half
    | 17 -> Vector (Half, 2)
    | 18 -> Vector (Half, 3)
    | 19 -> Vector (Half, 4)
    | 20 -> Matrix (Half, 2, 2)
    | 21 -> Matrix (Half, 2, 3)
    | 22 -> Matrix (Half, 2, 4)
    | 23 -> Matrix (Half, 3, 2)
    | 24 -> Matrix (Half, 3, 3)
    | 25 -> Matrix (Half, 3, 4)
    | 26 -> Matrix (Half, 4, 2)
    | 27 -> Matrix (Half, 4, 3)
    | 28 -> Matrix (Half, 4, 4)
    | 29 -> Scalar Int
    | 30 -> Vector (Int, 2)
    | 31 -> Vector (Int, 3)
    | 32 -> Vector (Int, 4)
    | 33 -> Scalar Uint
    | 34 -> Vector (Uint, 2)
    | 35 -> Vector (Uint, 3)
    | 36 -> Vector (Uint, 4)
    | 37 -> Scalar Short
    | 38 -> Vector (Short, 2)
    | 39 -> Vector (Short, 3)
    | 40 -> Vector (Short, 4)
    | 41 -> Scalar Ushort
    | 42 -> Vector (Ushort, 2)
    | 43 -> Vector (Ushort, 3)
    | 44 -> Vector (Ushort, 4)
    | 45 -> Scalar Char
    | 46 -> Vector (Char, 2)
    | 47 -> Vector (Char, 3)
    | 48 -> Vector (Char, 4)
    | 49 -> Scalar Uchar
    | 50 -> Vector (Uchar, 2)
    | 51 -> Vector (Uchar, 3)
    | 52 -> Vector (Uchar, 4)
    | 53 -> Scalar Bool
    | 54 -> Vector (Bool, 2)
    | 55 -> Vector (Bool, 3)
    | 56 -> Vector (Bool, 4)
    | 58 -> Texture_type
    | 59 -> Sampler_type
    | 60 -> Pointer
    | 81 -> Scalar Long
    | 82 -> Vector (Long, 2)
    | 83 -> Vector (Long, 3)
    | 84 -> Vector (Long, 4)
    | 85 -> Scalar Ulong
    | 86 -> Vector (Ulong, 2)
    | 87 -> Vector (Ulong, 3)
    | 88 -> Vector (Ulong, 4)
    | 121 -> Scalar Bfloat
    | 122 -> Vector (Bfloat, 2)
    | 123 -> Vector (Bfloat, 3)
    | 124 -> Vector (Bfloat, 4)
    | code -> Other_data_type code
end

module Reflection = Metal_argument_reflection_snapshot

module Binding = struct
  type access = shader_binding_access =
    | Read_only
    | Read_write
    | Write_only
    | Unknown_access of int

  type buffer = buffer_binding_layout = {
    alignment : int64;
    data_size : int64;
    data_type : Shader_type.t;
  }

  type texture = texture_binding_layout = {
    texture_kind : Texture.kind;
    data_type : Shader_type.t;
    depth : bool;
    array_length : int64;
  }

  type sized = sized_binding_layout = { alignment : int64; data_size : int64 }

  type kind = shader_binding_kind =
    | Buffer_binding of buffer
    | Threadgroup_memory_binding of sized
    | Texture_binding of texture
    | Sampler_binding
    | Imageblock_data_binding
    | Imageblock_binding
    | Visible_function_table_binding
    | Primitive_acceleration_structure_binding
    | Instance_acceleration_structure_binding
    | Intersection_function_table_binding
    | Object_payload_binding of sized
    | Tensor_binding
    | Unknown_binding of int

  type t = shader_binding = {
    name : string;
    index : int64;
    access : access;
    used : bool;
    argument : bool;
    kind : kind;
    reflection : Reflection.reflected_type option;
  }

  type layout_kind = shader_binding_layout_kind =
    | Buffer_layout
    | Threadgroup_memory_layout
    | Texture_layout
    | Sampler_layout
    | Imageblock_data_layout
    | Imageblock_layout
    | Visible_function_table_layout
    | Primitive_acceleration_structure_layout
    | Instance_acceleration_structure_layout
    | Intersection_function_table_layout
    | Object_payload_layout
    | Tensor_layout
    | Other_binding_layout of int

  type layout = shader_binding_layout = {
    name : string;
    index : int64;
    access : access;
    kind : layout_kind;
    data_type : Shader_type.t option;
  }

  let access_of_code = function
    | 0 -> Read_only
    | 1 -> Read_write
    | 2 -> Write_only
    | code -> Unknown_access code

  let texture_kind_of_code = function
    | 0 -> Some Texture.Texture_1d
    | 1 -> Some Texture.Texture_1d_array
    | 2 -> Some Texture.Texture_2d
    | 3 -> Some Texture.Texture_2d_array
    | 4 -> Some Texture.Texture_2d_multisample
    | 5 -> Some Texture.Texture_cube
    | 6 -> Some Texture.Texture_cube_array
    | 7 -> Some Texture.Texture_3d
    | 8 -> Some Texture.Texture_2d_multisample_array
    | 9 -> Some Texture.Texture_buffer
    | _ -> None

  let of_raw
      ( name,
        kind_code,
        access_code,
        index,
        used,
        argument,
        buffer_alignment,
        buffer_data_size,
        buffer_data_type,
        texture_kind,
        texture_data_type,
        depth,
        array_length,
        threadgroup_alignment,
        threadgroup_data_size,
        object_alignment,
        object_data_size,
        reflection ) =
    let kind =
      match kind_code with
      | 0 ->
          Buffer_binding
            {
              alignment = buffer_alignment;
              data_size = buffer_data_size;
              data_type = Shader_type.of_code buffer_data_type;
            }
      | 1 ->
          Threadgroup_memory_binding
            { alignment = threadgroup_alignment; data_size = threadgroup_data_size }
      | 2 -> (
          match texture_kind_of_code texture_kind with
          | Some texture_kind ->
              Texture_binding
                {
                  texture_kind;
                  data_type = Shader_type.of_code texture_data_type;
                  depth;
                  array_length;
                }
          | None -> Unknown_binding kind_code)
      | 3 -> Sampler_binding
      | 16 -> Imageblock_data_binding
      | 17 -> Imageblock_binding
      | 24 -> Visible_function_table_binding
      | 25 -> Primitive_acceleration_structure_binding
      | 26 -> Instance_acceleration_structure_binding
      | 27 -> Intersection_function_table_binding
      | 34 -> Object_payload_binding { alignment = object_alignment; data_size = object_data_size }
      | 37 -> Tensor_binding
      | code -> Unknown_binding code
    in
    { name; index; access = access_of_code access_code; used; argument; kind; reflection }

end

module Library = struct
  type t = library

  type kind = library_kind =
    | Executable_library
    | Dynamic_library_source
    | Unknown_library_kind of int

  let kind_of_code = function
    | 0 -> Executable_library
    | 1 -> Dynamic_library_source
    | code -> Unknown_library_kind code

  let make device raw =
    let value : t = { raw; lifetime = lifetime (); device } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let native_constructor operation (device : Device.t) native =
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match native device.raw with
            | Error message -> native_error operation message
            | Ok raw -> Ok (make device raw)))

  let load_data ~(device : Device.t) bytes =
    let operation = "Metal.Library.load_data" in
    if bytes = "" then error operation Invalid_argument "compiled library data is empty"
    else
      native_constructor operation device (fun raw ->
          Metal_raw.device_library_data raw (Bytes.to_string (Bytes.of_string bytes)))

  let validate_source operation source label =
    if source = "" then error operation Invalid_argument "shader source is empty"
    else if contains_nul source then
      error operation Invalid_argument "shader source contains a NUL byte"
    else if option_exists contains_nul label then
      error operation Invalid_argument "library label contains a NUL byte"
    else Ok ()

  let compile_descriptor_raw operation ~(device : Device.t) ?label ~library_type ~install_name
      ~linked_libraries source =
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_source operation source label with
            | Error _ as failure -> failure
            | Ok () when library_type = 1 && Option.is_none install_name ->
                error operation Invalid_argument "a dynamic-library source requires an install name"
            | Ok () when option_exists (fun value -> value = "" || contains_nul value) install_name
              ->
                error operation Invalid_argument
                  "library install name must be nonempty and contain no NUL byte"
            | Ok () -> (
                let descriptor : Metal_raw.library_compile_descriptor =
                  { label; library_type; install_name; linked_libraries }
                in
                match Metal_raw.library_compile_descriptor device.raw source descriptor with
                | Error message -> native_error operation message
                | Ok raw -> Ok (make device raw))))

  let compile_source ?label ~(device : Device.t) source =
    on_main "Metal.Library.compile_source" (fun () ->
        match ensure_live "Metal.Library.compile_source" device.lifetime with
        | Error _ as failure -> failure
        | Ok () when source = "" ->
            error "Metal.Library.compile_source" Invalid_argument "shader source is empty"
        | Ok () when contains_nul source ->
            error "Metal.Library.compile_source" Invalid_argument
              "shader source contains a NUL byte"
        | Ok () when option_exists contains_nul label ->
            error "Metal.Library.compile_source" Invalid_argument
              "library label contains a NUL byte"
        | Ok () -> (
            match Metal_raw.library_compile device.raw source label with
            | Error message -> native_error "Metal.Library.compile_source" message
            | Ok raw -> Ok (make device raw)))

  let compile_dynamic_source ?label ~(device : Device.t) ~install_name source =
    let operation = "Metal.Library.compile_dynamic_source" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () when not (probe (Metal_raw.Registry.device_supports_dynamic_libraries device.raw)) ->
            error operation Unsupported "the Metal device has no dynamic-library support"
        | Ok () ->
            compile_descriptor_raw operation ~device ?label ~library_type:1
              ~install_name:(Some install_name) ~linked_libraries:[||] source)

  let destroy (value : t) =
    destroy_parent "Metal.Library.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Function = struct
  type t = function_handle

  type kind = function_kind =
    | Vertex
    | Fragment
    | Kernel
    | Visible
    | Intersection
    | Mesh
    | Object
    | Unknown_function_kind of int

  type constant_value = function_constant_value =
    | Bool_constant of bool
    | Int8_constant of int
    | Uint8_constant of int
    | Int16_constant of int
    | Uint16_constant of int
    | Int32_constant of int32
    | Uint32_constant of int64
    | Int64_constant of int64
    | Uint64_bits_constant of int64
    | Float16_constant of float
    | Float32_constant of float

  type constant = function_constant = {
    name : string;
    data_type : Shader_type.t;
    index : int64;
    required : bool;
  }

  type descriptor = {
    name : string;
    specialized_name : string option;
    constants : (string * constant_value) list;
    compile_to_binary : bool;
    binary_archives : binary_archive list;
    intersection : bool;
    descriptor_lifetime : lifetime;
  } [@@warning "-69"]

  let kind_of_code = function
    | 1 -> Vertex
    | 2 -> Fragment
    | 3 -> Kernel
    | 5 -> Visible
    | 6 -> Intersection
    | 7 -> Mesh
    | 8 -> Object
    | code -> Unknown_function_kind code

  let validate_constant_name operation name =
    if name = "" || contains_nul name then
      error operation Invalid_argument
        "function-constant names must be nonempty and contain no NUL byte"
    else Ok ()

  let raw_constant operation (name, value) =
    match validate_constant_name operation name with
    | Error _ as failure -> failure
    | Ok () -> (
        let integral tag value = Ok (name, tag, value, 0.) in
        match value with
        | Bool_constant value -> integral 0 (if value then 1L else 0L)
        | Int8_constant value when value >= -128 && value <= 127 -> integral 1 (Int64.of_int value)
        | Uint8_constant value when value >= 0 && value <= 255 -> integral 2 (Int64.of_int value)
        | Int16_constant value when value >= -32_768 && value <= 32_767 ->
            integral 3 (Int64.of_int value)
        | Uint16_constant value when value >= 0 && value <= 65_535 ->
            integral 4 (Int64.of_int value)
        | Int32_constant value -> integral 5 (Int64.of_int32 value)
        | Uint32_constant value when value >= 0L && value <= 0xffff_ffffL -> integral 6 value
        | Int64_constant value -> integral 7 value
        | Uint64_bits_constant value -> integral 8 value
        | Float16_constant value -> Ok (name, 9, 0L, value)
        | Float32_constant value -> Ok (name, 10, 0L, value)
        | Int8_constant _ ->
            error operation Invalid_argument "int8 function constant is out of range"
        | Uint8_constant _ ->
            error operation Invalid_argument "uint8 function constant is out of range"
        | Int16_constant _ ->
            error operation Invalid_argument "int16 function constant is out of range"
        | Uint16_constant _ ->
            error operation Invalid_argument "uint16 function constant is out of range"
        | Uint32_constant _ ->
            error operation Invalid_argument "uint32 function constant is out of range")

  let raw_constants operation constants =
    let rec loop seen reversed = function
      | [] -> Ok (Array.of_list (List.rev reversed))
      | ((name, _) as constant) :: rest -> (
          if List.mem name seen then
            error operation Invalid_argument "function-constant list contains a duplicate name"
          else
            match raw_constant operation constant with
            | Error _ as failure -> failure
            | Ok raw -> loop (name :: seen) (raw :: reversed) rest)
    in
    loop [] [] constants

  let find ~(library : Library.t) name =
    on_main "Metal.Function.find" (fun () ->
        match ensure_live "Metal.Function.find" library.lifetime with
        | Error _ as failure -> failure
        | Ok () when name = "" || contains_nul name ->
            error "Metal.Function.find" Invalid_argument
              "function name must be nonempty and contain no NUL byte"
        | Ok () -> (
            match Metal_raw.function_find library.raw name with
            | Error message -> native_error "Metal.Function.find" message
            | Ok raw ->
                let value : t = { raw; lifetime = lifetime (); library } in
                attach library.lifetime;
                attach_finalizer value value.lifetime library.lifetime;
                Ok value))

  let kind (value : t) =
    on_main "Metal.Function.kind" (fun () ->
        match ensure_live "Metal.Function.kind" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> Ok (kind_of_code (Metal_raw.function_kind value.raw)))

  let specialize ~(library : Library.t) ?label ~constants name =
    let operation = "Metal.Function.specialize" in
    on_main operation (fun () ->
        match ensure_live operation library.lifetime with
        | Error _ as failure -> failure
        | Ok () when name = "" || contains_nul name ->
            error operation Invalid_argument
              "function name must be nonempty and contain no NUL byte"
        | Ok () when option_exists contains_nul label ->
            error operation Invalid_argument "function label contains a NUL byte"
        | Ok () -> (
            match raw_constants operation constants with
            | Error _ as failure -> failure
            | Ok raw_constants -> (
                match Metal_raw.function_specialize library.raw name raw_constants label with
                | Error message -> native_error operation message
                | Ok raw ->
                    let value : t = { raw; lifetime = lifetime (); library } in
                    attach library.lifetime;
                    attach_finalizer value value.lifetime library.lifetime;
                    Ok value)))

  type options = int64
  type patch_type = No_patch | Triangle_patch | Quad_patch | Other_patch of int64

  let query operation raw (value : t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> ( match raw value.raw with Error m -> native_error operation m | Ok x -> Ok x))

  let argument_encoder (value : t) ~buffer_index =
    let operation = "Metal.Function.argument_encoder" in
    if buffer_index < 0L then error operation Invalid_argument "buffer index must be nonnegative"
    else
      Result.bind
        (query operation
           (fun raw -> Metal_raw.shader_function_argument_encoder raw buffer_index)
           value)
        (fun raw ->
          match Metal_raw.argument_encoder_snapshot raw with
          | Error m ->
              ignore (Metal_raw.destroy raw);
              native_error operation m
          | Ok (_, _, _, registry) when registry <> value.library.device.registry_id ->
              ignore (Metal_raw.destroy raw);
              error operation Device_mismatch "argument encoder device disagrees with function"
          | Ok (_argument_label, encoded_length, alignment, _) ->
              let x : shader_argument_encoder =
                {
                  raw;
                  lifetime = lifetime ();
                  function_ = Some value;

                  device = value.library.device;

                  encoded_length;
                  alignment;
                  retained = Hashtbl.create 17;
                  parent_encoder = None;
                }
              in
              attach value.lifetime;
              attach_finalizer
                ~on_finalize:(fun () ->
                  Hashtbl.iter (fun _ lifetime -> detach lifetime) x.retained;
                  Hashtbl.clear x.retained)
                x x.lifetime value.lifetime;
              Ok x)

  let destroy (value : t) =
    destroy_parent "Metal.Function.destroy" value.lifetime value.raw (fun () ->
        detach value.library.lifetime)
end

module Shader_argument_encoder = struct
  type t = shader_argument_encoder

  type resource =
    | Buffer of buffer
    | Texture of texture
    | Sampler of sampler
    | Acceleration_structure of acceleration_structure
    | Indirect_command_buffer of indirect_command_buffer
    | Visible_function_table of visible_function_table
    | Intersection_function_table of intersection_function_table
    | Render_pipeline of render_pipeline
    | Compute_pipeline of compute_pipeline
    | Depth_stencil of depth_stencil

  type access = Read_only | Read_write | Write_only

  type descriptor = {
    data_type : Data_type.t;
    index : int64;
    array_length : int64;
    access : access;
    texture_kind : Texture.kind;
    constant_block_alignment : int64;
  }

  let encoded_length (value : t) = value.encoded_length
  let alignment (value : t) = value.alignment

  let parts = function
    | Buffer x -> (0, x.raw, x.lifetime, x.device)
    | Texture x -> (1, x.raw, x.lifetime, x.device)
    | Sampler x -> (2, x.raw, x.lifetime, x.device)
    | Acceleration_structure x -> (3, x.raw, x.lifetime, x.device)
    | Indirect_command_buffer x -> (4, x.raw, x.lifetime, x.device)
    | Visible_function_table x -> (5, x.raw, x.lifetime, x.pipeline.device)
    | Intersection_function_table x -> (6, x.raw, x.lifetime, x.pipeline.device)
    | Render_pipeline x -> (7, x.raw, x.lifetime, x.device)
    | Compute_pipeline x -> (8, x.raw, x.lifetime, x.device)
    | Depth_stencil x -> (9, x.raw, x.lifetime, x.device)

  let retain_at (value : t) index (lifetime : lifetime) =
    match Hashtbl.find_opt value.retained index with
    | Some old when old == lifetime -> ()
    | old ->
        Option.iter detach old;
        attach lifetime;
        Hashtbl.replace value.retained index lifetime

  let set (value : t) ~index ?(offset = 0L) resource =
    let op = "Metal.Shader_argument_encoder.set" in
    on_main op (fun () ->
        match ensure_live op value.lifetime with
        | Error _ as e -> e
        | Ok () when index < 0L || offset < 0L ->
            error op Invalid_argument "argument index or offset is negative"
        | Ok () -> (
            let tag, raw, lifetime, device = parts resource in
            match ensure_live op lifetime with
            | Error _ as e -> e
            | Ok () when not (same_device value.device device) ->
                error op Device_mismatch "argument resource belongs to another device"
            | Ok () -> (
                match Metal_raw.argument_encoder_single value.raw tag raw offset index with
                | Error m -> native_error op m
                | Ok () ->
                    retain_at value index lifetime;
                    Ok ())))

  let set_argument_buffer (value : t) (buffer : buffer) ~offset ?(start_offset = 0L)
      ?(array_element = 0L) () =
    let op = "Metal.Shader_argument_encoder.set_argument_buffer" in
    on_main op (fun () ->
        match ensure_live op value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match ensure_buffer_usable op buffer with
            | Error _ as e -> e
            | Ok () when not (same_device value.device buffer.device) ->
                error op Device_mismatch "argument buffer belongs to another device"
            | Ok ()
              when offset < 0L || offset > buffer.length || start_offset < 0L || array_element < 0L
              ->
                error op Invalid_argument "argument buffer range is invalid"
            | Ok () -> (
                match
                  Metal_raw.argument_encoder_set_buffer value.raw buffer.raw offset start_offset
                    array_element
                with
                | Error m -> native_error op m
                | Ok () ->
                    retain_at value (-1L) buffer.lifetime;
                    Ok ())))

  let destroy (value : t) =
    destroy_parent "Metal.Shader_argument_encoder.destroy" value.lifetime value.raw (fun () ->
        Hashtbl.iter (fun _ lifetime -> detach lifetime) value.retained;
        Hashtbl.clear value.retained;
        match value.parent_encoder with
        | Some parent -> detach parent.lifetime
        | None ->
            Option.iter (fun (f : function_handle) -> detach f.lifetime) value.function_;
            if Option.is_none value.function_ then detach value.device.lifetime)
end

let validate_linked_functions operation device linked_functions =
  let rec loop names = function
    | [] -> Ok ()
    | (linked : Function.t) :: rest -> (
        match ensure_live operation linked.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_same_device operation device linked.library.device with
            | Error _ as failure -> failure
            | Ok () -> (
                let name = Metal_raw.function_name linked.raw in
                if List.mem name names then
                  error operation Invalid_argument "linked functions must have unique names"
                else
                  match Function.kind_of_code (Metal_raw.function_kind linked.raw) with
                  | Function.Visible | Function.Intersection -> loop (name :: names) rest
                  | _ ->
                      error operation Invalid_argument
                        "linked functions must be visible or intersection Metal functions")))
  in
  loop [] linked_functions

let validate_dynamic_libraries operation device libraries =
  let rec loop install_names = function
    | [] -> Ok ()
    | (library : dynamic_library) :: rest -> (
        match ensure_live operation library.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_same_device operation device library.device with
            | Error _ as failure -> failure
            | Ok () ->
                let install_name = Metal_raw.dynamic_library_install_name library.raw in
                if List.mem install_name install_names then
                  error operation Invalid_argument
                    "dynamic-library list contains a duplicate install name"
                else loop (install_name :: install_names) rest))
  in
  loop [] libraries

let validate_binary_archives operation device archives =
  let rec loop seen = function
    | [] -> Ok ()
    | (archive : binary_archive) :: rest -> (
        if List.exists (fun (value : binary_archive) -> value.lifetime == archive.lifetime) seen
        then error operation Invalid_argument "binary-archive list contains a duplicate handle"
        else
          match ensure_live operation archive.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match ensure_same_device operation device archive.device with
              | Error _ as failure -> failure
              | Ok () -> loop (archive :: seen) rest))
  in
  loop [] archives

module Dynamic_library = struct
  type t = dynamic_library

  let make device raw =
    let value : t = { raw; lifetime = lifetime (); device } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let check_support operation (device : Device.t) =
    match ensure_live operation device.lifetime with
    | Error _ as failure -> failure
    | Ok () when not (probe (Metal_raw.Registry.device_supports_dynamic_libraries device.raw)) ->
        error operation Unsupported "the Metal device has no dynamic-library support"
    | Ok () -> Ok ()

  let create ?label (library : Library.t) =
    let operation = "Metal.Dynamic_library.create" in
    on_main operation (fun () ->
        match ensure_live operation library.lifetime with
        | Error _ as failure -> failure
        | Ok () when option_exists contains_nul label ->
            error operation Invalid_argument "dynamic-library label contains a NUL byte"
        | Ok () -> (
            let device = library.device in
            match check_support operation device with
            | Error _ as failure -> failure
            | Ok ()
              when Library.kind_of_code (Metal_raw.library_kind library.raw)
                   <> Library.Dynamic_library_source ->
                error operation Invalid_argument
                  "source library was not compiled as a dynamic library"
            | Ok () -> (
                match Metal_raw.dynamic_library_create device.raw library.raw label with
                | Error message -> native_error operation message
                | Ok raw -> Ok (make device raw))))

  let load_file ?label ~(device : Device.t) path =
    let operation = "Metal.Dynamic_library.load_file" in
    on_main operation (fun () ->
        match check_support operation device with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_absolute_path operation path with
            | Error _ as failure -> failure
            | Ok () when option_exists contains_nul label ->
                error operation Invalid_argument "dynamic-library label contains a NUL byte"
            | Ok () -> (
                match Metal_raw.dynamic_library_load_file device.raw path label with
                | Error message -> native_error operation message
                | Ok raw -> Ok (make device raw))))

  let compile_source ?label ~(device : Device.t) ~libraries source =
    let operation = "Metal.Dynamic_library.compile_source" in
    on_main operation (fun () ->
        match check_support operation device with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_dynamic_libraries operation device libraries with
            | Error _ as failure -> failure
            | Ok () ->
                Library.compile_descriptor_raw operation ~device ?label ~library_type:0
                  ~install_name:None
                  ~linked_libraries:
                    (Array.of_list (List.map (fun (value : t) -> value.raw) libraries))
                  source))

  let serialize (value : t) path =
    let operation = "Metal.Dynamic_library.serialize" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_absolute_path operation path with
            | Error _ as failure -> failure
            | Ok () -> (
                match Metal_raw.dynamic_library_serialize value.raw path with
                | Error message -> native_error operation message
                | Ok () -> Ok ())))

  let destroy (value : t) =
    destroy_leaf "Metal.Dynamic_library.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Binary_archive = struct
  type t = binary_archive

  let make device raw =
    let value : binary_archive = { raw; lifetime = lifetime (); device; archive_edges = ref [] } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let create ?path ?label (device : Device.t) =
    let operation = "Metal.Binary_archive.create" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () when option_exists contains_nul label ->
            error operation Invalid_argument "binary-archive label contains a NUL byte"
        | Ok () -> (
            match path with
            | Some path -> (
                match validate_absolute_path operation path with
                | Error _ as failure -> failure
                | Ok () -> (
                    match Metal_raw.binary_archive_create device.raw (Some path) label with
                    | Error message -> native_error operation message
                    | Ok raw -> Ok (make device raw)))
            | None -> (
                match Metal_raw.binary_archive_create device.raw None label with
                | Error message -> native_error operation message
                | Ok raw -> Ok (make device raw))))

  let add_compute_functions (value : t) ?(linked_functions = []) ?(preloaded_libraries = [])
      (function_value : Function.t) =
    let operation = "Metal.Binary_archive.add_compute_functions" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_live operation function_value.lifetime with
            | Error _ as failure -> failure
            | Ok () -> (
                match ensure_same_device operation value.device function_value.library.device with
                | Error _ as failure -> failure
                | Ok ()
                  when Function.kind_of_code (Metal_raw.function_kind function_value.raw)
                       <> Function.Kernel ->
                    error operation Invalid_argument "archive compute entry point must be a kernel"
                | Ok () -> (
                    match validate_linked_functions operation value.device linked_functions with
                    | Error _ as failure -> failure
                    | Ok ()
                      when linked_functions <> []
                           && not (probe (Metal_raw.Registry.device_supports_function_pointers value.device.raw)) ->
                        error operation Unsupported
                          "archived linked functions require Metal function-pointer support"
                    | Ok () -> (
                        match
                          validate_dynamic_libraries operation value.device preloaded_libraries
                        with
                        | Error _ as failure -> failure
                        | Ok ()
                          when preloaded_libraries <> []
                               && not (probe (Metal_raw.Registry.device_supports_dynamic_libraries value.device.raw))
                          ->
                            error operation Unsupported
                              "archived preloads require Metal dynamic-library support"
                        | Ok () -> (
                            match
                              Metal_raw.binary_archive_add_compute value.raw function_value.raw
                                (Array.of_list
                                   (List.map
                                      (fun (linked : Function.t) -> linked.raw)
                                      linked_functions))
                                (Array.of_list
                                   (List.map
                                      (fun (library : Dynamic_library.t) -> library.raw)
                                      preloaded_libraries))
                            with
                            | Error message -> native_error operation message
                            | Ok () -> Ok ()))))))

  let serialize (value : t) path =
    let operation = "Metal.Binary_archive.serialize" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate_absolute_path operation path with
            | Error _ as failure -> failure
            | Ok () -> (
                match Metal_raw.binary_archive_serialize value.raw path with
                | Error message -> native_error operation message
                | Ok () -> Ok ())))

  let add_configured operation kind (value : binary_archive) first second format =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            let functions = first :: Option.to_list second in
            let rec validate = function
              | [] -> Ok ()
              | (fn : function_handle) :: rest ->
                  Result.bind (ensure_live operation fn.lifetime) (fun () ->
                      Result.bind (ensure_same_device operation value.device fn.library.device)
                        (fun () -> validate rest))
            in
            Result.bind (validate functions) (fun () ->
                match
                  Metal_raw.binary_archive5_configured_descriptor kind first.raw
                    (Option.map (fun (fn : function_handle) -> fn.raw) second)
                    format
                with
                | Error message -> native_error operation message
                | Ok descriptor -> (
                    let library = first.library in
                    let added =
                      Metal_raw.binary_archive5_add value.raw kind descriptor
                        (if kind = 0 then Some library.raw else None)
                        value.device.registry_id value.device.registry_id
                        (if kind = 0 then Some value.device.registry_id else None)
                    in
                    ignore (Metal_raw.destroy descriptor);
                    match added with
                    | Error message -> native_error operation message
                    | Ok () ->
                        List.iter
                          (fun (fn : function_handle) ->
                            attach fn.lifetime;
                            value.archive_edges := fn.lifetime :: !(value.archive_edges))
                          functions;
                        attach library.lifetime;
                        value.archive_edges := library.lifetime :: !(value.archive_edges);
                        Ok ())))

  let add_mesh_render_pipeline (value : t) ~(mesh : Function.t) ?fragment ~color_format () =
    match
      ( Function.kind mesh,
        match fragment with
        | None -> Ok None
        | Some function_value -> Result.map Option.some (Function.kind function_value) )
    with
    | (Error _ as failure), _ | _, (Error _ as failure) -> failure
    | Ok mesh_kind, _ when mesh_kind <> Function.Mesh ->
        error "Metal.Binary_archive.add_mesh_render_pipeline" Invalid_argument
          "archive mesh descriptor requires a mesh function"
    | _, Ok (Some fragment_kind) when fragment_kind <> Function.Fragment ->
        error "Metal.Binary_archive.add_mesh_render_pipeline" Invalid_argument
          "archive mesh descriptor requires a fragment function"
    | Ok _, Ok _ ->
        add_configured "Metal.Binary_archive.add_mesh_render_pipeline" 2 value mesh fragment
          (Int64.of_int (Metal_format.code color_format))

  let add_tile_render_pipeline (value : t) ~(tile : Function.t) ~color_format =
    match Function.kind tile with
    | Error _ as failure -> failure
    | Ok kind when kind <> Function.Kernel ->
        error "Metal.Binary_archive.add_tile_render_pipeline" Invalid_argument
          "archive tile descriptor requires a kernel/tile function"
    | Ok _ ->
        add_configured "Metal.Binary_archive.add_tile_render_pipeline" 4 value tile None
          (Int64.of_int (Metal_format.code color_format))

  let destroy (value : t) =
    destroy_parent "Metal.Binary_archive.destroy" value.lifetime value.raw (fun () ->
        List.iter detach !(value.archive_edges);
        value.archive_edges := [];
        detach value.device.lifetime)
end

type pipeline_buffer_mutability = Default | Mutable | Immutable

type pipeline_buffer_descriptor = {

  lifetime : lifetime;
  mutability : pipeline_buffer_mutability;
}

module Pipeline_buffer_descriptor = struct
  type mutability = pipeline_buffer_mutability = Default | Mutable | Immutable
  type t = pipeline_buffer_descriptor

  let mutability_code = function Default -> 0 | Mutable -> 1 | Immutable -> 2

end

module Compute_pipeline = struct
  type t = compute_pipeline
  type size3 = Metal_gen.Record.Mtl_size.t = { width : int64; height : int64; depth : int64 }
  type shader_validation = Default | Enabled | Disabled
  type function_handle_info = { name : string; kind : Function.kind; resource_id : int64 }

  let make device ~reflection raw raw_bindings =
    let bindings = if reflection then Some (Array.map Binding.of_raw raw_bindings) else None in
    let value : t =
      {
        raw;
        lifetime = lifetime ();
        device;
        bindings;

        max_total_threads = Metal_raw.compute_pipeline_max_total_threads raw;
      }
    in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let create ?label ?(buffer_descriptors = []) ?(linked_functions = []) ?(preloaded_libraries = [])
      ?(binary_archives = []) ?(fail_on_binary_archive_miss = false)
      ?(support_indirect_command_buffers = false) ?(reflection = false)
      (function_value : Function.t) =
    let operation = "Metal.Compute_pipeline.create" in
    on_main operation (fun () ->
        let ( let* ) value callback = Result.bind value callback in
        let* () = ensure_live operation function_value.lifetime in
        let buffer_mutabilities = Array.make 31 0 in
        let rec validate_buffers seen = function
          | [] -> Ok ()
          | (index, _) :: _ when index < 0 || index >= 31 ->
              error operation Invalid_argument "pipeline buffer index must be in [0,31)"
          | (index, _) :: _ when List.mem index seen ->
              error operation Invalid_argument "pipeline buffer indices must be unique"
          | (index, None) :: rest -> validate_buffers (index :: seen) rest
          | (index, Some (descriptor : pipeline_buffer_descriptor)) :: rest ->
              let* () = ensure_live operation descriptor.lifetime in
              buffer_mutabilities.(index) <-
                Pipeline_buffer_descriptor.mutability_code descriptor.mutability;
              validate_buffers (index :: seen) rest
        in
        let* () = validate_buffers [] buffer_descriptors in
        if option_exists contains_nul label then
          error operation Invalid_argument "pipeline label contains a NUL byte"
        else
          let device = function_value.library.device in
          if Function.kind_of_code (Metal_raw.function_kind function_value.raw) <> Function.Kernel
          then
            error operation Invalid_argument
              "the pipeline entry point must be a Metal kernel function"
          else
            let* () = validate_linked_functions operation device linked_functions in
            if
              linked_functions <> [] && not (probe (Metal_raw.Registry.device_supports_function_pointers device.raw))
            then
              error operation Unsupported "linked functions require Metal function-pointer support"
            else
              let* () = validate_dynamic_libraries operation device preloaded_libraries in
              if
                preloaded_libraries <> []
                && not (probe (Metal_raw.Registry.device_supports_dynamic_libraries device.raw))
              then
                error operation Unsupported
                  "preloaded libraries require Metal dynamic-library support"
              else
                let* () = validate_binary_archives operation device binary_archives in
                if fail_on_binary_archive_miss && binary_archives = [] then
                  error operation Invalid_argument
                    "fail-on-archive-miss requires at least one binary archive"
                else
                  let descriptor_required =
                    label <> None || linked_functions <> [] || preloaded_libraries <> []
                    || binary_archives <> [] || fail_on_binary_archive_miss
                    || support_indirect_command_buffers || reflection || buffer_descriptors <> []
                  in
                  let creation =
                    if not descriptor_required then
                      Result.map
                        (fun raw -> (raw, [||]))
                        (Metal_raw.compute_pipeline_create device.raw function_value.raw)
                    else
                      let descriptor : Metal_raw.compute_pipeline_descriptor =
                        {
                          label;
                          reflection;
                          linked_functions =
                            Array.of_list
                              (List.map (fun (value : Function.t) -> value.raw) linked_functions);
                          preloaded_libraries =
                            Array.of_list
                              (List.map
                                 (fun (value : Dynamic_library.t) -> value.raw)
                                 preloaded_libraries);
                          binary_archives =
                            Array.of_list
                              (List.map
                                 (fun (value : Binary_archive.t) -> value.raw)
                                 binary_archives);
                          fail_on_binary_archive_miss;
                          support_indirect_command_buffers;
                          buffer_mutabilities;
                        }
                      in
                      Metal_raw.compute_pipeline_create_descriptor device.raw function_value.raw
                        descriptor
                  in
                  match creation with
                  | Error message -> native_error operation message
                  | Ok (raw, raw_bindings) -> Ok (make device ~reflection raw raw_bindings))

  let bindings (value : t) = Option.map Array.to_list value.bindings

  let destroy (value : t) =
    destroy_parent "Metal.Compute_pipeline.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

module Function_handle = struct
  type t = linked_function_handle

  let create ~(pipeline : compute_pipeline) ~(function_ : function_handle) =
    let operation = "Metal.Function_handle.create" in
    on_main operation (fun () ->
        match ensure_live operation pipeline.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_live operation function_.lifetime with
            | Error _ as failure -> failure
            | Ok () when function_.library.device.lifetime != pipeline.device.lifetime ->
                error operation Device_mismatch "function and pipeline use different devices"
            | Ok () -> (
                match Metal_raw.compute_pipeline_function_handle pipeline.raw function_.raw with
                | Error message -> error operation Unsupported message
                | Ok raw ->
                    let value = { raw; lifetime = lifetime (); pipeline; function_ } in
                    attach pipeline.lifetime;
                    attach function_.lifetime;
                    Gc.finalise
                      (fun _ ->
                        finalize_child value.lifetime pipeline.lifetime (fun () ->
                            detach function_.lifetime))
                      value;
                    Ok value)))

  let destroy (value : t) =
    destroy_parent "Metal.Function_handle.destroy" value.lifetime value.raw (fun () ->
        detach value.function_.lifetime;
        detach value.pipeline.lifetime)
end

module Visible_function_table = struct
  type t = visible_function_table

  let create ~(pipeline : compute_pipeline) ~capacity =
    let operation = "Metal.Visible_function_table.create" in
    on_main operation (fun () ->
        if capacity <= 0 || capacity > 1_000_000 then
          error operation Invalid_argument "capacity must be between 1 and 1000000"
        else
          match ensure_live operation pipeline.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match
                Metal_raw.compute_pipeline_visible_function_table pipeline.raw
                  (Int64.of_int capacity)
              with
              | Error message -> native_error operation message
              | Ok raw ->
                  let value =
                    {
                      raw;
                      lifetime = lifetime ();
                      pipeline;
                      capacity;
                      functions = Array.make capacity None;
                    }
                  in
                  attach pipeline.lifetime;
                  attach_finalizer
                    ~on_finalize:(fun () ->
                      Array.iter
                        (Option.iter (fun (item : linked_function_handle) -> detach item.lifetime))
                        value.functions)
                    value value.lifetime pipeline.lifetime;
                  Ok value))

  let set_function (value : t) ~index function_ =
    let operation = "Metal.Visible_function_table.set_function" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when index < 0 || index >= value.capacity ->
            error operation Invalid_argument "function-table index is out of range"
        | Ok () -> (
            match function_ with
            | Some (handle : linked_function_handle)
              when handle.pipeline.device.lifetime != value.pipeline.device.lifetime ->
                error operation Device_mismatch "function handle belongs to another device"
            | _ -> (
                match
                  Metal_raw.visible_function_table_set_function value.raw
                    (Option.map (fun (handle : linked_function_handle) -> handle.raw) function_)
                    index
                with
                | Error message -> native_error operation message
                | Ok () ->
                    Option.iter
                      (fun (old : linked_function_handle) -> detach old.lifetime)
                      value.functions.(index);
                    Option.iter
                      (fun (next : linked_function_handle) -> attach next.lifetime)
                      function_;
                    value.functions.(index) <- function_;
                    Ok ())))

  let destroy (value : t) =
    destroy_parent "Metal.Visible_function_table.destroy" value.lifetime value.raw (fun () ->
        Array.iter
          (Option.iter (fun (item : linked_function_handle) -> detach item.lifetime))
          value.functions;
        Array.fill value.functions 0 value.capacity None;
        detach value.pipeline.lifetime)
end

module Intersection_function_table = struct
  type t = intersection_function_table
  type opaque_shape = Triangle | Curve

  let create ~(pipeline : compute_pipeline) ~capacity =
    let operation = "Metal.Intersection_function_table.create" in
    on_main operation (fun () ->
        if capacity <= 0 || capacity > 1_000_000 then
          error operation Invalid_argument "capacity must be between 1 and 1000000"
        else
          match ensure_live operation pipeline.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match
                Metal_raw.compute_pipeline_intersection_function_table pipeline.raw
                  (Int64.of_int capacity)
              with
              | Error message -> native_error operation message
              | Ok raw ->
                  let value =
                    {
                      raw;
                      lifetime = lifetime ();
                      pipeline;
                      capacity;
                      functions = Array.make capacity None;
                      buffers = Array.make capacity None;
                      visible_tables = Array.make capacity None;
                    }
                  in
                  attach pipeline.lifetime;
                  let release values lifetime =
                    Array.iter (Option.iter (fun item -> detach (lifetime item))) values
                  in
                  attach_finalizer
                    ~on_finalize:(fun () ->
                      release value.functions (fun item -> item.lifetime);
                      release value.buffers (fun item -> item.lifetime);
                      release value.visible_tables (fun item -> item.lifetime))
                    value value.lifetime pipeline.lifetime;
                  Ok value))

  let validate (value : t) operation index =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () when index < 0 || index >= value.capacity ->
        error operation Invalid_argument "function-table index is out of range"
    | Ok () -> Ok ()

  let replace values index lifetime next =
    Option.iter (fun old -> detach (lifetime old)) values.(index);
    Option.iter (fun item -> attach (lifetime item)) next;
    values.(index) <- next

  let set_function (value : t) ~index function_ =
    let operation = "Metal.Intersection_function_table.set_function" in
    on_main operation (fun () ->
        match validate value operation index with
        | Error _ as failure -> failure
        | Ok () -> (
            match function_ with
            | Some (item : linked_function_handle)
              when item.pipeline.device.lifetime != value.pipeline.device.lifetime ->
                error operation Device_mismatch "function handle belongs to another device"
            | _ -> (
                match
                  Metal_raw.intersection_function_table_set_function value.raw
                    (Option.map (fun (item : linked_function_handle) -> item.raw) function_)
                    index
                with
                | Error message -> native_error operation message
                | Ok () ->
                    replace value.functions index (fun item -> item.lifetime) function_;
                    Ok ())))

  let set_buffer (value : t) ~index ?(offset = 0L) buffer =
    let operation = "Metal.Intersection_function_table.set_buffer" in
    on_main operation (fun () ->
        match validate value operation index with
        | Error _ as failure -> failure
        | Ok () when offset < 0L -> error operation Invalid_argument "buffer offset is negative"
        | Ok () -> (
            match buffer with
            | Some (item : buffer) when item.device.lifetime != value.pipeline.device.lifetime ->
                error operation Device_mismatch "buffer belongs to another device"
            | Some item when offset >= item.length ->
                error operation Invalid_argument "buffer offset exceeds its length"
            | _ -> (
                match
                  Metal_raw.intersection_function_table_set_buffer value.raw
                    (Option.map (fun (item : buffer) -> item.raw) buffer)
                    offset index
                with
                | Error message -> native_error operation message
                | Ok () ->
                    replace value.buffers index (fun item -> item.lifetime) buffer;
                    Ok ())))

  let destroy (value : t) =
    destroy_parent "Metal.Intersection_function_table.destroy" value.lifetime value.raw (fun () ->
        Array.iter
          (Option.iter (fun (item : linked_function_handle) -> detach item.lifetime))
          value.functions;
        Array.iter (Option.iter (fun (item : buffer) -> detach item.lifetime)) value.buffers;
        Array.iter
          (Option.iter (fun (item : visible_function_table) -> detach item.lifetime))
          value.visible_tables;
        Array.fill value.functions 0 value.capacity None;
        Array.fill value.buffers 0 value.capacity None;
        Array.fill value.visible_tables 0 value.capacity None;
        detach value.pipeline.lifetime)
end

module Render_pipeline = struct
  type t = render_pipeline
  type size3 = { width : int64; height : int64; depth : int64 }
  type shader_validation = Default | Enabled | Disabled
  type kind = render_pipeline_kind = Render | Tile | Mesh
  type primitive_topology = Point | Line | Triangle
  type color_attachment_mapping = render_color_attachment_mapping = Identity | Inherited
  type blend_state = render_blend_state = Blend_disabled | Blend_enabled

  type blend_factor = render_blend_factor =
    | Blend_zero
    | Blend_one
    | Blend_source_color
    | Blend_one_minus_source_color
    | Blend_source_alpha
    | Blend_one_minus_source_alpha
    | Blend_destination_color
    | Blend_one_minus_destination_color
    | Blend_destination_alpha
    | Blend_one_minus_destination_alpha
    | Blend_source_alpha_saturated
    | Blend_color
    | Blend_one_minus_color
    | Blend_alpha
    | Blend_one_minus_alpha
    | Blend_source1_color
    | Blend_one_minus_source1_color
    | Blend_source1_alpha
    | Blend_one_minus_source1_alpha

  type blend_operation = render_blend_operation =
    | Blend_add
    | Blend_subtract
    | Blend_reverse_subtract
    | Blend_min
    | Blend_max

  type color_write = render_color_write = Write_red | Write_green | Write_blue | Write_alpha

  type color_attachment = render_color_attachment = {
    format : Texture.format;
    blending : blend_state;
    source_rgb : blend_factor;
    destination_rgb : blend_factor;
    rgb_operation : blend_operation;
    source_alpha : blend_factor;
    destination_alpha : blend_factor;
    alpha_operation : blend_operation;
    write_mask : color_write list;
  }

  type reflection = {
    vertex : Binding.t list;
    fragment : Binding.t list;
    tile : Binding.t list;
    object_ : Binding.t list;
    mesh : Binding.t list;
  }

  let color_attachment ?(blending = Blend_disabled) ?(source_rgb = Blend_one)
      ?(destination_rgb = Blend_zero) ?(rgb_operation = Blend_add) ?(source_alpha = Blend_one)
      ?(destination_alpha = Blend_zero) ?(alpha_operation = Blend_add)
      ?(write_mask = [ Write_red; Write_green; Write_blue; Write_alpha ]) format =
    {
      format;
      blending;
      source_rgb;
      destination_rgb;
      rgb_operation;
      source_alpha;
      destination_alpha;
      alpha_operation;
      write_mask;
    }

  let blend_state_code = function Blend_disabled -> 0 | Blend_enabled -> 1
  let color_attachment_mapping_code = function Identity -> 0 | Inherited -> 1

  let blend_factor_code = function
    | Blend_zero -> 0
    | Blend_one -> 1
    | Blend_source_color -> 2
    | Blend_one_minus_source_color -> 3
    | Blend_source_alpha -> 4
    | Blend_one_minus_source_alpha -> 5
    | Blend_destination_color -> 6
    | Blend_one_minus_destination_color -> 7
    | Blend_destination_alpha -> 8
    | Blend_one_minus_destination_alpha -> 9
    | Blend_source_alpha_saturated -> 10
    | Blend_color -> 11
    | Blend_one_minus_color -> 12
    | Blend_alpha -> 13
    | Blend_one_minus_alpha -> 14
    | Blend_source1_color -> 15
    | Blend_one_minus_source1_color -> 16
    | Blend_source1_alpha -> 17
    | Blend_one_minus_source1_alpha -> 18

  let blend_operation_code = function
    | Blend_add -> 0
    | Blend_subtract -> 1
    | Blend_reverse_subtract -> 2
    | Blend_min -> 3
    | Blend_max -> 4

  let color_write_bit = function
    | Write_red -> 8
    | Write_green -> 4
    | Write_blue -> 2
    | Write_alpha -> 1

  let write_mask_code values =
    List.fold_left (fun mask value -> mask lor color_write_bit value) 0 values

  let raw_color_attachment (value : color_attachment) =
    ({
       Metal_raw.pixel_format = Metal_format.code value.format;
       blending_state = blend_state_code value.blending;
       source_rgb_blend_factor = blend_factor_code value.source_rgb;
       destination_rgb_blend_factor = blend_factor_code value.destination_rgb;
       rgb_blend_operation = blend_operation_code value.rgb_operation;
       source_alpha_blend_factor = blend_factor_code value.source_alpha;
       destination_alpha_blend_factor = blend_factor_code value.destination_alpha;
       alpha_blend_operation = blend_operation_code value.alpha_operation;
       write_mask = write_mask_code value.write_mask;
     }
      : Metal_raw.metal4_render_color_attachment_descriptor)

  let topology_code = function Point -> 1 | Line -> 2 | Triangle -> 3

  let make ?mesh_constraints ?tile_constraints ?color_attachments ?vertex_descriptor:_
      ?alpha_to_coverage:_ ?alpha_to_one:_ ?max_vertex_amplification_count:_
      ?color_attachment_mapping:_ device ~kind ~raster_sample_count ~color_formats
      ~reflection raw (raw_reflection : Metal_raw.render_pipeline_reflection) =
    let map values = Array.map Binding.of_raw values in
    let reflection =
      if reflection then
        Some
          {
            vertex_bindings = map raw_reflection.vertex_bindings;
            fragment_bindings = map raw_reflection.fragment_bindings;
            tile_bindings = map raw_reflection.tile_bindings;
            object_bindings = map raw_reflection.object_bindings;
            mesh_bindings = map raw_reflection.mesh_bindings;
          }
      else None
    in
    let value : t =
      {
        raw;
        lifetime = lifetime ();
        device;
        kind;
        raster_sample_count;

        color_formats;
        color_attachments =
          Option.value color_attachments ~default:(List.map color_attachment color_formats);

        reflection;
        mesh_constraints;
        tile_constraints;
      }
    in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let state_query operation raw (value : t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> ( match raw value.raw with Error m -> native_error operation m | Ok x -> Ok x))

  let supports_indirect_command_buffers value =
    state_query "Metal.Render_pipeline.supports_indirect_command_buffers"
      Metal_raw.pipeline_render_indirect value

  let kind (value : t) = value.kind
  let color_formats (value : t) = value.color_formats
  let color_attachments (value : t) = value.color_attachments

  let reflection (value : t) =
    Option.map
      (fun reflection ->
        {
          vertex = Array.to_list reflection.vertex_bindings;
          fragment = Array.to_list reflection.fragment_bindings;
          tile = Array.to_list reflection.tile_bindings;
          object_ = Array.to_list reflection.object_bindings;
          mesh = Array.to_list reflection.mesh_bindings;
        })
      value.reflection

  module Mesh_tile = struct
    module Option = struct
      include Stdlib.Option

      let exists predicate = function Some x -> predicate x | None -> false
    end

    module Function = struct
      type kind = Fragment | Mesh | Object | Tile | Other

      let kind_of_code = function 2 -> Fragment | 3 -> Tile | 7 -> Mesh | 8 -> Object | _ -> Other
    end

    type size3 = { width : int64; height : int64; depth : int64 }
    type mutability = pipeline_buffer_mutability = Default | Mutable | Immutable

    type mesh_descriptor = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      device : device;
      functions : function_handle list;
      archives : binary_archive list;

      object_linked : linked_functions option;
      mesh_linked : linked_functions option;
      fragment_linked : linked_functions option;
      required_mesh : size3;
      required_object : size3;
      has_object : bool;
    }

    type tile_descriptor = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      device : device;
      function_ : function_handle;
      archives : binary_archive list;
      libraries : dynamic_library list;
      linked : linked_functions option;
      required : size3;
    }

    type buffer_descriptor = pipeline_buffer_descriptor

    type color_attachment = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      value : render_color_attachment;
    } [@@warning "-69"]

    type descriptor_kind = Render_descriptor | Mesh_descriptor | Tile_descriptor

    type buffer_stage =
      | Vertex_buffers
      | Fragment_buffers
      | Object_buffers
      | Mesh_buffers
      | Tile_buffers

    type pipeline_descriptor = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      descriptor_kind : descriptor_kind;
      mutable descriptor_label : string option;
      descriptor_colors : color_attachment option array;
      mutable vertex_descriptor : Vertex_descriptor.t option;
    } [@@warning "-69"]

    type color_attachment_array = color_attachment option array

    let snapshot_formats operation raw descriptor_kind =
      on_main operation (fun () ->
          match Metal_raw.render93_array_snapshot raw descriptor_kind 0 with
          | Error m -> native_error operation m
          | Ok codes ->
              Ok
                (Array.map
                   (fun code ->
                     if code = 0L then None else Metal_format.of_code (Int64.to_int code))
                   codes))

    let positive s =
      let maximum = Int64.of_int max_int in
      s.width > 0L && s.height > 0L && s.depth > 0L && s.width <= maximum && s.height <= maximum
      && s.depth <= maximum

    let validate_functions operation (device : device) (values : function_handle list) =
      let rec loop = function
        | [] -> Ok ()
        | (x : function_handle) :: xs ->
            Result.bind (ensure_live operation x.lifetime) (fun () ->
                Result.bind (ensure_same_device operation device x.library.device) (fun () ->
                    loop xs))
      in
      loop values

    let mesh_descriptor ?label ?(object_function : function_handle option)
        ?(fragment_function : function_handle option) ?(binary_archives = [])
        ~(mesh_function : function_handle) ?depth_format ?stencil_format ~required_mesh_threads
        ~required_object_threads () =
      let operation = "Metal.Render_pipeline.Mesh_tile.mesh_descriptor" in
      let zero s = s.width = 0L && s.height = 0L && s.depth = 0L in
      let object_size_valid =
        match object_function with
        | None -> zero required_object_threads
        | Some _ -> positive required_object_threads
      in
      if
        option_exists contains_nul label || not (positive required_mesh_threads && object_size_valid)
      then error operation Invalid_argument "label or required threadgroup size is invalid"
      else if Function.kind_of_code (Metal_raw.function_kind mesh_function.raw) <> Function.Mesh
      then error operation Invalid_argument "mesh_function must be a mesh-stage function"
      else if
        Option.exists
          (fun (x : function_handle) ->
            Function.kind_of_code (Metal_raw.function_kind x.raw) <> Function.Object)
          object_function
        || Option.exists
             (fun (x : function_handle) ->
               Function.kind_of_code (Metal_raw.function_kind x.raw) <> Function.Fragment)
             fragment_function
      then error operation Invalid_argument "optional functions have the wrong stage"
      else
        let functions =
          mesh_function :: List.filter_map (fun x -> x) [ object_function; fragment_function ]
        in
        let device = mesh_function.library.device in
        Result.bind (validate_functions operation device functions) (fun () ->
            match
              Metal_raw.mesh_pipeline_descriptor_owned
                {
                  object_function = Option.map (fun (x : function_handle) -> x.raw) object_function;
                  mesh_function = mesh_function.raw;
                  fragment_function =
                    Option.map (fun (x : function_handle) -> x.raw) fragment_function;
                  binary_archives =
                    Array.of_list (List.map (fun (x : binary_archive) -> x.raw) binary_archives);
                  object_linked_functions = None;
                  mesh_linked_functions = None;
                  fragment_linked_functions = None;
                }
            with
            | Error m -> native_error operation m
            | Ok raw -> (
                match
                  Metal_raw.mesh_descriptor_set_mechanical raw label
                    (Int64.of_int (Option.fold ~none:0 ~some:Metal_format.code depth_format))
                    (Int64.of_int (Option.fold ~none:0 ~some:Metal_format.code stencil_format))
                    ( required_mesh_threads.width,
                      required_mesh_threads.height,
                      required_mesh_threads.depth )
                    ( required_object_threads.width,
                      required_object_threads.height,
                      required_object_threads.depth )
                with
                | Error m ->
                    ignore (Metal_raw.destroy raw);
                    native_error operation m
                | Ok () ->
                    let value : mesh_descriptor =
                      {
                        raw;
                        lifetime = lifetime ();
                        device;
                        functions;
                        archives = binary_archives;

                        object_linked = None;
                        mesh_linked = None;
                        fragment_linked = None;
                        required_mesh = required_mesh_threads;
                        required_object = required_object_threads;
                        has_object = Option.is_some object_function;
                      }
                    in
                    List.iter (fun (x : function_handle) -> attach x.lifetime) functions;
                    List.iter (fun (x : binary_archive) -> attach x.lifetime) binary_archives;
                    Gc.finalise
                      (fun _ ->
                        if Atomic.compare_and_set value.lifetime.destroyed false true then (
                          List.iter (fun (x : function_handle) -> detach x.lifetime) value.functions;
                          List.iter (fun (x : binary_archive) -> detach x.lifetime) value.archives;
                          List.iter
                            (Option.iter (fun (x : linked_functions) -> detach x.lifetime))
                            [ value.object_linked; value.mesh_linked; value.fragment_linked ];
                          ignore (Metal_raw.destroy value.raw)))
                      value;
                    Ok value))

    let tile_descriptor ?label ?(binary_archives = []) ?(preloaded_libraries = [])
        ~(tile_function : function_handle) ~required_threads () =
      let operation = "Metal.Render_pipeline.Mesh_tile.tile_descriptor" in
      if option_exists contains_nul label || not (positive required_threads) then
        error operation Invalid_argument "label or required threadgroup size is invalid"
      else if Function.kind_of_code (Metal_raw.function_kind tile_function.raw) <> Function.Tile
      then error operation Invalid_argument "tile_function must be a tile-stage function"
      else
        let device = tile_function.library.device in
        Result.bind (validate_functions operation device [ tile_function ]) (fun () ->
            match
              Metal_raw.tile_pipeline_descriptor_owned
                {
                  tile_function = tile_function.raw;
                  binary_archives =
                    Array.of_list (List.map (fun (x : binary_archive) -> x.raw) binary_archives);
                  preloaded_libraries =
                    Array.of_list
                      (List.map (fun (x : dynamic_library) -> x.raw) preloaded_libraries);
                  linked_functions = None;
                }
            with
            | Error m -> native_error operation m
            | Ok raw -> (
                match
                  Metal_raw.tile_descriptor_set_mechanical raw label
                    (required_threads.width, required_threads.height, required_threads.depth)
                with
                | Error m ->
                    ignore (Metal_raw.destroy raw);
                    native_error operation m
                | Ok () ->
                    let value : tile_descriptor =
                      {
                        raw;
                        lifetime = lifetime ();
                        device;
                        function_ = tile_function;
                        archives = binary_archives;
                        libraries = preloaded_libraries;
                        linked = None;
                        required = required_threads;
                      }
                    in
                    attach tile_function.lifetime;
                    List.iter (fun (x : binary_archive) -> attach x.lifetime) binary_archives;
                    List.iter (fun (x : dynamic_library) -> attach x.lifetime) preloaded_libraries;
                    Gc.finalise
                      (fun _ ->
                        if Atomic.compare_and_set value.lifetime.destroyed false true then (
                          detach value.function_.lifetime;
                          List.iter (fun (x : binary_archive) -> detach x.lifetime) value.archives;
                          List.iter (fun (x : dynamic_library) -> detach x.lifetime) value.libraries;
                          Option.iter (fun (x : linked_functions) -> detach x.lifetime) value.linked;
                          ignore (Metal_raw.destroy value.raw)))
                      value;
                    Ok value))

    let tuple ({ width; height; depth } : size3) =
      (Int64.to_int width, Int64.to_int height, Int64.to_int depth)

    let set_color_format ~tile operation raw lifetime ~index format =
      on_main operation (fun () ->
          match ensure_live operation lifetime with
          | Error _ as e -> e
          | Ok () when index < 0 || index >= 8 ->
              error operation Invalid_argument "color attachment index is outside [0,8)"
          | Ok () -> (
              match
                Metal_raw.mesh_tile_descriptor_set_color_format raw tile index
                  (Texture.format_code format)
              with
              | Error m -> native_error operation m
              | Ok () -> Ok ()))

    let set_mesh_color_format (value : mesh_descriptor) ~index format =
      set_color_format ~tile:false "Metal.Render_pipeline.Mesh_tile.set_mesh_color_format" value.raw
        value.lifetime ~index format

    let set_tile_color_format (value : tile_descriptor) ~index format =
      set_color_format ~tile:true "Metal.Render_pipeline.Mesh_tile.set_tile_color_format" value.raw
        value.lifetime ~index format

    let compile_mesh ?(reflection = false) (value : mesh_descriptor) =
      let operation = "Metal.Render_pipeline.Mesh_tile.compile_mesh" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live operation value.device.lifetime with
              | Error _ as e -> e
              | Ok () -> (
                  match
                    Metal_raw.mesh_pipeline_compile value.device.raw value.raw
                      (if reflection then 3L else 0L)
                  with
                  | Error m -> native_error operation m
                  | Ok (raw, reflected) ->
                      let constraints =
                        {
                          has_object_stage = value.has_object;
                          required_object_threads =
                            (if value.has_object then Some (tuple value.required_object) else None);
                          required_mesh_threads = Some (tuple value.required_mesh);
                        }
                      in
                      (* Color formats set on the descriptor become the pipeline's. *)
                      let color_formats =
                        match snapshot_formats operation value.raw 1 with
                        | Ok formats -> List.filter_map Fun.id (Array.to_list formats)
                        | Error _ -> []
                      in
                      Ok
                        (make ~mesh_constraints:constraints value.device ~kind:Mesh
                           ~raster_sample_count:1 ~color_formats ~reflection raw reflected))))

    let compile_tile ?(reflection = false) (value : tile_descriptor) =
      let operation = "Metal.Render_pipeline.Mesh_tile.compile_tile" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live operation value.device.lifetime with
              | Error _ as e -> e
              | Ok () -> (
                  match
                    Metal_raw.tile_pipeline_compile value.device.raw value.raw
                      (if reflection then 3L else 0L)
                  with
                  | Error m -> native_error operation m
                  | Ok (raw, reflected) ->
                      let constraints =
                        {
                          required_tile_threads = Some (tuple value.required);
                        }
                      in
                      let color_formats =
                        match snapshot_formats operation value.raw 2 with
                        | Ok formats -> List.filter_map Fun.id (Array.to_list formats)
                        | Error _ -> []
                      in
                      Ok
                        (make ~tile_constraints:constraints value.device ~kind:Tile
                           ~raster_sample_count:1 ~color_formats ~reflection raw reflected))))

    let destroy_mesh (value : mesh_descriptor) =
      destroy_leaf "Metal.Render_pipeline.Mesh_tile.destroy_mesh" value.lifetime value.raw
        (fun () ->
          List.iter (fun (x : function_handle) -> detach x.lifetime) value.functions;
          List.iter (fun (x : binary_archive) -> detach x.lifetime) value.archives;
          List.iter
            (Option.iter (fun (x : linked_functions) -> detach x.lifetime))
            [ value.object_linked; value.mesh_linked; value.fragment_linked ])

    let destroy_tile (value : tile_descriptor) =
      destroy_leaf "Metal.Render_pipeline.Mesh_tile.destroy_tile" value.lifetime value.raw
        (fun () ->
          detach value.function_.lifetime;
          List.iter (fun (x : binary_archive) -> detach x.lifetime) value.archives;
          List.iter (fun (x : dynamic_library) -> detach x.lifetime) value.libraries;
          Option.iter (fun (x : linked_functions) -> detach x.lifetime) value.linked)
  end

  let destroy (value : t) =
    destroy_parent "Metal.Render_pipeline.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

let ensure_metal4 operation (device : Device.t) =
  match ensure_live operation device.lifetime with
  | Error _ as failure -> failure
  | Ok () when not (Result.value ~default:false
      (Metal_raw.Registry.device_supports_family device.raw (Int64.of_int (Device.family_code Device.Metal4))))
    ->
      error operation Unsupported "the Metal device does not support Metal 4"
  | Ok () -> Ok ()

module Pipeline_dataset = struct
  type t = pipeline_dataset
  type capture = Descriptors | Binaries

end

module Binary_function = struct
  type t = binary_function
  type function_t = t

  module Descriptor = struct
    type t = binary_functions_descriptor
    type stage = Vertex | Fragment | Tile | Object | Mesh

  end
end

module Pipeline_archive = struct
  type t = pipeline_archive

end

let validate_binary_functions operation device functions =
  let rec loop names seen = function
    | [] -> Ok ()
    | (function_ : binary_function) :: rest -> (
        if List.exists (fun (value : binary_function) -> value.lifetime == function_.lifetime) seen
        then error operation Invalid_argument "binary-function list contains a duplicate handle"
        else
          match ensure_live operation function_.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match ensure_same_device operation device function_.device with
              | Error _ as failure -> failure
              | Ok () ->
                  if List.mem function_.name names then
                    error operation Invalid_argument
                      "binary-function list contains a duplicate name"
                  else loop (function_.name :: names) (function_ :: seen) rest))
  in
  loop [] [] functions

let validate_pipeline_archives operation device archives =
  let rec loop seen = function
    | [] -> Ok ()
    | (archive : pipeline_archive) :: rest -> (
        if List.exists (fun (value : pipeline_archive) -> value.lifetime == archive.lifetime) seen
        then error operation Invalid_argument "pipeline-archive list contains a duplicate handle"
        else
          match ensure_live operation archive.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match ensure_same_device operation device archive.device with
              | Error _ as failure -> failure
              | Ok () -> loop (archive :: seen) rest))
  in
  loop [] archives

module Compiler = struct
  type t = compiler
  type static_function = { library : Library.t; name : string }

  type static_linking = {
    functions : static_function list;
    private_functions : static_function list;
    groups : (string * static_function list) list;
  }

  type stage_linking = {
    binary_functions : Binary_function.t list;
    preloaded_libraries : Dynamic_library.t list;
    max_call_stack_depth : int;
  }

  let validate_static_functions operation device category functions =
    let rec loop names reversed = function
      | [] -> Ok (Array.of_list (List.rev reversed))
      | function_ :: rest -> (
          match ensure_live operation function_.library.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match ensure_same_device operation device function_.library.device with
              | Error _ as failure -> failure
              | Ok () when function_.name = "" || contains_nul function_.name ->
                  error operation Invalid_argument
                    (category ^ " function name must be nonempty and contain no NUL byte")
              | Ok () when List.mem function_.name names ->
                  error operation Invalid_argument
                    (category ^ " function list contains a duplicate name")
              | Ok () ->
                  loop (function_.name :: names)
                    ((function_.library.raw, function_.name) :: reversed)
                    rest))
    in
    loop [] [] functions

  let validate_static_linking ?supports_public_linking operation device = function
    | None -> Ok None
    | Some ({ functions; private_functions; groups } : static_linking) ->
        let ( let* ) result callback = Result.bind result callback in
        if functions = [] && private_functions = [] && groups = [] then
          error operation Invalid_argument
            "static-linking descriptor must contain at least one function"
        else
          let* raw_functions =
            validate_static_functions operation device "public static-linked" functions
          in
          let* raw_private_functions =
            validate_static_functions operation device "private static-linked" private_functions
          in
          let public_names = List.map (fun value -> value.name) functions in
          let private_names = List.map (fun value -> value.name) private_functions in
          if List.exists (fun name -> List.mem name private_names) public_names then
            error operation Invalid_argument
              "a static-linked function cannot be both public and private"
          else
            let rec validate_groups names reversed = function
              | [] -> Ok (Array.of_list (List.rev reversed))
              | (name, _) :: _ when name = "" || contains_nul name ->
                  error operation Invalid_argument
                    "static-link group name must be nonempty and contain no NUL byte"
              | (name, _) :: _ when List.mem name names ->
                  error operation Invalid_argument "static-link groups contain a duplicate name"
              | (_, []) :: _ ->
                  error operation Invalid_argument
                    "static-link groups must contain at least one function"
              | (name, functions) :: rest ->
                  let* raw_group =
                    validate_static_functions operation device ("static-link group " ^ name)
                      functions
                  in
                  validate_groups (name :: names) ((name, raw_group) :: reversed) rest
            in
            let* raw_groups = validate_groups [] [] groups in
            let supports_public_linking =
              match supports_public_linking with
              | Some supported -> supported
              | None -> probe (Metal_raw.Registry.device_supports_function_pointers device.raw)
            in
            if (functions <> [] || groups <> []) && not supports_public_linking then
              error operation Unsupported
                "public static linking requires Metal function-pointer support"
            else
              Ok
                (Some
                   ({
                      functions = raw_functions;
                      private_functions = raw_private_functions;
                      groups = raw_groups;
                    }
                     : Metal_raw.metal4_static_linking_descriptor))

  let make device dataset raw =
    let value : t = { raw; lifetime = lifetime (); device; dataset } in
    attach device.lifetime;
    Option.iter (fun (dataset : pipeline_dataset) -> attach dataset.lifetime) dataset;
    attach_finalizer
      ~on_finalize:(fun () ->
        Option.iter (fun (dataset : pipeline_dataset) -> detach dataset.lifetime) dataset)
      value value.lifetime device.lifetime;
    value

  let create ?label ?dataset device =
    let operation = "Metal.Compiler.create" in
    on_main operation (fun () ->
        let ( let* ) value callback = Result.bind value callback in
        let* () = ensure_metal4 operation device in
        if option_exists contains_nul label then
          error operation Invalid_argument "compiler label contains a NUL byte"
        else
          let* () =
            match dataset with
            | None -> Ok ()
            | Some (dataset : Pipeline_dataset.t) ->
                let* () = ensure_live operation dataset.lifetime in
                ensure_same_device operation device dataset.device
          in
          match
            Metal_raw.compiler_create device.raw
              (Option.map (fun (value : Pipeline_dataset.t) -> value.raw) dataset)
              label
          with
          | Error message -> native_error operation message
          | Ok raw -> Ok (make device dataset raw))

  let validate_pipeline_entry operation (library : Library.t) ~stage name =
    if name = "" || contains_nul name then
      error operation Invalid_argument
        (stage ^ " function name must be nonempty and contain no NUL byte")
    else if not (Array.exists (String.equal name) (Metal_raw.library_function_names library.raw))
    then error operation Invalid_argument (stage ^ " function is absent from the source library")
    else Ok ()

  let validate_optional_pipeline_entry operation library ~stage = function
    | None -> Ok ()
    | Some name -> validate_pipeline_entry operation library ~stage name

  let resolve_color_attachments operation ?color_formats ?color_attachments () =
    match (color_formats, color_attachments) with
    | Some _, Some _ ->
        error operation Invalid_argument
          "color_formats and color_attachments are mutually exclusive"
    | Some formats, None -> Ok (List.map Render_pipeline.color_attachment formats)
    | None, Some attachments -> Ok attachments
    | None, None -> Ok [ Render_pipeline.color_attachment Texture.Bgra8_unorm ]

  let raw_stage_dynamic_linking operation device ~support_binary_linking ~stage = function
    | None -> Ok None
    | Some (linking : stage_linking) ->
        let ( let* ) result callback = Result.bind result callback in
        if linking.max_call_stack_depth <= 0 then
          error operation Invalid_argument
            (stage ^ " dynamic-link call-stack depth must be positive")
        else
          let* () = validate_binary_functions operation device linking.binary_functions in
          let* () = validate_dynamic_libraries operation device linking.preloaded_libraries in
          if linking.binary_functions <> [] && not support_binary_linking then
            error operation Invalid_argument
              (stage ^ " binary functions require binary-linking support")
          else if
            linking.preloaded_libraries <> []
            && not (probe (Metal_raw.Registry.device_supports_dynamic_libraries device.raw))
          then
            error operation Unsupported
              (stage ^ " preloaded libraries require dynamic-library support")
          else
            Ok
              (Some
                 ({
                    max_call_stack_depth = Int64.of_int linking.max_call_stack_depth;
                    binary_linked_functions =
                      Array.of_list
                        (List.map
                           (fun (function_ : Binary_function.t) -> function_.raw)
                           linking.binary_functions);
                    preloaded_libraries =
                      Array.of_list
                        (List.map
                           (fun (library : Dynamic_library.t) -> library.raw)
                           linking.preloaded_libraries);
                  }
                   : Metal_raw.metal4_stage_dynamic_linking_descriptor))

  let validate_render_target operation (device : Device.t) ~has_fragment ~raster_sample_count
      ~color_attachments ~rasterization_enabled =
    if rasterization_enabled <> has_fragment then
      error operation Invalid_argument "rasterization requires exactly one fragment function"
    else if
      (rasterization_enabled && color_attachments = [])
      || ((not rasterization_enabled) && color_attachments <> [])
      || List.length color_attachments > 8
    then
      error operation Invalid_argument
        "render color attachments must match rasterization and not exceed eight"
    else if
      List.exists
        (fun (attachment : Render_pipeline.color_attachment) ->
          Metal_format.is_depth_or_stencil attachment.format)
        color_attachments
    then error operation Invalid_argument "render color attachments require color pixel formats"
    else if
      List.exists
        (fun (attachment : Render_pipeline.color_attachment) ->
          List.length attachment.write_mask
          <> List.length (List.sort_uniq compare attachment.write_mask))
        color_attachments
    then error operation Invalid_argument "render color-write masks contain duplicate channels"
    else if raster_sample_count <= 0 then
      error operation Invalid_argument "render raster sample count must be positive"
    else if not (probe (Metal_raw.Registry.device_supports_texture_sample_count device.raw (Int64.of_int raster_sample_count))) then
      error operation Unsupported "the Metal device does not support the render sample count"
    else
      Ok
        ( Int64.of_int raster_sample_count,
          List.map
            (fun (attachment : Render_pipeline.color_attachment) -> attachment.format)
            color_attachments,
          Array.of_list (List.map Render_pipeline.raw_color_attachment color_attachments) )

  let with_render_descriptor operation callback ?label ?fragment ?(reflection = false)
      ?(raster_sample_count = 1) ?color_formats ?color_attachments ?vertex_descriptor
      ?(alpha_to_coverage = false) ?(alpha_to_one = false) ?(max_vertex_amplification_count = 1)
      ?(color_attachment_mapping = Render_pipeline.Identity)
      ?(support_vertex_binary_linking = false) ?(support_fragment_binary_linking = false)
      ?vertex_dynamic_linking ?fragment_dynamic_linking ?vertex_static_linking
      ?fragment_static_linking ?(rasterization_enabled = true)
      ?(primitive_topology = Render_pipeline.Triangle) ?(support_indirect_command_buffers = false)
      ?(lookup_archives = []) (value : t) ~(library : Library.t) ~vertex =
    on_main operation (fun () ->
        let ( let* ) result callback = Result.bind result callback in
        let* () = ensure_live operation value.lifetime in
        let* () = ensure_live operation library.lifetime in
        let* () = ensure_same_device operation value.device library.device in
        let* () = validate_pipeline_entry operation library ~stage:"vertex" vertex in
        let* () = validate_optional_pipeline_entry operation library ~stage:"fragment" fragment in
        let render_function_pointers =
          probe (Metal_raw.Registry.device_supports_function_pointers_from_render value.device.raw)
        in
        if option_exists contains_nul label then
          error operation Invalid_argument "render-pipeline label contains a NUL byte"
        else if max_vertex_amplification_count <= 0 then
          error operation Invalid_argument "maximum vertex amplification count must be positive"
        else if
          not
            (probe (Metal_raw.Registry.device_supports_vertex_amplification_count value.device.raw (Int64.of_int max_vertex_amplification_count)))
        then
          error operation Unsupported
            "the Metal device does not support the vertex amplification count"
        else if
          Option.is_none fragment
          && (support_fragment_binary_linking
             || Option.is_some fragment_dynamic_linking
             || Option.is_some fragment_static_linking)
        then error operation Invalid_argument "fragment-stage linking requires a fragment function"
        else
          let* color_attachments =
            resolve_color_attachments operation ?color_formats ?color_attachments ()
          in
          let* raster_sample_count, color_formats, raw_color_attachments =
            validate_render_target operation value.device ~has_fragment:(Option.is_some fragment)
              ~raster_sample_count ~color_attachments ~rasterization_enabled
          in
          let* () =
            if
              (support_vertex_binary_linking || support_fragment_binary_linking)
              && not render_function_pointers
            then
              error operation Unsupported "render binary linking requires function-pointer support"
            else Ok ()
          in
          let* vertex_dynamic_linking =
            raw_stage_dynamic_linking operation value.device
              ~support_binary_linking:support_vertex_binary_linking ~stage:"vertex"
              vertex_dynamic_linking
          in
          let* fragment_dynamic_linking =
            raw_stage_dynamic_linking operation value.device
              ~support_binary_linking:support_fragment_binary_linking ~stage:"fragment"
              fragment_dynamic_linking
          in
          let* vertex_static_linking =
            validate_static_linking ~supports_public_linking:render_function_pointers operation
              value.device vertex_static_linking
          in
          let* fragment_static_linking =
            validate_static_linking ~supports_public_linking:render_function_pointers operation
              value.device fragment_static_linking
          in
          let* () = validate_pipeline_archives operation value.device lookup_archives in
          let descriptor : Metal_raw.metal4_render_descriptor =
            {
              label;
              library = library.raw;
              vertex_function = vertex;
              fragment_function = fragment;
              reflection;
              raster_sample_count;
              color_attachments = raw_color_attachments;
              rasterization_enabled;
              primitive_topology = Render_pipeline.topology_code primitive_topology;
              support_indirect_commands = support_indirect_command_buffers;
              lookup_archives =
                Array.of_list
                  (List.map (fun (archive : Pipeline_archive.t) -> archive.raw) lookup_archives);
              vertex_descriptor = Option.map Vertex_descriptor.raw vertex_descriptor;
              support_vertex_binary_linking;
              support_fragment_binary_linking;
              vertex_dynamic_linking;
              fragment_dynamic_linking;
              vertex_static_linking;
              fragment_static_linking;
              alpha_to_coverage;
              alpha_to_one;
              max_vertex_amplification_count = Int64.of_int max_vertex_amplification_count;
              color_attachment_mapping =
                Render_pipeline.color_attachment_mapping_code color_attachment_mapping;
            }
          in
          callback reflection vertex_descriptor color_attachments color_formats descriptor)

  let create_render_pipeline ?label ?fragment ?(reflection = false) ?(raster_sample_count = 1)
      ?color_formats ?color_attachments ?vertex_descriptor ?(alpha_to_coverage = false)
      ?(alpha_to_one = false) ?(max_vertex_amplification_count = 1)
      ?(color_attachment_mapping = Render_pipeline.Identity)
      ?(support_vertex_binary_linking = false) ?(support_fragment_binary_linking = false)
      ?vertex_dynamic_linking ?fragment_dynamic_linking ?vertex_static_linking
      ?fragment_static_linking ?(rasterization_enabled = true)
      ?(primitive_topology = Render_pipeline.Triangle) ?(support_indirect_command_buffers = false)
      ?(lookup_archives = []) (value : t) ~(library : Library.t) ~vertex =
    let operation = "Metal.Compiler.create_render_pipeline" in
    with_render_descriptor operation
      (fun reflection vertex_descriptor color_attachments color_formats descriptor ->
        match Metal_raw.compiler_create_render_pipeline value.raw descriptor with
        | Error message -> native_error operation message
        | Ok (raw, raw_reflection) ->
            Ok
              (Render_pipeline.make value.device ~kind:Render_pipeline.Render ~raster_sample_count
                 ~alpha_to_coverage ~alpha_to_one ~max_vertex_amplification_count
                 ~color_attachment_mapping ~color_formats ~color_attachments ?vertex_descriptor
                 ~reflection raw raw_reflection))
      ?label ?fragment ~reflection ~raster_sample_count ?color_formats ?color_attachments
      ?vertex_descriptor ~alpha_to_coverage ~alpha_to_one ~max_vertex_amplification_count
      ~color_attachment_mapping ~support_vertex_binary_linking ~support_fragment_binary_linking
      ?vertex_dynamic_linking ?fragment_dynamic_linking ?vertex_static_linking
      ?fragment_static_linking ~rasterization_enabled ~primitive_topology
      ~support_indirect_command_buffers ~lookup_archives value ~library ~vertex

  let destroy (value : t) =
    destroy_parent "Metal.Compiler.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime;
        Option.iter (fun (dataset : pipeline_dataset) -> detach dataset.lifetime) value.dataset)
end

module Indirect_command_buffer = struct
  type command_type = indirect_command_kind =
    | Indirect_draw
    | Indirect_draw_indexed
    | Indirect_concurrent_dispatch
    | Indirect_concurrent_dispatch_threads

  type descriptor = indirect_command_buffer_descriptor
  type t = indirect_command_buffer
  type buffer = t

  let descriptor ?(inherit_buffers = false) ?(inherit_pipeline_state = false)
      ?(max_vertex_buffer_bind_count = 0) ?(max_fragment_buffer_bind_count = 0)
      ?(max_kernel_buffer_bind_count = 0) ?(support_ray_tracing = false)
      ?(support_dynamic_attribute_stride = false) ?(max_kernel_threadgroup_memory_bind_count = 0)
      ?(max_object_buffer_bind_count = 0) ?(max_mesh_buffer_bind_count = 0)
      ?(max_object_threadgroup_memory_bind_count = 0) ?(inherit_depth_stencil_state = true)
      ?(inherit_depth_bias = true) ?(inherit_depth_clip_mode = true) ?(inherit_cull_mode = true)
      ?(inherit_front_facing_winding = true) ?(inherit_triangle_fill_mode = true)
      ?(support_color_attachment_mapping = false) ~command_types () =
    {
      command_types;
      inherit_buffers;
      inherit_pipeline_state;
      max_vertex_buffer_bind_count;
      max_fragment_buffer_bind_count;
      max_kernel_buffer_bind_count;
      support_ray_tracing;
      support_dynamic_attribute_stride;
      max_kernel_threadgroup_memory_bind_count;
      max_object_buffer_bind_count;
      max_mesh_buffer_bind_count;
      max_object_threadgroup_memory_bind_count;
      inherit_depth_stencil_state;
      inherit_depth_bias;
      inherit_depth_clip_mode;
      inherit_cull_mode;
      inherit_front_facing_winding;
      inherit_triangle_fill_mode;
      support_color_attachment_mapping;
    }

  let command_bit = function
    | Indirect_draw -> 1L
    | Indirect_draw_indexed -> 2L
    | Indirect_concurrent_dispatch -> 32L
    | Indirect_concurrent_dispatch_threads -> 64L

  let has kind kinds = List.exists (( = ) kind) kinds

  let release_retained retained =
    let values = !retained in
    retained := [];
    List.iter
      (function
        | Indirect_buffer value -> detach value.lifetime

        | Indirect_render_pipeline value -> detach value.lifetime
        )
      values

  let retain value retained =
    let lifetime =
      match retained with
      | Indirect_buffer value -> value.lifetime

      | Indirect_render_pipeline value -> value.lifetime

    in
    attach lifetime;
    value.retained := retained :: !(value.retained)

  let raw_descriptor (value : descriptor) =
    ({
       Metal_raw.command_types =
         List.fold_left
           (fun bits kind -> Int64.logor bits (command_bit kind))
           0L value.command_types;
       inherit_buffers = value.inherit_buffers;
       inherit_pipeline_state = value.inherit_pipeline_state;
       max_vertex_buffer_bind_count = Int64.of_int value.max_vertex_buffer_bind_count;
       max_fragment_buffer_bind_count = Int64.of_int value.max_fragment_buffer_bind_count;
       max_kernel_buffer_bind_count = Int64.of_int value.max_kernel_buffer_bind_count;
       support_ray_tracing = value.support_ray_tracing;
       support_dynamic_attribute_stride = value.support_dynamic_attribute_stride;
       max_kernel_threadgroup_memory_bind_count =
         Int64.of_int value.max_kernel_threadgroup_memory_bind_count;
       max_object_buffer_bind_count = Int64.of_int value.max_object_buffer_bind_count;
       max_mesh_buffer_bind_count = Int64.of_int value.max_mesh_buffer_bind_count;
       max_object_threadgroup_memory_bind_count =
         Int64.of_int value.max_object_threadgroup_memory_bind_count;
       inherit_depth_stencil_state = value.inherit_depth_stencil_state;
       inherit_depth_bias = value.inherit_depth_bias;
       inherit_depth_clip_mode = value.inherit_depth_clip_mode;
       inherit_cull_mode = value.inherit_cull_mode;
       inherit_front_facing_winding = value.inherit_front_facing_winding;
       inherit_triangle_fill_mode = value.inherit_triangle_fill_mode;
       support_color_attachment_mapping = value.support_color_attachment_mapping;
     }
      : Metal_raw.indirect_command_buffer_descriptor)

  let create ~(device : Device.t) ?(storage = Buffer.Private) ?(cpu_cache = Buffer.Default_cache)
      ?(hazard_tracking = Buffer.Default_hazard_tracking) ~max_command_count
      (descriptor : descriptor) =
    let operation = "Metal.Indirect_command_buffer.create" in
    on_main operation (fun () ->
        let counts =
          [
            descriptor.max_vertex_buffer_bind_count;
            descriptor.max_fragment_buffer_bind_count;
            descriptor.max_kernel_buffer_bind_count;
            descriptor.max_kernel_threadgroup_memory_bind_count;
            descriptor.max_object_buffer_bind_count;
            descriptor.max_mesh_buffer_bind_count;
            descriptor.max_object_threadgroup_memory_bind_count;
          ]
        in
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () when descriptor.command_types = [] ->
            error operation Invalid_argument "at least one indirect command type is required"
        | Ok () when List.sort_uniq compare descriptor.command_types <> descriptor.command_types ->
            error operation Invalid_argument "indirect command types must be unique and ordered"
        | Ok () when max_command_count <= 0 ->
            error operation Invalid_argument "maximum command count must be positive"
        | Ok () when List.exists (fun count -> count < 0 || count > 31) counts ->
            error operation Invalid_argument "indirect binding counts must be in [0, 31]"
        | Ok () -> (
            let options = resource_options_code ~storage ~cpu_cache ~hazard_tracking in
            match
              Metal_raw.indirect_command_buffer_create device.raw (raw_descriptor descriptor)
                (Int64.of_int max_command_count) (Int64.of_int options)
            with
            | Error message -> native_error operation message
            | Ok raw ->
                let value =
                  {
                    raw;
                    lifetime = lifetime ();
                    device;
                    max_command_count;
                    command_types = descriptor.command_types;

                    retained = ref [];
                  }
                in
                attach device.lifetime;
                attach_finalizer
                  ~on_finalize:(fun () -> release_retained value.retained)
                  value value.lifetime device.lifetime;
                Ok value))

  let validate_range operation (value : t) ~location ~length =
    if
      location < 0 || length < 0
      || location > value.max_command_count
      || length > value.max_command_count - location
    then error operation Invalid_argument "range exceeds the indirect command buffer"
    else Ok ()

  let reset (value : t) ~location ~length =
    let operation = "Metal.Indirect_command_buffer.reset" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when dependent_count value.lifetime <> 0 ->
            error operation Parent_has_dependents "indirect commands are still borrowed"
        | Ok () ->
            Result.bind (validate_range operation value ~location ~length) (fun () ->
                match
                  Metal_raw.indirect_command_buffer_reset value.raw (Int64.of_int location)
                    (Int64.of_int length)
                with
                | Error message -> native_error operation message
                | Ok () ->
                    release_retained value.retained;
                    Ok ()))

  let destroy (value : t) =
    destroy_parent "Metal.Indirect_command_buffer.destroy" value.lifetime value.raw (fun () ->
        release_retained value.retained;
        detach value.device.lifetime)

  module Render_command = struct
    type t = indirect_render_command
    type primitive = Point | Line | Line_strip | Triangle | Triangle_strip
    type index_type = Uint16 | Uint32

    let primitive_code = function
      | Point -> 0
      | Line -> 1
      | Line_strip -> 2
      | Triangle -> 3
      | Triangle_strip -> 4

    let at (value : buffer) index =
      let operation = "Metal.Indirect_command_buffer.Render_command.at" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok ()
            when not
                   (has Indirect_draw value.command_types
                   || has Indirect_draw_indexed value.command_types) ->
              error operation Invalid_state "descriptor does not enable render commands"
          | Ok () ->
              Result.bind (validate_range operation value ~location:index ~length:1) (fun () ->
                  match Metal_raw.indirect_render_command value.raw (Int64.of_int index) with
                  | Error message -> native_error operation message
                  | Ok raw ->
                      let command : t = { raw; lifetime = lifetime (); parent = value } in
                      attach value.lifetime;
                      attach_finalizer command command.lifetime value.lifetime;
                      Ok command))

    type cull_mode = No_cull | Cull_front | Cull_back
    type depth_clip_mode = Clip | Clamp
    type winding = Clockwise | Counter_clockwise
    type fill_mode = Fill | Lines

    let set_pipeline (value : t) (pipeline : Render_pipeline.t) =
      let operation = "Metal.Indirect_command_buffer.Render_command.set_pipeline" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live operation pipeline.lifetime with
              | Error _ as e -> e
              | Ok () -> (
                  match ensure_same_device operation value.parent.device pipeline.device with
                  | Error _ as e -> e
                  | Ok () -> (
                      match
                        Metal_raw.Registry.render_pipeline_state_support_indirect_command_buffers
                          pipeline.raw
                      with
                      | Error message -> native_error operation message
                      | Ok false ->
                          error operation Unsupported
                            "pipeline was not compiled for indirect command buffers"
                      | Ok true -> (
                          match
                            Metal_raw.indirect_render_command_set_pipeline value.raw pipeline.raw
                          with
                          | Error message -> native_error operation message
                          | Ok () ->
                              retain value.parent (Indirect_render_pipeline pipeline);
                              Ok ())))))

    let set_buffer operation native (value : t) ~index ~offset (buffer : Buffer.t) =
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_buffer_usable operation buffer with
              | Error _ as e -> e
              | Ok () when index < 0 || index >= 31 ->
                  error operation Invalid_argument "buffer index must be in [0, 31)"
              | Ok () when offset < 0L || offset > buffer.length ->
                  error operation Invalid_argument "buffer offset is outside the resource"
              | Ok () -> (
                  match ensure_same_device operation value.parent.device buffer.device with
                  | Error _ as e -> e
                  | Ok () -> (
                      match native value.raw buffer.raw offset index with
                      | Error message -> native_error operation message
                      | Ok () ->
                          retain value.parent (Indirect_buffer buffer);
                          Ok ()))))

    let set_vertex_buffer value ~index ~offset buffer =
      set_buffer "Metal.Indirect_command_buffer.Render_command.set_vertex_buffer"
        Metal_raw.indirect_render_command_set_vertex_buffer value ~index ~offset buffer

    let set_fragment_buffer value ~index ~offset buffer =
      set_buffer "Metal.Indirect_command_buffer.Render_command.set_fragment_buffer"
        Metal_raw.indirect_render_command_set_fragment_buffer value ~index ~offset buffer

    let draw_indexed (value : t) ~primitive ~index_type ~(index_buffer : Buffer.t) ~index_offset
        ~index_count ?(instance_count = 1L) ?(base_vertex = 0L) ?(base_instance = 0L) () =
      let operation = "Metal.Indirect_command_buffer.Render_command.draw_indexed" in
      let type_code, element = match index_type with Uint16 -> (0, 2L) | Uint32 -> (1, 4L) in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () ->
              Result.bind (ensure_buffer_usable operation index_buffer) (fun () ->
                  if
                    index_count <= 0L || instance_count <= 0L || base_instance < 0L
                    || index_offset < 0L
                    || Int64.rem index_offset element <> 0L
                    || index_offset > index_buffer.length
                    || index_count > Int64.div (Int64.sub index_buffer.length index_offset) element
                  then error operation Invalid_argument "indexed indirect draw range is invalid"
                  else
                    Result.bind
                      (ensure_same_device operation value.parent.device index_buffer.device)
                      (fun () ->
                        match
                          Metal_raw.indirect_render_draw_indexed value.raw
                            (primitive_code primitive) index_count type_code index_buffer.raw
                            index_offset instance_count base_vertex base_instance
                            value.parent.device.registry_id
                        with
                        | Error m -> native_error operation m
                        | Ok () ->
                            retain value.parent (Indirect_buffer index_buffer);
                            Ok ())))

    let draw_primitives (value : t) ~primitive ~vertex_start ~vertex_count ?(instance_count = 1)
        ?(base_instance = 0) () =
      let operation = "Metal.Indirect_command_buffer.Render_command.draw_primitives" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok ()
            when vertex_start < 0 || vertex_count <= 0 || instance_count <= 0 || base_instance < 0
            ->
              error operation Invalid_argument "draw ranges must be nonnegative and counts positive"
          | Ok () -> (
              match
                Metal_raw.indirect_render_command_draw_primitives value.raw
                  (primitive_code primitive) (Int64.of_int vertex_start) (Int64.of_int vertex_count)
                  (Int64.of_int instance_count) (Int64.of_int base_instance)
              with
              | Error message -> native_error operation message
              | Ok () -> Ok ()))

    let destroy (value : t) =
      destroy_leaf "Metal.Indirect_command_buffer.Render_command.destroy" value.lifetime value.raw
        (fun () -> detach value.parent.lifetime)
  end

end

module Command_queue = struct
  type t = command_queue

  let same_residency_set (left : residency_set) (right : residency_set) =
    left.lifetime == right.lifetime

  let rec validate_unique operation seen = function
    | [] -> Ok ()
    | value :: rest ->
        if List.exists (same_residency_set value) seen then
          error operation Invalid_argument "residency-set list contains a duplicate handle"
        else validate_unique operation (value :: seen) rest

  let validate_sets operation (value : t) residency_sets =
    match validate_unique operation [] residency_sets with
    | Error _ as failure -> failure
    | Ok () ->
        let rec loop = function
          | [] -> Ok ()
          | (residency_set : residency_set) :: rest -> (
              match ensure_live operation residency_set.lifetime with
              | Error _ as failure -> failure
              | Ok () -> (
                  match ensure_same_device operation value.device residency_set.device with
                  | Error _ as failure -> failure
                  | Ok () -> loop rest))
        in
        loop residency_sets

  let create (device : Device.t) =
    on_main "Metal.Command_queue.create" (fun () ->
        match ensure_live "Metal.Command_queue.create" device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.command_queue_create device.raw with
            | Error message -> native_error "Metal.Command_queue.create" message
            | Ok raw ->
                let residency_sets = ref [] in
                let value : t = { raw; lifetime = lifetime (); device; residency_sets } in
                attach device.lifetime;
                attach_finalizer
                  ~on_finalize:(fun () -> release_queue_residency_sets residency_sets)
                  value value.lifetime device.lifetime;
                Ok value))

  let add operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () -> (
        match validate_sets operation value residency_sets with
        | Error _ as failure -> failure
        | Ok () -> (
            let changes =
              List.filter
                (fun residency_set ->
                  not (List.exists (same_residency_set residency_set) !(value.residency_sets)))
                residency_sets
            in
            if changes = [] then Ok ()
            else
              let raw_result =
                match (bulk, changes) with
                | false, [ residency_set ] ->
                    Metal_raw.Registry.command_queue_add_residency_set value.raw residency_set.raw
                | false, _ -> assert false
                | true, _ ->
                    Metal_raw.command_queue_add_residency_sets value.raw
                      (Array.of_list (List.map (fun (set : residency_set) -> set.raw) changes))
              in
              match raw_result with
              | Error message -> native_error operation message
              | Ok () ->
                  List.iter
                    (fun (residency_set : residency_set) -> attach residency_set.lifetime)
                    changes;
                  value.residency_sets := List.rev_append changes !(value.residency_sets);
                  Ok ()))

  let add_residency_set (value : t) residency_set =
    on_main "Metal.Command_queue.add_residency_set" (fun () ->
        add "Metal.Command_queue.add_residency_set" ~bulk:false value [ residency_set ])

  let remove operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () -> (
        match validate_sets operation value residency_sets with
        | Error _ as failure -> failure
        | Ok () -> (
            let changes =
              List.filter
                (fun residency_set ->
                  List.exists (same_residency_set residency_set) !(value.residency_sets))
                residency_sets
            in
            if changes = [] then Ok ()
            else
              let raw_result =
                match (bulk, changes) with
                | false, [ residency_set ] ->
                    Metal_raw.Registry.command_queue_remove_residency_set value.raw residency_set.raw
                | false, _ -> assert false
                | true, _ ->
                    Metal_raw.command_queue_remove_residency_sets value.raw
                      (Array.of_list (List.map (fun (set : residency_set) -> set.raw) changes))
              in
              match raw_result with
              | Error message -> native_error operation message
              | Ok () ->
                  value.residency_sets :=
                    List.filter
                      (fun retained -> not (List.exists (same_residency_set retained) changes))
                      !(value.residency_sets);
                  List.iter
                    (fun (residency_set : residency_set) -> detach residency_set.lifetime)
                    changes;
                  Ok ()))

  let remove_residency_set (value : t) residency_set =
    on_main "Metal.Command_queue.remove_residency_set" (fun () ->
        remove "Metal.Command_queue.remove_residency_set" ~bulk:false value [ residency_set ])

  let destroy (value : t) =
    destroy_parent "Metal.Command_queue.destroy" value.lifetime value.raw (fun () ->
        release_queue_residency_sets value.residency_sets;
        detach value.device.lifetime)
end

module Command_buffer = struct
  type t = command_buffer
  type present_time = Immediate | At_time of float | After_minimum_duration of float

  type status =
    | Not_enqueued
    | Enqueued
    | Committed
    | Scheduled
    | Completed
    | Error of string
    | Unknown of int

  type diagnostics = {
    error_options : int64;
    gpu_start_time : float;
    gpu_end_time : float;
    kernel_start_time : float;
    kernel_end_time : float;
    retained_references : bool;
  }

  type encoder_info = { label : string option; debug_signposts : string list; error_state : int }
  type dispatch_type = Serial | Concurrent

  let release_callback_tokens tokens =
    let retained = !tokens in
    tokens := [];
    List.iter Metal_raw.command_buffer_cancel_handler retained

  let create_owned ~finalize (queue : Command_queue.t) ?label () =
    match before_main "Metal.Command_buffer.create" with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live "Metal.Command_buffer.create" queue.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match label with
            | Some label when contains_nul label ->
                error "Metal.Command_buffer.create" Invalid_argument "label contains a NUL byte"
            | _ -> (
                match Metal_raw.Registry.command_buffer_create queue.raw with
                | Error message -> native_error "Metal.Command_buffer.create" message
                | Ok raw -> (
                    let prepared_resource =
                      if finalize then
                        Some { prepared_active = false; prepared_lifetime = queue.lifetime }
                      else None
                    in
                    let prepared_command_slot =
                      {
                        prepared_command_active = false;
                        prepared_command = empty_prepared_command_resources;
                      }
                    in
                    let value : t =
                      {
                        raw;
                        lifetime = lifetime ();
                        queue;

                        phase = Recording;
                        resources = ref [];
                        retained_identities = Hashtbl.create 16;
                        prepared_resource;
                        prepared_command_slot;
                        scoped_prepared_active = false;
                        scoped_prepared_lifetime = queue.lifetime;
                        callback_tokens = ref [];
                        presentation_events = ref [];

                      }
                    in
                    attach queue.lifetime;
                    let resources = value.resources
                    and identities = value.retained_identities
                    and callback_tokens = value.callback_tokens
                    and presentation_events = value.presentation_events in
                    if finalize then
                      attach_lifetime_finalizer
                        ~on_finalize:(fun () ->
                          Option.iter
                            (fun prepared_resource ->
                              release_finalized_command_buffer_resources resources identities
                                prepared_resource prepared_command_slot)
                            prepared_resource;
                          release_callback_tokens callback_tokens;
                          List.iter detach !presentation_events;
                          presentation_events := [])
                        value.lifetime queue.lifetime;
                    match label with
                    | None -> Ok value
                    | Some label -> (
                        match Metal_raw.Registry.set_command_buffer_label raw label with
                        | Ok () -> Ok value
                        | Error message ->
                            ignore (Metal_raw.destroy raw);
                            if Atomic.compare_and_set value.lifetime.destroyed false true then
                              detach queue.lifetime;
                            native_error "Metal.Command_buffer.create" message)))))

  let create queue ?label () = create_owned ~finalize:true queue ?label ()

  module Private = struct
    (* Scoped callers must arrange [destroy] on every exit.  In particular a
       submitted buffer must first be brought to a terminal state with
       [wait_until_completed].  Omitting the finalizer prevents a blocking
       synchronous submission from depending on a later major collection. *)

  end

  let device (value : t) = value.queue.device
  let destroyed (value : t) = is_destroyed value.lifetime

  let release_presentation_events (value : t) =
    List.iter detach !(value.presentation_events);
    value.presentation_events := []

  let diagnostics (value : t) =
    let operation = "Metal.Command_buffer.diagnostics" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.presentation_command_snapshot value.raw with
            | Error m -> native_error operation m
            | Ok
                ( queue_id,
                  device_id,
                  error_options,
                  gpu_start_time,
                  gpu_end_time,
                  kernel_start_time,
                  kernel_end_time,
                  retained_references ) ->
                if
                  queue_id <> value.queue.device.registry_id
                  || device_id <> value.queue.device.registry_id
                then error operation Device_mismatch "native command-buffer device identity changed"
                else if
                  not
                    (List.for_all Float.is_finite
                       [ gpu_start_time; gpu_end_time; kernel_start_time; kernel_end_time ])
                then error operation Native_error "native command-buffer timestamps are non-finite"
                else
                  Ok
                    {
                      error_options;
                      gpu_start_time;
                      gpu_end_time;
                      kernel_start_time;
                      kernel_end_time;
                      retained_references;
                    }))

  let encode_shared_event signal (value : t) (event : command_shared_event) number =
    let operation =
      if signal then "Metal.Command_buffer.encode_signal_shared_event"
      else "Metal.Command_buffer.encode_wait_for_shared_event"
    in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () when value.phase <> Recording ->
            error operation Invalid_state "event encoding requires a recording command buffer"
        | Ok () when dependent_count value.lifetime <> 0 ->
            error operation Invalid_state "event encoding requires no open encoder"
        | Ok () -> (
            match ensure_live operation event.lifetime with
            | Error _ as e -> e
            | Ok () when event.registry_id <> value.queue.device.registry_id ->
                error operation Device_mismatch "shared event belongs to another device"
            | Ok () when number < 0L ->
                error operation Invalid_argument "event value must be nonnegative"
            | Ok () -> (
                match (if signal then Metal_raw.Registry.command_buffer_encode_signal_event value.raw event.raw number
                 else Metal_raw.Registry.command_buffer_encode_wait_for_event value.raw event.raw number) with
                | Error m -> native_error operation m
                | Ok () ->
                    attach event.lifetime;
                    value.presentation_events := event.lifetime :: !(value.presentation_events);
                    Ok ())))

  let encode_signal_shared_event value event ~value:number = encode_shared_event true value event number
  let encode_wait_for_shared_event value event ~value:number = encode_shared_event false value event number

  let retains_residency_set (value : t) (residency_set : residency_set) =
    List.exists
      (function
        | Command_residency_set retained -> retained.lifetime == residency_set.lifetime
        | Command_buffer_buffer _
        | Command_buffer_acceleration_structure _ | Command_buffer_texture _
        | Command_buffer_sampler _ | Command_buffer_render_pipeline _ | Command_buffer_indirect _
        | Command_buffer_fence _ | Command_buffer_heap _ | Command_buffer_drawable _
        | Command_buffer_depth_stencil _ | Command_buffer_visible_table _
        | Command_buffer_intersection_table _ | Command_buffer_prepared_command _ ->
            false)
      !(value.resources)

  let use operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () when value.phase <> Recording ->
        error operation Invalid_state "command buffer is no longer recording"
    | Ok () -> (
        match Command_queue.validate_sets operation value.queue residency_sets with
        | Error _ as failure -> failure
        | Ok () -> (
            let changes =
              List.filter
                (fun residency_set -> not (retains_residency_set value residency_set))
                residency_sets
            in
            if changes = [] then Ok ()
            else
              let raw_result =
                match (bulk, changes) with
                | false, [ residency_set ] ->
                    Metal_raw.Registry.command_buffer_use_residency_set value.raw residency_set.raw
                | false, _ -> assert false
                | true, _ ->
                    Metal_raw.command_buffer_use_residency_sets value.raw
                      (Array.of_list (List.map (fun (set : residency_set) -> set.raw) changes))
              in
              match raw_result with
              | Error message -> native_error operation message
              | Ok () ->
                  List.iter (retain_command_buffer_residency_set value) changes;
                  Ok ()))

  let use_residency_set (value : t) residency_set =
    on_main "Metal.Command_buffer.use_residency_set" (fun () ->
        use "Metal.Command_buffer.use_residency_set" ~bulk:false value [ residency_set ])

  let status (value : t) =
    on_main "Metal.Command_buffer.status" (fun () ->
        match ensure_live "Metal.Command_buffer.status" value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            let status = command_buffer_status value.raw in
            if status = 4 || status = 5 then begin
              release_command_buffer_resources value;
              release_callback_tokens value.callback_tokens;
              release_presentation_events value
            end;
            Ok
              (match status with
              | 0 -> Not_enqueued
              | 1 -> Enqueued
              | 2 -> Committed
              | 3 -> Scheduled
              | 4 -> Completed
              | 5 ->
                  Error
                    (Option.value
                       (Metal_raw.command_buffer_error value.raw)
                       ~default:"Metal command buffer failed without NSError")
              | value -> Unknown value))

  let present (value : t) (drawable : metal_drawable) ?(at = Immediate) () =
    let operation = "Metal.Command_buffer.present" in
    match before_main operation with
    | Error _ as error -> error
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () when value.phase <> Recording ->
            error operation Invalid_state "command buffer is no longer recording"
        | Ok () -> (
            match ensure_live operation drawable.lifetime with
            | Error _ as e -> e
            | Ok () when drawable.presentation_scheduled ->
                error operation Invalid_state "drawable is already scheduled for presentation"
            | Ok () -> (
                match ensure_same_device operation value.queue.device drawable.layer.device with
                | Error _ as error -> error
                | Ok () -> (
                    let mode, time =
                      match at with
                      | Immediate -> (0, 0.)
                      | At_time t -> (1, t)
                      | After_minimum_duration t -> (2, t)
                    in
                    if (not (Float.is_finite time)) || time < 0. then
                      error operation Invalid_argument
                        "presentation time must be finite and nonnegative"
                    else
                      match
                        Metal_raw.command_buffer_present_drawable value.raw drawable.raw mode time
                      with
                      | Error m -> native_error operation m
                      | Ok () ->
                          drawable.presentation_scheduled <- true;
                          retain_command_buffer_drawable value drawable;
                          Ok ()))))

  let commit (value : t) =
    match before_main "Metal.Command_buffer.commit" with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live "Metal.Command_buffer.commit" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when value.phase <> Recording ->
            error "Metal.Command_buffer.commit" Invalid_state "command buffer was already submitted"
        | Ok () when dependent_count value.lifetime <> 0 ->
            error "Metal.Command_buffer.commit" Invalid_state "a command encoder is still open"
        | Ok () -> (
            match Metal_raw.Registry.command_buffer_commit value.raw with
            | Error message -> native_error "Metal.Command_buffer.commit" message
            | Ok () ->
                value.phase <- Submitted;
                Ok ()))

  let wait_until_completed (value : t) =
    match before_main "Metal.Command_buffer.wait_until_completed" with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live "Metal.Command_buffer.wait_until_completed" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when value.phase <> Submitted ->
            error "Metal.Command_buffer.wait_until_completed" Invalid_state
              "command buffer has not been committed"
        | Ok () ->
            Metal_raw.command_buffer_wait value.raw;
            let status = command_buffer_status value.raw in
            if status = 4 || status = 5 then begin
              release_command_buffer_resources value;
              release_callback_tokens value.callback_tokens;
              release_presentation_events value
            end;
            if status = 4 then Ok ()
            else
              native_error "Metal.Command_buffer.wait_until_completed"
                (Option.value
                   (Metal_raw.command_buffer_error value.raw)
                   ~default:(Printf.sprintf "command buffer ended with status %d" status)))

  let destroy (value : t) =
    if
      value.phase = Submitted
      &&
      let status = command_buffer_status value.raw in
      status <> 4 && status <> 5
    then
      error "Metal.Command_buffer.destroy" Parent_has_dependents
        "submitted command buffer has not reached a terminal state"
    else
      match before_main "Metal.Command_buffer.destroy" with
      | Error _ as failure -> failure
      | Ok () ->
          if is_destroyed value.lifetime then Ok ()
          else
            let dependents = dependent_count value.lifetime in
            if dependents <> 0 then
              error "Metal.Command_buffer.destroy" Parent_has_dependents
                (Printf.sprintf "handle still owns %d live dependent(s)" dependents)
            else begin
              Atomic.set value.lifetime.destroyed true;
              (* Metal may synchronously run completion blocks while deallocating
               an uncommitted command buffer.  Cancel and unroot callbacks
               before releasing the native object so those blocks become
               harmless no-ops instead of re-entering the OCaml runtime. *)
              release_callback_tokens value.callback_tokens;
              ignore (Metal_raw.destroy value.raw);
              release_command_buffer_resources value;
              release_presentation_events value;
              detach value.queue.lifetime;
              Ok ()
            end
end

module Acceleration_encoder = struct
  type t = acceleration_encoder
  type resource_usage = Read | Write | Read_write
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type compacted_size_type = Uint32 | Uint64

  let create (command_buffer : Command_buffer.t) =
    let operation = "Metal.Acceleration_encoder.create" in
    on_main operation (fun () ->
        match ensure_live operation command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error operation Invalid_state "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error operation Invalid_state "command buffer already has an open encoder"
        | Ok () -> (
            match Metal_raw.Registry.command_buffer_acceleration_encoder command_buffer.raw with
            | Error message -> native_error operation message
            | Ok raw ->
                let value = { raw; lifetime = lifetime (); command_buffer } in
                attach command_buffer.lifetime;
                attach_finalizer value value.lifetime command_buffer.lifetime;
                Ok value))

  (* Build or refit through a generic [Build.t] descriptor; every buffer and
     structure it references stays alive until the command buffer completes. *)
  let with_descriptor operation (value : t) ~(descriptor : Acceleration_structure.Build.t)
      ~(scratch : buffer) ~scratch_offset ~required ~destinations run =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            let device = value.command_buffer.queue.device in
            match ensure_live operation descriptor.lifetime with
            | Error _ as failure -> failure
            | Ok () when not (same_device device descriptor.device) ->
                error operation Device_mismatch "descriptor belongs to another device"
            | Ok () -> (
                let buffers = scratch :: descriptor.buffers in
                let rec validate = function
                  | [] -> Ok ()
                  | (buffer : buffer) :: rest -> (
                      match ensure_live operation buffer.lifetime with
                      | Error _ as failure -> failure
                      | Ok () when buffer.device.lifetime != device.lifetime ->
                          error operation Device_mismatch "build resource belongs to another device"
                      | Ok () -> validate rest)
                in
                let rec validate_structures = function
                  | [] -> Ok ()
                  | (x : Acceleration_structure.t) :: rest -> (
                      match ensure_live operation x.lifetime with
                      | Error _ as failure -> failure
                      | Ok () when x.device.lifetime != device.lifetime ->
                          error operation Device_mismatch "structure belongs to another device"
                      | Ok () -> validate_structures rest)
                in
                match validate buffers with
                | Error _ as failure -> failure
                | Ok () -> (
                    match validate_structures (destinations @ descriptor.structures) with
                    | Error _ as failure -> failure
                    | Ok () when scratch_offset < 0L || scratch_offset > scratch.length ->
                        error operation Invalid_argument "scratch offset exceeds its buffer"
                    | Ok () -> (
                        match Metal_raw.accel_descriptor_sizes device.raw descriptor.raw with
                        | Error message -> native_error operation message
                        | Ok sizes -> (
                            let structure_size, build_scratch, refit_scratch = sizes in
                            let scratch_needed = required build_scratch refit_scratch in
                            if List.exists (fun (x : Acceleration_structure.t) -> x.size < structure_size) destinations then
                              error operation Invalid_argument
                                "destination acceleration structure is too small"
                            else if scratch_needed > Int64.sub scratch.length scratch_offset then
                              error operation Invalid_argument "scratch range is too small"
                            else
                              match run () with
                              | Error message -> native_error operation message
                              | Ok () ->
                                  List.iter (retain_command_buffer_buffer value.command_buffer) buffers;
                                  List.iter
                                    (retain_command_buffer_acceleration_structure value.command_buffer)
                                    (destinations @ descriptor.structures);
                                  Ok ()))))))

  let build_with (value : t) ~(destination : Acceleration_structure.t) ~descriptor ~scratch
      ~scratch_offset =
    with_descriptor "Metal.Acceleration_encoder.build_with" value ~descriptor ~scratch
      ~scratch_offset ~required:(fun build _ -> build) ~destinations:[ destination ] (fun () ->
        Metal_raw.accel_encoder_build_descriptor value.raw destination.raw
          descriptor.Acceleration_structure.Build.raw scratch.raw scratch_offset)

  let refit_with (value : t) ~(source : Acceleration_structure.t)
      ~(destination : Acceleration_structure.t) ~descriptor ~scratch ~scratch_offset =
    with_descriptor "Metal.Acceleration_encoder.refit_with" value ~descriptor ~scratch
      ~scratch_offset ~required:(fun _ refit -> refit) ~destinations:[ source; destination ]
      (fun () ->
        Metal_raw.accel_encoder_refit_descriptor value.raw source.raw destination.raw
          descriptor.Acceleration_structure.Build.raw scratch.raw scratch_offset)

  let validate_acceleration operation (device : device) (value : acceleration_structure) =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () when value.device.lifetime != device.lifetime ->
        error operation Device_mismatch "acceleration structure belongs to another device"
    | Ok () -> Ok ()

  let copy_common operation native (value : t) ~(source : acceleration_structure)
      ~(destination : acceleration_structure) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            let device = value.command_buffer.queue.device in
            match validate_acceleration operation device source with
            | Error _ as failure -> failure
            | Ok () -> (
                match validate_acceleration operation device destination with
                | Error _ as failure -> failure
                | Ok () -> (
                    match native value.raw source.raw destination.raw with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_acceleration_structure value.command_buffer source;
                        retain_command_buffer_acceleration_structure value.command_buffer
                          destination;
                        Ok ()))))

  let copy value ~source ~destination =
    if destination.size < source.size then
      error "Metal.Acceleration_encoder.copy" Invalid_argument
        "copy destination is smaller than source"
    else
      copy_common "Metal.Acceleration_encoder.copy" Metal_raw.acceleration_encoder_copy value
        ~source ~destination

  let copy_and_compact value ~source ~destination =
    copy_common "Metal.Acceleration_encoder.copy_and_compact"
      Metal_raw.acceleration_encoder_copy_and_compact value ~source ~destination

  let write_compacted_size_typed (value : t) ~source ~destination ~offset kind =
    let operation = "Metal.Acceleration_encoder.write_compacted_size_typed" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            let bytes, code = match kind with Uint32 -> (4L, 0) | Uint64 -> (8L, 1) in
            Result.bind (validate_acceleration operation value.command_buffer.queue.device source)
              (fun () ->
                Result.bind (ensure_buffer_usable operation destination) (fun () ->
                    Result.bind
                      (ensure_same_device operation value.command_buffer.queue.device
                         destination.device) (fun () ->
                        if
                          offset < 0L
                          || Int64.rem offset bytes <> 0L
                          || offset > destination.length
                          || bytes > Int64.sub destination.length offset
                        then
                          error operation Invalid_argument "compacted-size output range is invalid"
                        else
                          match
                            Metal_raw.acceleration_encoder_write_type value.raw source.raw
                              destination.raw offset code
                          with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_acceleration_structure value.command_buffer
                                source;
                              retain_command_buffer_buffer value.command_buffer destination;
                              Ok ()))))

  let end_encoding (value : acceleration_encoder) =
    let operation = "Metal.Acceleration_encoder.end_encoding" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.acceleration_encoder_end value.raw with
            | Error message -> native_error operation message
            | Ok () ->
                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                  ignore (Metal_raw.destroy value.raw);
                  detach value.command_buffer.lifetime
                end;
                Ok ()))
end

module Render_encoder = struct
  type t = render_encoder
  type cull_mode = No_cull | Cull_front | Cull_back
  type winding = Clockwise | Counter_clockwise
  type fill_mode = Fill | Lines
  type visibility = Visibility_disabled | Visibility_boolean | Visibility_counting

  type store_action =
    | Store_dont_care
    | Store
    | Multisample_resolve
    | Store_and_multisample_resolve

  type stage = Vertex | Fragment | Tile | Object | Mesh
  type barrier_scope = Buffers | Textures | Render_targets
  type resource_usage = Read | Write | Sample
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type primitive = Point | Line | Line_strip | Triangle | Triangle_strip
  type index_type = Uint16 | Uint32
  type prepared_resources = render_encoder_prepared_resources

  type prepared_resource_use = {
    resources : prepared_resources;
    usage : resource_usage list;
    stages : stage list;
  }

  type viewport = {
    x : float;
    y : float;
    width : float;
    height : float;
    znear : float;
    zfar : float;
  }

  type scissor = { x : int; y : int; width : int; height : int }

  let bits code values = List.fold_left (fun mask value -> mask lor code value) 0 values
  let stage_code = function Vertex -> 1 | Fragment -> 2 | Tile -> 4 | Object -> 8 | Mesh -> 16
  let usage_code = function Read -> 1 | Write -> 2 | Sample -> 4

  let depth_attachment_formats =
    [
      Texture.Depth16_unorm;
      Texture.Depth32_float;
      Texture.Depth24_unorm_stencil8;
      Texture.Depth32_float_stencil8;
    ]

  let stencil_attachment_formats =
    [ Texture.Stencil8; Texture.Depth24_unorm_stencil8; Texture.Depth32_float_stencil8 ]

  let validate_attachment operation (command_buffer : command_buffer) (target : texture) formats
      (texture : texture) =
    match ensure_texture_usable operation texture with
    | Error _ as failure -> failure
    | Ok () when not (List.mem Render_target texture.descriptor.usage) ->
        error operation Invalid_argument "attachment lacks Render_target usage"
    | Ok () when not (List.mem texture.descriptor.format formats) ->
        error operation Invalid_argument "attachment pixel format is incompatible"
    | Ok ()
      when texture.descriptor.width <> target.descriptor.width
           || texture.descriptor.height <> target.descriptor.height
           || texture.descriptor.sample_count <> target.descriptor.sample_count ->
        error operation Invalid_argument "attachment dimensions or sample count differ"
    | Ok () -> ensure_same_device operation command_buffer.queue.device texture.device

  let create_owned ~finalize (command_buffer : Command_buffer.t) ~(target : Texture.t)
      ?(clear = (0., 0., 0., 1.)) ?(depth : Texture.t option) ?(stencil : Texture.t option) () =
    let operation = "Metal.Render_encoder.create" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error operation Invalid_state "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error operation Invalid_state "command buffer already has an open encoder"
        | Ok () -> (
            match ensure_texture_usable operation target with
            | Error _ as failure -> failure
            | Ok () when not (List.mem Render_target target.descriptor.usage) ->
                error operation Invalid_argument "render target texture lacks Render_target usage"
            | Ok () when target.descriptor.sample_count <> 1 ->
                error operation Invalid_argument
                  "classic render encoder currently requires one sample"
            | Ok () when not (same_device command_buffer.queue.device target.device) ->
                error operation Device_mismatch "render target belongs to another device"
            | Ok () -> (
                let attachment_check =
                  match depth with
                  | Some texture ->
                      validate_attachment operation command_buffer target depth_attachment_formats
                        texture
                  | None -> Ok ()
                in
                let attachment_check =
                  match attachment_check with
                  | Error _ as failure -> failure
                  | Ok () -> (
                      match stencil with
                      | Some texture ->
                          validate_attachment operation command_buffer target
                            stencil_attachment_formats texture
                      | None -> Ok ())
                in
                match attachment_check with
                | Error _ as failure -> failure
                | Ok () -> (
                    let r, g, b, a = clear in
                    if not (List.for_all Float.is_finite [ r; g; b; a ]) then
                      error operation Invalid_argument "clear color must be finite"
                    else
                      match
                        Metal_raw.command_buffer_render_encoder_attachments command_buffer.raw
                          target.raw
                          (Option.map (fun (x : texture) -> x.raw) depth)
                          (Option.map (fun (x : texture) -> x.raw) stencil)
                          clear
                      with
                      | Error message -> native_error operation message
                      | Ok raw ->
                          let value : t =
                            {
                              raw;
                              lifetime = lifetime ();
                              command_buffer;
                              target;

                              pipeline = None;
                            }
                          in
                          attach command_buffer.lifetime;
                          retain_command_buffer_texture command_buffer target;
                          Option.iter (retain_command_buffer_texture command_buffer) depth;
                          Option.iter (retain_command_buffer_texture command_buffer) stencil;
                          if finalize then
                            attach_lifetime_finalizer value.lifetime command_buffer.lifetime;
                          Ok value))))

  let create command_buffer ~target ?clear ?depth ?stencil () =
    create_owned ~finalize:true command_buffer ~target ?clear ?depth ?stencil ()

  let create_from_pass_owned ~finalize (command_buffer : Command_buffer.t)
      (pass : render_pass_descriptor) =
    let operation = "Metal.Render_encoder.create_from_pass" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error operation Invalid_state "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error operation Invalid_state "command buffer already has an open encoder"
        | Ok () -> (
            match ensure_live operation pass.lifetime with
            | Error _ as failure -> failure
            | Ok () -> (
                match pass.pass_color with
                | None -> error operation Invalid_state "render pass has no color attachment"
                | Some target -> (
                    match
                      ensure_same_device operation command_buffer.queue.device target.device
                    with
                    | Error _ as failure -> failure
                    | Ok () -> (
                        match
                          Metal_raw.Registry.command_buffer_render_encoder_from_pass command_buffer.raw
                            pass.raw
                        with
                        | Error message -> native_error operation message
                        | Ok raw ->
                            let value : t =
                              {
                                raw;
                                lifetime = lifetime ();
                                command_buffer;
                                target;

                                pipeline = None;
                              }
                            in
                            attach command_buffer.lifetime;
                            retain_command_buffer_texture command_buffer target;
                            Option.iter
                              (retain_command_buffer_texture command_buffer)
                              pass.pass_depth;
                            Option.iter
                              (retain_command_buffer_texture command_buffer)
                              pass.pass_stencil;
                            Option.iter
                              (retain_command_buffer_buffer command_buffer)
                              pass.pass_visibility;
                            Option.iter
                              (retain_command_buffer_texture command_buffer)
                              pass.pass_resolve;
                            Array.iter
                              (Option.iter (fun (state : render_pass_sample_state) ->
                                   if
                                     not
                                       (List.exists
                                          (( == ) state.sample_buffer.lifetime)
                                          !(command_buffer.presentation_events))
                                   then begin
                                     attach state.sample_buffer.lifetime;
                                     command_buffer.presentation_events :=
                                       state.sample_buffer.lifetime
                                       :: !(command_buffer.presentation_events)
                                   end))
                              pass.pass_samples;
                            if finalize then
                              attach_lifetime_finalizer value.lifetime command_buffer.lifetime;
                            Ok value)))))

  module Private = struct
    type prepared_indexed_binding = {
      prepared_stage : stage;
      prepared_index : int;
      prepared_offset : int64;
      prepared_buffer : Buffer.t;
    }

    type prepared_indexed_draw = {
      prepared_pipeline : Render_pipeline.t;
      prepared_bindings : prepared_indexed_binding array;
      prepared_primitive : primitive;
      prepared_index_type : index_type;
      prepared_index_buffer : Buffer.t;
      prepared_index_offset : int64;
      prepared_index_count : int64;
    }

    type prepared_indexed_draws = {
      prepared_device : device;
      prepared_draws : prepared_indexed_draw array;
      prepared_pipeline_raws : Metal_raw.handle array;
      prepared_buffer_raws : Metal_raw.handle array array;
      prepared_stages : int array array;
      prepared_offsets : int64 array array;
      prepared_slots : int array array;
      prepared_primitives : int array;
      prepared_counts : int64 array;
      prepared_index_types : int array;
      prepared_index_raws : Metal_raw.handle array;
      prepared_index_offsets : int64 array;
      prepared_command_resources : prepared_command_resources;
    }

    type prepared_render_pass_header = {

      prepared_pass : render_pass_descriptor;
      prepared_pass_color : texture;
      prepared_pass_depth : texture option;
      prepared_pass_stencil : texture option;
      prepared_pass_resolve : texture option;
      prepared_pass_visibility : buffer option;
      prepared_pass_samples : render_pass_sample_state option array;

    } [@@warning "-69"]

    type prepared_indirect_render_pass = {
      prepared_indirect_header : prepared_render_pass_header;
      prepared_indirect_pipeline : render_pipeline;
      prepared_indirect_commands : indirect_command_buffer;
      prepared_indirect_location : int;
      prepared_indirect_length : int;
      prepared_indirect_resource_uses : prepared_resource_use array;

    } [@@warning "-69"]

    let distinct_roots lifetime_of values =
      let length = Array.length values in
      if length = 0 then [||]
      else
        let seen = Hashtbl.create length
        and roots = Array.make length (Array.unsafe_get values 0)
        and root_count = ref 0 in
        Array.iter
          (fun value ->
            let identity = (lifetime_of value).identity in
            if not (Hashtbl.mem seen identity) then begin
              Hashtbl.add seen identity ();
              Array.unsafe_set roots !root_count value;
              incr root_count
            end)
          values;
        Array.sub roots 0 !root_count

    let create_from_pass_scoped command_buffer pass =
      create_from_pass_owned ~finalize:false command_buffer pass

    let prepare_indexed_draws (device : Device.t) (draws : prepared_indexed_draw array) =
      let operation = "Metal.Render_encoder.Private.prepare_indexed_draws" in
      match before_main operation with
      | Error _ as failure -> failure
      | Ok () -> (
          match ensure_live operation device.lifetime with
          | Error _ as failure -> failure
          | Ok () when Array.length draws = 0 ->
              error operation Invalid_argument "indexed draw array is empty"
          | Ok () -> (
              let draws =
                Array.map
                  (fun draw -> { draw with prepared_bindings = Array.copy draw.prepared_bindings })
                  draws
              in
              let duplicate_binding bindings index =
                let candidate = Array.unsafe_get bindings index in
                let rec scan other =
                  if other = index then false
                  else
                    let binding = Array.unsafe_get bindings other in
                    binding.prepared_stage = candidate.prepared_stage
                    && binding.prepared_index = candidate.prepared_index
                    || scan (other + 1)
                in
                scan 0
              in
              let validate_binding bindings index =
                let binding : prepared_indexed_binding = Array.unsafe_get bindings index in
                if binding.prepared_stage <> Vertex && binding.prepared_stage <> Fragment then
                  error operation Invalid_argument
                    "indexed draw binding must target vertex or fragment"
                else if binding.prepared_index < 0 || binding.prepared_index >= 31 then
                  error operation Invalid_argument "buffer index must be in [0, 31)"
                else if duplicate_binding bindings index then
                  error operation Invalid_argument "buffer binding is duplicated"
                else
                  match ensure_buffer_usable operation binding.prepared_buffer with
                  | Error _ as failure -> failure
                  | Ok ()
                    when binding.prepared_offset < 0L
                         || binding.prepared_offset > binding.prepared_buffer.length ->
                      error operation Invalid_argument "buffer offset is outside the resource"
                  | Ok () -> ensure_same_device operation device binding.prepared_buffer.device
              in
              let validate_draw draw =
                match ensure_live operation draw.prepared_pipeline.lifetime with
                | Error _ as failure -> failure
                | Ok () when draw.prepared_pipeline.kind <> Render ->
                    error operation Invalid_argument "pipeline is not renderable"
                | Ok () -> (
                    match ensure_same_device operation device draw.prepared_pipeline.device with
                    | Error _ as failure -> failure
                    | Ok () -> (
                        let rec bindings index =
                          if index = Array.length draw.prepared_bindings then Ok ()
                          else
                            match validate_binding draw.prepared_bindings index with
                            | Error _ as failure -> failure
                            | Ok () -> bindings (index + 1)
                        in
                        match bindings 0 with
                        | Error _ as failure -> failure
                        | Ok () -> (
                            match ensure_buffer_usable operation draw.prepared_index_buffer with
                            | Error _ as failure -> failure
                            | Ok () -> (
                                match
                                  ensure_same_device operation device
                                    draw.prepared_index_buffer.device
                                with
                                | Error _ as failure -> failure
                                | Ok () ->
                                    let width =
                                      match draw.prepared_index_type with
                                      | Uint16 -> 2L
                                      | Uint32 -> 4L
                                    in
                                    if
                                      draw.prepared_index_count <= 0L
                                      || draw.prepared_index_offset < 0L
                                      || Int64.rem draw.prepared_index_offset width <> 0L
                                      || width > Int64.div Int64.max_int draw.prepared_index_count
                                    then
                                      error operation Invalid_argument
                                        "indexed draw range is invalid"
                                    else
                                      let required = Int64.mul width draw.prepared_index_count in
                                      if
                                        draw.prepared_index_offset
                                        > draw.prepared_index_buffer.length
                                        || required
                                           > Int64.sub draw.prepared_index_buffer.length
                                               draw.prepared_index_offset
                                      then
                                        error operation Invalid_argument
                                          "indexed draw exceeds the index buffer"
                                      else Ok ()))))
              in
              let rec validate index =
                if index = Array.length draws then Ok ()
                else
                  match validate_draw draws.(index) with
                  | Error _ as failure -> failure
                  | Ok () -> validate (index + 1)
              in
              match validate 0 with
              | Error _ as failure -> failure
              | Ok () -> (
                  let rec count_resources draw_index count =
                    if draw_index = Array.length draws then Ok count
                    else
                      let draw = Array.unsafe_get draws draw_index in
                      let additional = Array.length draw.prepared_bindings + 2 in
                      if count > Sys.max_array_length - additional then
                        error operation Invalid_argument
                          "indexed draw resources exceed the supported array size"
                      else count_resources (draw_index + 1) (count + additional)
                  in
                  match count_resources 0 0 with
                  | Error _ as failure -> failure
                  | Ok resource_count ->
                      let prepared_buffer_raws =
                        Array.map
                          (fun draw ->
                            Array.map
                              (fun binding -> binding.prepared_buffer.raw)
                              draw.prepared_bindings)
                          draws
                      and prepared_stages =
                        Array.map
                          (fun draw ->
                            Array.map
                              (fun binding -> if binding.prepared_stage = Vertex then 0 else 1)
                              draw.prepared_bindings)
                          draws
                      and prepared_offsets =
                        Array.map
                          (fun draw ->
                            Array.map
                              (fun binding -> binding.prepared_offset)
                              draw.prepared_bindings)
                          draws
                      and prepared_slots =
                        Array.map
                          (fun draw ->
                            Array.map (fun binding -> binding.prepared_index) draw.prepared_bindings)
                          draws
                      in
                      let prepared_pipeline_roots =
                        distinct_roots
                          (fun (pipeline : render_pipeline) -> pipeline.lifetime)
                          (Array.map (fun draw -> draw.prepared_pipeline) draws)
                      and all_buffer_roots =
                        Array.make
                          (resource_count - Array.length draws)
                          draws.(0).prepared_index_buffer
                      in
                      let buffer_index = ref 0 in
                      let add_buffer_root buffer =
                        Array.unsafe_set all_buffer_roots !buffer_index buffer;
                        incr buffer_index
                      in
                      for draw_index = 0 to Array.length draws - 1 do
                        let draw = Array.unsafe_get draws draw_index in
                        for binding_index = 0 to Array.length draw.prepared_bindings - 1 do
                          let buffer =
                            (Array.unsafe_get draw.prepared_bindings binding_index).prepared_buffer
                          in
                          add_buffer_root buffer
                        done;
                        let index_buffer = draw.prepared_index_buffer in
                        add_buffer_root index_buffer
                      done;
                      let prepared_buffer_roots =
                        distinct_roots (fun (buffer : buffer) -> buffer.lifetime) all_buffer_roots
                      in
                      let prepared_command_resources =
                        {
                          prepared_pipeline_roots;
                          prepared_buffer_roots;
                          prepared_texture_roots = [||];
                          prepared_depth_stencil_roots = [||];
                          prepared_sample_roots = [||];
                          prepared_indirect_roots = [||];
                          prepared_resource_roots = [||];
                        }
                      in
                      Ok
                        {
                          prepared_device = device;
                          prepared_draws = draws;
                          prepared_pipeline_raws =
                            Array.map (fun draw -> draw.prepared_pipeline.raw) draws;
                          prepared_buffer_raws;
                          prepared_stages;
                          prepared_offsets;
                          prepared_slots;
                          prepared_primitives =
                            Array.map
                              (fun draw ->
                                match draw.prepared_primitive with
                                | Point -> 0
                                | Line -> 1
                                | Line_strip -> 2
                                | Triangle -> 3
                                | Triangle_strip -> 4)
                              draws;
                          prepared_counts = Array.map (fun draw -> draw.prepared_index_count) draws;
                          prepared_index_types =
                            Array.map
                              (fun draw ->
                                match draw.prepared_index_type with Uint16 -> 0 | Uint32 -> 1)
                              draws;
                          prepared_index_raws =
                            Array.map (fun draw -> draw.prepared_index_buffer.raw) draws;
                          prepared_index_offsets =
                            Array.map (fun draw -> draw.prepared_index_offset) draws;
                          prepared_command_resources;
                        })))

    let rec validate_prepared_bindings operation bindings index =
      if index = Array.length bindings then Ok ()
      else
        match ensure_buffer_usable operation bindings.(index).prepared_buffer with
        | Error _ as failure -> failure
        | Ok () -> validate_prepared_bindings operation bindings (index + 1)

    let rec validate_prepared_execution operation (target : texture) draws index =
      if index = Array.length draws then Ok ()
      else
        let draw = draws.(index) in
        match ensure_live operation draw.prepared_pipeline.lifetime with
        | Error _ as failure -> failure
        | Ok ()
          when draw.prepared_pipeline.raster_sample_count <> target.descriptor.sample_count
               || draw.prepared_pipeline.color_formats = []
               || List.hd draw.prepared_pipeline.color_formats <> target.descriptor.format ->
            error operation Invalid_argument "pipeline differs from the render target"
        | Ok () -> (
            match ensure_buffer_usable operation draw.prepared_index_buffer with
            | Error _ as failure -> failure
            | Ok () -> (
                match validate_prepared_bindings operation draw.prepared_bindings 0 with
                | Error _ as failure -> failure
                | Ok () -> validate_prepared_execution operation target draws (index + 1)))

    let close_failed_prepared_encoder (value : t) =
      ignore (Metal_raw.Registry.render_encoder_end value.raw);
      if Atomic.compare_and_set value.lifetime.destroyed false true then begin
        ignore (Metal_raw.destroy value.raw);
        detach value.command_buffer.lifetime
      end;
      value.command_buffer.phase <- Failed

    let execute_prepared_indexed_draws (value : t) prepared =
      let operation = "Metal.Render_encoder.Private.execute_prepared_indexed_draws" in
      match before_main operation with
      | Error _ as failure -> failure
      | Ok () -> (
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> (
              match
                ensure_same_device operation value.command_buffer.queue.device
                  prepared.prepared_device
              with
              | Error _ as failure -> failure
              | Ok () -> (
                  match
                    validate_prepared_execution operation value.target prepared.prepared_draws 0
                  with
                  | Error _ as failure -> failure
                  | Ok () -> (
                      match
                        Metal_raw.render_encoder_execute_indexed_draws value.raw
                          prepared.prepared_pipeline_raws prepared.prepared_buffer_raws
                          prepared.prepared_stages prepared.prepared_offsets prepared.prepared_slots
                          prepared.prepared_primitives prepared.prepared_counts
                          prepared.prepared_index_types prepared.prepared_index_raws
                          prepared.prepared_index_offsets
                      with
                      | Error message ->
                          close_failed_prepared_encoder value;
                          native_error operation message
                      | Ok () ->
                          retain_command_buffer_prepared_command value.command_buffer
                            prepared.prepared_command_resources;
                          value.pipeline <-
                            Some
                              prepared.prepared_draws.(Array.length prepared.prepared_draws - 1)
                                .prepared_pipeline;
                          Ok ()))))
  end

  let destroyed (value : t) = is_destroyed value.lifetime

  let set_pipeline (value : t) (pipeline : Render_pipeline.t) =
    let operation = "Metal.Render_encoder.set_pipeline" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_live operation pipeline.lifetime with
            | Error _ as failure -> failure
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device pipeline.device
                with
                | Error _ as failure -> failure
                | Ok () when pipeline.kind = Render && false ->
                    error operation Invalid_argument
                      "classic render encoder requires a render pipeline"
                | Ok () when pipeline.raster_sample_count <> value.target.descriptor.sample_count ->
                    error operation Invalid_argument
                      "pipeline sample count differs from the render target"
                | Ok ()
                  when pipeline.color_formats = []
                       || List.hd pipeline.color_formats <> value.target.descriptor.format ->
                    error operation Invalid_argument
                      "pipeline color format differs from the render target"
                | Ok () -> (
                    match Metal_raw.render_encoder_set_pipeline value.raw pipeline.raw with
                    | Error message -> native_error operation message
                    | Ok () ->
                        (match value.pipeline with
                        | Some current when current == pipeline -> ()
                        | None | Some _ -> value.pipeline <- Some pipeline);
                        retain_command_buffer_render_pipeline value.command_buffer pipeline;
                        Ok ()))))

  let set_buffer operation raw_call (value : t) ~index ~offset (buffer : Buffer.t) =
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_buffer_usable operation buffer with
            | Error _ as failure -> failure
            | Ok () when index < 0 || index >= 31 ->
                error operation Invalid_argument "buffer index must be in [0, 31)"
            | Ok () when offset < 0L || offset > buffer.length ->
                error operation Invalid_argument "buffer offset is outside the resource"
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device buffer.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match raw_call value.raw buffer.raw offset index with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_buffer value.command_buffer buffer;
                        Ok ()))))

  let set_vertex_buffer =
    set_buffer "Metal.Render_encoder.set_vertex_buffer" Metal_raw.render_encoder_set_vertex_buffer

  let set_fragment_buffer =
    set_buffer "Metal.Render_encoder.set_fragment_buffer"
      Metal_raw.render_encoder_set_fragment_buffer

  let set_texture operation raw_call (value : t) ~index (texture : Texture.t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_texture_usable operation texture with
            | Error _ as failure -> failure
            | Ok () when index < 0 || index >= 31 ->
                error operation Invalid_argument "texture index must be in [0, 31)"
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device texture.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match raw_call value.raw texture.raw index with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_texture value.command_buffer texture;
                        Ok ()))))

  let set_vertex_texture =
    set_texture "Metal.Render_encoder.set_vertex_texture"
      Metal_raw.render_encoder_set_vertex_texture

  let set_fragment_texture =
    set_texture "Metal.Render_encoder.set_fragment_texture"
      Metal_raw.render_encoder_set_fragment_texture

  let set_bytes operation raw_call (value : t) ~index bytes =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when index < 0 || index >= 31 ->
            error operation Invalid_argument "byte index must be in [0, 31)"
        | Ok () when Bytes.length bytes = 0 || Bytes.length bytes > 4096 ->
            error operation Invalid_argument "inline bytes must contain 1..4096 bytes"
        | Ok () -> (
            match raw_call value.raw bytes index with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let set_vertex_bytes =
    set_bytes "Metal.Render_encoder.set_vertex_bytes" Metal_raw.render_encoder_set_vertex_bytes

  let set_fragment_bytes =
    set_bytes "Metal.Render_encoder.set_fragment_bytes" Metal_raw.render_encoder_set_fragment_bytes

  let set_sampler operation raw_call (value : t) ~index ?lod_min ?lod_max (sampler : Sampler.t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_live operation sampler.lifetime with
            | Error _ as failure -> failure
            | Ok () when index < 0 || index >= 31 ->
                error operation Invalid_argument "sampler index must be in [0, 31)"
            | Ok ()
              when match (lod_min, lod_max) with
                   | None, None -> false
                   | Some lo, Some hi ->
                       not (Float.is_finite lo && Float.is_finite hi && lo >= 0. && lo <= hi)
                   | _ -> true ->
                error operation Invalid_argument
                  "LOD clamps must be finite, nonnegative, ordered, and supplied together"
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device sampler.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    let result =
                      match (lod_min, lod_max) with
                      | None, None -> raw_call `Plain value.raw sampler.raw index
                      | Some lo, Some hi -> raw_call (`Lod (lo, hi)) value.raw sampler.raw index
                      | _ -> assert false
                    in
                    match result with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_sampler value.command_buffer sampler;
                        Ok ()))))

  let sampler_call plain lod = function
    | `Plain -> plain
    | `Lod clamps -> fun encoder sampler index -> lod encoder sampler clamps index

  let set_vertex_sampler =
    set_sampler "Metal.Render_encoder.set_vertex_sampler"
      (sampler_call Metal_raw.render_encoder_set_vertex_sampler
         Metal_raw.render_encoder_set_vertex_sampler_lod)

  let set_fragment_sampler =
    set_sampler "Metal.Render_encoder.set_fragment_sampler"
      (sampler_call Metal_raw.render_encoder_set_fragment_sampler
         Metal_raw.render_encoder_set_fragment_sampler_lod)

  let set_validated operation validate raw_call (value : t) argument =
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match validate value argument with
            | Error _ as failure -> failure
            | Ok raw_argument -> (
                match raw_call value.raw raw_argument with
                | Ok () -> Ok ()
                | Error message -> native_error operation message)))

  let set_viewport (value : t) (viewport : viewport) =
    let operation = "Metal.Render_encoder.set_viewport" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            if
              not
                (Float.is_finite viewport.x && Float.is_finite viewport.y
               && Float.is_finite viewport.width && Float.is_finite viewport.height
               && Float.is_finite viewport.znear && Float.is_finite viewport.zfar)
            then error operation Invalid_argument "viewport values must be finite"
            else if
              viewport.x < 0. || viewport.y < 0. || viewport.width <= 0. || viewport.height <= 0.
              || viewport.x +. viewport.width > float value.target.descriptor.width
              || viewport.y +. viewport.height > float value.target.descriptor.height
              || viewport.znear < 0. || viewport.znear > 1. || viewport.zfar < 0.
              || viewport.zfar > 1. || viewport.znear > viewport.zfar
            then
              error operation Invalid_argument
                "viewport is outside the render target or depth range"
            else
              match
                Metal_raw.render_encoder_set_viewport value.raw
                  ( viewport.x,
                    viewport.y,
                    viewport.width,
                    viewport.height,
                    viewport.znear,
                    viewport.zfar )
              with
              | Ok () -> Ok ()
              | Error message -> native_error operation message))

  let set_scissor (value : t) (scissor : scissor) =
    let operation = "Metal.Render_encoder.set_scissor" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            if
              scissor.x < 0 || scissor.y < 0 || scissor.width <= 0 || scissor.height <= 0
              || scissor.x > value.target.descriptor.width - scissor.width
              || scissor.y > value.target.descriptor.height - scissor.height
            then error operation Invalid_argument "scissor rectangle is outside the render target"
            else
              match
                Metal_raw.render_encoder_set_scissor value.raw
                  (scissor.x, scissor.y, scissor.width, scissor.height)
              with
              | Ok () -> Ok ()
              | Error message -> native_error operation message))

  let set_cull_mode (value : t) mode =
    let operation = "Metal.Render_encoder.set_cull_mode" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            let mode = match mode with No_cull -> 0 | Cull_front -> 1 | Cull_back -> 2 in
            match Metal_raw.render_encoder_set_cull_mode value.raw mode with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let set_front_facing_winding =
    set_validated "Metal.Render_encoder.set_front_facing_winding"
      (fun _ winding -> Ok (match winding with Clockwise -> 0 | Counter_clockwise -> 1))
      Metal_raw.render_encoder_set_winding

  let set_stencil_reference_values (value : t) ~front ~back =
    on_main "Metal.Render_encoder.set_stencil_reference_values" (fun () ->
        match ensure_live "Metal.Render_encoder.set_stencil_reference_values" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.render_encoder_set_stencil_reference value.raw front back with
            | Ok () -> Ok ()
            | Error message ->
                native_error "Metal.Render_encoder.set_stencil_reference_values" message))

  let tile_width (value : t) =
    on_main "Metal.Render_encoder.tile_width" (fun () ->
        match ensure_live "Metal.Render_encoder.tile_width" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> Ok (Metal_raw.render_encoder_tile_width value.raw))

  let tile_height (value : t) =
    on_main "Metal.Render_encoder.tile_height" (fun () ->
        match ensure_live "Metal.Render_encoder.tile_height" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> Ok (Metal_raw.render_encoder_tile_height value.raw))

  let validate_nonempty operation what values =
    if values = [] then error operation Invalid_argument (what ^ " must be nonempty") else Ok ()

  let validate_resource operation device = function
    | Buffer_resource b ->
        Result.bind (ensure_buffer_usable operation b) (fun () ->
            ensure_same_device operation device b.device)
    | Texture_resource t ->
        Result.bind (ensure_texture_usable operation t) (fun () ->
            ensure_same_device operation device t.device)

  let resource_raw = function Buffer_resource b -> b.raw | Texture_resource t -> t.raw

  let resource_lifetime = function
    | Buffer_resource b -> b.lifetime
    | Texture_resource t -> t.lifetime

  let has_duplicate_lifetimes lifetimes =
    let rec loop seen = function
      | [] -> false
      | value :: rest ->
          List.exists (fun current -> current == value) seen || loop (value :: seen) rest
    in
    loop [] lifetimes

  let retain_resource command_buffer = function
    | Buffer_resource b -> retain_command_buffer_buffer command_buffer b
    | Texture_resource t -> retain_command_buffer_texture command_buffer t

  let fence_call operation raw (value : t) (fence : fence) stages =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match ensure_live operation fence.lifetime with
            | Error _ as e -> e
            | Ok () ->
                Result.bind
                  (ensure_same_device operation value.command_buffer.queue.device fence.device)
                  (fun () ->
                    Result.bind (validate_nonempty operation "stages" stages) (fun () ->
                        match raw value.raw fence.raw (bits stage_code stages) with
                        | Error m -> native_error operation m
                        | Ok () ->
                            retain_command_buffer_fence value.command_buffer fence;
                            Ok ()))))

  let update_fence value fence ~after =
    fence_call "Metal.Render_encoder.update_fence" Metal_raw.render_encoder_update_fence value fence
      after

  let wait_for_fence value fence ~before =
    fence_call "Metal.Render_encoder.wait_for_fence" Metal_raw.render_encoder_wait_fence value fence
      before

  let use_heaps (value : t) heaps ~stages =
    let operation = "Metal.Render_encoder.use_heaps" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            Result.bind (validate_nonempty operation "heaps" heaps) (fun () ->
                Result.bind (validate_nonempty operation "stages" stages) (fun () ->
                    let device = value.command_buffer.queue.device in
                    if has_duplicate_lifetimes (List.map (fun (h : heap) -> h.lifetime) heaps) then
                      error operation Invalid_argument "heaps contain duplicate identities"
                    else
                      match List.find_opt (fun (h : heap) -> is_destroyed h.lifetime) heaps with
                      | Some _ -> error operation Destroyed "heap is destroyed"
                      | None -> (
                          match
                            List.find_opt
                              (fun (h : heap) -> not (same_device device h.device))
                              heaps
                          with
                          | Some _ ->
                              error operation Device_mismatch "heap belongs to another device"
                          | None -> (
                              match
                                Metal_raw.render_encoder_use_heaps value.raw
                                  (Array.of_list (List.map (fun (h : heap) -> h.raw) heaps))
                                  (bits stage_code stages)
                              with
                              | Error m -> native_error operation m
                              | Ok () ->
                                  List.iter (retain_command_buffer_heap value.command_buffer) heaps;
                                  Ok ())))))

  let use_resources (value : t) resources ~usage ~stages =
    let operation = "Metal.Render_encoder.use_resources" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            Result.bind (validate_nonempty operation "resources" resources) (fun () ->
                Result.bind (validate_nonempty operation "usage" usage) (fun () ->
                    Result.bind (validate_nonempty operation "stages" stages) (fun () ->
                        let device = value.command_buffer.queue.device in
                        if has_duplicate_lifetimes (List.map resource_lifetime resources) then
                          error operation Invalid_argument "resources contain duplicate identities"
                        else
                          match
                            List.find_map
                              (fun r ->
                                match validate_resource operation device r with
                                | Ok () -> None
                                | Error e -> Some e)
                              resources
                          with
                          | Some e -> Error e
                          | None -> (
                              match
                                Metal_raw.render_encoder_use_resources value.raw
                                  (Array.of_list (List.map resource_raw resources))
                                  (bits usage_code usage) (bits stage_code stages)
                              with
                              | Error m -> native_error operation m
                              | Ok () ->
                                  List.iter (retain_resource value.command_buffer) resources;
                                  Ok ())))))

  let binding_stage_code = function
    | Vertex -> 0
    | Fragment -> 1
    | Tile -> 2
    | Object -> 3
    | Mesh -> 4

  let set_stage_buffer (value : t) ~stage ~index ~offset ?(stride = 0L) (buffer : Buffer.t option) =
    let operation = "Metal.Render_encoder.set_stage_buffer" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if stage = Fragment then
              error operation Unsupported "fragment single-buffer binding has no stride selector"
            else if index < 0 || index >= 31 || offset < 0L || stride < 0L then
              error operation Invalid_argument "invalid buffer binding index, offset, or stride"
            else
              match buffer with
              | Some b ->
                  Result.bind (ensure_buffer_usable operation b) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device b.device)
                        (fun () ->
                          if offset > b.length then
                            error operation Invalid_argument "buffer offset is outside the resource"
                          else
                            match
                              Metal_raw.render_stage_buffer value.raw (binding_stage_code stage)
                                (Some b.raw) offset stride (Int64.of_int index)
                            with
                            | Error m -> native_error operation m
                            | Ok () ->
                                retain_command_buffer_buffer value.command_buffer b;
                                Ok ()))
              | None -> (
                  if offset <> 0L || stride <> 0L then
                    error operation Invalid_argument "nil binding requires zero offset and stride"
                  else
                    match
                      Metal_raw.render_stage_buffer value.raw (binding_stage_code stage) None 0L 0L
                        (Int64.of_int index)
                    with
                    | Error m -> native_error operation m
                    | Ok () -> Ok ())))

  let set_stage_texture (value : t) ~stage ~index (texture : Texture.t option) =
    let operation = "Metal.Render_encoder.set_stage_texture" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if stage = Vertex || stage = Fragment then
              error operation Unsupported "vertex/fragment texture binding uses the array selector"
            else if index < 0 || index >= 31 then
              error operation Invalid_argument "texture index must be in [0, 31)"
            else
              match texture with
              | Some t ->
                  Result.bind (ensure_texture_usable operation t) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device t.device)
                        (fun () ->
                          match
                            Metal_raw.render_stage_texture value.raw (binding_stage_code stage)
                              (Some t.raw) (Int64.of_int index)
                          with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_texture value.command_buffer t;
                              Ok ()))
              | None -> (
                  match
                    Metal_raw.render_stage_texture value.raw (binding_stage_code stage) None
                      (Int64.of_int index)
                  with
                  | Error m -> native_error operation m
                  | Ok () -> Ok ())))

  let set_stage_sampler (value : t) ~stage ~index ?lod_min ?lod_max (sampler : Sampler.t option) =
    let operation = "Metal.Render_encoder.set_stage_sampler" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            if stage = Vertex || stage = Fragment then
              error operation Unsupported "vertex/fragment sampler binding uses the array selector"
            else if index < 0 || index >= 31 then
              error operation Invalid_argument "sampler index must be in [0,31)"
            else
              let lod =
                match (lod_min, lod_max) with
                | None, None -> Ok (false, (0., 0.))
                | Some lo, Some hi
                  when Float.is_finite lo && Float.is_finite hi && lo >= 0. && lo <= hi ->
                    Ok (true, (lo, hi))
                | _ ->
                    error operation Invalid_argument
                      "LOD clamps must be finite, ordered, and supplied together"
              in
              Result.bind lod (fun (has_lod, clamps) ->
                  match sampler with
                  | Some s ->
                      Result.bind (ensure_live operation s.lifetime) (fun () ->
                          Result.bind
                            (ensure_same_device operation value.command_buffer.queue.device s.device)
                            (fun () ->
                              match
                                Metal_raw.render_stage_sampler value.raw (binding_stage_code stage)
                                  (Some s.raw) has_lod clamps (Int64.of_int index)
                              with
                              | Error m -> native_error operation m
                              | Ok () ->
                                  retain_command_buffer_sampler value.command_buffer s;
                                  Ok ()))
                  | None -> (
                      if has_lod then
                        error operation Invalid_argument "nil sampler cannot have LOD clamps"
                      else
                        match
                          Metal_raw.render_stage_sampler value.raw (binding_stage_code stage) None
                            false clamps (Int64.of_int index)
                        with
                        | Error m -> native_error operation m
                        | Ok () -> Ok ())))

  let set_depth_stencil_state (value : t) (state : Depth_stencil.t option) =
    let operation = "Metal.Render_encoder.set_depth_stencil_state" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match state with
            | Some x -> (
                match ensure_live operation x.lifetime with
                | Error _ as failure -> failure
                | Ok () -> (
                    match
                      ensure_same_device operation value.command_buffer.queue.device x.device
                    with
                    | Error _ as failure -> failure
                    | Ok () -> (
                        match Metal_raw.render_depth_stencil value.raw (Some x.raw) with
                        | Error message -> native_error operation message
                        | Ok () ->
                            retain_command_buffer_depth_stencil value.command_buffer x;
                            Ok ())))
            | None -> (
                match Metal_raw.render_depth_stencil value.raw None with
                | Error message -> native_error operation message
                | Ok () -> Ok ())))

  let set_stage_bytes (value : t) ~stage ~index bytes =
    let operation = "Metal.Render_encoder.set_stage_bytes" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if
              stage = Fragment || index < 0 || index >= 31
              || Bytes.length bytes = 0
              || Bytes.length bytes > 4096
            then
              error operation Invalid_argument
                "inline binding requires index [0,31) and 1..4096 bytes"
            else
              match
                Metal_raw.render_stage_bytes value.raw (binding_stage_code stage) bytes
                  (Int64.of_int (Bytes.length bytes))
                  (Int64.of_int index)
              with
              | Error m -> native_error operation m
              | Ok () -> Ok ()))

  let primitive_code = function
    | Point -> 0
    | Line -> 1
    | Line_strip -> 2
    | Triangle -> 3
    | Triangle_strip -> 4

  let index_type_code = function Uint16 -> 0 | Uint32 -> 1
  let index_width = function Uint16 -> 2L | Uint32 -> 4L

  let validate_draw_buffer operation (value : t) (buffer : buffer) ~offset ~required =
    match ensure_buffer_usable operation buffer with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_same_device operation value.command_buffer.queue.device buffer.device with
        | Error _ as failure -> failure
        | Ok () ->
            if
              offset < 0L || required < 0L || offset > buffer.length
              || required > Int64.sub buffer.length offset
            then error operation Invalid_argument "draw buffer range is outside the resource"
            else Ok ())

  let checked_product operation a b =
    if a < 0L || b < 0L || (a <> 0L && b > Int64.div Int64.max_int a) then
      error operation Invalid_argument "draw range overflows"
    else Ok (Int64.mul a b)

  let draw_indexed_basic (value : t) ~primitive ~index_type ~(index_buffer : Buffer.t) ~index_offset
      ~index_count =
    let operation = "Metal.Render_encoder.draw_indexed_basic" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if Option.is_none value.pipeline then
              error operation Invalid_state "no render pipeline is bound"
            else if index_count <= 0L then
              error operation Invalid_argument "index count must be positive"
            else
              let width = index_width index_type in
              if index_offset < 0L || Int64.rem index_offset width <> 0L then
                error operation Invalid_argument "index offset is misaligned"
              else if index_count <> 0L && width > Int64.div Int64.max_int index_count then
                error operation Invalid_argument "draw range overflows"
              else
                let required = Int64.mul index_count width in
                match
                  validate_draw_buffer operation value index_buffer ~offset:index_offset ~required
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match
                      Metal_raw.render_draw_indexed_basic value.raw (primitive_code primitive)
                        index_count (index_type_code index_type) index_buffer.raw index_offset
                    with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_buffer value.command_buffer index_buffer;
                        Ok ())))

  let draw_indexed_instances (value : t) ~primitive ~index_type ~(index_buffer : Buffer.t)
      ~index_offset ~index_count ~instances =
    let operation = "Metal.Render_encoder.draw_indexed_instances" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            if Option.is_none value.pipeline then
              error operation Invalid_state "no render pipeline is bound"
            else if index_count <= 0L || instances <= 0L then
              error operation Invalid_argument "draw counts must be positive"
            else
              let width = index_width index_type in
              if index_offset < 0L || Int64.rem index_offset width <> 0L then
                error operation Invalid_argument "index offset is misaligned"
              else
                Result.bind (checked_product operation index_count width) (fun required ->
                    Result.bind
                      (validate_draw_buffer operation value index_buffer ~offset:index_offset
                         ~required) (fun () ->
                        match
                          Metal_raw.render_draw_indexed_instances value.raw
                            (primitive_code primitive) index_count (index_type_code index_type)
                            index_buffer.raw index_offset instances
                        with
                        | Error m -> native_error operation m
                        | Ok () ->
                            retain_command_buffer_buffer value.command_buffer index_buffer;
                            Ok ())))

  let pipeline_supports_icb operation (value : t) =
    match value.pipeline with
    | None -> error operation Invalid_state "no render pipeline is bound"
    | Some p -> (
        match
          Metal_raw.Registry.render_pipeline_state_support_indirect_command_buffers p.raw
        with
        | Error m -> native_error operation m
        | Ok b -> Ok b)

  let execute_indirect_commands (value : t) (commands : indirect_command_buffer) ~location ~length =
    let operation = "Metal.Render_encoder.execute_indirect_commands" in
    match before_main operation with
    | Error _ as error -> error
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as error -> error
        | Ok () -> (
            match ensure_live operation commands.lifetime with
            | Error _ as error -> error
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device commands.device
                with
                | Error _ as error -> error
                | Ok () -> (
                    match
                      Indirect_command_buffer.validate_range operation commands ~location ~length
                    with
                    | Error _ as error -> error
                    | Ok () -> (
                        match pipeline_supports_icb operation value with
                        | Error _ as error -> error
                        | Ok false ->
                            error operation Unsupported
                              "pipeline lacks indirect-command-buffer support"
                        | Ok true -> (
                            match
                              Metal_raw.render_encoder_execute_icb_range value.raw commands.raw
                                location length
                            with
                            | Error message -> native_error operation message
                            | Ok () ->
                                retain_command_buffer_indirect value.command_buffer commands;
                                Ok ()))))))

  let draw_primitives (value : t) ~primitive ~first ~count ?(instances = 1) () =
    let operation = "Metal.Render_encoder.draw_primitives" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Option.is_none value.pipeline ->
            error operation Invalid_state "no render pipeline is bound"
        | Ok () when first < 0 || count <= 0 || instances <= 0 ->
            error operation Invalid_argument "draw range must be positive"
        | Ok () -> (
            let code = match primitive with
              | Point -> 0 | Line -> 1 | Line_strip -> 2 | Triangle -> 3 | Triangle_strip -> 4 in
            match Metal_raw.render_encoder_draw_primitives value.raw code first count instances with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let positive3 (x, y, z) = x > 0 && y > 0 && z > 0

  (* Classic mesh dispatch: the bound pipeline must be a mesh pipeline, an
     object threadgroup is given exactly when it has an object stage, and any
     required threadgroup sizes compiled into it must match. *)
  let draw_mesh_threadgroups (value : t) ~threadgroups ?object_threadgroup ~mesh_threadgroup () =
    let operation = "Metal.Render_encoder.draw_mesh_threadgroups" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match value.pipeline with
            | None -> error operation Invalid_state "no render pipeline is bound"
            | Some pipeline when pipeline.kind <> Mesh ->
                error operation Invalid_state "mesh draws require a mesh render pipeline"
            | Some { mesh_constraints = None; _ } ->
                error operation Native_error "bound mesh pipeline lost its checked constraints"
            | Some { mesh_constraints = Some constraints; _ } -> (
                let object_size =
                  match (constraints.has_object_stage, object_threadgroup) with
                  | false, None -> Ok (1, 1, 1)
                  | false, Some _ ->
                      error operation Invalid_argument "an object threadgroup requires an object stage"
                  | true, None ->
                      error operation Invalid_argument "the mesh pipeline requires an object threadgroup"
                  | true, Some size -> Ok size
                in
                match object_size with
                | Error _ as failure -> failure
                | Ok object_size ->
                    let required stage given = function
                      | Some size when size <> given ->
                          error operation Invalid_argument
                            (stage ^ " threadgroup differs from the compiled required size")
                      | _ -> Ok ()
                    in
                    if not (positive3 threadgroups && positive3 object_size && positive3 mesh_threadgroup) then
                      error operation Invalid_argument "mesh dispatch sizes must be positive"
                    else
                      match required "mesh" mesh_threadgroup constraints.required_mesh_threads with
                      | Error _ as failure -> failure
                      | Ok () -> (
                          match
                            if constraints.has_object_stage then
                              required "object" object_size constraints.required_object_threads
                            else Ok ()
                          with
                          | Error _ as failure -> failure
                          | Ok () -> (
                              let gx, gy, gz = threadgroups and ox, oy, oz = object_size
                              and mx, my, mz = mesh_threadgroup in
                              match
                                Metal_raw.render_encoder_draw_mesh_threadgroups value.raw
                                  (gx, gy, gz, ox, oy, oz, mx, my, mz)
                              with
                              | Ok () -> Ok ()
                              | Error message -> native_error operation message)))))

  let dispatch_threads_per_tile (value : t) ~threads =
    let operation = "Metal.Render_encoder.dispatch_threads_per_tile" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match value.pipeline with
            | None -> error operation Invalid_state "no render pipeline is bound"
            | Some pipeline when pipeline.kind <> Tile ->
                error operation Invalid_state "tile dispatches require a tile render pipeline"
            | Some pipeline -> (
                let width, height, depth = threads in
                let required =
                  match pipeline.tile_constraints with
                  | Some { required_tile_threads = Some size; _ } when size <> threads ->
                      error operation Invalid_argument
                        "tile threads differ from the compiled required size"
                  | _ -> Ok ()
                in
                match required with
                | Error _ as failure -> failure
                | Ok () ->
                    if width <= 0 || height <= 0 || depth <> 1 then
                      error operation Invalid_argument
                        "tile thread dimensions must be positive with depth one"
                    else
                      match Metal_raw.render_encoder_dispatch_threads_per_tile value.raw width height depth with
                      | Ok () -> Ok ()
                      | Error message -> native_error operation message)))

  let draw_triangles (value : t) ~first ~count ?(instances = 1) () =
    let operation = "Metal.Render_encoder.draw_triangles" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Option.is_none value.pipeline ->
            error operation Invalid_state "no render pipeline is bound"
        | Ok () when first < 0 || count <= 0 || instances <= 0 ->
            error operation Invalid_argument "draw range must be positive"
        | Ok () -> (
            match Metal_raw.render_encoder_draw value.raw first count instances with
            | Ok () -> Ok ()
            | Error message -> native_error operation message))

  let end_encoding (value : t) =
    let operation = "Metal.Render_encoder.end_encoding" in
    match before_main operation with
    | Error _ as failure -> failure
    | Ok () -> (
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.render_encoder_end value.raw with
            | Error message -> native_error operation message
            | Ok () ->
                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                  ignore (Metal_raw.destroy value.raw);
                  detach value.command_buffer.lifetime
                end;
                Ok ()))
end

module Compute_encoder = struct
  type t = compute_encoder
  type dispatch_type = Serial | Concurrent
  type barrier_scope = Barrier_buffers | Barrier_textures
  type resource_usage = Resource_read | Resource_write | Resource_sample
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type region = { x : int64; y : int64; z : int64; width : int64; height : int64; depth : int64 }

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Compute_encoder.create" (fun () ->
        match ensure_live "Metal.Compute_encoder.create" command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error "Metal.Compute_encoder.create" Invalid_state
              "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error "Metal.Compute_encoder.create" Invalid_state
              "command buffer already has an open encoder"
        | Ok () -> (
            match Metal_raw.Registry.command_buffer_compute_encoder command_buffer.raw with
            | Error message -> native_error "Metal.Compute_encoder.create" message
            | Ok raw ->
                let value : t = { raw; lifetime = lifetime (); command_buffer; pipeline = None } in
                attach command_buffer.lifetime;
                attach_finalizer value value.lifetime command_buffer.lifetime;
                Ok value))

  let set_pipeline (value : t) (pipeline : Compute_pipeline.t) =
    on_main "Metal.Compute_encoder.set_pipeline" (fun () ->
        match ensure_live "Metal.Compute_encoder.set_pipeline" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_live "Metal.Compute_encoder.set_pipeline" pipeline.lifetime with
            | Error _ as failure -> failure
            | Ok () -> (
                match
                  ensure_same_device "Metal.Compute_encoder.set_pipeline"
                    value.command_buffer.queue.device pipeline.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match Metal_raw.compute_encoder_set_pipeline value.raw pipeline.raw with
                    | Error message -> native_error "Metal.Compute_encoder.set_pipeline" message
                    | Ok () ->
                        value.pipeline <- Some pipeline;
                        Ok ()))))

  let set_buffer (value : t) ~index ~offset (buffer : Buffer.t) =
    on_main "Metal.Compute_encoder.set_buffer" (fun () ->
        match ensure_live "Metal.Compute_encoder.set_buffer" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_buffer_usable "Metal.Compute_encoder.set_buffer" buffer with
            | Error _ as failure -> failure
            | Ok () when index < 0 || index >= 31 ->
                error "Metal.Compute_encoder.set_buffer" Invalid_argument
                  "buffer index must be in [0, 31)"
            | Ok () when offset < 0L || offset > buffer.length ->
                error "Metal.Compute_encoder.set_buffer" Invalid_argument
                  "buffer offset is outside the resource"
            | Ok () -> (
                match
                  ensure_same_device "Metal.Compute_encoder.set_buffer"
                    value.command_buffer.queue.device buffer.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match
                      Metal_raw.compute_encoder_set_buffer value.raw buffer.raw offset index
                    with
                    | Ok () ->
                        retain_command_buffer_buffer value.command_buffer buffer;
                        Ok ()
                    | Error message -> native_error "Metal.Compute_encoder.set_buffer" message))))

  let set_texture (value : t) ~index (texture : Texture.t) =
    on_main "Metal.Compute_encoder.set_texture" (fun () ->
        match ensure_live "Metal.Compute_encoder.set_texture" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_texture_usable "Metal.Compute_encoder.set_texture" texture with
            | Error _ as failure -> failure
            | Ok () when index < 0 || index >= 31 ->
                error "Metal.Compute_encoder.set_texture" Invalid_argument
                  "texture index must be in [0, 31)"
            | Ok () -> (
                match
                  ensure_same_device "Metal.Compute_encoder.set_texture"
                    value.command_buffer.queue.device texture.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match Metal_raw.compute_encoder_set_texture value.raw texture.raw index with
                    | Ok () ->
                        retain_command_buffer_texture value.command_buffer texture;
                        Ok ()
                    | Error message -> native_error "Metal.Compute_encoder.set_texture" message))))

  let set_acceleration_structure (value : t) ~index (x : Acceleration_structure.t option) =
    let operation = "Metal.Compute_encoder.set_acceleration_structure" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if index < 0 || index >= 31 then
              error operation Invalid_argument "buffer index is outside [0, 31)"
            else
              match x with
              | Some a ->
                  Result.bind (ensure_live operation a.lifetime) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device a.device)
                        (fun () ->
                          match
                            Metal_raw.compute35_acceleration value.raw (Some a.raw)
                              (Int64.of_int index)
                          with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_acceleration_structure value.command_buffer a;
                              Ok ()))
              | None -> (
                  match Metal_raw.compute35_acceleration value.raw None (Int64.of_int index) with
                  | Error m -> native_error operation m
                  | Ok () -> Ok ())))

  let set_visible_function_table (value : t) ~index (x : Visible_function_table.t option) =
    let operation = "Metal.Compute_encoder.set_visible_function_table" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if index < 0 || index >= 31 then
              error operation Invalid_argument "buffer index is outside [0, 31)"
            else
              match x with
              | Some table ->
                  Result.bind (ensure_live operation table.lifetime) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device
                           table.pipeline.device) (fun () ->
                          match
                            Metal_raw.compute35_visible value.raw (Some table.raw)
                              (Int64.of_int index)
                          with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_visible_table value.command_buffer table;
                              Ok ()))
              | None -> (
                  match Metal_raw.compute35_visible value.raw None (Int64.of_int index) with
                  | Error m -> native_error operation m
                  | Ok () -> Ok ())))

  let set_intersection_function_table (value : t) ~index (x : Intersection_function_table.t option)
      =
    let operation = "Metal.Compute_encoder.set_intersection_function_table" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if index < 0 || index >= 31 then
              error operation Invalid_argument "buffer index is outside [0, 31)"
            else
              match x with
              | Some table ->
                  Result.bind (ensure_live operation table.lifetime) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device
                           table.pipeline.device) (fun () ->
                          match
                            Metal_raw.compute35_intersection value.raw (Some table.raw)
                              (Int64.of_int index)
                          with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_intersection_table value.command_buffer table;
                              Ok ()))
              | None -> (
                  match Metal_raw.compute35_intersection value.raw None (Int64.of_int index) with
                  | Error m -> native_error operation m
                  | Ok () -> Ok ())))

  let compute35_positive_size (x, y, z) = x > 0 && y > 0 && z > 0

  let compute35_product3 x y z =
    if y = 0 || x > max_int / y then None
    else
      let xy = x * y in
      if z = 0 || xy > max_int / z then None else Some (xy * z)

  let set_bytes (value : t) ~index bytes =
    let operation = "Metal.Compute_encoder.set_bytes" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            if index < 0 || index >= 31 || Bytes.length bytes = 0 then
              error operation Invalid_argument "byte binding index or length is invalid"
            else
              match Metal_raw.compute35_bytes_plain value.raw bytes (Int64.of_int index) with
              | Error m -> native_error operation m
              | Ok () -> Ok ()))

  let validate_group operation group =
    if compute35_positive_size group then Ok ()
    else error operation Invalid_argument "dispatch dimensions must be positive"

  let dispatch_threadgroups (value : t) ~threadgroups ~threadgroup =
    let operation = "Metal.Compute_encoder.dispatch_threadgroups" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () when Option.is_none value.pipeline ->
            error operation Invalid_state "no compute pipeline is bound"
        | Ok () ->
            Result.bind (validate_group operation threadgroups) (fun () ->
                Result.bind (validate_group operation threadgroup) (fun () ->
                    let x, y, z = threadgroup in
                    match compute35_product3 x y z with
                    | None -> error operation Invalid_argument "threadgroup cardinality overflows"
                    | Some n when n > (Option.get value.pipeline).max_total_threads ->
                        error operation Invalid_argument "threadgroup exceeds pipeline limit"
                    | Some _ -> (
                        match
                          Metal_raw.compute35_dispatch_groups value.raw threadgroups threadgroup
                        with
                        | Error m -> native_error operation m
                        | Ok () -> Ok ()))))

  let fence_call operation raw (value : t) (fence : Fence.t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            Result.bind (ensure_live operation fence.lifetime) (fun () ->
                Result.bind
                  (ensure_same_device operation value.command_buffer.queue.device fence.device)
                  (fun () ->
                    match raw value.raw fence.raw with
                    | Error m -> native_error operation m
                    | Ok () ->
                        retain_command_buffer_fence value.command_buffer fence;
                        Ok ())))

  let update_fence value fence =
    fence_call "Metal.Compute_encoder.update_fence" Metal_raw.compute35_update_fence value fence

  let wait_for_fence value fence =
    fence_call "Metal.Compute_encoder.wait_for_fence" Metal_raw.compute35_wait_fence value fence

  let use_heaps (value : t) heaps =
    let operation = "Metal.Compute_encoder.use_heaps" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () ->
            if heaps = [] then error operation Invalid_argument "heaps must not be empty"
            else
              let device = value.command_buffer.queue.device in
              let rec check = function
                | [] -> Ok ()
                | (h : heap) :: xs ->
                    Result.bind (ensure_live operation h.lifetime) (fun () ->
                        Result.bind (ensure_same_device operation device h.device) (fun () ->
                            check xs))
              in
              Result.bind (check heaps) (fun () ->
                  match
                    Metal_raw.compute35_heaps value.raw
                      (Array.of_list (List.map (fun (h : heap) -> h.raw) heaps))
                  with
                  | Error m -> native_error operation m
                  | Ok () ->
                      List.iter (retain_command_buffer_heap value.command_buffer) heaps;
                      Ok ()))

  let positive_size (x, y, z) = x > 0 && y > 0 && z > 0

  let product3 x y z =
    if x > max_int / y then None
    else
      let xy = x * y in
      if xy > max_int / z then None else Some (xy * z)

  let dispatch_threads (value : t) ~threads ~threadgroup =
    on_main "Metal.Compute_encoder.dispatch_threads" (fun () ->
        match ensure_live "Metal.Compute_encoder.dispatch_threads" value.lifetime with
        | Error _ as failure -> failure
        | Ok () when Option.is_none value.pipeline ->
            error "Metal.Compute_encoder.dispatch_threads" Invalid_state
              "no compute pipeline is bound"
        | Ok () when not (positive_size threads && positive_size threadgroup) ->
            error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
              "thread and threadgroup dimensions must be positive"
        | Ok () -> (
            let tx, ty, tz = threadgroup in
            let pipeline = Option.get value.pipeline in
            match product3 tx ty tz with
            | None ->
                error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
                  "threadgroup cardinality overflows an OCaml integer"
            | Some product when product > pipeline.max_total_threads ->
                error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
                  "threadgroup exceeds the pipeline's maximum total thread count"
            | Some _ -> (
                match Metal_raw.compute_encoder_dispatch value.raw threads threadgroup with
                | Ok () -> Ok ()
                | Error message -> native_error "Metal.Compute_encoder.dispatch_threads" message)))

  let end_encoding (value : t) =
    on_main "Metal.Compute_encoder.end_encoding" (fun () ->
        match ensure_live "Metal.Compute_encoder.end_encoding" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.compute_encoder_end value.raw with
            | Error message -> native_error "Metal.Compute_encoder.end_encoding" message
            | Ok () ->
                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                  ignore (Metal_raw.destroy value.raw);
                  detach value.command_buffer.lifetime
                end;
                Ok ()))
end

module Resource_state_encoder = struct
  type t = resource_state_encoder
  type mapping_mode = Map | Unmap
  type tile_region = { x : int; y : int; z : int; width : int; height : int; depth : int }

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Resource_state_encoder.create" (fun () ->
        match ensure_live "Metal.Resource_state_encoder.create" command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error "Metal.Resource_state_encoder.create" Invalid_state
              "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error "Metal.Resource_state_encoder.create" Invalid_state
              "command buffer already has an open encoder"
        | Ok () -> (
            match Metal_raw.Registry.command_buffer_resource_state_encoder command_buffer.raw with
            | Error message -> native_error "Metal.Resource_state_encoder.create" message
            | Ok raw ->
                let value : t = { raw; lifetime = lifetime (); command_buffer } in
                attach command_buffer.lifetime;
                attach_finalizer value value.lifetime command_buffer.lifetime;
                Ok value))

  let mode_code = function Map -> 0 | Unmap -> 1
  let ceil_div value divisor = 1 + ((value - 1) / divisor)

  let region_tuple (region : tile_region) =
    (region.x, region.y, region.z, region.width, region.height, region.depth)

  let valid_axis origin length limit =
    origin >= 0 && length > 0 && origin <= limit && length <= limit - origin

  let tile_cardinality operation region =
    if region.width > max_int / region.height then
      error operation Invalid_argument "sparse tile-region cardinality overflows an OCaml integer"
    else
      let area = region.width * region.height in
      if area > max_int / region.depth then
        error operation Invalid_argument "sparse tile-region cardinality overflows an OCaml integer"
      else Ok (area * region.depth)

  let update_texture_mapping (value : t) ~mode (texture : Texture.t) ~mip_level ~slice
      ~(region : tile_region) =
    let operation = "Metal.Resource_state_encoder.update_texture_mapping" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_texture_usable operation texture with
            | Error _ as failure -> failure
            | Ok () when Option.is_some texture.placement_sparse_page_size ->
                error operation Unsupported
                  "placement sparse mappings require the Metal 4 command queue"
            | Ok () -> (
                match
                  ensure_same_device operation value.command_buffer.queue.device texture.device
                with
                | Error _ as failure -> failure
                | Ok () -> (
                    match Texture.sparse_info_raw operation texture with
                    | Error _ as failure -> failure
                    | Ok None -> error operation Invalid_argument "texture is not sparse"
                    | Ok (Some info) -> (
                        let descriptor = texture.descriptor in
                        if mip_level < 0 || mip_level >= descriptor.mip_levels then
                          error operation Invalid_argument
                            "sparse mapping mip level is outside the texture"
                        else if slice < 0 || slice >= Texture.total_slices descriptor then
                          error operation Invalid_argument
                            "sparse mapping slice is outside the texture"
                        else
                          let mip_width = Texture.mip_dimension descriptor.width mip_level
                          and mip_height = Texture.mip_dimension descriptor.height mip_level
                          and mip_depth = Texture.mip_dimension descriptor.depth mip_level in
                          let tile_width = ceil_div mip_width info.tile_width
                          and tile_height = ceil_div mip_height info.tile_height
                          and tile_depth = ceil_div mip_depth info.tile_depth in
                          if
                            not
                              (valid_axis region.x region.width tile_width
                              && valid_axis region.y region.height tile_height
                              && valid_axis region.z region.depth tile_depth)
                          then
                            error operation Invalid_argument
                              "sparse tile region exceeds the selected mip level"
                          else
                            let tail_error =
                              match info.first_mip_in_tail with
                              | Some first when mip_level > first ->
                                  Some "map a sparse mip tail through its first mip level"
                              | Some first
                                when mip_level = first
                                     && region
                                        <> { x = 0; y = 0; z = 0; width = 1; height = 1; depth = 1 }
                                ->
                                  Some "a sparse mip tail mapping must cover its single tail tile"
                              | None | Some _ -> None
                            in
                            match tail_error with
                            | Some message -> error operation Invalid_argument message
                            | None -> (
                                match tile_cardinality operation region with
                                | Error _ as failure -> failure
                                | Ok tile_count -> (
                                    let required_bytes =
                                      match info.first_mip_in_tail with
                                      | Some first when mip_level = first -> info.tail_size_in_bytes
                                      | None | Some _ ->
                                          Int64.mul (Int64.of_int tile_count)
                                            info.tile_size_in_bytes
                                    in
                                    let sparse_heap =
                                      match texture_heap texture with
                                      | Some heap -> heap
                                      | None -> assert false
                                    in
                                    if required_bytes > sparse_heap.descriptor.size then
                                      error operation Invalid_argument
                                        "mapping requires more physical pages than the sparse heap \
                                         owns"
                                    else
                                      match
                                        Metal_raw.resource_state_encoder_update_texture_mapping
                                          value.raw texture.raw (mode_code mode)
                                          (region_tuple region) mip_level slice
                                      with
                                      | Error message -> native_error operation message
                                      | Ok () ->
                                          retain_command_buffer_texture value.command_buffer texture;
                                          Ok ())))))))

  let end_encoding (value : t) =
    on_main "Metal.Resource_state_encoder.end_encoding" (fun () ->
        match ensure_live "Metal.Resource_state_encoder.end_encoding" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.resource_state_encoder_end value.raw with
            | Error message -> native_error "Metal.Resource_state_encoder.end_encoding" message
            | Ok () ->
                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                  ignore (Metal_raw.destroy value.raw);
                  detach value.command_buffer.lifetime
                end;
                Ok ()))
end

module Blit_encoder = struct
  type t = blit_encoder

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Blit_encoder.create" (fun () ->
        match ensure_live "Metal.Blit_encoder.create" command_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () when command_buffer.phase <> Recording ->
            error "Metal.Blit_encoder.create" Invalid_state "command buffer is no longer recording"
        | Ok () when dependent_count command_buffer.lifetime <> 0 ->
            error "Metal.Blit_encoder.create" Invalid_state
              "command buffer already has an open encoder"
        | Ok () -> (
            match Metal_raw.Registry.command_buffer_blit_encoder command_buffer.raw with
            | Error message -> native_error "Metal.Blit_encoder.create" message
            | Ok raw ->
                let value : t = { raw; lifetime = lifetime (); command_buffer } in
                attach command_buffer.lifetime;
                attach_finalizer value value.lifetime command_buffer.lifetime;
                Ok value))

  let copy_buffer_to_texture (value : t) ~(source : Buffer.t) ~source_offset ~source_bytes_per_row
      ~source_bytes_per_image ~(destination : Texture.t) ~destination_slice ~destination_level
      ~(destination_region : Texture.region) =
    let operation = "Metal.Blit_encoder.copy_buffer_to_texture" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_buffer_usable operation source with
            | Error _ as failure -> failure
            | Ok () -> (
                match ensure_texture_usable operation destination with
                | Error _ as failure -> failure
                | Ok () -> (
                    let descriptor = destination.descriptor in
                    if
                      source_offset < 0L || source_bytes_per_row <= 0 || source_bytes_per_image <= 0
                    then
                      error operation Invalid_argument
                        "blit source offset and pitches must be nonnegative and positive"
                    else if descriptor.sample_count <> 1 then
                      error operation Unsupported "multisample textures do not accept buffer blits"
                    else if destination_level < 0 || destination_level >= descriptor.mip_levels then
                      error operation Invalid_argument
                        "blit destination mip level is outside the texture"
                    else if
                      destination_slice < 0 || destination_slice >= Texture.total_slices descriptor
                    then
                      error operation Invalid_argument
                        "blit destination slice is outside the texture"
                    else if
                      destination_region.x < 0 || destination_region.y < 0
                      || destination_region.z < 0 || destination_region.width <= 0
                      || destination_region.height <= 0 || destination_region.depth <= 0
                    then error operation Invalid_argument "blit destination region is invalid"
                    else
                      let mip_width = Texture.mip_dimension descriptor.width destination_level
                      and mip_height = Texture.mip_dimension descriptor.height destination_level
                      and mip_depth = Texture.mip_dimension descriptor.depth destination_level in
                      if
                        destination_region.x > mip_width
                        || destination_region.width > mip_width - destination_region.x
                        || destination_region.y > mip_height
                        || destination_region.height > mip_height - destination_region.y
                        || destination_region.z > mip_depth
                        || destination_region.depth > mip_depth - destination_region.z
                      then
                        error operation Invalid_argument
                          "blit destination region exceeds the selected mip level"
                      else
                        let layout = Texture.format_layout descriptor.format in
                        let aligned origin length limit block =
                          origin mod block = 0 && (length mod block = 0 || origin + length = limit)
                        in
                        if
                          not
                            (aligned destination_region.x destination_region.width mip_width
                               layout.block_width
                            && aligned destination_region.y destination_region.height mip_height
                                 layout.block_height)
                        then
                          error operation Invalid_argument
                            "blit destination region is not format-block aligned"
                        else
                          let blocks value block = 1 + ((value - 1) / block) in
                          let row_blocks = blocks destination_region.width layout.block_width in
                          match Texture.checked_mul row_blocks layout.bytes_per_block with
                          | None ->
                              error operation Invalid_argument
                                "blit row cardinality overflows an OCaml integer"
                          | Some minimum_row
                            when source_bytes_per_row < minimum_row
                                 || source_bytes_per_row mod layout.bytes_per_block <> 0 ->
                              error operation Invalid_argument
                                "blit source row pitch is too small or not block-aligned"
                          | Some _ -> (
                              match
                                Texture.checked_mul source_bytes_per_row
                                  (blocks destination_region.height layout.block_height)
                              with
                              | None ->
                                  error operation Invalid_argument
                                    "blit image cardinality overflows an OCaml integer"
                              | Some minimum_image when source_bytes_per_image < minimum_image ->
                                  error operation Invalid_argument
                                    "blit source image pitch is smaller than its rows"
                              | Some _ -> (
                                  let image_bytes = Int64.of_int source_bytes_per_image
                                  and depth = Int64.of_int destination_region.depth in
                                  if image_bytes > Int64.div Int64.max_int depth then
                                    error operation Invalid_argument
                                      "blit source cardinality overflows 64 bits"
                                  else
                                    let total = Int64.mul image_bytes depth in
                                    if
                                      source_offset > source.length
                                      || total > Int64.sub source.length source_offset
                                    then
                                      error operation Invalid_argument
                                        "blit source range exceeds the buffer"
                                    else
                                      match
                                        ensure_same_device operation
                                          value.command_buffer.queue.device source.device
                                      with
                                      | Error _ as failure -> failure
                                      | Ok () -> (
                                          match
                                            ensure_same_device operation
                                              value.command_buffer.queue.device destination.device
                                          with
                                          | Error _ as failure -> failure
                                          | Ok () -> (
                                              let copy =
                                                ( source_offset,
                                                  source_bytes_per_row,
                                                  source_bytes_per_image,
                                                  ( destination_region.width,
                                                    destination_region.height,
                                                    destination_region.depth ),
                                                  destination_slice,
                                                  destination_level,
                                                  ( destination_region.x,
                                                    destination_region.y,
                                                    destination_region.z ) )
                                              in
                                              match
                                                Metal_raw.blit_encoder_copy_buffer_to_texture
                                                  value.raw source.raw destination.raw copy
                                              with
                                              | Error message -> native_error operation message
                                              | Ok () ->
                                                  retain_command_buffer_buffer value.command_buffer
                                                    source;
                                                  retain_command_buffer_texture value.command_buffer
                                                    destination;
                                                  Ok ()))))))))

  let fill_buffer (value : t) (buffer : Buffer.t) ~offset ~length ~byte =
    let operation = "Metal.Blit_encoder.fill_buffer" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (ensure_buffer_usable operation buffer) (fun () ->
                if
                  offset < 0L || length < 0L || offset > buffer.length
                  || length > Int64.sub buffer.length offset
                  || byte < 0 || byte > 255
                then error operation Invalid_argument "invalid fill range/value"
                else
                  Result.bind
                    (ensure_same_device operation value.command_buffer.queue.device buffer.device)
                    (fun () ->
                      match
                        Metal_raw.blit_fill_mipmap value.raw buffer.raw false
                          (offset, length, Int64.of_int byte)
                      with
                      | Error message -> native_error operation message
                      | Ok () ->
                          retain_command_buffer_buffer value.command_buffer buffer;
                          Ok ())))

  let copy_buffer (value : t) ~(source : Buffer.t) ~source_offset ~(destination : Buffer.t)
      ~destination_offset ~length =
    let operation = "Metal.Blit_encoder.copy_buffer" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (ensure_buffer_usable operation source) (fun () ->
                Result.bind (ensure_buffer_usable operation destination) (fun () ->
                    if
                      source_offset < 0L || destination_offset < 0L || length < 0L
                      || source_offset > source.length
                      || length > Int64.sub source.length source_offset
                      || destination_offset > destination.length
                      || length > Int64.sub destination.length destination_offset
                    then error operation Invalid_argument "copy range exceeds a buffer"
                    else
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device
                           source.device) (fun () ->
                          Result.bind
                            (ensure_same_device operation source.device destination.device)
                            (fun () ->
                              match
                                Metal_raw.blit_copy value.raw 1 source.raw destination.raw
                                  (Metal_raw.Blit_buffer_to_buffer
                                     (source_offset, destination_offset, length))
                              with
                              | Error message -> native_error operation message
                              | Ok () ->
                                  retain_command_buffer_buffer value.command_buffer source;
                                  retain_command_buffer_buffer value.command_buffer destination;
                                  Ok ())))))

  let copy_texture_to_buffer (value : t) ~(source : Texture.t) ~source_slice ~source_level
      ~(source_region : Texture.region) ~(destination : Buffer.t) ~destination_offset
      ~destination_bytes_per_row ~destination_bytes_per_image ?(options = 0L) () =
    let operation = "Metal.Blit_encoder.copy_texture_to_buffer" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (ensure_texture_usable operation source) (fun () ->
                Result.bind (ensure_buffer_usable operation destination) (fun () ->
                    let d = source.descriptor in
                    if
                      source_slice < 0
                      || source_slice >= Texture.total_slices d
                      || source_level < 0 || source_level >= d.mip_levels || source_region.x < 0
                      || source_region.y < 0 || source_region.z < 0 || source_region.width <= 0
                      || source_region.height <= 0 || source_region.depth <= 0
                      || destination_offset < 0L || destination_bytes_per_row <= 0L
                      || destination_bytes_per_image <= 0L
                    then
                      error operation Invalid_argument "texture-to-buffer region/layout is invalid"
                    else
                      let total =
                        Int64.mul destination_bytes_per_image (Int64.of_int source_region.depth)
                      in
                      if
                        total < 0L
                        || destination_offset > destination.length
                        || total > Int64.sub destination.length destination_offset
                      then
                        error operation Invalid_argument
                          "texture-to-buffer destination range exceeds buffer"
                      else
                        Result.bind
                          (ensure_same_device operation value.command_buffer.queue.device
                             source.device) (fun () ->
                            Result.bind
                              (ensure_same_device operation source.device destination.device)
                              (fun () ->
                                match
                                  Metal_raw.blit_copy value.raw 3 source.raw destination.raw
                                    (Metal_raw.Blit_texture_to_buffer
                                       ( Int64.of_int source_slice,
                                         Int64.of_int source_level,
                                         Int64.of_int source_region.x,
                                         Int64.of_int source_region.y,
                                         Int64.of_int source_region.z,
                                         Int64.of_int source_region.width,
                                         Int64.of_int source_region.height,
                                         Int64.of_int source_region.depth,
                                         destination_offset,
                                         destination_bytes_per_row,
                                         destination_bytes_per_image,
                                         options ))
                                with
                                | Error message -> native_error operation message
                                | Ok () ->
                                    retain_command_buffer_texture value.command_buffer source;
                                    retain_command_buffer_buffer value.command_buffer destination;
                                    Ok ())))))

  let copy_texture_region (value : t) ~(source : Texture.t) ~source_slice ~source_level
      ~(source_region : Texture.region) ~(destination : Texture.t) ~destination_slice
      ~destination_level ~destination_origin =
    let operation = "Metal.Blit_encoder.copy_texture_region" in
    let dx, dy, dz = destination_origin in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (ensure_texture_usable operation source) (fun () ->
                Result.bind (ensure_texture_usable operation destination) (fun () ->
                    if
                      source_slice < 0 || destination_slice < 0 || source_level < 0
                      || destination_level < 0
                      || source_slice >= Texture.total_slices source.descriptor
                      || destination_slice >= Texture.total_slices destination.descriptor
                      || source_level >= source.descriptor.mip_levels
                      || destination_level >= destination.descriptor.mip_levels
                      || source_region.width <= 0 || source_region.height <= 0
                      || source_region.depth <= 0 || source_region.x < 0 || source_region.y < 0
                      || source_region.z < 0 || dx < 0 || dy < 0 || dz < 0
                      || source.descriptor.format <> destination.descriptor.format
                    then error operation Invalid_argument "texture copy region is invalid"
                    else
                      Result.bind
                        (ensure_same_device operation value.command_buffer.queue.device
                           source.device) (fun () ->
                          Result.bind
                            (ensure_same_device operation source.device destination.device)
                            (fun () ->
                              match
                                Metal_raw.blit_copy value.raw 4 source.raw destination.raw
                                  (Metal_raw.Blit_texture_region
                                     ( Int64.of_int source_slice,
                                       Int64.of_int source_level,
                                       Int64.of_int source_region.x,
                                       Int64.of_int source_region.y,
                                       Int64.of_int source_region.z,
                                       Int64.of_int source_region.width,
                                       Int64.of_int source_region.height,
                                       Int64.of_int source_region.depth,
                                       Int64.of_int destination_slice,
                                       Int64.of_int destination_level,
                                       Int64.of_int dx,
                                       Int64.of_int dy,
                                       Int64.of_int dz ))
                              with
                              | Error message -> native_error operation message
                              | Ok () ->
                                  retain_command_buffer_texture value.command_buffer source;
                                  retain_command_buffer_texture value.command_buffer destination;
                                  Ok ())))))

  let fence_call operation update (value : t) (fence : Fence.t) =
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (ensure_live operation fence.lifetime) (fun () ->
                Result.bind
                  (ensure_same_device operation value.command_buffer.queue.device fence.device)
                  (fun () ->
                    match Metal_raw.blit_fence value.raw fence.raw update with
                    | Error message -> native_error operation message
                    | Ok () ->
                        retain_command_buffer_fence value.command_buffer fence;
                        Ok ())))

  let update_fence value fence = fence_call "Metal.Blit_encoder.update_fence" true value fence
  let wait_for_fence value fence = fence_call "Metal.Blit_encoder.wait_for_fence" false value fence

  let end_encoding (value : t) =
    on_main "Metal.Blit_encoder.end_encoding" (fun () ->
        match ensure_live "Metal.Blit_encoder.end_encoding" value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.Registry.blit_encoder_end value.raw with
            | Error message -> native_error "Metal.Blit_encoder.end_encoding" message
            | Ok () ->
                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                  ignore (Metal_raw.destroy value.raw);
                  detach value.command_buffer.lifetime
                end;
                Ok ()))
end

module Resource100 = struct
  type tensor = resource100_tensor
  type sample_buffer = counter_sample_buffer

  module Sample_buffer = struct
    type t = resource100_sample_buffer

    let create (device : Device.t) ?label ~sample_count () =
      let op = "Metal.Resource100.Sample_buffer.create" in
      on_main op (fun () ->
          match ensure_live op device.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              if sample_count <= 0L || option_exists contains_nul label then
                error op Invalid_argument "sample count or label is invalid"
              else
                match Metal_raw.counter_sets device.raw with
                | Error m -> native_error op m
                | Ok sets -> (
                    match Array.to_list sets with
                    | [] -> error op Unsupported "device exposes no counter sets"
                    | (counter_set, _) :: _ -> (
                        let cleanup () =
                          Array.iter (fun (raw, _) -> ignore (Metal_raw.destroy raw)) sets
                        in
                        match Metal_raw.counter_descriptor_create () with
                        | Error m ->
                            cleanup ();
                            native_error op m
                        | Ok descriptor -> (
                            match
                              Metal_raw.counter_descriptor_set descriptor counter_set label
                                sample_count 0L
                            with
                            | Error m ->
                                ignore (Metal_raw.destroy descriptor);
                                cleanup ();
                                native_error op m
                            | Ok () -> (
                                let created =
                                  Metal_raw.counter_sample_buffer_create device.raw descriptor
                                in
                                ignore (Metal_raw.destroy descriptor);
                                cleanup ();
                                match created with
                                | Error m -> native_error op m
                                | Ok raw ->
                                    let value : t =
                                      { raw; lifetime = lifetime (); device; sample_count }
                                    in
                                    attach device.lifetime;
                                    attach_finalizer value value.lifetime device.lifetime;
                                    Ok value))))))

    let retain_for_command (commands : command_buffer) (value : t) =
      if not (List.exists (( == ) value.lifetime) !(commands.presentation_events)) then begin
        attach value.lifetime;
        commands.presentation_events := value.lifetime :: !(commands.presentation_events)
      end

    let sample (encoder : Blit_encoder.t) (value : t) ~index =
      let op = "Metal.Resource100.Sample_buffer.sample" in
      on_main op (fun () ->
          match ensure_live op encoder.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live op value.lifetime with
              | Error _ as e -> e
              | Ok () -> (
                  if index < 0L || index >= value.sample_count then
                    error op Invalid_argument "sample index is out of range"
                  else
                    match
                      ensure_same_device op encoder.command_buffer.queue.device value.device
                    with
                    | Error _ as e -> e
                    | Ok () -> (
                        match
                          Metal_raw.blit_counter encoder.raw value.raw index 0L value.raw 0L true
                        with
                        | Error m -> native_error op m
                        | Ok () ->
                            retain_for_command encoder.command_buffer value;
                            Ok ()))))

    let resolve (encoder : Blit_encoder.t) (value : t) ~first ~count (destination : Buffer.t)
        ~offset =
      let op = "Metal.Resource100.Sample_buffer.resolve" in
      on_main op (fun () ->
          match ensure_live op encoder.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live op value.lifetime with
              | Error _ as e -> e
              | Ok () -> (
                  match ensure_buffer_usable op destination with
                  | Error _ as e -> e
                  | Ok () -> (
                      if
                        first < 0L || count < 0L || first > value.sample_count
                        || count > Int64.sub value.sample_count first
                        || offset < 0L || offset > destination.length
                      then error op Invalid_argument "counter resolve range is invalid"
                      else
                        match
                          ensure_same_device op encoder.command_buffer.queue.device value.device
                        with
                        | Error _ as e -> e
                        | Ok () -> (
                            match ensure_same_device op value.device destination.device with
                            | Error _ as e -> e
                            | Ok () -> (
                                match
                                  Metal_raw.blit_counter encoder.raw value.raw first count
                                    destination.raw offset false
                                with
                                | Error m -> native_error op m
                                | Ok () ->
                                    retain_for_command encoder.command_buffer value;
                                    retain_command_buffer_buffer encoder.command_buffer destination;
                                    Ok ()))))))

    let destroy (value : t) =
      destroy_parent "Metal.Resource100.Sample_buffer.destroy" value.lifetime value.raw (fun () ->
          detach value.device.lifetime)
  end

end

module Counters = struct
  type sampling_point = Stage_boundary | Draw_boundary | Dispatch_boundary | Blit_boundary
  type set = { name : string; counters : string list }

  let point_code = function
    | Stage_boundary -> 0
    | Draw_boundary -> 1
    | Dispatch_boundary -> 2
    | Blit_boundary -> 3

  let supports (device : Device.t) point =
    let operation = "Metal.Counters.supports" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.counter_supports_sampling device.raw (point_code point) with
            | Error m -> native_error operation m
            | Ok x -> Ok x))

  let sets (device : Device.t) =
    let operation = "Metal.Counters.sets" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match Metal_raw.counter_sets device.raw with
            | Error m -> native_error operation m
            | Ok raw_sets ->
                let rec collect i acc =
                  if i = Array.length raw_sets then Ok (List.rev acc)
                  else
                    let raw, name = raw_sets.(i) in
                    match Metal_raw.counter_set_counters raw with
                    | Error m ->
                        Array.iter (fun (r, _) -> ignore (Metal_raw.destroy r)) raw_sets;
                        native_error operation m
                    | Ok counters ->
                        let names = Array.to_list (Array.map snd counters) in
                        Array.iter (fun (r, _) -> ignore (Metal_raw.destroy r)) counters;
                        collect (i + 1) ({ name; counters = names } :: acc)
                in
                let result = collect 0 [] in
                Array.iter (fun (r, _) -> ignore (Metal_raw.destroy r)) raw_sets;
                result))

  module Descriptor = struct
    type t = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      device : device;

      sample_count : int64;

    }

    let create (device : Device.t) ~set_name ?label ~sample_count ~storage () =
      let operation = "Metal.Counters.Descriptor.create" in
      on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as e -> e
          | Ok ()
            when set_name = "" || contains_nul set_name || option_exists contains_nul label
                 || sample_count <= 0L ->
              error operation Invalid_argument "counter set, label, or sample count is invalid"
          | Ok () when storage <> Buffer.Shared ->
              error operation Unsupported "safe counter samples require shared storage"
          | Ok () -> (
              match Metal_raw.counter_sets device.raw with
              | Error m -> native_error operation m
              | Ok sets -> (
                  match Array.find_opt (fun (_, name) -> name = set_name) sets with
                  | None ->
                      Array.iter (fun (raw, _) -> ignore (Metal_raw.destroy raw)) sets;
                      error operation Unsupported "counter set is unavailable"
                  | Some (set_raw, _) -> (
                      match Metal_raw.counter_descriptor_create () with
                      | Error m ->
                          Array.iter (fun (raw, _) -> ignore (Metal_raw.destroy raw)) sets;
                          native_error operation m
                      | Ok raw -> (
                          let result =
                            Metal_raw.counter_descriptor_set raw set_raw label sample_count 0L
                          in
                          Array.iter (fun (h, _) -> ignore (Metal_raw.destroy h)) sets;
                          match result with
                          | Error m ->
                              ignore (Metal_raw.destroy raw);
                              native_error operation m
                          | Ok () ->
                              let value =
                                {
                                  raw;
                                  lifetime = lifetime ();
                                  device;

                                  sample_count;

                                }
                              in
                              attach device.lifetime;
                              attach_finalizer value value.lifetime device.lifetime;
                              Ok value)))))

    let create_buffer (t : t) =
      let operation = "Metal.Counters.Descriptor.create_buffer" in
      on_main operation (fun () ->
          match ensure_live operation t.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match Metal_raw.counter_sample_buffer_create t.device.raw t.raw with
              | Error m -> native_error operation m
              | Ok raw ->
                  let value : counter_sample_buffer =
                    {
                      raw;
                      lifetime = lifetime ();
                      device = t.device;
                      sample_count = t.sample_count;

                    }
                  in
                  attach t.device.lifetime;
                  attach_finalizer value value.lifetime t.device.lifetime;
                  Ok value))

    let destroy (t : t) =
      destroy_parent "Metal.Counters.Descriptor.destroy" t.lifetime t.raw (fun () ->
          detach t.device.lifetime)
  end

  let resolve (samples : counter_sample_buffer) ~first ~count =
    let operation = "Metal.Counters.resolve" in
    on_main operation (fun () ->
        match ensure_live operation samples.lifetime with
        | Error _ as e -> e
        | Ok ()
          when first < 0L || count < 0L || first > samples.sample_count
               || count > Int64.sub samples.sample_count first ->
            error operation Invalid_argument "counter range is out of bounds"
        | Ok () -> (
            match Metal_raw.counter_sample_resolve samples.raw first count with
            | Error m -> native_error operation m
            | Ok bytes -> Ok bytes))

  let set_render_pass_attachment pass ~index samples ~start_vertex ~end_vertex ~start_fragment
      ~end_fragment =
    Render_pass_descriptor.set_sample_attachment pass ~index (Some samples) ~start_vertex
      ~end_vertex ~start_fragment ~end_fragment

end

module rec Blit_pass_descriptor : sig
  type t = blit_pass_descriptor

  val create : Device.t -> (t, error) result
  val attachments : t -> (Blit_pass_attachments.t, error) result
  val create_encoder : Command_buffer.t -> t -> (Blit_encoder.t, error) result
  val destroy : t -> (unit, error) result
end = struct
  type t = blit_pass_descriptor

  let create (device : Device.t) =
    let operation = "Metal.Blit_pass_descriptor.create" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match Metal_raw.blit_pass_create () with
            | Error message -> native_error operation message
            | Ok raw ->
                attach device.lifetime;
                let value = { raw; lifetime = lifetime (); device; blit_attachments = None } in
                attach_finalizer value value.lifetime device.lifetime;
                Ok value))

  let attachments (value : t) =
    let operation = "Metal.Blit_pass_descriptor.attachments" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match value.blit_attachments with
            | Some attachments -> Ok attachments
            | None -> (
                match Metal_raw.blit_pass_attachments value.raw with
                | Error message -> native_error operation message
                | Ok raw ->
                    let attachments =
                      { raw; lifetime = lifetime (); parent = value; slots = Array.make 4 None }
                    in
                    attach value.lifetime;
                    attach_finalizer attachments attachments.lifetime value.lifetime;
                    value.blit_attachments <- Some attachments;
                    Ok attachments)))

  let create_encoder (command : Command_buffer.t) (value : t) =
    let operation = "Metal.Blit_pass_descriptor.create_encoder" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match ensure_live operation command.lifetime with
            | Error _ as e -> e
            | Ok () when command.phase <> Recording || dependent_count command.lifetime <> 0 ->
                error operation Invalid_state "command buffer cannot create a blit encoder"
            | Ok () ->
                Result.bind (ensure_same_device operation command.queue.device value.device)
                  (fun () ->
                    match Metal_raw.Registry.command_buffer_blit_encoder_with_pass command.raw value.raw with
                    | Error m -> native_error operation m
                    | Ok raw ->
                        let encoder : blit_encoder = { raw; lifetime = lifetime (); command_buffer = command } in
                        attach command.lifetime;
                        attach value.lifetime;
                        command.presentation_events := value.lifetime :: !(command.presentation_events);
                        Option.iter
                          (fun (attachments : blit_pass_attachment_array) ->
                            Array.iter
                              (Option.iter (fun (attachment : blit_pass_attachment) ->
                                   Option.iter
                                     (fun (buffer : counter_sample_buffer) ->
                                       attach buffer.lifetime;
                                       command.presentation_events :=
                                         buffer.lifetime :: !(command.presentation_events))
                                     attachment.blit_sample_buffer))
                              attachments.slots)
                          value.blit_attachments;
                        attach_finalizer encoder encoder.lifetime command.lifetime;
                        Ok encoder)))

  let destroy (value : t) =
    destroy_parent "Metal.Blit_pass_descriptor.destroy" value.lifetime value.raw (fun () ->
        detach value.device.lifetime)
end

and Blit_pass_attachments : sig
  type t = blit_pass_attachment_array

  val get : t -> index:int -> (Blit_pass_attachment.t option, error) result
  val destroy : t -> (unit, error) result
end = struct
  type t = blit_pass_attachment_array

  let capacity = 4

  let valid operation index =
    if index < 0 || index >= capacity then
      error operation Invalid_argument "blit attachment index must be in [0,4)"
    else Ok ()

  let get (value : t) ~index =
    let operation = "Metal.Blit_pass_attachments.get" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            Result.bind (valid operation index) (fun () ->
                match value.slots.(index) with
                | Some attachment -> Ok (Some attachment)
                | None -> (
                    match Metal_raw.blit_pass10_attachment_at value.raw (Int64.of_int index) with
                    | Error message -> native_error operation message
                    | Ok None -> Ok None
                    | Ok (Some raw) ->
                        let attachment =
                          {
                            raw;
                            lifetime = lifetime ();
                            parent = value;
                            index;
                            blit_sample_buffer = None;

                          }
                        in
                        attach value.lifetime;
                        attach_finalizer attachment attachment.lifetime value.lifetime;
                        value.slots.(index) <- Some attachment;
                        Ok (Some attachment))))

  let destroy (value : t) =
    destroy_parent "Metal.Blit_pass_attachments.destroy" value.lifetime value.raw (fun () ->
        detach value.parent.lifetime)
end

and Blit_pass_attachment : sig
  type t = blit_pass_attachment
  type sample_index = Dont_sample | Index of int64

  val configure :
    t ->
    sample_buffer:Resource100.Sample_buffer.t option ->
    start:sample_index ->
    finish:sample_index ->
    (unit, error) result

  val destroy : t -> (unit, error) result
end = struct
  type t = blit_pass_attachment
  type sample_index = Dont_sample | Index of int64

  let code = function Dont_sample -> -1L | Index index -> index

  let configure (value : t) ~sample_buffer ~start ~finish =
    let operation = "Metal.Blit_pass_attachment.configure" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            let first = code start and last = code finish in
            let validated =
              match sample_buffer with
              | None when first = -1L && last = -1L -> Ok ()
              | None ->
                  error operation Invalid_argument "sample indices require a counter sample buffer"
              | Some (buffer : counter_sample_buffer) ->
                  Result.bind (ensure_live operation buffer.lifetime) (fun () ->
                      Result.bind
                        (ensure_same_device operation value.parent.parent.device buffer.device)
                        (fun () ->
                          if first < 0L || last < first || last >= buffer.sample_count then
                            error operation Invalid_argument "blit sample range is invalid"
                          else Ok ()))
            in
            Result.bind validated (fun () ->
                let raw_buffer =
                  Option.map (fun (buffer : counter_sample_buffer) -> buffer.raw) sample_buffer
                in
                match
                  Metal_raw.blit_attachment value.parent.raw (Int64.of_int value.index) raw_buffer
                    first last
                with
                | Error message -> native_error operation message
                | Ok temporary -> (
                    ignore (Metal_raw.destroy temporary);
                    match
                      Metal_raw.blit_pass10_set_sample_buffer value.raw raw_buffer
                        value.parent.parent.device.registry_id
                    with
                    | Error message -> native_error operation message
                    | Ok () ->
                        Option.iter
                          (fun (buffer : counter_sample_buffer) -> detach buffer.lifetime)
                          value.blit_sample_buffer;
                        Option.iter
                          (fun (buffer : counter_sample_buffer) -> attach buffer.lifetime)
                          sample_buffer;
                        value.blit_sample_buffer <- sample_buffer;
                        ();
                        ();
                        Ok ())))

  let destroy (value : t) =
    destroy_leaf "Metal.Blit_pass_attachment.destroy" value.lifetime value.raw (fun () ->
        Option.iter
          (fun (buffer : counter_sample_buffer) -> detach buffer.lifetime)
          value.blit_sample_buffer;
        detach value.parent.lifetime)
end

module Compute_pass = struct
  type dispatch = Serial | Concurrent

  type attachment = {
    sample_buffer : Resource100.Sample_buffer.t;
    start_index : int64;
    end_index : int64;
  }

  type t = compute_pass_descriptor

  let capacity = 4
  let dispatch_code = function Serial -> 0 | Concurrent -> 1

  let validate operation (device : Device.t) (value : attachment option) =
    match value with
    | None -> Ok ()
    | Some value -> (
        match ensure_live operation value.sample_buffer.lifetime with
        | Error _ as failure -> failure
        | Ok () -> (
            match ensure_same_device operation device value.sample_buffer.device with
            | Error _ as failure -> failure
            | Ok ()
              when value.start_index < 0L
                   || value.end_index < value.start_index
                   || value.end_index >= value.sample_buffer.sample_count ->
                error operation Invalid_argument "compute sample indices are out of range"
            | Ok () -> Ok ()))

  let set_native operation array_raw index (attachment : attachment option) =
    let buffer, start, finish =
      match attachment with
      | None -> (None, -1L, -1L)
      | Some value -> (Some value.sample_buffer.raw, value.start_index, value.end_index)
    in
    match Metal_raw.compute_pass_attachment array_raw (Int64.of_int index) buffer start finish with
    | Error message -> native_error operation message
    | Ok raw -> (
        let snapshot = Metal_raw.compute_pass_attachment_snapshot raw in
        ignore (Metal_raw.destroy raw);
        match snapshot with
        | Error message -> native_error operation message
        | Ok (native_buffer, native_start, native_finish) ->
            Option.iter (fun raw -> ignore (Metal_raw.destroy raw)) native_buffer;
            if
              Option.is_some native_buffer <> Option.is_some buffer
              || native_start <> start || native_finish <> finish
            then native_error operation "native compute attachment snapshot drift"
            else Ok ())

  let create (device : Device.t) ?(dispatch = Serial)
      ?(attachments : attachment option array = [||]) () =
    let operation = "Metal.Compute_pass.create" in
    on_main operation (fun () ->
        match ensure_live operation device.lifetime with
        | Error _ as failure -> failure
        | Ok () when Array.length attachments > capacity ->
            error operation Invalid_argument "too many compute attachments"
        | Ok () -> (
            let slots = Array.make capacity None in
            Array.blit attachments 0 slots 0 (Array.length attachments);
            let rec checked i =
              if i = capacity then Ok ()
              else
                match validate operation device slots.(i) with
                | Error _ as failure -> failure
                | Ok () -> checked (i + 1)
            in
            match checked 0 with
            | Error _ as failure -> failure
            | Ok () -> (
                match Metal_raw.compute_pass_create (dispatch_code dispatch) with
                | Error message -> native_error operation message
                | Ok raw -> (
                    match Metal_raw.compute_pass_snapshot raw with
                    | Error message ->
                        ignore (Metal_raw.destroy raw);
                        native_error operation message
                    | Ok (native_dispatch, array_raw) -> (
                        let rec fill i =
                          if i = capacity then Ok ()
                          else
                            match set_native operation array_raw i slots.(i) with
                            | Error _ as failure -> failure
                            | Ok () -> fill (i + 1)
                        in
                        let outcome =
                          if native_dispatch <> dispatch_code dispatch then
                            native_error operation "native compute dispatch drift"
                          else fill 0
                        in
                        ignore (Metal_raw.destroy array_raw);
                        match outcome with
                        | Error _ as failure ->
                            ignore (Metal_raw.destroy raw);
                            failure
                        | Ok () ->
                            Array.iter
                              (Option.iter (fun (value : attachment) ->
                                   attach value.sample_buffer.lifetime))
                              slots;
                            attach device.lifetime;
                            let value : t =
                              {
                                raw;
                                lifetime = lifetime ();
                                device;

                                compute_attachments =
                                  Array.map
                                    (Option.map (fun (value : attachment) ->
                                         (value.sample_buffer, value.start_index, value.end_index)))
                                    slots;
                              }
                            in
                            Gc.finalise
                              (fun (value : t) ->
                                if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                                  ignore (Metal_raw.destroy value.raw);
                                  Array.iter
                                    (Option.iter
                                       (fun ((buffer : resource100_sample_buffer), _, _) ->
                                         detach buffer.lifetime))
                                    value.compute_attachments;
                                  detach value.device.lifetime
                                end)
                              value;
                            Ok value)))))

  let create_encoder (command : Command_buffer.t) (value : t) =
    let operation = "Metal.Compute_pass.create_encoder" in
    on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as e -> e
        | Ok () -> (
            match ensure_live operation command.lifetime with
            | Error _ as e -> e
            | Ok () when command.phase <> Recording || dependent_count command.lifetime <> 0 ->
                error operation Invalid_state "command buffer cannot create a compute encoder"
            | Ok () ->
                Result.bind (ensure_same_device operation command.queue.device value.device)
                  (fun () ->
                    match Metal_raw.Registry.command_buffer_compute_encoder_with_pass command.raw value.raw with
                    | Error m -> native_error operation m
                    | Ok raw ->
                        let encoder : compute_encoder =
                          { raw; lifetime = lifetime (); command_buffer = command; pipeline = None }
                        in
                        attach command.lifetime;
                        attach value.lifetime;
                        command.presentation_events := value.lifetime :: !(command.presentation_events);
                        Array.iter
                          (Option.iter (fun ((buffer : resource100_sample_buffer), _, _) ->
                               attach buffer.lifetime;
                               command.presentation_events :=
                                 buffer.lifetime :: !(command.presentation_events)))
                          value.compute_attachments;
                        attach_finalizer encoder encoder.lifetime command.lifetime;
                        Ok encoder)))

  let destroy (value : t) =
    destroy_parent "Metal.Compute_pass.destroy" value.lifetime value.raw (fun () ->
        Array.iter
          (Option.iter (fun ((buffer : resource100_sample_buffer), _, _) -> detach buffer.lifetime))
          value.compute_attachments;
        detach value.device.lifetime)
end

module Fx = struct
  module Spatial_scaler = struct
    type t = {
      raw : Metal_raw.handle;
      lifetime : lifetime;
      device : device;
      input : int * int;
      output : int * int;

    }

    let supported (device : Device.t) =
      let operation = "Metal.Fx.Spatial_scaler.supported" in
      on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match Metal_raw.fx_spatial_supported device.raw with
              | Error m -> native_error operation m
              | Ok x -> Ok x))

    let create (device : Device.t) ~input:(iw, ih) ~output:(ow, oh) ~color_format ~output_format =
      let operation = "Metal.Fx.Spatial_scaler.create" in
      on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as e -> e
          | Ok () when iw <= 0 || ih <= 0 || ow < iw || oh < ih ->
              error operation Invalid_argument
                "scaler input must be positive and the output no smaller than the input"
          | Ok () -> (
              match
                Metal_raw.fx_spatial_create device.raw
                  ( iw, ih, ow, oh,
                    Texture.format_code color_format,
                    Texture.format_code output_format )
              with
              | Error m -> native_error operation m
              | Ok raw ->
                  attach device.lifetime;
                  let value = { raw; lifetime = lifetime (); device; input = (iw, ih); output = (ow, oh) } in
                  attach_finalizer value value.lifetime device.lifetime;
                  Ok value))

    let input value = value.input
    let output value = value.output

    (* Encodes between encoders of a recording command buffer, which retains
       the scaler and both textures until completion. *)
    let encode (value : t) (command : Command_buffer.t) ~(color : Texture.t) ~(output : Texture.t) =
      let operation = "Metal.Fx.Spatial_scaler.encode" in
      on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as e -> e
          | Ok () -> (
              match ensure_live operation command.lifetime with
              | Error _ as e -> e
              | Ok () when command.phase <> Recording || dependent_count command.lifetime <> 0 ->
                  error operation Invalid_state "scaling requires a recording command buffer with no open encoder"
              | Ok () -> (
                  match ensure_same_device operation command.queue.device value.device with
                  | Error _ as e -> e
                  | Ok () -> (
                      match (ensure_live operation color.lifetime, ensure_live operation output.lifetime) with
                      | (Error _ as e), _ | _, (Error _ as e) -> e
                      | Ok (), Ok () when not (same_device color.device value.device && same_device output.device value.device) ->
                          error operation Device_mismatch "scaler textures belong to another device"
                      | Ok (), Ok () when (color.descriptor.width, color.descriptor.height) <> value.input
                                          || (output.descriptor.width, output.descriptor.height) <> value.output ->
                          error operation Invalid_argument "texture sizes differ from the scaler configuration"
                      | Ok (), Ok () -> (
                          match Metal_raw.fx_spatial_encode value.raw command.raw color.raw output.raw with
                          | Error m -> native_error operation m
                          | Ok () ->
                              retain_command_buffer_texture command color;
                              retain_command_buffer_texture command output;
                              attach value.lifetime;
                              command.presentation_events := value.lifetime :: !(command.presentation_events);
                              Ok ())))))

    let destroy (value : t) =
      destroy_parent "Metal.Fx.Spatial_scaler.destroy" value.lifetime value.raw (fun () ->
          detach value.device.lifetime)
  end
end
