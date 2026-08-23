(** Ownership-aware bindings to Metal.framework on macOS. *)

type error_kind =
  | Native_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Invalid_state
  | Unsupported
  | Device_mismatch
  | Release_queue_overflow

type error = private
  { operation : string
  ; kind : error_kind
  ; message : string
  }

type purgeable_state =
  | Nonvolatile
  | Volatile
  | Empty

module Sparse_page_size : sig
  type t =
    | Page_16_kib
    | Page_64_kib
    | Page_256_kib

  val bytes : t -> int64
end

val pp_error : Format.formatter -> error -> unit

module Provenance : sig
  val sdk_version : string
  val deployment_target : string
  val target_triple : string
  val header_count : int
  val header_sha256 : string
end

module Thread : sig
  val is_initial_domain : unit -> bool
  val is_platform_main_thread : unit -> bool
end

module Release_queue : sig
  type stats =
    { pending : int
    ; dropped : int
    ; live_handles : int
    ; total_created : int64
    ; total_released : int64
    ; external_deallocations : int64
    ; external_deallocation_mismatches : int64
    ; placement_mapping_operations : int64
    ; resident_bytes : int64
    }

  val drain : unit -> (int, error) result
  val stats : unit -> (stats, error) result
end

module Device : sig
  type t

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
    ; raytracing : bool
    ; raytracing_from_render : bool
    ; dynamic_libraries : bool
    ; function_pointers : bool
    }

  val system_default : unit -> (t, error) result
  val all : unit -> (t list, error) result
  val generation : t -> int64
  val registry_id : t -> int64
  val same : t -> t -> bool
  val destroyed : t -> bool
  val info : t -> (info, error) result
  val supports_family : t -> family -> (bool, error) result
  val supports_texture_sample_count : t -> int -> (bool, error) result
  val supports_depth24_stencil8 : t -> (bool, error) result
  val supports_bc_texture_compression : t -> (bool, error) result
  val supports_residency_sets : t -> (bool, error) result
  val supports_sparse_textures : t -> (bool, error) result

  (** Runtime-gated macOS 26.4 placement-sparse capability. *)
  val supports_placement_sparse : t -> (bool, error) result

  (** Runtime- and Apple-GPU-family-10-gated sampler reduction modes and LOD
      bias. *)
  val supports_sampler_reduction : t -> (bool, error) result

  (** Runtime- and Apple-GPU-family-8-gated lossy texture compression. *)
  val supports_lossy_texture_compression : t -> (bool, error) result
  val destroy : t -> (unit, error) result
end

module Buffer : sig
  type t

  module External : sig
    type t

    val page_size : unit -> (int, error) result
    val create : length:int64 -> (t, error) result
    val generation : t -> int64
    val length : t -> int64
    val alignment : t -> int64
    val destroyed : t -> bool
    val write_bytes :
      t -> ?src_offset:int -> dst_offset:int64 -> bytes -> (unit, error) result
    val read_bytes : t -> offset:int64 -> length:int -> (bytes, error) result
    val destroy : t -> (unit, error) result
  end

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

  (** Creates an initially unbacked virtual buffer. Physical pages are assigned
      by Metal 4 placement-mapping operations, not CPU mapping. *)
  val create_placement_sparse :
    device:Device.t -> page_size:Sparse_page_size.t -> length:int64 ->
    storage:storage_mode -> ?cpu_cache:cpu_cache_mode ->
    ?hazard_tracking:hazard_tracking_mode -> ?label:string -> unit ->
    (t, error) result
  val create_copy :
    device:Device.t -> storage:storage_mode -> ?cpu_cache:cpu_cache_mode ->
    ?hazard_tracking:hazard_tracking_mode -> ?label:string -> ?src_offset:int ->
    ?length:int -> bytes -> (t, error) result
  val create_no_copy :
    device:Device.t -> memory:External.t -> storage:storage_mode ->
    ?cpu_cache:cpu_cache_mode -> ?hazard_tracking:hazard_tracking_mode ->
    ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val length : t -> int64
  val storage_mode : t -> storage_mode
  val cpu_cache_mode : t -> cpu_cache_mode
  val hazard_tracking_mode : t -> hazard_tracking_mode
  val heap_offset : t -> int64 option
  val placement_sparse_page_size : t -> Sparse_page_size.t option

  (** Returns the native tier when callable and the guaranteed tier-1 minimum
      for a typed sparse resource when a driver omits the tier selector. *)
  val sparse_tier : t -> (sparse_tier, error) result
  val external_memory : t -> External.t option
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val set_label : t -> string -> (unit, error) result
  val write_bytes :
    t -> ?src_offset:int -> dst_offset:int64 -> bytes -> (unit, error) result
  val read_bytes : t -> offset:int64 -> length:int -> (bytes, error) result

  module Mapping : sig
    type t

    val length : t -> (int, error) result
    val read_bytes : t -> offset:int -> length:int -> (bytes, error) result
    val write_bytes :
      t -> ?src_offset:int -> dst_offset:int -> bytes -> (unit, error) result
  end

  val with_mapping :
    t -> offset:int64 -> length:int -> (Mapping.t -> 'a) -> ('a, error) result
  val purgeable_state : t -> (purgeable_state, error) result
  val set_purgeable_state :
    t -> purgeable_state -> (purgeable_state, error) result
  val is_aliasable : t -> (bool, error) result
  val make_aliasable : t -> (unit, error) result
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

  module Io_surface : sig
    type t

    type plane_descriptor =
      { width : int
      ; height : int
      ; bytes_per_element : int
      }

    type plane =
      { width : int
      ; height : int
      ; bytes_per_element : int
      ; bytes_per_row : int
      ; size : int64
      }

    val plane_descriptor :
      width:int -> height:int -> bytes_per_element:int -> plane_descriptor
    val create :
      ?label:string -> width:int -> height:int -> bytes_per_element:int ->
      unit -> (t, error) result
    val create_planar :
      ?label:string -> plane_descriptor list -> (t, error) result
    val id : t -> int64
    val allocation_size : t -> int64
    val planar : t -> bool
    val plane_count : t -> int
    val plane : t -> int -> (plane, error) result
    val generation : t -> int64
    val destroyed : t -> bool
    val label : t -> (string option, error) result
    val write_bytes :
      t -> plane:int -> ?src_offset:int -> dst_offset:int64 -> bytes ->
      (unit, error) result
    val read_bytes :
      t -> plane:int -> offset:int64 -> length:int -> (bytes, error) result

    module Xpc : sig
      (** Bounded cross-process IOSurface transport through an embedded macOS
          XPC service. Numeric identity and every plane-layout field are
          validated against the received native surface. Debug labels are
          process-local and are not transported. *)

      type connection
      type request

      val connect :
        ?max_payload_bytes:int -> service_name:string -> unit ->
        (connection, error) result
      val service_name : connection -> string
      val connection_destroyed : connection -> bool
      val destroy_connection : connection -> (unit, error) result
      val call :
        ?timeout_ms:int -> connection -> operation:string -> surface:t ->
        bytes -> (t * bytes, error) result

      val request_operation : request -> (string, error) result
      val request_surface : request -> (t, error) result
      val request_data : request -> (bytes, error) result
      val request_completed : request -> bool

      (** Completing a request is one-shot. Its incoming surface is destroyed
          unless a live texture still retains that surface. The surface
          supplied to [reply] remains owned by the caller. *)
      val reply : request -> surface:t -> bytes -> (unit, error) result
      val reject : request -> string -> (unit, error) result

      (** Installs the process's embedded XPC service listener. The handler
          runs synchronously on OCaml domain zero's XPC main executor and must
          reply or reject before returning. *)
      val serve :
        ?capacity:int -> ?max_payload_bytes:int -> (request -> unit) ->
        (unit, error) result
    end

    val destroy : t -> (unit, error) result
  end

  type io_surface_backing =
    { surface : Io_surface.t
    ; plane : int
    }

  module Shared_handle : sig
    type t

    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val label : t -> (string option, error) result
    val destroy : t -> (unit, error) result

    module Xpc : sig
      (** Bounded transport of shared texture handles through an embedded macOS
          XPC service. Connections and requests retain their device. *)

      type connection
      type request

      val connect :
        ?max_payload_bytes:int -> device:Device.t -> service_name:string ->
        unit -> (connection, error) result
      val service_name : connection -> string
      val connection_destroyed : connection -> bool
      val destroy_connection : connection -> (unit, error) result
      val call :
        ?timeout_ms:int -> connection -> operation:string -> handle:t -> bytes ->
        (t * bytes, error) result

      val request_operation : request -> (string, error) result
      val request_handle : request -> (t, error) result
      val request_data : request -> (bytes, error) result
      val request_completed : request -> bool

      (** Completing a request is one-shot and destroys its incoming handle.
          The handle supplied to [reply] remains owned by the caller. *)
      val reply : request -> handle:t -> bytes -> (unit, error) result
      val reject : request -> string -> (unit, error) result

      (** [serve ~device handler] installs the process's embedded XPC service
          listener and does not normally return. [handler] runs synchronously
          on OCaml domain zero's XPC main executor and must reply or reject
          before returning; abandonment and exceptions are rejected. *)
      val serve :
        ?capacity:int -> ?max_payload_bytes:int -> device:Device.t ->
        (request -> unit) -> (unit, error) result
    end
  end

  val format_layout : format -> format_layout
  val all_formats : format list
  val default_swizzle : swizzle
  val make_swizzle :
    red:swizzle_channel -> green:swizzle_channel -> blue:swizzle_channel ->
    alpha:swizzle_channel -> swizzle
  val descriptor_2d :
    ?mipmapped:bool -> ?storage:Buffer.storage_mode -> ?usage:usage list ->
    ?compression:compression_type -> ?swizzle:swizzle -> ?label:string ->
    format:format -> width:int -> height:int -> unit -> descriptor
  val minimum_buffer_alignment :
    device:Device.t -> kind:kind -> format:format -> (int64, error) result
  val create : device:Device.t -> descriptor -> (t, error) result

  (** Creates an initially unbacked virtual texture. The descriptor is
      capability-checked before native allocation. *)
  val create_placement_sparse :
    device:Device.t -> page_size:Sparse_page_size.t -> descriptor ->
    (t, error) result
  val create_shared : device:Device.t -> descriptor -> (t, error) result
  val create_from_buffer :
    buffer:Buffer.t -> offset:int64 -> bytes_per_row:int -> descriptor ->
    (t, error) result
  val create_from_io_surface :
    device:Device.t -> surface:Io_surface.t -> plane:int -> descriptor ->
    (t, error) result

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
  val heap_offset : t -> int64 option
  val placement_sparse_page_size : t -> Sparse_page_size.t option
  val buffer_backing : t -> buffer_backing option
  val io_surface_backing : t -> io_surface_backing option

  (** Returns the native tier when callable and the guaranteed tier-1 minimum
      for a typed sparse resource when a driver omits the tier selector. *)
  val sparse_tier : t -> (sparse_tier, error) result
  val sparse_info : t -> (sparse_info option, error) result
  val is_shareable : t -> (bool, error) result
  val shared_handle : t -> (Shared_handle.t, error) result
  val import_shared :
    device:Device.t -> Shared_handle.t -> (t, error) result
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val set_label : t -> string -> (unit, error) result
  val write_bytes :
    t -> region:region -> mip_level:int -> slice:int -> ?src_offset:int ->
    bytes_per_row:int -> bytes_per_image:int -> bytes -> (unit, error) result
  val read_bytes :
    t -> region:region -> mip_level:int -> slice:int -> bytes_per_row:int ->
    bytes_per_image:int -> (bytes, error) result
  val purgeable_state : t -> (purgeable_state, error) result
  val set_purgeable_state :
    t -> purgeable_state -> (purgeable_state, error) result
  val is_aliasable : t -> (bool, error) result
  val make_aliasable : t -> (unit, error) result
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
  val sparse_tile_size_in_bytes :
    device:Device.t -> Sparse_page_size.t -> (int64, error) result
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
  val device : t -> Device.t
  val descriptor : t -> descriptor
  val generation : t -> int64
  val destroyed : t -> bool
  val info : t -> (info, error) result
  val label : t -> (string option, error) result
  val set_label : t -> string -> (unit, error) result
  val purgeable_state : t -> (purgeable_state, error) result
  val set_purgeable_state :
    t -> purgeable_state -> (purgeable_state, error) result
  val max_available_size : t -> alignment:int64 -> (int64, error) result
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
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val allocated_size : t -> (int64, error) result
  val allocation_size : allocation -> (int64, error) result
  val allocation_count : t -> (int, error) result
  val allocations : t -> (allocation list, error) result
  val add_allocation : t -> allocation -> (unit, error) result
  val add_allocations : t -> allocation list -> (unit, error) result
  val remove_allocation : t -> allocation -> (unit, error) result
  val remove_allocations : t -> allocation list -> (unit, error) result
  val remove_all_allocations : t -> (unit, error) result
  val contains : t -> allocation -> (bool, error) result
  val commit : t -> (unit, error) result
  val request_residency : t -> (unit, error) result
  val end_residency : t -> (unit, error) result
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
  val device : t -> Device.t
  val descriptor : t -> descriptor
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val destroy : t -> (unit, error) result
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

  val layout : t -> layout

  (** Compares generated binding metadata with native Metal reflection. Order
      is ignored; names, indices, access, resource classes, and reflected data
      types must match exactly. *)
  val validate_layout :
    expected:layout list -> t list -> (unit, error) result
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

  (** Loads a compiled [.metallib]. The path must be absolute. *)
  val load_file :
    ?label:string -> device:Device.t -> string -> (t, error) result

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val kind : t -> (kind, error) result
  val install_name : t -> (string option, error) result
  val function_names : t -> (string list, error) result
  val destroy : t -> (unit, error) result
end

module Function : sig
  type t

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

  val find : library:Library.t -> string -> (t, error) result
  val specialize :
    library:Library.t -> ?label:string ->
    constants:(string * constant_value) list -> string -> (t, error) result
  val name : t -> (string, error) result
  val label : t -> (string option, error) result
  val kind : t -> (kind, error) result
  val constants : t -> (constant list, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
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

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val install_name : t -> (string, error) result

  (** Serializes device code and its source-library fallback to an absolute
      file path. *)
  val serialize : t -> string -> (unit, error) result
  val destroy : t -> (unit, error) result
end

module Binary_archive : sig
  type t

  (** With no [path], creates an empty archive. An absolute [path] opens a
      previously serialized archive. *)
  val create :
    ?path:string -> ?label:string -> Device.t -> (t, error) result

  val add_compute_functions :
    t -> ?linked_functions:Function.t list ->
    ?preloaded_libraries:Dynamic_library.t list -> Function.t ->
    (unit, error) result

  val serialize : t -> string -> (unit, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val destroy : t -> (unit, error) result
end

module Compute_pipeline : sig
  type t

  val create :
    ?label:string -> ?linked_functions:Function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?binary_archives:Binary_archive.t list ->
    ?fail_on_binary_archive_miss:bool -> ?reflection:bool -> Function.t ->
    (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val label : t -> (string option, error) result
  val bindings : t -> Binding.t list option
  val thread_execution_width : t -> int
  val max_total_threads_per_threadgroup : t -> int
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Render_pipeline : sig
  type t

  type kind =
    | Render
    | Tile
    | Mesh

  type primitive_topology =
    | Point
    | Line
    | Triangle

  type reflection =
    { vertex : Binding.t list
    ; fragment : Binding.t list
    ; tile : Binding.t list
    ; object_ : Binding.t list
    ; mesh : Binding.t list
    }

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val kind : t -> kind
  val reflection : t -> reflection option
  val label : t -> (string option, error) result
  val destroy : t -> (unit, error) result
end

module Pipeline_dataset : sig
  type t

  type capture =
    | Descriptors
    | Binaries

  (** Creates a Metal 4 dataset serializer. At least one unique capture mode
      is required. *)
  val create : device:Device.t -> capture list -> (t, error) result
  val captures : t -> capture list

  (** Returns the captured pipeline script as opaque bytes. Descriptor capture
      must have been enabled. *)
  val serialize_script : t -> (bytes, error) result

  (** Serializes captured binaries to an absolute archive path and flushes the
      serializer's current binary dataset. *)
  val serialize_archive : t -> string -> (unit, error) result

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Binary_function : sig
  type t

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val pipeline_independent : t -> bool

  (** Returns the checked descriptor identity used for compilation and archive
      lookup. *)
  val name : t -> string
  val kind : t -> Function.kind
  val destroy : t -> (unit, error) result
end

module Pipeline_archive : sig
  type t

  (** Loads a read-only Metal 4 archive from an absolute path. *)
  val load_file :
    ?label:string -> device:Device.t -> string -> (t, error) result

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val label : t -> (string option, error) result

  (** Performs a strict synchronous binary-function lookup in this archive.
      The source descriptor supplies the visible or intersection function
      identity used when the binary was captured. *)
  val load_binary_function :
    ?pipeline_independent:bool -> t -> source:Function.t -> name:string ->
    (Binary_function.t, error) result

  val destroy : t -> (unit, error) result
end

module Compiler_task : sig
  type 'a t

  type status =
    | None_
    | Scheduled
    | Compiling
    | Finished
    | Unknown_status of int

  type 'a poll =
    | Pending
    | Complete of ('a, error) result

  val id : 'a t -> int64
  val device : 'a t -> Device.t
  val generation : 'a t -> int64
  val destroyed : 'a t -> bool
  val status : 'a t -> (status, error) result

  (** Blocks without holding the OCaml runtime lock. The native completion
      handler only records immutable result state and a bounded completion ID;
      [poll] materializes the OCaml result on the initial domain. *)
  val wait : 'a t -> (unit, error) result
  val poll : 'a t -> ('a poll, error) result

  val completion_capacity : int
  val drain_completions : ?limit:int -> unit -> (int64 list, error) result
  val dropped_completions : unit -> (int64, error) result
  val pending_completions : unit -> (int, error) result
  val destroy : 'a t -> (unit, error) result
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

  (** Creates a synchronous Metal 4 compiler. A supplied pipeline dataset is
      retained by the compiler until compiler destruction. *)
  val create :
    ?label:string -> ?dataset:Pipeline_dataset.t -> Device.t ->
    (t, error) result

  (** Compiles runtime MSL through [MTL4Compiler]. [name] is the Metal 4
      library descriptor name and is included in compilation diagnostics. *)
  val compile_source :
    ?name:string -> t -> string -> (Library.t, error) result

  val compile_source_async :
    ?name:string -> t -> string ->
    (Library.t Compiler_task.t, error) result

  (** Builds a dynamic library through the Metal 4 compiler. The input must be
      a same-device [Library.Dynamic_library_source] with an install name. *)
  val create_dynamic_library :
    ?label:string -> t -> Library.t -> (Dynamic_library.t, error) result

  (** The native task retains the source library through completion. *)
  val create_dynamic_library_async :
    ?label:string -> t -> Library.t ->
    (Dynamic_library.t Compiler_task.t, error) result

  (** Loads serialized dynamic-library device code from an absolute path. *)
  val load_dynamic_library :
    ?label:string -> t -> string -> (Dynamic_library.t, error) result

  (** The native task retains the file URL through completion. *)
  val load_dynamic_library_async :
    ?label:string -> t -> string ->
    (Dynamic_library.t Compiler_task.t, error) result

  (** Compiles a visible or intersection function to device machine code.
      Lookup archives are searched by Metal before compiling a miss. *)
  val create_binary_function :
    ?pipeline_independent:bool -> ?lookup_archives:Pipeline_archive.t list ->
    t -> source:Function.t -> name:string ->
    (Binary_function.t, error) result

  val create_binary_function_async :
    ?pipeline_independent:bool -> ?lookup_archives:Pipeline_archive.t list ->
    t -> source:Function.t -> name:string ->
    (Binary_function.t Compiler_task.t, error) result

  val create_compute_pipeline :
    ?label:string -> ?reflection:bool ->
    ?threadgroup_size_multiple:bool ->
    ?max_total_threads_per_threadgroup:int ->
    ?required_threads_per_threadgroup:(int * int * int) ->
    ?support_binary_linking:bool ->
    ?support_indirect_command_buffers:bool ->
    ?static_linking:static_linking ->
    ?binary_linked_functions:Binary_function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?max_call_stack_depth:int ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    string -> (Compute_pipeline.t, error) result

  (** The task retains native descriptor inputs through completion. Dynamic
      linking is capability-gated to Apple9/M3-or-newer GPUs because the
      Apple7/M1 Metal 4 driver cannot safely serialize that async request. *)
  val create_compute_pipeline_async :
    ?label:string -> ?reflection:bool ->
    ?threadgroup_size_multiple:bool ->
    ?max_total_threads_per_threadgroup:int ->
    ?required_threads_per_threadgroup:(int * int * int) ->
    ?support_binary_linking:bool ->
    ?support_indirect_command_buffers:bool ->
    ?static_linking:static_linking ->
    ?binary_linked_functions:Binary_function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?max_call_stack_depth:int ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    string -> (Compute_pipeline.t Compiler_task.t, error) result

  (** Compiles a conventional vertex/fragment Metal 4 render pipeline.
      Rasterized pipelines require a fragment function and one to eight color
      formats. Vertex-only pipelines use a void-returning vertex function,
      disable rasterization, and use no color formats. *)
  val create_render_pipeline :
    ?label:string -> ?fragment:string -> ?reflection:bool ->
    ?raster_sample_count:int -> ?color_formats:Texture.format list ->
    ?rasterization_enabled:bool ->
    ?primitive_topology:Render_pipeline.primitive_topology ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    vertex:string -> (Render_pipeline.t, error) result

  (** The native task retains its library and render descriptor through
      completion; [Compiler_task.poll] materializes the result on the initial
      domain. *)
  val create_render_pipeline_async :
    ?label:string -> ?fragment:string -> ?reflection:bool ->
    ?raster_sample_count:int -> ?color_formats:Texture.format list ->
    ?rasterization_enabled:bool ->
    ?primitive_topology:Render_pipeline.primitive_topology ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    vertex:string ->
    (Render_pipeline.t Compiler_task.t, error) result

  (** Compiles a Metal 4 mesh pipeline, optionally with an object stage.
      Object-stage limits and payload configuration require [object_function].
      Rasterization and color-format rules match [create_render_pipeline].
      Mesh shading requires an Apple7-or-newer or Mac2 GPU. *)
  val create_mesh_pipeline :
    ?label:string -> ?object_function:string -> ?fragment:string ->
    ?reflection:bool ->
    ?max_total_threads_per_object_threadgroup:int ->
    ?max_total_threads_per_mesh_threadgroup:int ->
    ?required_threads_per_object_threadgroup:(int * int * int) ->
    ?required_threads_per_mesh_threadgroup:(int * int * int) ->
    ?object_threadgroup_size_multiple:bool ->
    ?mesh_threadgroup_size_multiple:bool -> ?payload_memory_length:int ->
    ?max_total_threadgroups_per_mesh_grid:int -> ?raster_sample_count:int ->
    ?color_formats:Texture.format list -> ?rasterization_enabled:bool ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    mesh:string -> (Render_pipeline.t, error) result

  (** The native task retains the mesh descriptor and every function library
      through completion. Indirect mesh draws are rejected below Apple9/M3. *)
  val create_mesh_pipeline_async :
    ?label:string -> ?object_function:string -> ?fragment:string ->
    ?reflection:bool ->
    ?max_total_threads_per_object_threadgroup:int ->
    ?max_total_threads_per_mesh_threadgroup:int ->
    ?required_threads_per_object_threadgroup:(int * int * int) ->
    ?required_threads_per_mesh_threadgroup:(int * int * int) ->
    ?object_threadgroup_size_multiple:bool ->
    ?mesh_threadgroup_size_multiple:bool -> ?payload_memory_length:int ->
    ?max_total_threadgroups_per_mesh_grid:int -> ?raster_sample_count:int ->
    ?color_formats:Texture.format list -> ?rasterization_enabled:bool ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    mesh:string -> (Render_pipeline.t Compiler_task.t, error) result

  (** Compiles a Metal 4 tile pipeline for an Apple4-or-newer GPU. Tile entry
      points may be kernel- or fragment-based. Empty [color_formats] are
      permitted for tile work that does not access an imageblock attachment. *)
  val create_tile_pipeline :
    ?label:string -> ?reflection:bool -> ?raster_sample_count:int ->
    ?color_formats:Texture.format list ->
    ?threadgroup_size_matches_tile_size:bool ->
    ?max_total_threads_per_threadgroup:int ->
    ?required_threads_per_threadgroup:(int * int * int) ->
    ?support_binary_linking:bool -> ?static_linking:static_linking ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    tile:string -> (Render_pipeline.t, error) result

  (** The native compiler task owns the tile descriptor, source libraries,
      static-link inputs, and lookup archives through completion. *)
  val create_tile_pipeline_async :
    ?label:string -> ?reflection:bool -> ?raster_sample_count:int ->
    ?color_formats:Texture.format list ->
    ?threadgroup_size_matches_tile_size:bool ->
    ?max_total_threads_per_threadgroup:int ->
    ?required_threads_per_threadgroup:(int * int * int) ->
    ?support_binary_linking:bool -> ?static_linking:static_linking ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    tile:string -> (Render_pipeline.t Compiler_task.t, error) result

  val device : t -> Device.t
  val generation : t -> int64
  val dataset : t -> Pipeline_dataset.t option
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val destroy : t -> (unit, error) result
end

module Command_queue : sig
  type t

  val create : Device.t -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val add_residency_set : t -> Residency_set.t -> (unit, error) result
  val add_residency_sets : t -> Residency_set.t list -> (unit, error) result
  val remove_residency_set : t -> Residency_set.t -> (unit, error) result
  val remove_residency_sets : t -> Residency_set.t list -> (unit, error) result
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Command_buffer : sig
  type t

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
  val generation : t -> int64
  val use_residency_set : t -> Residency_set.t -> (unit, error) result
  val use_residency_sets : t -> Residency_set.t list -> (unit, error) result
  val status : t -> (status, error) result
  val commit : t -> (unit, error) result
  val wait_until_completed : t -> (unit, error) result
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Compute_encoder : sig
  type t

  val create : Command_buffer.t -> (t, error) result
  val set_pipeline : t -> Compute_pipeline.t -> (unit, error) result
  val set_buffer :
    t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
  val set_texture : t -> index:int -> Texture.t -> (unit, error) result
  val dispatch_threads :
    t -> threads:int * int * int -> threadgroup:int * int * int ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
end

module Resource_state_encoder : sig
  type t

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
  val destroyed : t -> bool
end

(** Synchronous Metal 4 placement-sparse mapping. A live mapping owns its
    virtual resource and physical heap range until [unmap] succeeds. Virtual
    buffer ranges and texture regions are expressed in sparse tiles;
    [heap_offset] is expressed in bytes. *)
module Placement_mapping : sig
  type queue
  type t

  type tile_range =
    { offset : int
    ; length : int
    }

  type kind =
    | Buffer
    | Texture

  val create_queue : ?label:string -> Device.t -> (queue, error) result
  val queue_device : queue -> Device.t
  val queue_generation : queue -> int64
  val queue_label : queue -> (string option, error) result
  val queue_destroyed : queue -> bool

  (** Fails while mappings created by the queue remain live. *)
  val destroy_queue : queue -> (unit, error) result

  val map_buffer :
    queue -> heap:Heap.t -> heap_offset:int64 -> Buffer.t ->
    range:tile_range -> (t, error) result

  val map_texture :
    queue -> heap:Heap.t -> heap_offset:int64 -> Texture.t -> mip_level:int ->
    slice:int -> region:Resource_state_encoder.tile_region ->
    (t, error) result

  val kind : t -> kind
  val heap : t -> Heap.t
  val page_size : t -> Sparse_page_size.t
  val heap_offset : t -> int64
  val mapped_bytes : t -> int64
  val destroyed : t -> bool

  (** Synchronously issues the matching Metal 4 unmap and releases ownership.
      Repeating [unmap] after success is harmless. *)
  val unmap : t -> (unit, error) result
end

module Blit_encoder : sig
  type t

  val create : Command_buffer.t -> (t, error) result
  val copy_buffer_to_texture :
    t -> source:Buffer.t -> source_offset:int64 -> source_bytes_per_row:int ->
    source_bytes_per_image:int -> destination:Texture.t ->
    destination_slice:int -> destination_level:int ->
    destination_region:Texture.region -> (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
end
