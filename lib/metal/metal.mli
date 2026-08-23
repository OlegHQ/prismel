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
  val descriptor_2d :
    ?mipmapped:bool -> ?storage:Buffer.storage_mode -> ?usage:usage list ->
    ?label:string -> format:format -> width:int -> height:int -> unit ->
    descriptor
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
  val create_view :
    t -> format:format -> base_mip:int -> mip_count:int -> base_slice:int ->
    slice_count:int -> ?label:string -> unit -> (t, error) result
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
    ; normalized_coordinates : bool
    ; lod_min_clamp : float
    ; lod_max_clamp : float
    ; lod_average : bool
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

module Library : sig
  type t

  val compile_source : device:Device.t -> string -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Function : sig
  type t

  val find : library:Library.t -> string -> (t, error) result
  val name : t -> (string, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Compute_pipeline : sig
  type t

  val create : Function.t -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val thread_execution_width : t -> int
  val max_total_threads_per_threadgroup : t -> int
  val destroyed : t -> bool
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
