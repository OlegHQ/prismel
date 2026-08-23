(** Ownership-aware bindings to Metal.framework on macOS. *)

(** Generated, handle-free SDK enum values. Every family is a distinct
    private type; mappings preserve aliases and carry pinned macOS
    availability metadata. *)
module Enum : module type of Metal_enum_generated

(** Generated, handle-free, fixed-layout SDK value records. *)
module Value : module type of Metal_value_record_generated

(** Generated immutable scalar/enum descriptor-property records. *)
module Descriptor : module type of Metal_descriptor_generated

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

(** Copied values of immutable, typed NSString globals exported by the Metal
    SDK. Each call returns an independently owned OCaml string. *)
module Global : module type of Metal_global_generated.Make (struct
    type t = error
    let of_native ~operation:_ _ = assert false
  end)

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

module Event : sig
  type t
  val device_registry_id:t->int64
  val label:t->(string option,error)result
  val set_label:t->string option->(unit,error)result
  val destroyed:t->bool
  val destroy:t->(unit,error)result
end
module Shared_event : sig
  type t
  val device_registry_id:t->int64
  val signaled_value:t->(int64,error)result
  val set_signaled_value:t->int64->(unit,error)result
  val destroyed:t->bool
  val destroy:t->(unit,error)result
end

type io_queue
type io_file
type io_command_buffer

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
    ; max_threadgroup_memory_length : int64
    ; raytracing : bool
    ; raytracing_from_render : bool
    ; dynamic_libraries : bool
    ; function_pointers : bool
    }

  type argument_buffers_tier = Tier_1 | Tier_2 | Unknown_argument_buffers_tier of int64
  type location = Built_in | Slot | External | Unspecified | Unknown_location of int64
  type read_write_texture_tier =
    | No_read_write_textures
    | Read_write_tier_1
    | Read_write_tier_2
    | Unknown_read_write_texture_tier of int64

  (** Scalar capabilities copied from the native device. Querying this record
      creates no Metal handles and preserves native availability failures. *)
  type capabilities =
    { argument_buffers_tier : argument_buffers_tier
    ; location : location
    ; location_number : int64
    ; max_argument_buffer_sampler_count : int64
    ; max_transfer_rate : int64
    ; maximum_concurrent_compilation_task_count : int64
    ; peer_count : int64
    ; peer_group_id : int64
    ; peer_index : int64
    ; programmable_sample_positions : bool
    ; raster_order_groups : bool
    ; read_write_texture_tier : read_write_texture_tier
    ; supports_32_bit_float_filtering : bool
    ; supports_32_bit_msaa : bool
    ; supports_primitive_motion_blur : bool
    ; supports_pull_model_interpolation : bool
    ; supports_query_texture_lod : bool
    ; supports_render_dynamic_libraries : bool
    ; supports_shader_barycentric_coordinates : bool
    }

  val system_default : unit -> (t, error) result
  val new_event:t->(Event.t,error)result
  val new_shared_event:t->(Shared_event.t,error)result
  type io_queue_type = Serial | Concurrent
  val new_io_queue :
    t -> ?queue_type:io_queue_type -> ?max_command_buffers:int64 ->
    ?max_commands_in_flight:int64 -> ?label:string -> unit ->
    (io_queue, error) result
  val open_io_file : t -> ?label:string -> string -> (io_file, error) result
  val all : unit -> (t list, error) result
  val generation : t -> int64
  val registry_id : t -> int64
  val same : t -> t -> bool
  val destroyed : t -> bool
  val info : t -> (info, error) result
  val capabilities : t -> (capabilities, error) result
  val supports_family : t -> family -> (bool, error) result
  val supports_texture_sample_count : t -> int -> (bool, error) result

  (** Whether a positive vertex-amplification count is accepted by this
      device. Pipeline creation performs the same check. *)
  val supports_vertex_amplification_count : t -> int -> (bool, error) result
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

module Acceleration_structure : sig
  type t

  type sizes =
    { acceleration_structure_size : int64
    ; build_scratch_buffer_size : int64
    ; refit_scratch_buffer_size : int64
    }

  module Triangle : sig
    type t

    val create :
      vertex_buffer:Buffer.t -> ?vertex_offset:int64 -> vertex_stride:int64 ->
      triangle_count:int64 -> ?index_buffer:Buffer.t -> ?index_offset:int64 ->
      unit -> (t, error) result
  end

  val sizes : device:Device.t -> Triangle.t -> (sizes, error) result
  val create : device:Device.t -> size:int64 -> (t, error) result
  val device : t -> Device.t
  val size : t -> int64
  val generation : t -> int64
  val destroyed : t -> bool
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

module Metal_layer : sig
  type t
  type config =
    { width:int; height:int; format:Texture.format; framebuffer_only:bool
    ; maximum_drawables:int; allows_timeout:bool; display_sync:bool
    ; presents_with_transaction:bool }
  val default : width:int -> height:int -> config
  val create : Device.t -> config -> (t,error) result
  val configure : t -> config -> (unit,error) result
  val device : t -> Device.t
  val size : t -> int * int
  val config : t -> config
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

module Drawable : sig
  type t
  type loss = Timeout_or_unavailable
  val acquire : Metal_layer.t -> ((t,loss) result,error) result
  val layer : t -> Metal_layer.t
  val texture : t -> (Texture.t,error) result
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

module Render_pass_descriptor : sig
  type t
  val create : width:int -> height:int -> ?array_length:int -> ?sample_count:int -> unit -> (t,error) result
  val size : t -> int * int
  val array_length : t -> int
  val sample_count : t -> int
  val set_attachments :
    t -> color:Texture.t -> ?clear:float * float * float * float ->
    ?depth:Texture.t -> ?stencil:Texture.t -> ?visibility_result:Buffer.t ->
    unit -> (unit,error) result
  val color_attachment : t -> Texture.t option
  val depth_attachment : t -> Texture.t option
  val stencil_attachment : t -> Texture.t option
  val visibility_result_buffer : t -> Buffer.t option
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

module Fence : sig
  type t
  val create : Device.t -> (t, error) result
  val device : t -> Device.t
  val destroyed : t -> bool
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

  val device : t -> Device.t
  val depth_compare : t -> compare_function
  val depth_write : t -> bool
  val front_face : t -> face option
  val back_face : t -> face option
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

  val reflection : t -> Reflection.reflected_type option

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

  type descriptor = private
    { name : string
    ; specialized_name : string option
    ; constants : (string * constant_value) list
    ; compile_to_binary : bool
    }

  (** Builds an immutable function descriptor. The native
      [MTLFunctionDescriptor] and its copied strings/constant table exist only
      for the duration of [create]; they are never exposed as handles. *)
  val descriptor :
    ?specialized_name:string -> ?compile_to_binary:bool ->
    constants:(string * constant_value) list -> string ->
    (descriptor, error) result

  (** Creates a function through Metal's checked descriptor API. The returned
      function retains its library in the same way as [find] and [specialize]. *)
  val create : library:Library.t -> descriptor -> (t, error) result

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
  val options : t -> (options,error) result
  val patch_control_point_count : t -> (int64,error) result
  val patch_type : t -> (patch_type,error) result
  val attributes : t -> vertex:bool -> (Shader_attribute.t list,error) result
  val argument_encoder : t -> buffer_index:int64 -> (Shader_argument_encoder.t,error) result
  val destroy : t -> (unit, error) result
end

and Shader_attribute : sig
  type t
  val name : t -> (string option,error) result
  val index : t -> (int64,error) result
  val data_type : t -> (Shader_type.t,error) result
  val active : t -> (bool,error) result
  val patch_control_point_data : t -> (bool,error) result
  val patch_data : t -> (bool,error) result
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

and Shader_argument_encoder : sig
  type t
  val buffer_index : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit,error) result
end

module rec Shader_stage_descriptor : sig
  type t
  type index_type=Uint16|Uint32
  val create:unit->(t,error)result
  val index_buffer_index:t->(int64,error)result
  val index_type:t->(index_type,error)result
  val set_index_buffer_index:t->int64->(unit,error)result
  val set_index_type:t->index_type->(unit,error)result
  val reset:t->(unit,error)result
  val attributes:t->(Shader_attribute_descriptors.t,error)result
  val layouts:t->(Shader_buffer_layout_descriptors.t,error)result
  val destroyed:t->bool
  val destroy:t->(unit,error)result
end
and Shader_attribute_descriptors : sig
  type t
  val capacity:int
  val at:t->index:int->(Shader_attribute_descriptor.t,error)result
  val set:t->index:int->Shader_attribute_descriptor.t->(unit,error)result
  val destroyed:t->bool val destroy:t->(unit,error)result
end
and Shader_attribute_descriptor : sig
  type t
  val buffer_index:t->(int64,error)result
  val offset:t->(int64,error)result
  val format:t->(Enum.Mtl_attribute_format.t,error)result
  val set_buffer_index:t->int64->(unit,error)result
  val set_offset:t->int64->(unit,error)result
  val set_format:t->Enum.Mtl_attribute_format.t->(unit,error)result
  val destroyed:t->bool
  val destroy:t->(unit,error)result
end
and Shader_buffer_layout_descriptors : sig type t val destroyed:t->bool val destroy:t->(unit,error)result end

module Shader_stitching_input : sig
  type t
  val create:argument_index:int64->(t,error)result
  val argument_index:t->(int64,error)result
  val set_argument_index:t->int64->(unit,error)result
  val destroyed:t->bool
  val destroy:t->(unit,error)result
end

module Capture : sig
  type destination=Developer_tools|Gpu_trace_document
  module Descriptor:sig
    type t
    val create:?destination:destination->unit->(t,error)result
    val destination:t->destination
    val set_destination:t->destination->(unit,error)result
    val destroyed:t->bool
    val destroy:t->(unit,error)result
  end
  module Manager:sig
    type t
    val shared:unit->(t,error)result
    val supports_destination:t->destination->(bool,error)result
    val is_capturing:t->(bool,error)result
    val destroyed:t->bool
    val destroy:t->(unit,error)result
  end
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
  type size3 = { width:int64; height:int64; depth:int64 }
  type shader_validation = Default | Enabled | Disabled

  val create :
    ?label:string -> ?linked_functions:Function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?binary_archives:Binary_archive.t list ->
    ?fail_on_binary_archive_miss:bool -> ?support_indirect_command_buffers:bool ->
    ?reflection:bool -> Function.t ->
    (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val label : t -> (string option, error) result
  val bindings : t -> Binding.t list option
  val thread_execution_width : t -> int
  val max_total_threads_per_threadgroup : t -> int
  val static_threadgroup_memory_length : t -> (int64, error) result
  val destroyed : t -> bool
  val resource_id : t -> (int64,error) result
  val required_threads_per_threadgroup : t -> (size3,error) result
  val shader_validation : t -> (shader_validation,error) result
  val supports_indirect_command_buffers : t -> (bool,error) result
  val imageblock_memory_length : t -> size3 -> (int64,error) result
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

  val attribute :
    index:int -> format:format -> offset:int -> buffer_index:int -> attribute

  val layout :
    ?step_function:step_function -> ?step_rate:int -> buffer_index:int ->
    stride:stride -> unit -> layout

  (** Validates and canonicalizes one immutable vertex input layout. Attribute
      and buffer indices are unique values between zero and 30 inclusive. Every
      attribute has a matching used layout; static strides contain their
      attributes. Only a constant layout may use a zero static stride. *)
  val create :
    attributes:attribute list -> layouts:layout list -> (t, error) result

  val attributes : t -> attribute list
  val layouts : t -> layout list
end

module Function_handle : sig
  type t
  val create : pipeline:Compute_pipeline.t -> function_:Function.t -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Visible_function_table : sig
  type t
  val create : pipeline:Compute_pipeline.t -> capacity:int -> (t, error) result
  val set_function : t -> index:int -> Function_handle.t option -> (unit, error) result
  val device : t -> Device.t
  val capacity : t -> int
  val resource_id : t -> int64
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Intersection_function_table : sig
  type t
  val create : pipeline:Compute_pipeline.t -> capacity:int -> (t, error) result
  val set_function : t -> index:int -> Function_handle.t option -> (unit, error) result
  val set_buffer : t -> index:int -> ?offset:int64 -> Buffer.t option -> (unit, error) result
  val set_visible_table : t -> buffer_index:int -> Visible_function_table.t option -> (unit, error) result
  val device : t -> Device.t
  val capacity : t -> int
  val resource_id : t -> int64
  val destroyed : t -> bool
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

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val resource_id : t -> (int64,error) result
  val imageblock_sample_length : t -> (int64,error) result
  val mesh_threads_per_threadgroup : t -> (size3,error) result
  val object_threads_per_threadgroup : t -> (size3,error) result
  val tile_threads_per_threadgroup : t -> (size3,error) result
  val shader_validation : t -> (shader_validation,error) result
  val supports_indirect_command_buffers : t -> (bool,error) result
  val imageblock_memory_length : t -> size3 -> (int64,error) result
  val kind : t -> kind
  val raster_sample_count : t -> int
  val alpha_to_coverage : t -> bool
  val alpha_to_one : t -> bool
  val max_vertex_amplification_count : t -> int
  val color_attachment_mapping : t -> color_attachment_mapping
  val color_formats : t -> Texture.format list
  val color_attachments : t -> color_attachment list
  val vertex_descriptor : t -> Vertex_descriptor.t option
  val reflection : t -> reflection option
  val label : t -> (string option, error) result
  module Mesh_tile:sig
    type size3={width:int64;height:int64;depth:int64}
    type mutability=Default|Mutable|Immutable
    type mesh_descriptor
    type tile_descriptor
    type buffer_descriptor
    type color_attachment
    val buffer_descriptor : ?mutability:mutability -> unit -> (buffer_descriptor,error) result
    val set_buffer_mutability : buffer_descriptor -> mutability -> (unit,error) result
    val buffer_mutability : buffer_descriptor -> mutability
    val create_color_attachment : Texture.format -> (color_attachment,error) result
    val create_color_attachment_configured : ?blending:blend_state -> ?source_rgb:blend_factor -> ?destination_rgb:blend_factor -> ?rgb_operation:blend_operation -> ?source_alpha:blend_factor -> ?destination_alpha:blend_factor -> ?alpha_operation:blend_operation -> ?write_mask:color_write list -> Texture.format -> (color_attachment,error) result
    val color_attachment_format : color_attachment -> Texture.format
    val mesh_descriptor : ?label:string -> ?object_function:Function.t -> ?fragment_function:Function.t -> ?binary_archives:Binary_archive.t list -> mesh_function:Function.t -> depth_format:Texture.format -> stencil_format:Texture.format -> required_mesh_threads:size3 -> required_object_threads:size3 -> unit -> (mesh_descriptor,error) result
    val tile_descriptor : ?label:string -> ?binary_archives:Binary_archive.t list -> ?preloaded_libraries:Dynamic_library.t list -> tile_function:Function.t -> required_threads:size3 -> unit -> (tile_descriptor,error) result
    val compile_mesh : ?reflection:bool -> mesh_descriptor -> (t,error) result
    val compile_tile : ?reflection:bool -> tile_descriptor -> (t,error) result
    val destroy_buffer : buffer_descriptor -> (unit,error) result
    val destroy_color : color_attachment -> (unit,error) result
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
  type function_t = t

  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val pipeline_independent : t -> bool

  (** Returns the checked descriptor identity used for compilation and archive
      lookup. *)
  val name : t -> string
  val kind : t -> Function.kind
  val destroy : t -> (unit, error) result
  module Descriptor : sig
    type t
    type stage = Vertex | Fragment | Tile | Object | Mesh
    val create : unit -> (t, error) result
    val destroyed : t -> bool
    val set : t -> stage -> function_t list -> (unit, error) result
    val get : t -> stage -> (function_t list, error) result
    val reset : t -> (unit, error) result
    val destroy : t -> (unit, error) result
  end
end

module Function_specialization : sig
  module Function_descriptor : sig
    type t
    val create : Function.t -> name:string -> (t,error) result
    val name : t -> string
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Constants : sig
    type t
    val create_empty : unit -> (t,error) result
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Specialized : sig
    type t
    val create : ?function_descriptor:Function_descriptor.t -> ?name:string -> ?constants:Constants.t -> unit -> (t,error) result
    val set : t -> ?function_descriptor:Function_descriptor.t -> ?name:string -> ?constants:Constants.t -> unit -> (unit,error) result
    val get : t -> ((Function_descriptor.t option * string option * Constants.t option),error) result
    val destroy : t -> (unit,error) result
  end
  module Stitched : sig
    type t
    val create : Function_descriptor.t list -> (t,error) result
    val set : t -> Function_descriptor.t list -> (unit,error) result
    val get : t -> (Function_descriptor.t list,error) result
    val destroy : t -> (unit,error) result
  end
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

  type stage_linking = private
    { binary_functions : Binary_function.t list
    ; preloaded_libraries : Dynamic_library.t list
    ; max_call_stack_depth : int
    }

  (** Builds immutable dynamic-link inputs for one render stage. A supplied
      value always creates a stage linking descriptor, even when its function
      and library lists are empty. *)
  val stage_linking :
    ?binary_functions:Binary_function.t list ->
    ?preloaded_libraries:Dynamic_library.t list ->
    ?max_call_stack_depth:int -> unit -> stage_linking

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

  (** The native task retains its library and render descriptor through
      completion; [Compiler_task.poll] materializes the result on the initial
      domain. Asynchronous dynamic linking requires Apple9/M3 or newer. *)
  val create_render_pipeline_async :
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
    vertex:string ->
    (Render_pipeline.t Compiler_task.t, error) result

  (** Compiles a Metal 4 mesh pipeline, optionally with an object stage.
      Object-stage limits and payload configuration require [object_function].
      Rasterization and color-format rules match [create_render_pipeline].
      Mesh shading requires an Apple7-or-newer or Mac2 GPU. Optional stage
      linking uses the same checked [stage_linking] values as conventional
      rendering. Binary functions in object or mesh stages require Apple9/M3;
      static linking and dynamic-library preloads remain independently gated.
      Alpha, amplification, and color-mapping defaults match conventional
      render pipelines. *)
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
    ?color_formats:Texture.format list ->
    ?color_attachments:Render_pipeline.color_attachment list ->
    ?alpha_to_coverage:bool -> ?alpha_to_one:bool ->
    ?max_vertex_amplification_count:int ->
    ?color_attachment_mapping:Render_pipeline.color_attachment_mapping ->
    ?support_object_binary_linking:bool ->
    ?support_mesh_binary_linking:bool ->
    ?support_fragment_binary_linking:bool ->
    ?object_dynamic_linking:stage_linking ->
    ?mesh_dynamic_linking:stage_linking ->
    ?fragment_dynamic_linking:stage_linking ->
    ?object_static_linking:static_linking ->
    ?mesh_static_linking:static_linking ->
    ?fragment_static_linking:static_linking ->
    ?rasterization_enabled:bool ->
    ?support_indirect_command_buffers:bool ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    mesh:string -> (Render_pipeline.t, error) result

  (** The native task retains the mesh descriptor and every linking input
      through completion. Indirect mesh draws and asynchronous dynamic linking
      are rejected below Apple9/M3. *)
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
    ?color_formats:Texture.format list ->
    ?color_attachments:Render_pipeline.color_attachment list ->
    ?alpha_to_coverage:bool -> ?alpha_to_one:bool ->
    ?max_vertex_amplification_count:int ->
    ?color_attachment_mapping:Render_pipeline.color_attachment_mapping ->
    ?support_object_binary_linking:bool ->
    ?support_mesh_binary_linking:bool ->
    ?support_fragment_binary_linking:bool ->
    ?object_dynamic_linking:stage_linking ->
    ?mesh_dynamic_linking:stage_linking ->
    ?fragment_dynamic_linking:stage_linking ->
    ?object_static_linking:static_linking ->
    ?mesh_static_linking:static_linking ->
    ?fragment_static_linking:static_linking ->
    ?rasterization_enabled:bool ->
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
    ?dynamic_linking:stage_linking ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    tile:string -> (Render_pipeline.t, error) result

  (** The native compiler task owns the tile descriptor, source libraries,
      static/dynamic-link inputs, and lookup archives through completion.
      Asynchronous dynamic linking requires Apple9/M3 or newer. *)
  val create_tile_pipeline_async :
    ?label:string -> ?reflection:bool -> ?raster_sample_count:int ->
    ?color_formats:Texture.format list ->
    ?threadgroup_size_matches_tile_size:bool ->
    ?max_total_threads_per_threadgroup:int ->
    ?required_threads_per_threadgroup:(int * int * int) ->
    ?support_binary_linking:bool -> ?static_linking:static_linking ->
    ?dynamic_linking:stage_linking ->
    ?lookup_archives:Pipeline_archive.t list -> t -> library:Library.t ->
    tile:string -> (Render_pipeline.t Compiler_task.t, error) result

  val device : t -> Device.t
  val generation : t -> int64
  val dataset : t -> Pipeline_dataset.t option
  val destroyed : t -> bool
  val label : t -> (string option, error) result
  val destroy : t -> (unit, error) result
end

(** Typed Metal 4 command recording. These objects are distinct from the
    legacy Metal command modules below: an allocator records one buffer at a
    time, queues return explicit submissions, and a submission must complete
    before its command resources are released. *)
type indirect_command_buffer_handle

module Machine_learning : sig
  module Descriptor : sig
    type t
    val create : ?label:string -> library:Library.t -> function_name:string -> unit -> (t,error) result
    val set_label : t -> string option -> (unit,error) result
    val label : t -> string option
    val function_ : t -> ((Library.t*string),error) result
    val set_input_dimensions : t -> index:int64 -> int64 array -> (unit,error) result
    val input_dimensions : t -> index:int64 -> (int64 array option,error) result
    val set_input_dimensions_range : t -> start:int64 -> int64 array option array -> (unit,error) result
    val reset : t -> (unit,error) result
    val destroy : t -> (unit,error) result
  end
  module Pipeline : sig
    type t
    val compile : Compiler.t -> Descriptor.t -> (t,error) result
    val label : t -> string option
    val intermediates_heap_size : t -> int64
    val bindings : t -> Binding.t list
    val device : t -> Device.t
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
end

module Command4 : sig
  module Counter_heap : sig
    type t
    type kind = Timestamp
    val create : ?label:string -> Device.t -> kind:kind -> count:int64 -> (t,error) result
    val info : t -> (kind * int64 * string option,error) result
    val set_label : t -> string option -> (unit,error) result
    val invalidate : t -> location:int64 -> length:int64 -> (unit,error) result
    val resolve : t -> location:int64 -> length:int64 -> (bytes,error) result
    val device : t -> Device.t
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Argument_table : sig
    type t

    (** Creates a checked Metal 4 argument table. The hardware limits are 31
        buffer slots, 128 texture slots, and 16 sampler slots; at least one
        capacity must be nonzero. *)
    val create :
      ?label:string -> ?initialize_bindings:bool ->
      ?support_attribute_strides:bool -> ?max_buffers:int ->
      ?max_textures:int -> ?max_samplers:int -> Device.t -> unit ->
      (t, error) result

    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val max_buffers : t -> int
    val max_textures : t -> int
    val max_samplers : t -> int
    val initializes_bindings : t -> bool
    val supports_attribute_strides : t -> bool
    val label : t -> (string option, error) result

    (** Binds [buffer] by GPU address. [offset] must select a byte inside the
        buffer. [attribute_stride] requires a table created with
        [support_attribute_strides:true]. *)
    val set_buffer :
      t -> index:int -> ?offset:int64 -> ?attribute_stride:int -> Buffer.t ->
      (unit, error) result

    val clear_buffer : t -> index:int -> (unit, error) result
    val set_texture : t -> index:int -> Texture.t -> (unit, error) result
    val clear_texture : t -> index:int -> (unit, error) result
    val set_sampler : t -> index:int -> Sampler.t -> (unit, error) result
    val clear_sampler : t -> index:int -> (unit, error) result
    val destroy : t -> (unit, error) result
  end

  module Allocator : sig
    type t

    val create : ?label:string -> Device.t -> (t, error) result
    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val label : t -> (string option, error) result
    val allocated_size : t -> (int64, error) result

    (** Requires every command buffer that used this allocator to be destroyed,
        which proves that no submitted work still owns allocator memory. *)
    val reset : t -> (unit, error) result

    val destroy : t -> (unit, error) result
  end

  module Command_buffer : sig
    type t

    type state =
      | Recording
      | Ended
      | Submitted
      | Completed
      | Failed of string

    val create : Allocator.t -> ?label:string -> unit -> (t, error) result
    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val state : t -> state
    val label : t -> (string option, error) result
    val push_debug_group : t -> string -> (unit, error) result
    val pop_debug_group : t -> (unit, error) result
    val use_residency_sets : t -> Residency_set.t list -> (unit, error) result
    val write_timestamp : t -> Counter_heap.t -> index:int64 -> (unit, error) result
    val resolve_counter : t -> Counter_heap.t -> location:int64 -> length:int64 ->
      destination:Buffer.t -> destination_offset:int64 -> ?wait_fence:Fence.t ->
      ?update_fence:Fence.t -> unit -> (unit, error) result

    (** Ends native command recording after the current encoder has ended. *)
    val end_recording : t -> (unit, error) result

    val destroy : t -> (unit, error) result
  end

  module Submission : sig
    type t
    type feedback={gpu_start_time:float;gpu_end_time:float;gpu_duration:float}

    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val completed : t -> bool
    val feedback : t -> (feedback,error) result

    (** Blocks without holding the OCaml runtime lock. GPU execution errors are
        returned from Metal 4 commit feedback with their native diagnostics. *)
    val wait : t -> (unit, error) result

    val destroy : t -> (unit, error) result
  end

  module Queue : sig
    type t

    val create : ?label:string -> Device.t -> (t, error) result
    val device : t -> Device.t
    val generation : t -> int64
    val destroyed : t -> bool
    val label : t -> (string option, error) result

    (** Commits one to 64 unique, ended command buffers in list order. *)
    val commit : t -> Command_buffer.t list -> (Submission.t, error) result
    val add_residency_sets : t -> Residency_set.t list -> (unit,error) result
    val remove_residency_set : t -> Residency_set.t -> (unit,error) result
    val remove_residency_sets : t -> Residency_set.t list -> (unit,error) result

    val destroy : t -> (unit, error) result
  end

  module Render_encoder : sig
    type t
    type color

    type load_action =
      | Load_dont_care
      | Load
      | Clear of color

    type store_action =
      | Store_dont_care
      | Store
      | Store_deferred

    type visibility_result_mode =
      | Visibility_disabled
      | Visibility_boolean
      | Visibility_counting

    type visibility_result_type =
      | Visibility_reset
      | Visibility_accumulate

    type depth_load_action =
      | Depth_load_dont_care
      | Depth_load
      | Depth_clear

    type stencil_load_action =
      | Stencil_load_dont_care
      | Stencil_load
      | Stencil_clear

    type color_attachment
    type depth_attachment
    type stencil_attachment
    type viewport
    type scissor_rect
    type vertex_amplification_view_mapping

    type winding =
      | Clockwise
      | Counter_clockwise

    type cull_mode =
      | Cull_none
      | Cull_front
      | Cull_back

    type depth_clip_mode =
      | Depth_clip
      | Depth_clamp

    type triangle_fill_mode =
      | Triangle_fill
      | Triangle_lines

    type primitive =
      | Point
      | Line
      | Line_strip
      | Triangle
      | Triangle_strip

    type index_type =
      | Uint16
      | Uint32
    type timestamp_granularity = Relaxed | Precise

    type stage =
      | Vertex
      | Fragment
      | Tile
      | Object
      | Mesh

    val color :
      red:float -> green:float -> blue:float -> alpha:float -> color

    (** Creates a base-level, single-sample 2D color attachment.
        [Store_deferred] must be finalized on the encoder before it ends. *)
    val color_attachment :
      ?load_action:load_action -> ?store_action:store_action -> Texture.t ->
      color_attachment

    (** Creates a base-level, single-sample 2D depth attachment.
        [Store_deferred] must be finalized on the encoder before it ends. *)
    val depth_attachment :
      ?load_action:depth_load_action -> ?store_action:store_action ->
      ?clear_depth:float -> Texture.t -> depth_attachment

    (** Creates a base-level, single-sample 2D stencil attachment. The clear
        value is interpreted as an unsigned 32-bit bit pattern.
        [Store_deferred] must be finalized on the encoder before it ends. *)
    val stencil_attachment :
      ?load_action:stencil_load_action -> ?store_action:store_action ->
      ?clear_stencil:int32 -> Texture.t -> stencil_attachment

    (** Describes the unsigned 32-bit viewport- and render-target-array index
        offsets for one amplified vertex output. Values are checked when the
        mapping is installed on an encoder. *)
    val vertex_amplification_view_mapping :
      ?viewport_array_index_offset:int ->
      ?render_target_array_index_offset:int -> unit ->
      vertex_amplification_view_mapping

    (** Creates a render encoder and optionally configures a visibility-result
        buffer containing one or more 64-bit slots. The buffer must be live,
        same-device, and at least eight bytes. [Visibility_accumulate] requires
        such a buffer; [Visibility_reset] remains the default. *)
    val create :
      ?label:string -> ?depth_attachment:depth_attachment ->
      ?stencil_attachment:stencil_attachment ->
      ?visibility_result_buffer:Buffer.t ->
      ?visibility_result_type:visibility_result_type ->
      ?support_color_attachment_mapping:bool -> Command_buffer.t ->
      color_attachments:color_attachment list -> (t, error) result

    (** Binds a conventional, mesh, or tile render pipeline whose sample count
        and ordered color formats match the render pass. *)
    val set_pipeline : t -> Render_pipeline.t -> (unit, error) result

    (** Sets the number of amplified vertex outputs for subsequent conventional
        or mesh draws. Metal 4 accepts one or two outputs; the count must also
        fit the bound pipeline and device. When present, [view_mappings] has
        exactly one unsigned-32-bit offset pair per output. *)
    val set_vertex_amplification_count :
      t -> ?view_mappings:vertex_amplification_view_mapping list -> int ->
      (unit, error) result

    (** Installs a complete logical-to-physical color-attachment permutation,
        or clears it to Metal's identity mapping with [None]. The pass must
        opt in at creation and the bound pipeline must use [Inherited]. *)
    val set_color_attachment_map :
      t -> int list option -> (unit, error) result

    (** Binds immutable depth/stencil state. Active depth testing or writes
        require a depth attachment, and an explicit stencil face requires a
        stencil attachment. [None] restores Metal's default state. *)
    val set_depth_stencil_state :
      t -> Depth_stencil.t option -> (unit, error) result

    (** Sets the unsigned 32-bit stencil reference for both primitive faces. *)
    val set_stencil_reference : t -> int32 -> (unit, error) result

    (** Sets independent unsigned 32-bit front/back stencil references. *)
    val set_stencil_references :
      t -> front:int32 -> back:int32 -> (unit, error) result

    (** Sets the finite float32 blend constant for subsequent draws. *)
    val set_blend_color : t -> color -> (unit, error) result

    (** Associates [table] with the selected render stages. Metal snapshots
        the table's current resources at each subsequent draw. [None] clears
        those stage bindings. *)
    val set_argument_table :
      t -> stages:stage list -> Argument_table.t option -> (unit, error) result

    (** Returns the native thread-tile dimensions captured at encoder creation. *)
    val tile_size : t -> int * int

    val viewport :
      x:float -> y:float -> width:float -> height:float -> z_near:float ->
      z_far:float -> viewport

    (** Builds an integer-pixel scissor rectangle. Bounds are checked against
        the render target when the rectangle is installed. *)
    val scissor_rect :
      x:int -> y:int -> width:int -> height:int -> scissor_rect

    val set_viewport : t -> viewport -> (unit, error) result

    (** Installs one to sixteen in-target viewports selected by shader
        [viewport_array_index] output. *)
    val set_viewports : t -> viewport list -> (unit, error) result

    val set_scissor_rect : t -> scissor_rect -> (unit, error) result

    (** Installs one to sixteen in-target scissor rectangles selected by shader
        [viewport_array_index] output. *)
    val set_scissor_rects : t -> scissor_rect list -> (unit, error) result

    val set_front_facing_winding : t -> winding -> (unit, error) result
    val set_cull_mode : t -> cull_mode -> (unit, error) result
    val set_depth_clip_mode : t -> depth_clip_mode -> (unit, error) result

    (** Sets finite float32 constant, slope-scale, and clamp depth bias. *)
    val set_depth_bias :
      t -> depth_bias:float -> slope_scale:float -> clamp:float ->
      (unit, error) result

    (** Sets ordered finite depth bounds in the closed interval zero to one.
        Any pair other than zero/one enables testing and requires a depth
        attachment and an Apple10-or-newer GPU. *)
    val set_depth_test_bounds :
      t -> min_bound:float -> max_bound:float -> (unit, error) result

    val set_triangle_fill_mode :
      t -> triangle_fill_mode -> (unit, error) result

    (** Finalizes a [Store_deferred] color attachment exactly once. *)
    val set_color_store_action :
      t -> index:int -> store_action -> (unit, error) result

    (** Finalizes a [Store_deferred] depth attachment exactly once. *)
    val set_depth_store_action : t -> store_action -> (unit, error) result

    (** Finalizes a [Store_deferred] stencil attachment exactly once. *)
    val set_stencil_store_action : t -> store_action -> (unit, error) result

    (** Configures one 64-bit visibility-result slot. Active boolean and
        counting modes require the live buffer supplied to [create]; [offset]
        must be nonnegative, eight-byte aligned, and in range. Disabled mode
        requires only a nonnegative aligned offset. *)
    val set_visibility_result_mode :
      t -> visibility_result_mode -> offset:int64 -> (unit, error) result

    val draw_primitives :
      t -> primitive -> vertex_start:int -> vertex_count:int ->
      (unit, error) result

    (** Draws a positive instance range starting at [base_instance]. *)
    val draw_primitives_instanced :
      t -> primitive -> vertex_start:int -> vertex_count:int ->
      instance_count:int -> base_instance:int -> (unit, error) result

    (** Draws from a checked aligned byte range of [index_buffer]. The buffer
        and current argument-table resources remain owned through completion. *)
    val draw_indexed_primitives :
      t -> primitive -> index_type -> index_buffer:Buffer.t ->
      index_offset:int64 -> index_count:int -> (unit, error) result

    (** Draws a checked indexed instance range. [base_vertex] is signed;
        [base_instance] is nonnegative. The index buffer and current
        argument-table resources remain owned through completion. *)
    val draw_indexed_primitives_instanced :
      t -> primitive -> index_type -> index_buffer:Buffer.t ->
      index_offset:int64 -> index_count:int -> instance_count:int ->
      base_vertex:int -> base_instance:int -> (unit, error) result

    (** Reads one 16-byte [MTLDrawPrimitivesIndirectArguments] value from a
        checked 4-byte-aligned buffer range. *)
    val draw_primitives_indirect :
      t -> primitive -> indirect_buffer:Buffer.t -> indirect_offset:int64 ->
      (unit, error) result

    (** Reads one 20-byte [MTLDrawIndexedPrimitivesIndirectArguments] value
        from a checked 4-byte-aligned range. [index_length] is a positive,
        naturally aligned accessible range starting at [index_offset]. Both
        buffers and current argument-table resources remain owned through
        completion. *)
    val draw_indexed_primitives_indirect :
      t -> primitive -> index_type -> index_buffer:Buffer.t ->
      index_offset:int64 -> index_length:int64 -> indirect_buffer:Buffer.t ->
      indirect_offset:int64 -> (unit, error) result

    (** Dispatches a positive grid of mesh threadgroups. [object_threadgroup]
        is required exactly when the compiled pipeline has an object stage.
        Required sizes, pipeline maxima, and execution-width promises are
        checked before command encoding. *)
    val draw_mesh_threadgroups :
      t -> threadgroups:(int * int * int) ->
      ?object_threadgroup:(int * int * int) ->
      mesh_threadgroup:(int * int * int) -> unit -> (unit, error) result

    (** Dispatches a tile pipeline with positive in-tile dimensions and depth
        one. The compiled maximum, optional required size, and exact-tile-size
        promise are checked before encoding. *)
    val dispatch_threads_per_tile :
      t -> threads:(int * int * int) -> (unit, error) result

    val draw : t -> primitive -> vertex_start:int64 -> vertex_count:int64 -> instance_count:int64 -> (unit,error) result
    val draw_indexed : t -> primitive -> index_type -> index_buffer:Buffer.t -> index_count:int64 -> index_length:int64 -> instance_count:int64 -> (unit,error) result
    val draw_mesh_threads_raw : t -> threads:(int*int*int) -> object_threadgroup:(int*int*int) -> mesh_threadgroup:(int*int*int) -> (unit,error) result
    val draw_mesh_indirect : t -> indirect_buffer:Buffer.t -> offset:int64 -> object_threadgroup:(int*int*int) -> mesh_threadgroup:(int*int*int) -> (unit,error) result
    val execute_icb_range : t -> indirect_command_buffer_handle -> location:int64 -> length:int64 -> (unit,error) result
    val execute_icb_indirect : t -> indirect_command_buffer_handle -> indirect_buffer:Buffer.t -> offset:int64 -> (unit,error) result
    val set_threadgroup_memory : t -> ?object_stage:bool -> length:int64 -> index:int64 -> offset:int64 -> unit -> (unit,error) result
    val write_timestamp : t -> granularity:timestamp_granularity -> after:stage list -> Counter_heap.t -> index:int64 -> (unit,error) result

    (** Ends the encoder after every [Store_deferred] action is finalized. *)
    val end_encoding : t -> (unit, error) result
    val destroyed : t -> bool
  end

  module Compute_encoder : sig
    type t
    type stage = Vertex | Fragment | Tile | Object | Mesh | Compute | Blit
    type timestamp_granularity = Relaxed | Precise
    type copy_options = No_options | Row_linear_pvrtc

    val create :
      ?label:string -> Command_buffer.t -> (t, error) result

    val set_pipeline : t -> Compute_pipeline.t -> (unit, error) result

    (** Configures one reflected [[threadgroup(index)]] binding. The bound
        pipeline must have been created with reflection, [index] is between
        zero and thirty, and [length] is a nonnegative multiple of sixteen
        bytes. Setting zero clears that index. Static and dynamic allocations
        together must fit the device threadgroup-memory limit. *)
    val set_threadgroup_memory_length :
      t -> index:int -> length:int -> (unit, error) result

    (** Associates the table with the compute stage. Metal snapshots its
        current resources at each subsequent dispatch. [None] clears it. *)
    val set_argument_table :
      t -> Argument_table.t option -> (unit, error) result

    val insert_debug_signpost : t -> string -> (unit,error) result
    val push_debug_group : t -> string -> (unit,error) result
    val pop_debug_group : t -> (unit,error) result
    val barrier : t -> after:stage list -> before:stage list -> ?before_queue:bool -> unit -> (unit,error) result
    val update_fence : t -> Fence.t -> after:stage list -> (unit,error) result
    val dispatch_threadgroups : t -> threadgroups:(int64*int64*int64) -> threads_per_threadgroup:(int64*int64*int64) -> (unit,error) result
    val dispatch_indirect_threadgroups : t -> indirect_buffer:Buffer.t -> offset:int64 -> threads_per_threadgroup:(int64*int64*int64) -> (unit,error) result
    val dispatch_indirect_threads : t -> indirect_buffer:Buffer.t -> offset:int64 -> (unit,error) result
    val set_imageblock_size : t -> width:int64 -> height:int64 -> (unit,error) result
    val stages : t -> (int64,error) result
    val fill_buffer : t -> Buffer.t -> offset:int64 -> length:int64 -> byte:int -> (unit,error) result
    val generate_mipmaps : t -> Texture.t -> (unit,error) result
    val optimize_for_cpu : t -> Texture.t -> (unit,error) result
    val optimize_for_gpu : t -> Texture.t -> (unit,error) result
    val optimize_level_for_cpu : t -> Texture.t -> slice:int64 -> level:int64 -> (unit,error) result
    val optimize_level_for_gpu : t -> Texture.t -> slice:int64 -> level:int64 -> (unit,error) result
    val copy_buffer : t -> source:Buffer.t -> source_offset:int64 -> destination:Buffer.t -> destination_offset:int64 -> size:int64 -> (unit,error) result
    val copy_texture : t -> source:Texture.t -> destination:Texture.t -> (unit,error) result
    val copy_texture_slices : t -> source:Texture.t -> source_slice:int64 -> source_level:int64 -> destination:Texture.t -> destination_slice:int64 -> destination_level:int64 -> slice_count:int64 -> level_count:int64 -> (unit,error) result
    val copy_texture_region : t -> source:Texture.t -> source_slice:int64 -> source_level:int64 -> source_origin:(int64*int64*int64) -> size:(int64*int64*int64) -> destination:Texture.t -> destination_slice:int64 -> destination_level:int64 -> destination_origin:(int64*int64*int64) -> (unit,error) result
    val buffer_to_texture : ?options:copy_options -> t -> source:Buffer.t -> source_offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> size:(int64*int64*int64) -> destination:Texture.t -> destination_slice:int64 -> destination_level:int64 -> destination_origin:(int64*int64*int64) -> (unit,error) result
    val texture_to_buffer : ?options:copy_options -> t -> source:Texture.t -> source_slice:int64 -> source_level:int64 -> source_origin:(int64*int64*int64) -> size:(int64*int64*int64) -> destination:Buffer.t -> destination_offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> (unit,error) result
    val execute_icb : t -> indirect_command_buffer_handle -> location:int64 -> length:int64 -> (unit,error) result
    val execute_icb_indirect : t -> indirect_command_buffer_handle -> indirect_buffer:Buffer.t -> offset:int64 -> (unit,error) result
    val optimize_icb : t -> indirect_command_buffer_handle -> location:int64 -> length:int64 -> (unit,error) result
    val reset_icb : t -> indirect_command_buffer_handle -> location:int64 -> length:int64 -> (unit,error) result
    val copy_icb : t -> source:indirect_command_buffer_handle -> source_location:int64 -> length:int64 -> destination:indirect_command_buffer_handle -> destination_index:int64 -> (unit,error) result
    val copy_acceleration_structure : t -> source:Acceleration_structure.t -> destination:Acceleration_structure.t -> compact:bool -> (unit,error) result
    val write_timestamp : t -> granularity:timestamp_granularity -> Counter_heap.t -> index:int64 -> (unit,error) result

    val dispatch_threads :
      t -> threads:(int * int * int) -> threadgroup:(int * int * int) ->
      (unit, error) result

    val end_encoding : t -> (unit, error) result
    val destroyed : t -> bool
  end

  module Machine_learning_encoder : sig
    type t
    val create : Command_buffer.t -> (t,error) result
    val set_pipeline : t -> Machine_learning.Pipeline.t -> (unit,error) result
    val set_argument_table : t -> Argument_table.t option -> (unit,error) result
    val dispatch : t -> Heap.t -> (unit,error) result
    val end_encoding : t -> (unit,error) result
  end
end

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
  val device : t -> Device.t
  val generation : t -> int64
  val destroyed : t -> bool
  val max_command_count : t -> int
  val allocated_size : t -> int64
  val reset : t -> location:int -> length:int -> (unit, error) result
  val destroy : t -> (unit, error) result

  module Render_command : sig
    type t
    type primitive = Point | Line | Line_strip | Triangle | Triangle_strip
    type cull_mode=No_cull|Cull_front|Cull_back
    type depth_clip_mode=Clip|Clamp
    type winding=Clockwise|Counter_clockwise
    type fill_mode=Fill|Lines
    val at : buffer -> int -> (t, error) result
    val destroyed : t -> bool
    val reset : t -> (unit, error) result
    val set_barrier:t->(unit,error)result
    val clear_barrier:t->(unit,error)result
    val set_cull_mode:t->cull_mode->(unit,error)result
    val set_depth_clip_mode:t->depth_clip_mode->(unit,error)result
    val set_front_facing_winding:t->winding->(unit,error)result
    val set_triangle_fill_mode:t->fill_mode->(unit,error)result
    val set_depth_bias:t->bias:float->slope_scale:float->clamp:float->(unit,error)result
    val set_depth_stencil_state:t->Depth_stencil.t->(unit,error)result
    val set_object_threadgroup_memory_length:t->index:int->length:int64->(unit,error)result
    val draw_mesh_threadgroups:t->threadgroups:(int64*int64*int64)->object_threadgroup:(int64*int64*int64)->mesh_threadgroup:(int64*int64*int64)->(unit,error)result
    val draw_mesh_threads:t->threads:(int64*int64*int64)->object_threadgroup:(int64*int64*int64)->mesh_threadgroup:(int64*int64*int64)->(unit,error)result
    val set_pipeline : t -> Render_pipeline.t -> (unit, error) result
    val set_vertex_buffer : t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
    val set_fragment_buffer : t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
    val draw_primitives : t -> primitive:primitive -> vertex_start:int ->
      vertex_count:int -> ?instance_count:int -> ?base_instance:int -> unit ->
      (unit, error) result
    val destroy : t -> (unit, error) result
  end

  module Compute_command : sig
    type t
    type region={x:int64;y:int64;z:int64;width:int64;height:int64;depth:int64}
    val at : buffer -> int -> (t, error) result
    val destroyed : t -> bool
    val reset : t -> (unit, error) result
    val set_barrier:t->(unit,error)result
    val clear_barrier:t->(unit,error)result
    val set_imageblock:t->width:int64->height:int64->(unit,error)result
    val set_stage_in_region:t->region->(unit,error)result
    val set_threadgroup_memory_length:t->index:int->length:int64->(unit,error)result
    val concurrent_dispatch_threadgroups:t->threadgroups:(int64*int64*int64)->threads_per_threadgroup:(int64*int64*int64)->(unit,error)result
    val set_pipeline : t -> Compute_pipeline.t -> (unit, error) result
    val set_kernel_buffer : t -> index:int -> offset:int64 -> Buffer.t -> (unit, error) result
    val dispatch_threads : t -> threads:(int * int * int) ->
      threadgroup:(int * int * int) -> (unit, error) result
    val destroy : t -> (unit, error) result
  end
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
  type present_time = Immediate | At_time of float | After_minimum_duration of float

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
  val present :
    t -> Drawable.t -> ?at:present_time -> unit -> (unit, error) result
  val add_scheduled_handler : t -> (unit -> unit) -> (unit, error) result
  val add_completed_handler : t -> (unit -> unit) -> (unit, error) result
  val commit : t -> (unit, error) result
  val wait_until_completed : t -> (unit, error) result
  val destroyed : t -> bool
  val destroy : t -> (unit, error) result
end

module Acceleration_encoder : sig
  type t

  val create : Command_buffer.t -> (t, error) result
  val build :
    t -> destination:Acceleration_structure.t ->
    descriptor:Acceleration_structure.Triangle.t -> scratch:Buffer.t ->
    scratch_offset:int64 -> (unit, error) result
  val refit :
    t -> source:Acceleration_structure.t ->
    destination:Acceleration_structure.t ->
    descriptor:Acceleration_structure.Triangle.t -> scratch:Buffer.t ->
    scratch_offset:int64 -> (unit, error) result
  val copy :
    t -> source:Acceleration_structure.t ->
    destination:Acceleration_structure.t -> (unit, error) result
  val write_compacted_size :
    t -> source:Acceleration_structure.t -> destination:Buffer.t ->
    offset:int64 -> (unit, error) result
  val copy_and_compact :
    t -> source:Acceleration_structure.t ->
    destination:Acceleration_structure.t -> (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
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
  val execute_indirect_commands :
    t -> Indirect_command_buffer.t -> location:int -> length:int ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
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
  type viewport =
    { x : float; y : float; width : float; height : float
    ; znear : float; zfar : float }
  type scissor = { x : int; y : int; width : int; height : int }

  val create :
    Command_buffer.t -> target:Texture.t ->
    ?clear:float * float * float * float -> ?depth:Texture.t ->
    ?stencil:Texture.t -> unit -> (t, error) result
  val create_from_pass :
    Command_buffer.t -> Render_pass_descriptor.t -> (t, error) result
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
  val set_triangle_fill_mode : t -> fill_mode -> (unit, error) result
  val set_blend_color :
    t -> red:float -> green:float -> blue:float -> alpha:float ->
    (unit, error) result
  val set_depth_bias :
    t -> bias:float -> slope_scale:float -> clamp:float ->
    (unit, error) result
  val set_stencil_reference_values :
    t -> front:int32 -> back:int32 -> (unit, error) result
  val set_stencil_reference_value : t -> int32 -> (unit, error) result
  val set_visibility_result :
    t -> mode:visibility -> offset:int64 -> (unit, error) result
  val tile_width : t -> (int, error) result
  val tile_height : t -> (int, error) result
  val set_color_store_action :
    t -> ?attachment:int -> store_action -> (unit, error) result
  val set_color_store_options :
    t -> ?attachment:int -> custom_sample_positions:bool -> unit ->
    (unit, error) result
  val memory_barrier : t -> scope:barrier_scope list -> after:stage list -> before:stage list -> (unit,error) result
  val memory_barrier_resources : t -> resource list -> after:stage list -> before:stage list -> (unit,error) result
  val update_fence : t -> Fence.t -> after:stage list -> (unit,error) result
  val wait_for_fence : t -> Fence.t -> before:stage list -> (unit,error) result
  val set_depth_store_action : t -> store_action -> (unit,error) result
  val set_depth_store_options : t -> custom_sample_positions:bool -> unit -> (unit,error) result
  val set_stencil_store_action : t -> store_action -> (unit,error) result
  val set_stencil_store_options : t -> custom_sample_positions:bool -> unit -> (unit,error) result
  val use_heap : t -> Heap.t -> stages:stage list -> (unit,error) result
  val use_heaps : t -> Heap.t list -> stages:stage list -> (unit,error) result
  val use_resource : t -> resource -> usage:resource_usage list -> stages:stage list -> (unit,error) result
  val use_resources : t -> resource list -> usage:resource_usage list -> stages:stage list -> (unit,error) result
  val set_stage_buffer : t -> stage:stage -> index:int -> offset:int64 -> ?stride:int64 -> Buffer.t option -> (unit,error) result
  val set_stage_texture : t -> stage:stage -> index:int -> Texture.t option -> (unit,error) result
  val set_stage_textures : t -> stage:stage -> start:int -> Texture.t option list -> (unit,error) result
  val set_stage_sampler : t -> stage:stage -> index:int -> ?lod_min:float -> ?lod_max:float -> Sampler.t option -> (unit,error) result
  val set_stage_samplers : t -> stage:stage -> start:int -> Sampler.t option list -> (unit,error) result
  val set_stage_acceleration_structure : t -> stage:stage -> index:int -> Acceleration_structure.t option -> (unit,error) result
  val set_stage_visible_function_table : t -> stage:stage -> index:int -> Visible_function_table.t option -> (unit,error) result
  val set_stage_intersection_function_table : t -> stage:stage -> index:int -> Intersection_function_table.t option -> (unit,error) result
  val set_stage_visible_function_tables : t -> stage:stage -> start:int -> Visible_function_table.t option list -> (unit,error) result
  val set_stage_intersection_function_tables : t -> stage:stage -> start:int -> Intersection_function_table.t option list -> (unit,error) result
  val set_depth_stencil_state : t -> Depth_stencil.t option -> (unit,error) result
  val set_stage_bytes : t -> stage:stage -> index:int -> bytes -> (unit,error) result
  val set_depth_clip_mode : t -> clamp:bool -> (unit,error) result
  val set_depth_bounds : t -> minimum:float -> maximum:float -> (unit,error) result
  val set_viewports : t -> viewport list -> (unit,error) result
  val set_scissors : t -> scissor list -> (unit,error) result
  val set_tessellation_factor_scale : t -> float -> (unit,error) result
  val set_vertex_amplification : t -> (int * int) list -> (unit,error) result
  val draw_indexed : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 -> ?instances:int64 -> ?base_vertex:int64 -> ?base_instance:int64 -> unit -> (unit,error) result
  val draw_indirect : t -> primitive:primitive -> buffer:Buffer.t -> offset:int64 -> (unit,error) result
  val set_tessellation_factor_buffer : t -> ?buffer:Buffer.t -> offset:int64 -> instance_stride:int64 -> unit -> (unit,error) result
  val draw_indexed_basic : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 -> (unit,error) result
  val draw_indexed_instances : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> index_count:int64 -> instances:int64 -> (unit,error) result
  val draw_indexed_indirect : t -> primitive:primitive -> index_type:index_type -> index_buffer:Buffer.t -> index_offset:int64 -> indirect_buffer:Buffer.t -> indirect_offset:int64 -> (unit,error) result
  val draw_patches : t -> control_points:int64 -> patch_start:int64 -> patch_count:int64 -> patch_index_buffer:Buffer.t -> patch_index_offset:int64 -> ?instances:int64 -> ?base_instance:int64 -> unit -> (unit,error) result
  val draw_patches_indirect : t -> control_points:int64 -> patch_index_buffer:Buffer.t -> patch_index_offset:int64 -> indirect_buffer:Buffer.t -> indirect_offset:int64 -> (unit,error) result
  val execute_indirect_commands : t -> Indirect_command_buffer.t -> location:int -> length:int -> (unit,error) result
  val execute_indirect_commands_indirect_range : t -> Indirect_command_buffer.t -> range_buffer:Buffer.t -> offset:int64 -> (unit,error) result
  val draw_triangles :
    t -> first:int -> count:int -> ?instances:int -> unit ->
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
  val update_fence : t -> Fence.t -> (unit,error) result
  val wait_for_fence : t -> Fence.t -> (unit,error) result
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

module Resource100 : sig
  module Buffer_ops : sig
    val add_debug_marker : Buffer.t -> label:string -> offset:int64 -> length:int64 -> (unit,error) result
    val remove_all_debug_markers : Buffer.t -> (unit,error) result
  end
  module Texture_ops : sig
    val view : Texture.t -> format:Texture.format -> (Texture.t,error) result
    val get_bytes : Texture.t -> bytes:bytes -> bytes_per_row:int -> region:Texture.region -> mip_level:int -> (unit,error) result
    val replace_region : Texture.t -> region:Texture.region -> mip_level:int -> bytes:bytes -> bytes_per_row:int -> (unit,error) result
  end
  module Buffer_layout : sig
    type t
    type step_function = Constant | Per_vertex | Per_instance | Per_patch | Per_patch_control_point
    val create : ?stride:int64 -> ?step_rate:int64 -> ?step_function:step_function -> unit -> (t,error) result
    val stride : t -> int64
    val step_rate : t -> int64
    val step_function : t -> step_function
    val set_stride : t -> int64 -> (unit,error) result
    val set_step_rate : t -> int64 -> (unit,error) result
    val set_step_function : t -> step_function -> (unit,error) result
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Sample_attachment : sig
    type t
    type sample_index = Dont_sample | Index of int64
    val create : ?start:sample_index -> ?finish:sample_index -> unit -> (t,error) result
    val range : t -> int64 * int64
    val set_range : t -> start:sample_index -> finish:sample_index -> (unit,error) result
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module View_pool_descriptor : sig
    type t
    val create : ?label:string -> count:int64 -> unit -> (t,error) result
    val count : t -> int64
    val label : t -> string option
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Texture_view_pool : sig
    type t
    val create : Device.t -> View_pool_descriptor.t -> (t,error) result
    val device : t -> Device.t
    val count : t -> int64
    val set : t -> index:int -> Texture.t -> (int64,error) result
    val copy : source:t -> source_index:int -> length:int -> destination:t -> destination_index:int -> (int64,error) result
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
  module Resource_state_pass : sig
    type t
    val create : unit -> (t,error) result
    val create_encoder : Command_buffer.t -> t -> (Resource_state_encoder.t,error) result
    val destroyed : t -> bool
    val destroy : t -> (unit,error) result
  end
end


module IO : sig
  module Queue : sig
    type t = io_queue
    val device : t -> Device.t
    val destroyed : t -> bool
    val create_command_buffer :
      t -> ?label:string -> unit -> (io_command_buffer, error) result
    val destroy : t -> (unit, error) result
  end
  module File : sig
    type t = io_file
    val device : t -> Device.t
    val destroyed : t -> bool
    val destroy : t -> (unit, error) result
  end
  module Command_buffer : sig
    type t = io_command_buffer
    type status = Recording | Submitted | Complete | Failed
    val status : t -> status
    val load_buffer :
      t -> destination:Buffer.t -> destination_offset:int64 -> size:int64 ->
      source:File.t -> source_offset:int64 -> (unit, error) result
    val commit_and_wait : t -> (status, error) result
    val destroyed : t -> bool
    val destroy : t -> (unit, error) result
  end
end


module Pipeline_descriptor : sig
  module Compute : sig
    type t
    type size3 = { width : int64; height : int64; depth : int64 }
    val create :
      ?preloaded_libraries:Dynamic_library.t list ->
      ?stage_input:Shader_stage_descriptor.t -> Function.t -> (t, error) result
    val required_threads : t -> (size3, error) result
    val set_required_threads : t -> size3 -> (unit, error) result
    val compile : ?reflection:bool -> t -> (Compute_pipeline.t, error) result
    val reset : t -> (unit, error) result
    val destroyed : t -> bool
    val destroy : t -> (unit, error) result
  end
  module Render : sig
    type t
    type topology = Unspecified | Point | Line | Triangle
    type winding = Clockwise | Counter_clockwise
    val create :
      ?fragment_function:Function.t -> ?binary_archives:Binary_archive.t list ->
      ?vertex_preloaded_libraries:Dynamic_library.t list ->
      ?fragment_preloaded_libraries:Dynamic_library.t list ->
      Function.t -> (t, error) result
    val depth_format : t -> (Texture.format option, error) result
    val set_depth_format : t -> Texture.format -> (unit, error) result
    val stencil_format : t -> (Texture.format option, error) result
    val set_stencil_format : t -> Texture.format -> (unit, error) result
    val input_topology : t -> (topology, error) result
    val set_input_topology : t -> topology -> (unit, error) result
    val sample_count : t -> (int, error) result
    val set_sample_count : t -> int -> (unit, error) result
    val tessellation_winding : t -> (winding, error) result
    val set_tessellation_winding : t -> winding -> (unit, error) result
    val compile : ?reflection:bool -> t -> (Render_pipeline.t, error) result
    val reset : t -> (unit, error) result
    val destroyed : t -> bool
    val destroy : t -> (unit, error) result
  end
end
