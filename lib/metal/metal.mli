(** Ownership-aware bindings to Metal.framework on macOS. *)

(** Registry-generated enum values used by the safe Metal API. *)
module Enum : module type of Metal_gen.Enum

(** Typed Metal data-type values, including packed formats and resource kinds. *)
module Data_type : module type of Metal_gen.Enum.Mtl_data_type
module Feature_set : module type of Metal_gen.Enum.Mtl_feature_set

type error_kind =
  | Native_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Invalid_state
  | Unsupported
  | Device_mismatch

type error = private
  { operation : string
  ; kind : error_kind
  ; message : string
  }

type acceleration_structure
type indirect_command_buffer
type visible_function_table
type intersection_function_table
type render_pipeline
type compute_pipeline
type depth_stencil
type binary_archive
type counter_sample_buffer

type purgeable_state =
  | Nonvolatile
  | Volatile
  | Empty

module Sparse_page_size : sig
  type t =
    | Page_16_kib
    | Page_64_kib
    | Page_256_kib

end

val pp_error : Format.formatter -> error -> unit

module Release_queue : sig
  type stats =
    { pending : int
    ; live_handles : int
    ; total_created : int64
    ; total_released : int64
    ; external_deallocations : int64
    ; external_deallocation_mismatches : int64
    ; resident_bytes : int64
    }

  val drain : unit -> (int, error) result
  val stats : unit -> (stats, error) result
end

type device
module Shared_event : sig
  type t
  val signaled_value:t->(int64,error)result
  val set_signaled_value:t->int64->(unit,error)result

  (** Blocks the calling thread (releasing the OCaml runtime) until the event
      reaches [value] or [timeout_ms] elapses; [Ok false] on timeout. *)
  val wait_until_signaled:t->value:int64->timeout_ms:int64->(bool,error)result
  val destroy:t->(unit,error)result
end

type compute_encoder
type acceleration_encoder
type blit_encoder
type resource_state_encoder
type command_queue
type fence
module Device : sig
  type t = device
  type counter_sampling_point=Stage_boundary|Draw_boundary|Dispatch_boundary|Blit_boundary
  type capability_snapshot={barycentric_coordinates:bool;max_threads:(int64*int64*int64);maximize_concurrent_compilation:bool;bc_texture_compression:bool;counter_set_count:int}

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

  type info =
    { name : string
    ; registry_id : int64
    ; low_power : bool
    ; removable : bool
    ; headless : bool
    ; unified_memory : bool
    ; recommended_max_working_set_size : int64
    ; current_allocated_size : int64
    ; max_buffer_length : int64
    ; max_threadgroup_memory_length : int64
    ; raytracing : bool
    ; raytracing_from_render : bool
    ; dynamic_libraries : bool
    ; function_pointers : bool
    }

  val system_default : unit -> (t, error) result
  val new_fence : t -> (fence,error) result
  val new_shared_event:t->(Shared_event.t,error)result
  val same : t -> t -> bool
  val info : t -> (info, error) result
  val supports_family : t -> family -> (bool, error) result
  val supports_texture_sample_count : t -> int -> (bool, error) result

  val supports_residency_sets : t -> (bool, error) result
  val supports_sparse_textures : t -> (bool, error) result

  type sparse_region = { x:int64; y:int64; z:int64; width:int64; height:int64; depth:int64 }
  type sparse_alignment = Outward | Inward
  val sample_timestamps : t -> ((int64*int64),error) result
  val timestamp_frequency : t -> (int64,error) result
  val destroy : t -> (unit, error) result
end

module Buffer : sig
  type t

  type storage_mode =
    | Shared
    | Managed
    | Private

  type cpu_cache_mode =
    | Default_cache
    | Write_combined

  type hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type sparse_tier =
    | Not_sparse
    | Sparse_tier_1

  val create :
    device:Device.t -> length:int64 -> storage:storage_mode ->
    ?cpu_cache:cpu_cache_mode -> ?hazard_tracking:hazard_tracking_mode ->
    ?label:string -> unit -> (t, error) result

  val length : t -> int64

  val write_bytes :
    t -> ?src_offset:int -> dst_offset:int64 -> bytes -> (unit, error) result
  val read_bytes : t -> offset:int64 -> length:int -> (bytes, error) result

  val make_aliasable : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Acceleration_structure : sig
  type t

  type sizes =
    { acceleration_structure_size : int64
    ; build_scratch_buffer_size : int64
    ; refit_scratch_buffer_size : int64
    }

  type structure = t

  (** Generic build descriptors (plan G5). A geometry lists one keyframe for a
      static structure or exactly [motion.keyframe_count] keyframes; ranges are
      validated against their buffers, and the descriptor keeps every buffer and
      instanced structure alive until it is destroyed. *)
  module Build : sig
    type keyframe = { buffer : Buffer.t; offset : int64 }
    type border = Clamp | Vanish
    type motion =
      { keyframe_count : int; start_time : float; end_time : float
      ; start_border : border; end_border : border }
    type index = { index_buffer : Buffer.t; index_offset : int64; index_uint16 : bool }
    type common =
      { opaque : bool; allow_duplicate_intersection : bool
      ; intersection_function_table_offset : int }
    val default_common : common
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

    (** Byte offsets inside one native instance record; [-1] where the kind
        lacks the field. [transform] is a packed 4x3 (48 bytes), [user_id] and
        the motion fields exist for the user-id and motion kinds. *)
    type instance_layout =
      { size : int; transform : int; options : int; mask : int; table_offset : int
      ; structure_index : int; user_id : int; transforms_start : int; transforms_count : int
      ; start_border_offset : int; end_border_offset : int; start_time_offset : int
      ; end_time_offset : int }
    val instance_layout : instance_kind -> instance_layout
    type t
    val primitive : Device.t -> ?motion:motion -> ?usage:usage list -> geometry list ->
      (t, error) result

    (** [motion_transforms] is (buffer, offset, count) of packed 4x3 keyframe
        transforms and is required for [Motion_instances]. *)
    val instances : Device.t -> buffer:Buffer.t -> ?offset:int64 -> ?stride:int64 ->
      count:int64 -> ?kind:instance_kind -> ?motion_transforms:(Buffer.t * int64 * int64) ->
      ?usage:usage list -> structure array -> (t, error) result
    val sizes : device:Device.t -> t -> (sizes, error) result

    val instance_kind : t -> instance_kind option
    val destroy : t -> (unit, error) result
  end

  val create : device:Device.t -> size:int64 -> (t, error) result
  val destroy : t -> (unit, error) result
end

module Texture : sig
  type t

  type kind =
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

  type format =
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

  type format_layout =
    { block_width : int
    ; block_height : int
    ; bytes_per_block : int
    }

  type cpu_cache_mode =
    | Default_cache
    | Write_combined

  type hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type usage =
    | Shader_read
    | Shader_write
    | Render_target
    | Pixel_format_view
    | Shader_atomic

  type compression_type =
    | Lossless
    | Lossy

  type swizzle_channel =
    | Zero
    | One
    | Red
    | Green
    | Blue
    | Alpha

  type swizzle =
    { red : swizzle_channel
    ; green : swizzle_channel
    ; blue : swizzle_channel
    ; alpha : swizzle_channel
    }

  type sparse_tier =
    | Not_sparse
    | Sparse_tier_1
    | Sparse_tier_2

  type descriptor =
    { kind : kind
    ; format : format
    ; width : int
    ; height : int
    ; depth : int
    ; mip_levels : int
    ; sample_count : int
    ; array_length : int
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; usage : usage list
    ; allow_gpu_optimized_contents : bool
    ; compression : compression_type
    ; swizzle : swizzle
    ; label : string option
    }

  type region =
    { x : int
    ; y : int
    ; z : int
    ; width : int
    ; height : int
    ; depth : int
    }

  type sparse_info =
    { page_size : Sparse_page_size.t
    ; tile_width : int
    ; tile_height : int
    ; tile_depth : int
    ; tile_size_in_bytes : int64
    ; first_mip_in_tail : int option
    ; tail_size_in_bytes : int64
    }

  type buffer_backing =
    { buffer : Buffer.t
    ; offset : int64
    ; bytes_per_row : int
    }

  val descriptor_2d :
    ?mipmapped:bool -> ?storage:Buffer.storage_mode -> ?usage:usage list ->
    ?compression:compression_type -> ?swizzle:swizzle -> ?label:string ->
    format:format -> width:int -> height:int -> unit -> descriptor
  val create : device:Device.t -> descriptor -> (t, error) result

  (** The optional swizzle is composed with the parent's effective swizzle.
      A same-format swizzled view does not require [Pixel_format_view]; format
      reinterpretation still does. The returned descriptor records the
      effective composed swizzle. *)
  val create_view :
    t -> format:format -> base_mip:int -> mip_count:int -> base_slice:int ->
    slice_count:int -> ?swizzle:swizzle -> ?label:string -> unit ->
    (t, error) result
  val device : t -> Device.t
  val descriptor : t -> descriptor

  val sparse_info : t -> (sparse_info option, error) result
  val destroyed : t -> bool
  val write_bytes :
    t -> region:region -> mip_level:int -> slice:int -> ?src_offset:int ->
    bytes_per_row:int -> bytes_per_image:int -> bytes -> (unit, error) result
  val read_bytes :
    t -> region:region -> mip_level:int -> slice:int -> bytes_per_row:int ->
    bytes_per_image:int -> (bytes, error) result
  (* Read directly into caller-owned storage.  The destination must have the
     exact pitched size of the requested region. *)
  val read_bytes_into :
    t -> region:region -> mip_level:int -> slice:int -> bytes_per_row:int ->
    bytes_per_image:int -> destination:bytes -> (unit, error) result
  val make_aliasable : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Metal_layer : sig
  type t
  type edr_metadata = Standard | Hlg | Hdr10 of {minimum_luminance:float;maximum_luminance:float;optical_output_scale:float}
  type config =
    { width:int; height:int; format:Texture.format; framebuffer_only:bool
    ; maximum_drawables:int; allows_timeout:bool; display_sync:bool
    ; presents_with_transaction:bool }
  val default : width:int -> height:int -> config
  val create : Device.t -> config -> (t,error) result
  val adopt_borrowed : Device.t -> Native_layer_token.t -> config -> (t,error) result
  val configure : t -> config -> (unit,error) result
  val device : t -> Device.t
  val config : t -> config
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

module Drawable : sig
  type t
  type loss = Timeout_or_unavailable
  type present_time = Immediate | At_time of float | After_minimum_duration of float
  val acquire : Metal_layer.t -> ((t,loss) result,error) result
  val texture : t -> (Texture.t,error) result
  val destroy : t -> (unit,error) result
  module Private : sig
    (** Acquires an explicitly-owned drawable without an OCaml finalizer.
        Destroy it on every exit, after destroying its texture wrapper.  A
        drawable scheduled on a retained-reference command buffer remains
        natively owned through terminal presentation. *)
    val acquire_scoped : Metal_layer.t -> ((t,loss) result,error) result
    (* Returns the explicitly-owned drawable texture wrapper without an OCaml
        finalizer.  Use this with [acquire_scoped], and destroy the texture
        before destroying its drawable. *)
    val texture_scoped : t -> (Texture.t,error) result
  end
end

module Render_pass_descriptor : sig
  type t
  type color_load_action = Load_dont_care | Load | Clear
  type visibility_result_type = Disabled | Boolean
  type sample_attachment =
    { start_vertex : int64
    ; end_vertex : int64
    ; start_fragment : int64
    ; end_fragment : int64
    ; has_sample_buffer : bool }
  type advanced =
    { imageblock_sample_length : int64
    ; threadgroup_memory_length : int64
    ; tile_width : int64
    ; tile_height : int64
    ; visibility_result_type : visibility_result_type
    ; support_color_attachment_mapping : bool
    ; sample_positions : (float * float) array }
  val create : width:int -> height:int -> ?array_length:int -> ?sample_count:int -> unit -> (t,error) result
  val set_resolve_texture : t -> Texture.t option -> (unit,error) result
  val set_color_store_action : t -> resolve:bool -> (unit,error) result
  val set_color_load_action : t -> color_load_action -> (unit,error) result
  type store_action = Store_dont_care | Store

  (** Load/store actions and clear values for the depth and stencil
      attachments set by [set_attachments]; absent attachments are left
      untouched. *)
  val set_depth_stencil_actions : t -> depth:(color_load_action * store_action * float) ->
    stencil:(color_load_action * store_action * int) -> (unit,error) result
  val set_attachments :
    t -> color:Texture.t -> ?clear:float * float * float * float ->
    ?depth:Texture.t -> ?stencil:Texture.t -> ?visibility_result:Buffer.t ->
    unit -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Fence : sig
  type t = fence
  val create : Device.t -> (t, error) result
  val destroy : t -> (unit, error) result
end

module Heap : sig
  type t
  type kind = Automatic | Placement | Sparse
  type cpu_cache_mode = Default_cache | Write_combined
  type hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type descriptor =
    { size : int64
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; kind : kind
    ; sparse_page_size : Sparse_page_size.t option
      (** Exact page size for [Sparse], or the maximum compatible placement
          sparse page size for [Placement]. [Automatic] requires [None]. *)
    ; label : string option
    }

  type size_and_align =
    { size : int64
    ; alignment : int64
    }

  type info =
    { size : int64
    ; used_size : int64
    ; current_allocated_size : int64
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; kind : kind
    }

  val make_descriptor :
    ?storage:Buffer.storage_mode -> ?cpu_cache:cpu_cache_mode ->
    ?hazard_tracking:hazard_tracking_mode -> ?kind:kind ->
    ?sparse_page_size:Sparse_page_size.t -> ?label:string -> size:int64 -> unit ->
    descriptor
  val buffer_size_and_align :
    device:Device.t -> length:int64 -> storage:Buffer.storage_mode ->
    ?cpu_cache:cpu_cache_mode -> ?hazard_tracking:hazard_tracking_mode ->
    unit -> (size_and_align, error) result
  val texture_size_and_align :
    device:Device.t -> Texture.descriptor -> (size_and_align, error) result
  val create : device:Device.t -> descriptor -> (t, error) result
  val create_buffer :
    t -> ?offset:int64 -> length:int64 -> ?label:string -> unit ->
    (Buffer.t, error) result
  val create_texture :
    t -> ?offset:int64 -> Texture.descriptor -> (Texture.t, error) result
  val descriptor : t -> descriptor
  val destroy : t -> (unit, error) result
end

module Residency_set : sig
  type t

  type allocation =
    | Buffer of Buffer.t
    | Texture of Texture.t
    | Heap of Heap.t

  type descriptor =
    { label : string option
    ; initial_capacity : int
    }

  val make_descriptor :
    ?label:string -> ?initial_capacity:int -> unit -> descriptor
  val create : device:Device.t -> descriptor -> (t, error) result
  val allocated_size : t -> (int64, error) result
  val add_allocation : t -> allocation -> (unit, error) result
  val remove_allocation : t -> allocation -> (unit, error) result
  val commit : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Sampler : sig
  type t
  type filter = Nearest | Linear
  type mip_filter = Not_mipmapped | Mip_nearest | Mip_linear
  type address_mode =
    | Clamp_to_edge
    | Mirror_clamp_to_edge
    | Repeat
    | Mirror_repeat
    | Clamp_to_zero
    | Clamp_to_border_color

  type border_color = Transparent_black | Opaque_black | Opaque_white
  type reduction_mode = Weighted_average | Minimum | Maximum
  type compare_function =
    | Never
    | Less
    | Equal
    | Less_equal
    | Greater
    | Not_equal
    | Greater_equal
    | Always

  type descriptor =
    { min_filter : filter
    ; mag_filter : filter
    ; mip_filter : mip_filter
    ; max_anisotropy : int
    ; s_address : address_mode
    ; t_address : address_mode
    ; r_address : address_mode
    ; border_color : border_color
    ; reduction_mode : reduction_mode
    ; normalized_coordinates : bool
    ; lod_min_clamp : float
    ; lod_max_clamp : float
    ; lod_average : bool
    ; lod_bias : float
    ; compare_function : compare_function
    ; support_argument_buffers : bool
    ; label : string option
    }

  val default : ?label:string -> unit -> descriptor
  val create : device:Device.t -> descriptor -> (t, error) result
  val destroy : t -> (unit, error) result

end

module Depth_stencil : sig
  type t
  type compare_function =
    | Never
    | Less
    | Equal
    | Less_equal
    | Greater
    | Not_equal
    | Greater_equal
    | Always

  type operation =
    | Keep
    | Zero
    | Replace
    | Increment_clamp
    | Decrement_clamp
    | Invert
    | Increment_wrap
    | Decrement_wrap

  type face = private
    { compare : compare_function
    ; stencil_fail : operation
    ; depth_fail : operation
    ; pass : operation
    ; read_mask : int32
    ; write_mask : int32
    }

  (** Builds one immutable stencil-face policy. Masks are unsigned 32-bit bit
      patterns; defaults are always/keep with all mask bits set. *)
  val face :
    ?compare:compare_function -> ?stencil_fail:operation ->
    ?depth_fail:operation -> ?pass:operation -> ?read_mask:int32 ->
    ?write_mask:int32 -> unit -> face

  (** Creates immutable depth-test state. The default is always-pass with depth
      writes disabled and with stencil testing disabled for both faces. *)
  val create :
    ?label:string -> ?depth_compare:compare_function -> ?depth_write:bool ->
    ?front_face:face -> ?back_face:face -> Device.t -> unit ->
    (t, error) result

  val destroy : t -> (unit, error) result

  module Private : sig
  end
end

module Shader_type : sig
  type scalar =
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

  type t =
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
end

module Reflection : module type of Metal_argument_reflection_snapshot

module Binding : sig
  type access =
    | Read_only
    | Read_write
    | Write_only
    | Unknown_access of int

  type buffer =
    { alignment : int64
    ; data_size : int64
    ; data_type : Shader_type.t
    }

  type texture =
    { texture_kind : Texture.kind
    ; data_type : Shader_type.t
    ; depth : bool
    ; array_length : int64
    }

  type sized =
    { alignment : int64
    ; data_size : int64
    }

  type kind =
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

  type t =
    { name : string
    ; index : int64
    ; access : access
    ; used : bool
    ; argument : bool
    ; kind : kind
    ; reflection : Reflection.reflected_type option
    }

  type layout_kind =
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

  type layout =
    { name : string
    ; index : int64
    ; access : access
    ; kind : layout_kind
    ; data_type : Shader_type.t option
    }

end

module Library : sig
  type t

  type kind =
    | Executable_library
    | Dynamic_library_source
    | Unknown_library_kind of int

  val compile_source :
    ?label:string -> device:Device.t -> string -> (t, error) result

  val compile_dynamic_source :
    ?label:string -> device:Device.t -> install_name:string -> string ->
    (t, error) result

  val load_data : device:Device.t -> string -> (t, error) result
  (* Calls the deprecated path-based SDK constructor exactly. New code should
     prefer [load_file], which uses the URL-based constructor. *)

  val destroy : t -> (unit, error) result
end

module rec Function : sig
  type t
  type options = int64
  type patch_type = No_patch | Triangle_patch | Quad_patch | Other_patch of int64

  type kind =
    | Vertex
    | Fragment
    | Kernel
    | Visible
    | Intersection
    | Mesh
    | Object
    | Unknown_function_kind of int

  type constant_value =
    | Bool_constant of bool
    | Int8_constant of int
    | Uint8_constant of int
    | Int16_constant of int
    | Uint16_constant of int
    | Int32_constant of int32
    | Uint32_constant of int64
    | Int64_constant of int64
    (** The [int64] bit pattern is reinterpreted as an unsigned Metal value. *)
    | Uint64_bits_constant of int64
    | Float16_constant of float
    | Float32_constant of float

  type constant =
    { name : string
    ; data_type : Shader_type.t
    ; index : int64
    ; required : bool
    }

  type descriptor

  val find : library:Library.t -> string -> (t, error) result
  val specialize :
    library:Library.t -> ?label:string ->
    constants:(string * constant_value) list -> string -> (t, error) result
  val argument_encoder : t -> buffer_index:int64 -> (Shader_argument_encoder.t,error) result
  val destroy : t -> (unit, error) result
end

and Shader_argument_encoder : sig
  type t
  type access = Read_only | Read_write | Write_only
  type descriptor =
    { data_type : Data_type.t
    ; index : int64
    ; array_length : int64
    ; access : access
    ; texture_kind : Texture.kind
    ; constant_block_alignment : int64 }
  type resource =
    | Buffer of Buffer.t | Texture of Texture.t | Sampler of Sampler.t
    | Acceleration_structure of acceleration_structure
    | Indirect_command_buffer of indirect_command_buffer
    | Visible_function_table of visible_function_table
    | Intersection_function_table of intersection_function_table
    | Render_pipeline of render_pipeline
    | Compute_pipeline of compute_pipeline | Depth_stencil of depth_stencil
  val encoded_length : t -> int64
  val alignment : t -> int64
  val set : t -> index:int64 -> ?offset:int64 -> resource -> (unit,error) result
  val set_argument_buffer : t -> Buffer.t -> offset:int64 -> ?start_offset:int64 -> ?array_element:int64 -> unit -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Dynamic_library : sig
  type t

  val create : ?label:string -> Library.t -> (t, error) result
  val load_file :
    ?label:string -> device:Device.t -> string -> (t, error) result

  (** Compiles an executable library whose unresolved symbols are linked
      against the supplied same-device dynamic libraries. *)
  val compile_source :
    ?label:string -> device:Device.t -> libraries:t list -> string ->
    (Library.t, error) result

  (** Serializes device code and its source-library fallback to an absolute
      file path. *)
  val serialize : t -> string -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Binary_archive : sig
  type t = binary_archive

  (** With no [path], creates an empty archive. An absolute [path] opens a
      previously serialized archive. *)
  val create :
    ?path:string -> ?label:string -> Device.t -> (t, error) result

  val add_compute_functions :
    t -> ?linked_functions:Function.t list ->
    ?preloaded_libraries:Dynamic_library.t list -> Function.t ->
    (unit, error) result

  val add_mesh_render_pipeline :
    t -> mesh:Function.t -> ?fragment:Function.t ->
    color_format:Texture.format -> unit -> (unit,error) result
  val add_tile_render_pipeline :
    t -> tile:Function.t -> color_format:Texture.format -> (unit,error) result

  val serialize : t -> string -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Pipeline_buffer_descriptor : sig
  type mutability = Default | Mutable | Immutable
  type t
end

module Compute_pipeline : sig
  type t
  type size3 = { width:int64; height:int64; depth:int64 }
  type shader_validation = Default | Enabled | Disabled
  type function_handle_info={name:string;kind:Function.kind;resource_id:int64}

  val create :
    ?label:string ->
    ?buffer_descriptors:(int * Pipeline_buffer_descriptor.t option) list ->
    ?linked_functions:Function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?binary_archives:Binary_archive.t list ->
    ?fail_on_binary_archive_miss:bool -> ?support_indirect_command_buffers:bool ->
    ?reflection:bool -> Function.t ->
    (t, error) result
  val bindings : t -> Binding.t list option
  val destroy : t -> (unit, error) result
end

module Vertex_descriptor : sig
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

  type step_function =
    | Constant
    | Per_vertex
    | Per_instance
    | Per_patch
    | Per_patch_control_point

  type stride =
    | Static of int
    | Dynamic

  type attribute = private
    { index : int
    ; format : format
    ; offset : int
    ; buffer_index : int
    }

  type layout = private
    { buffer_index : int
    ; stride : stride
    ; step_function : step_function
    ; step_rate : int
    }

  type t

end

module Function_handle : sig
  type t
  val create : pipeline:Compute_pipeline.t -> function_:Function.t -> (t, error) result
  val destroy : t -> (unit, error) result
end

module Visible_function_table : sig
  type t
  val create : pipeline:Compute_pipeline.t -> capacity:int -> (t, error) result
  val set_function : t -> index:int -> Function_handle.t option -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Intersection_function_table : sig
  type t
  type opaque_shape = Triangle | Curve
  val create : pipeline:Compute_pipeline.t -> capacity:int -> (t, error) result
  val set_function : t -> index:int -> Function_handle.t option -> (unit, error) result
  val set_buffer : t -> index:int -> ?offset:int64 -> Buffer.t option -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Render_pipeline : sig
  type t
  type size3 = { width:int64; height:int64; depth:int64 }
  type shader_validation = Default | Enabled | Disabled

  type kind =
    | Render
    | Tile
    | Mesh

  type primitive_topology =
    | Point
    | Line
    | Triangle

  (** [Identity] maps logical color outputs to the same physical indices.
      [Inherited] takes the mapping from the render encoder at draw time. *)
  type color_attachment_mapping =
    | Identity
    | Inherited

  type blend_state =
    | Blend_disabled
    | Blend_enabled

  type blend_factor =
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

  type blend_operation =
    | Blend_add
    | Blend_subtract
    | Blend_reverse_subtract
    | Blend_min
    | Blend_max

  type color_write =
    | Write_red
    | Write_green
    | Write_blue
    | Write_alpha

  type color_attachment = private
    { format : Texture.format
    ; blending : blend_state
    ; source_rgb : blend_factor
    ; destination_rgb : blend_factor
    ; rgb_operation : blend_operation
    ; source_alpha : blend_factor
    ; destination_alpha : blend_factor
    ; alpha_operation : blend_operation
    ; write_mask : color_write list
    }

  (** Builds one concrete color-attachment pipeline policy. *)
  val color_attachment :
    ?blending:blend_state -> ?source_rgb:blend_factor ->
    ?destination_rgb:blend_factor -> ?rgb_operation:blend_operation ->
    ?source_alpha:blend_factor -> ?destination_alpha:blend_factor ->
    ?alpha_operation:blend_operation -> ?write_mask:color_write list ->
    Texture.format -> color_attachment

  type reflection =
    { vertex : Binding.t list
    ; fragment : Binding.t list
    ; tile : Binding.t list
    ; object_ : Binding.t list
    ; mesh : Binding.t list
    }

  val supports_indirect_command_buffers : t -> (bool,error) result
  val kind : t -> kind
  val color_formats : t -> Texture.format list
  val color_attachments : t -> color_attachment list
  val reflection : t -> reflection option
  module Mesh_tile:sig
    type size3={width:int64;height:int64;depth:int64}
    type mutability=Pipeline_buffer_descriptor.mutability=Default|Mutable|Immutable
    type mesh_descriptor
    type tile_descriptor
    type buffer_descriptor=Pipeline_buffer_descriptor.t
    type color_attachment
    type descriptor_kind=Render_descriptor|Mesh_descriptor|Tile_descriptor
    type buffer_stage=Vertex_buffers|Fragment_buffers|Object_buffers|Mesh_buffers|Tile_buffers
    type pipeline_descriptor
    type color_attachment_array

    (** Without [depth_format]/[stencil_format] the pipeline renders to color
        attachments only. *)
    val mesh_descriptor : ?label:string -> ?object_function:Function.t -> ?fragment_function:Function.t -> ?binary_archives:Binary_archive.t list -> mesh_function:Function.t -> ?depth_format:Texture.format -> ?stencil_format:Texture.format -> required_mesh_threads:size3 -> required_object_threads:size3 -> unit -> (mesh_descriptor,error) result
    val tile_descriptor : ?label:string -> ?binary_archives:Binary_archive.t list -> ?preloaded_libraries:Dynamic_library.t list -> tile_function:Function.t -> required_threads:size3 -> unit -> (tile_descriptor,error) result

    (** Pixel format of a color attachment the pipeline renders into. *)
    val set_mesh_color_format : mesh_descriptor -> index:int -> Texture.format -> (unit,error) result
    val set_tile_color_format : tile_descriptor -> index:int -> Texture.format -> (unit,error) result
    val compile_mesh : ?reflection:bool -> mesh_descriptor -> (t,error) result
    val compile_tile : ?reflection:bool -> tile_descriptor -> (t,error) result
    val destroy_mesh : mesh_descriptor -> (unit,error) result
    val destroy_tile : tile_descriptor -> (unit,error) result
  end
  val destroy : t -> (unit, error) result
end

module Pipeline_dataset : sig
  type t

  type capture =
    | Descriptors
    | Binaries

end

module Binary_function : sig
  type t
  type function_t = t

  module Descriptor : sig
    type t
    type stage = Vertex | Fragment | Tile | Object | Mesh
  end
end

module Pipeline_archive : sig
  type t

end

module Compiler : sig
  type t

  type static_function =
    { library : Library.t
    ; name : string
    }

  (** Functions are exported for function handles, private functions are linked
      without requiring function-pointer support, and groups constrain named
      indirect call sites. *)
  type static_linking =
    { functions : static_function list
    ; private_functions : static_function list
    ; groups : (string * static_function list) list
    }

  type stage_linking = private
    { binary_functions : Binary_function.t list
    ; preloaded_libraries : Dynamic_library.t list
    ; max_call_stack_depth : int
    }

  (** Creates a synchronous Metal 4 compiler. A supplied pipeline dataset is
      retained by the compiler until compiler destruction. *)
  val create :
    ?label:string -> ?dataset:Pipeline_dataset.t -> Device.t ->
    (t, error) result

  (** Compiles a conventional vertex/fragment Metal 4 render pipeline.
      Rasterized pipelines require a fragment function and one to eight color
      formats or typed color attachments, but not both. Vertex-only pipelines
      use a void-returning vertex function, disable rasterization, and use no
      color attachments. An optional immutable vertex descriptor enables
      Metal stage-in attribute fetch. Optional static descriptors and dynamic
      linking values configure the vertex and fragment stages independently;
      dynamic values carry binary functions, preloaded libraries, and maximum
      call-stack depth. Alpha-to-coverage/one default off, vertex amplification
      defaults to one, and color-attachment mapping defaults to identity. *)
  val create_render_pipeline :
    ?label:string -> ?fragment:string -> ?reflection:bool ->
    ?raster_sample_count:int -> ?color_formats:Texture.format list ->
    ?color_attachments:Render_pipeline.color_attachment list ->
    ?vertex_descriptor:Vertex_descriptor.t ->
    ?alpha_to_coverage:bool -> ?alpha_to_one:bool ->
    ?max_vertex_amplification_count:int ->
    ?color_attachment_mapping:Render_pipeline.color_attachment_mapping ->
    ?support_vertex_binary_linking:bool ->
    ?support_fragment_binary_linking:bool ->
    ?vertex_dynamic_linking:stage_linking ->
    ?fragment_dynamic_linking:stage_linking ->
    ?vertex_static_linking:static_linking ->
    ?fragment_static_linking:static_linking ->
    ?rasterization_enabled:bool ->
    ?primitive_topology:Render_pipeline.primitive_topology ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    vertex:string -> (Render_pipeline.t, error) result

  (* Compiles a Metal 4 mesh pipeline, optionally with an object stage.
      Object-stage limits and payload configuration require [object_function].
      Rasterization and color-format rules match [create_render_pipeline].
      Mesh shading requires an Apple7-or-newer or Mac2 GPU. Optional stage
      linking uses the same checked [stage_linking] values as conventional
      rendering. Binary functions in object or mesh stages require Apple9/M3;
      static linking and dynamic-library preloads remain independently gated.
      Alpha, amplification, and color-mapping defaults match conventional
      render pipelines. *)

  val destroy : t -> (unit, error) result
end

(** Handle for indirect commands recorded through the legacy Metal command
    encoders below. *)
type indirect_command_buffer_handle

module Indirect_command_buffer : sig
  type command_type =
    | Indirect_draw
    | Indirect_draw_indexed
    | Indirect_concurrent_dispatch
    | Indirect_concurrent_dispatch_threads

  type descriptor
  type t = indirect_command_buffer_handle
  type buffer = t

  val descriptor :
    ?inherit_buffers:bool -> ?inherit_pipeline_state:bool ->
    ?max_vertex_buffer_bind_count:int -> ?max_fragment_buffer_bind_count:int ->
    ?max_kernel_buffer_bind_count:int -> ?support_ray_tracing:bool ->
    ?support_dynamic_attribute_stride:bool ->
    ?max_kernel_threadgroup_memory_bind_count:int ->
    ?max_object_buffer_bind_count:int -> ?max_mesh_buffer_bind_count:int ->
    ?max_object_threadgroup_memory_bind_count:int ->
    ?inherit_depth_stencil_state:bool -> ?inherit_depth_bias:bool ->
    ?inherit_depth_clip_mode:bool -> ?inherit_cull_mode:bool ->
    ?inherit_front_facing_winding:bool -> ?inherit_triangle_fill_mode:bool ->
    ?support_color_attachment_mapping:bool -> command_types:command_type list ->
    unit -> descriptor

  val create :
    device:Device.t -> ?storage:Buffer.storage_mode ->
    ?cpu_cache:Buffer.cpu_cache_mode ->
    ?hazard_tracking:Buffer.hazard_tracking_mode -> max_command_count:int ->
    descriptor -> (t, error) result
  val reset : t -> location:int -> length:int -> (unit, error) result
  val destroy : t -> (unit, error) result

  module Render_command : sig
    type t
    type primitive = Point | Line | Line_strip | Triangle | Triangle_strip
    type index_type = Uint16 | Uint32
    type cull_mode=No_cull|Cull_front|Cull_back
    type depth_clip_mode=Clip|Clamp
    type winding=Clockwise|Counter_clockwise
    type fill_mode=Fill|Lines
    val at : buffer -> int -> (t, error) result
    val set_pipeline : t -> Render_pipeline.t -> (unit, error) result
    val set_vertex_buffer : t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
    val set_fragment_buffer : t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
    val draw_indexed : t -> primitive:primitive -> index_type:index_type ->
      index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 ->
      ?instance_count:int64 -> ?base_vertex:int64 -> ?base_instance:int64 ->
      unit -> (unit,error) result
    val draw_primitives : t -> primitive:primitive -> vertex_start:int ->
      vertex_count:int -> ?instance_count:int -> ?base_instance:int -> unit ->
      (unit, error) result
    val destroy : t -> (unit, error) result
  end

end

module Command_queue : sig
  type t = command_queue
  val create : Device.t -> (t, error) result
  val add_residency_set : t -> Residency_set.t -> (unit, error) result
  val remove_residency_set : t -> Residency_set.t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Command_buffer : sig
  type t
  type present_time = Immediate | At_time of float | After_minimum_duration of float
  type diagnostics =
    { error_options:int64; gpu_start_time:float; gpu_end_time:float
    ; kernel_start_time:float; kernel_end_time:float; retained_references:bool }
  type encoder_info =
    { label : string option; debug_signposts : string list; error_state : int }
  type dispatch_type = Serial | Concurrent

  type status =
    | Not_enqueued
    | Enqueued
    | Committed
    | Scheduled
    | Completed
    | Error of string
    | Unknown of int

  val create : Command_queue.t -> ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val use_residency_set : t -> Residency_set.t -> (unit, error) result
  val status : t -> (status, error) result
  val diagnostics : t -> (diagnostics,error) result

  (** Shared (host-visible, cross-queue) event signal and wait, encoded between
      encoders of a recording command buffer. *)
  val encode_signal_shared_event : t -> Shared_event.t -> value:int64 -> (unit,error) result
  val encode_wait_for_shared_event : t -> Shared_event.t -> value:int64 -> (unit,error) result
  val present :
    t -> Drawable.t -> ?at:present_time -> unit -> (unit, error) result
  val commit : t -> (unit, error) result
  val wait_until_completed : t -> (unit, error) result
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result

  module Private : sig

  end
end

module Acceleration_encoder : sig
  type t = acceleration_encoder
  type resource_usage = Read | Write | Read_write
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type compacted_size_type = Uint32 | Uint64

  val create : Command_buffer.t -> (t, error) result

  (** Build or refit through a generic descriptor; the destination(s) must fit
      the descriptor's sizes and the scratch range its build/refit scratch. *)
  val build_with :
    t -> destination:Acceleration_structure.t -> descriptor:Acceleration_structure.Build.t ->
    scratch:Buffer.t -> scratch_offset:int64 -> (unit, error) result
  val refit_with :
    t -> source:Acceleration_structure.t -> destination:Acceleration_structure.t ->
    descriptor:Acceleration_structure.Build.t -> scratch:Buffer.t -> scratch_offset:int64 ->
    (unit, error) result
  val copy :
    t -> source:Acceleration_structure.t ->
    destination:Acceleration_structure.t -> (unit, error) result
  val copy_and_compact :
    t -> source:Acceleration_structure.t ->
    destination:Acceleration_structure.t -> (unit, error) result
  val write_compacted_size_typed : t -> source:Acceleration_structure.t -> destination:Buffer.t -> offset:int64 -> compacted_size_type -> (unit,error) result
  val end_encoding : t -> (unit, error) result

end

module Compute_encoder : sig
  type t = compute_encoder
  type dispatch_type = Serial | Concurrent
  type barrier_scope = Barrier_buffers | Barrier_textures
  type resource_usage = Resource_read | Resource_write | Resource_sample
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type region = { x:int64; y:int64; z:int64; width:int64; height:int64; depth:int64 }

  val create : Command_buffer.t -> (t, error) result
  val set_pipeline : t -> Compute_pipeline.t -> (unit, error) result
  val set_buffer :
    t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
  val set_texture : t -> index:int -> Texture.t -> (unit, error) result
  val set_acceleration_structure : t -> index:int -> Acceleration_structure.t option -> (unit,error) result
  val set_visible_function_table : t -> index:int -> Visible_function_table.t option -> (unit,error) result
  val set_intersection_function_table : t -> index:int -> Intersection_function_table.t option -> (unit,error) result
  val set_bytes : t -> index:int -> bytes -> (unit,error) result
  val dispatch_threadgroups : t -> threadgroups:int*int*int -> threadgroup:int*int*int -> (unit,error) result
  val update_fence : t -> Fence.t -> (unit,error) result
  val wait_for_fence : t -> Fence.t -> (unit,error) result
  val use_heaps : t -> Heap.t list -> (unit,error) result
  val dispatch_threads :
    t -> threads:int * int * int -> threadgroup:int * int * int ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
end

module Render_encoder : sig
  type t

  type cull_mode = No_cull | Cull_front | Cull_back
  type winding = Clockwise | Counter_clockwise
  type fill_mode = Fill | Lines
  type visibility = Visibility_disabled | Visibility_boolean | Visibility_counting
  type store_action = Store_dont_care | Store | Multisample_resolve
                    | Store_and_multisample_resolve
  type stage = Vertex | Fragment | Tile | Object | Mesh
  type barrier_scope = Buffers | Textures | Render_targets
  type resource_usage = Read | Write | Sample
  type resource = Buffer_resource of Buffer.t | Texture_resource of Texture.t
  type primitive = Point | Line | Line_strip | Triangle | Triangle_strip
  type index_type = Uint16 | Uint32
  type prepared_resources
  type prepared_resource_use =
    { resources : prepared_resources
    ; usage : resource_usage list
    ; stages : stage list }
  type viewport =
    { x : float; y : float; width : float; height : float
    ; znear : float; zfar : float }
  type scissor = { x : int; y : int; width : int; height : int }

  val create :
    Command_buffer.t -> target:Texture.t ->
    ?clear:float * float * float * float -> ?depth:Texture.t ->
    ?stencil:Texture.t -> unit -> (t, error) result
  val set_pipeline : t -> Render_pipeline.t -> (unit, error) result
  val set_vertex_buffer :
    t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
  val set_fragment_buffer :
    t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
  val set_vertex_texture : t -> index:int -> Texture.t -> (unit, error) result
  val set_fragment_texture : t -> index:int -> Texture.t -> (unit, error) result
  val set_vertex_bytes : t -> index:int -> bytes -> (unit, error) result
  val set_fragment_bytes : t -> index:int -> bytes -> (unit, error) result
  val set_vertex_sampler :
    t -> index:int -> ?lod_min:float -> ?lod_max:float -> Sampler.t ->
    (unit, error) result
  val set_fragment_sampler :
    t -> index:int -> ?lod_min:float -> ?lod_max:float -> Sampler.t ->
    (unit, error) result
  val set_viewport : t -> viewport -> (unit, error) result
  val set_scissor : t -> scissor -> (unit, error) result
  val set_cull_mode : t -> cull_mode -> (unit, error) result
  val set_front_facing_winding : t -> winding -> (unit, error) result
  val set_stencil_reference_values :
    t -> front:int32 -> back:int32 -> (unit, error) result
  val tile_width : t -> (int, error) result
  val tile_height : t -> (int, error) result
  val update_fence : t -> Fence.t -> after:stage list -> (unit,error) result
  val wait_for_fence : t -> Fence.t -> before:stage list -> (unit,error) result
  val use_heaps : t -> Heap.t list -> stages:stage list -> (unit,error) result
  val use_resources : t -> resource list -> usage:resource_usage list -> stages:stage list -> (unit,error) result
  val set_stage_buffer : t -> stage:stage -> index:int -> offset:int64 -> ?stride:int64 -> Buffer.t option -> (unit,error) result
  val set_stage_texture : t -> stage:stage -> index:int -> Texture.t option -> (unit,error) result
  val set_stage_sampler : t -> stage:stage -> index:int -> ?lod_min:float -> ?lod_max:float -> Sampler.t option -> (unit,error) result
  val set_depth_stencil_state : t -> Depth_stencil.t option -> (unit,error) result
  val set_stage_bytes : t -> stage:stage -> index:int -> bytes -> (unit,error) result
  val draw_indexed_basic : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 -> (unit,error) result
  val draw_indexed_instances : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 -> instances:int64 -> (unit,error) result
  val execute_indirect_commands : t -> Indirect_command_buffer.t -> location:int -> length:int -> (unit,error) result

  (** Mesh dispatch on the classic encoder. The bound pipeline must be a mesh
      pipeline; [object_threadgroup] is given exactly when it has an object
      stage; compiled required sizes must match. *)
  val draw_mesh_threadgroups :
    t -> threadgroups:(int * int * int) -> ?object_threadgroup:(int * int * int) ->
    mesh_threadgroup:(int * int * int) -> unit -> (unit, error) result

  (** Tile dispatch on the classic encoder; the bound pipeline must be a tile
      pipeline and [threads] positive with depth one. *)
  val dispatch_threads_per_tile : t -> threads:(int * int * int) -> (unit, error) result

  val draw_triangles :
    t -> first:int -> count:int -> ?instances:int -> unit ->
    (unit, error) result
  val draw_primitives :
    t -> primitive:primitive -> first:int -> count:int -> ?instances:int -> unit ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool

  module Private : sig
    type prepared_indexed_binding=
      { prepared_stage:stage
      ; prepared_index:int
      ; prepared_offset:int64
      ; prepared_buffer:Buffer.t }
    type prepared_indexed_draw=
      { prepared_pipeline:Render_pipeline.t
      ; prepared_bindings:prepared_indexed_binding array
      ; prepared_primitive:primitive
      ; prepared_index_type:index_type
      ; prepared_index_buffer:Buffer.t
      ; prepared_index_offset:int64
      ; prepared_index_count:int64 }
    type prepared_indexed_draws
    type prepared_indirect_render_pass

    (* Creates an explicitly-ended pass encoder without an OCaml finalizer. *)
    val create_from_pass_scoped :
      Command_buffer.t -> Render_pass_descriptor.t -> (t, error) result
    val prepare_indexed_draws :
      Device.t -> prepared_indexed_draw array ->
      (prepared_indexed_draws,error) result
    val execute_prepared_indexed_draws :
      t -> prepared_indexed_draws -> (unit,error) result
  end
end

module Resource_state_encoder : sig
  type t = resource_state_encoder

  type mapping_mode =
    | Map
    | Unmap

  type tile_region =
    { x : int
    ; y : int
    ; z : int
    ; width : int
    ; height : int
    ; depth : int
    }

  val create : Command_buffer.t -> (t, error) result
  val update_texture_mapping :
    t -> mode:mapping_mode -> Texture.t -> mip_level:int -> slice:int ->
    region:tile_region -> (unit, error) result
  val end_encoding : t -> (unit, error) result
end

module Blit_encoder : sig
  type t = blit_encoder

  val create : Command_buffer.t -> (t, error) result
  val copy_buffer_to_texture :
    t -> source:Buffer.t -> source_offset:int64 -> source_bytes_per_row:int ->
    source_bytes_per_image:int -> destination:Texture.t ->
    destination_slice:int -> destination_level:int ->
    destination_region:Texture.region -> (unit, error) result
  val fill_buffer : t -> Buffer.t -> offset:int64 -> length:int64 -> byte:int -> (unit,error) result
  val copy_buffer : t -> source:Buffer.t -> source_offset:int64 -> destination:Buffer.t -> destination_offset:int64 -> length:int64 -> (unit,error) result
  val copy_texture_to_buffer : t -> source:Texture.t -> source_slice:int -> source_level:int -> source_region:Texture.region -> destination:Buffer.t -> destination_offset:int64 -> destination_bytes_per_row:int64 -> destination_bytes_per_image:int64 -> ?options:int64 -> unit -> (unit,error) result
  val copy_texture_region : t -> source:Texture.t -> source_slice:int -> source_level:int -> source_region:Texture.region -> destination:Texture.t -> destination_slice:int -> destination_level:int -> destination_origin:(int*int*int) -> (unit,error) result
  val update_fence : t -> Fence.t -> (unit,error) result
  val wait_for_fence : t -> Fence.t -> (unit,error) result
  val end_encoding : t -> (unit, error) result
end

module Resource100 : sig
  type tensor
  type sample_buffer = counter_sample_buffer
  module Sample_buffer : sig
    type t = sample_buffer
    val create : Device.t -> ?label:string -> sample_count:int64 -> unit -> (t,error) result
    val sample : Blit_encoder.t -> t -> index:int64 -> (unit,error) result
    val resolve : Blit_encoder.t -> t -> first:int64 -> count:int64 -> Buffer.t -> offset:int64 -> (unit,error) result
    val destroy : t -> (unit,error) result
  end
end

module Counters : sig
  type sampling_point=Stage_boundary|Draw_boundary|Dispatch_boundary|Blit_boundary
  type set={name:string;counters:string list}
  val supports : Device.t -> sampling_point -> (bool,error) result
  val sets : Device.t -> (set list,error) result
  module Descriptor : sig
    type t
    val create : Device.t -> set_name:string -> ?label:string -> sample_count:int64 -> storage:Buffer.storage_mode -> unit -> (t,error) result
    val create_buffer : t -> (counter_sample_buffer,error) result
    val destroy : t -> (unit,error) result
  end
  val resolve : counter_sample_buffer -> first:int64 -> count:int64 -> (bytes,error) result
  val set_render_pass_attachment :
    Render_pass_descriptor.t -> index:int -> counter_sample_buffer ->
    start_vertex:int64 -> end_vertex:int64 -> start_fragment:int64 ->
    end_fragment:int64 -> (unit,error) result
end

module rec Blit_pass_descriptor : sig
  type t
  val create : Device.t -> (t,error) result
  val attachments : t -> (Blit_pass_attachments.t,error) result

  (** A blit encoder whose stage boundaries sample the configured counter
      attachments; the command buffer retains the descriptor and its sample
      buffers until completion. *)
  val create_encoder : Command_buffer.t -> t -> (Blit_encoder.t,error) result
  val destroy : t -> (unit,error) result
end
and Blit_pass_attachments : sig
  type t
  val get : t -> index:int -> (Blit_pass_attachment.t option,error) result
  val destroy : t -> (unit,error) result
end
and Blit_pass_attachment : sig
  type t
  type sample_index = Dont_sample | Index of int64
  val configure : t -> sample_buffer:Resource100.Sample_buffer.t option ->
    start:sample_index -> finish:sample_index -> (unit,error) result
  val destroy : t -> (unit,error) result
end

module Compute_pass : sig
  type dispatch = Serial | Concurrent
  type attachment =
    { sample_buffer : Resource100.Sample_buffer.t
    ; start_index : int64
    ; end_index : int64 }
  type t
  val create : Device.t -> ?dispatch:dispatch ->
    ?attachments:attachment option array -> unit -> (t,error) result

  (** A compute encoder whose stage boundaries sample the configured counter
      attachments; the command buffer retains the descriptor and its sample
      buffers until completion. *)
  val create_encoder : Command_buffer.t -> t -> (Compute_encoder.t,error) result
  val destroy : t -> (unit,error) result
end

(** MetalFX, linked as its own framework. *)
module Fx : sig
  (** Spatial upscaling of one color texture into a larger output. *)
  module Spatial_scaler : sig
    type t
    val supported : Device.t -> (bool, error) result

    (** [input]/[output] are (width, height); the output is never smaller
        than the input. The color texture needs shader-read usage and the
        output shader-read plus render-target usage, checked at [encode]. *)
    val create :
      Device.t -> input:int * int -> output:int * int -> color_format:Texture.format ->
      output_format:Texture.format -> (t, error) result
    val input : t -> int * int
    val output : t -> int * int

    (** Encodes the upscale between encoders of a recording command buffer,
        which retains the scaler and both textures until it completes. *)
    val encode : t -> Command_buffer.t -> color:Texture.t -> output:Texture.t -> (unit, error) result
    val destroy : t -> (unit, error) result
  end
end
