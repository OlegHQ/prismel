type buffer_usage = Copy_src | Copy_dst | Uniform | Storage | Vertex | Index

(** Host-visible [Shared] storage (default) or GPU-only [Device_local] storage,
    which rejects host reads and writes with a typed [Unsupported] error. *)
type memory = Shared | Device_local
type buffer_descriptor = { label:string option; size:int64; usage:buffer_usage list }
type texture_usage = Texture_binding | Storage_binding | Render_attachment | Texture_copy_src | Texture_copy_dst
(** Color texel formats. Host bytes are little-endian RGBA: [Rgba8_unorm] 4
    bytes per texel, [Rgba16_float] 8 (IEEE binary16, see {!half_of_float}),
    [Rgba32_float] 16 (IEEE binary32). All three are filterable and
    storage-capable on Apple7+ (M1 reports [supports32BitFloatFiltering]);
    float formats reject [Render_attachment] usage and multisampling with a
    typed [Unsupported] error. Depth and stencil constructors fix their own
    native format; pass [Rgba8_unorm] there. *)
type texture_format = Rgba8_unorm | Rgba16_float | Rgba32_float
type texture_descriptor =
  { label:string option; width:int; height:int; depth:int; mip_levels:int
  ; sample_count:int; format:texture_format; usage:texture_usage list }

(** Bytes per texel of a format: 4, 8 or 16. Upload and readback rows need
    [bytes_per_row >= width * texel_bytes format]. *)
val texel_bytes : texture_format -> int

(* Texel regions for blit copies. *)
type origin={x:int;y:int;z:int}
type extent={width:int;height:int;depth:int}
type sampler_filter = Nearest | Linear
type mip_filter = No_mip | Nearest_mip | Linear_mip
type address_mode = Clamp_to_edge | Repeat | Mirror_repeat
type sampler_descriptor =
  { label:string option; min_filter:sampler_filter; mag_filter:sampler_filter
  ; mip_filter:mip_filter; address_u:address_mode; address_v:address_mode
  ; lod_min:float; lod_max:float; max_anisotropy:int }
val validate_buffer : Caps.t -> buffer_descriptor -> (unit,Error.t) result
val validate_texture : Caps.t -> texture_descriptor -> (unit,Error.t) result
val validate_sampler : sampler_descriptor -> (unit,Error.t) result

(** IEEE 754 binary16 bits (0..0xffff) of a float, rounding to nearest even;
    overflow gives infinity and NaN a quiet NaN. Write each [Rgba16_float]
    channel as these 16 bits little-endian ([Bytes.set_uint16_le]). *)
val half_of_float : float -> int
