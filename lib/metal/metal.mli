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

  val create :
    device:Device.t -> length:int64 -> storage:storage_mode ->
    ?cpu_cache:cpu_cache_mode -> ?hazard_tracking:hazard_tracking_mode ->
    ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val generation : t -> int64
  val length : t -> int64
  val storage_mode : t -> storage_mode
  val cpu_cache_mode : t -> cpu_cache_mode
  val hazard_tracking_mode : t -> hazard_tracking_mode
  val heap_offset : t -> int64 option
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
    | R8_uint
    | R16_float
    | R32_float
    | Rg8_unorm
    | Rg8_unorm_srgb
    | Rg16_float
    | Rg32_float
    | Rgba8_unorm
    | Rgba8_unorm_srgb
    | Bgra8_unorm
    | Bgra8_unorm_srgb
    | Rgb10a2_unorm
    | Rg11b10_float
    | Rgba16_float
    | Rgba32_float
    | Depth16_unorm
    | Depth32_float
    | Stencil8
    | Depth24_unorm_stencil8
    | Depth32_float_stencil8

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

  val descriptor_2d :
    ?mipmapped:bool -> ?storage:Buffer.storage_mode -> ?usage:usage list ->
    ?label:string -> format:format -> width:int -> height:int -> unit ->
    descriptor
  val create : device:Device.t -> descriptor -> (t, error) result
  val create_view :
    t -> format:format -> base_mip:int -> mip_count:int -> base_slice:int ->
    slice_count:int -> ?label:string -> unit -> (t, error) result
  val device : t -> Device.t
  val descriptor : t -> descriptor
  val heap_offset : t -> int64 option
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
  val destroy : t -> (unit, error) result
end

module Heap : sig
  type t
  type kind = Automatic | Placement
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
    ?hazard_tracking:hazard_tracking_mode -> ?kind:kind -> ?label:string ->
    size:int64 -> unit -> descriptor
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
  val max_available_size : t -> alignment:int64 -> (int64, error) result
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
  val dispatch_threads :
    t -> threads:int * int * int -> threadgroup:int * int * int ->
    (unit, error) result
  val end_encoding : t -> (unit, error) result
  val destroyed : t -> bool
end
