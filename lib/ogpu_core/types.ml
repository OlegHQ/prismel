type buffer_usage=Copy_src|Copy_dst|Uniform|Storage|Vertex|Index
type memory=Shared|Device_local
type buffer_descriptor={label:string option;size:int64;usage:buffer_usage list}
type texture_usage=Texture_binding|Storage_binding|Render_attachment|Texture_copy_src|Texture_copy_dst
type texture_format=Rgba8_unorm|Rgba16_float|Rgba32_float
type texture_descriptor={label:string option;width:int;height:int;depth:int;mip_levels:int;sample_count:int;format:texture_format;usage:texture_usage list}
let texel_bytes=function Rgba8_unorm->4|Rgba16_float->8|Rgba32_float->16
(* Texel regions for blit copies. *)
type origin={x:int;y:int;z:int}
type extent={width:int;height:int;depth:int}
type sampler_filter=Nearest|Linear
type mip_filter=No_mip|Nearest_mip|Linear_mip
type address_mode=Clamp_to_edge|Repeat|Mirror_repeat
type sampler_descriptor={label:string option;min_filter:sampler_filter;mag_filter:sampler_filter;mip_filter:mip_filter;address_u:address_mode;address_v:address_mode;lod_min:float;lod_max:float;max_anisotropy:int}
let validate_buffer (caps:Caps.t) (value:buffer_descriptor)=
  let operation="Ogpu.Types.validate_buffer"in match Validation.validate_label~operation value.label with Error _ as failure->failure|Ok()->
  Validation.validate_buffer~operation~max_size:caps.Caps.limits.max_buffer_size~size:value.size~usage_count:(List.length value.usage)
let validate_texture (caps:Caps.t) (value:texture_descriptor)=
  let operation="Ogpu.Types.validate_texture"and l=caps.Caps.limits in match Validation.validate_label~operation value.label with Error _ as failure->failure|Ok()->
  match Validation.validate_texture_shape~operation~max_dimension:l.max_texture_dimension_2d~max_samples:l.max_sample_count
    ~width:value.width~height:value.height~depth:value.depth~mip_levels:value.mip_levels~sample_count:value.sample_count~usage_count:(List.length value.usage)with
  |Error _ as failure->failure
  (* Pipelines target Rgba8_unorm only; float textures are sampled, stored and copied. *)
  |Ok() when value.format<>Rgba8_unorm&&(List.mem Render_attachment value.usage||value.sample_count>1)->
    Error(Error.make operation Error.Unsupported"float textures are not render attachments")
  |Ok()->Ok()
(* IEEE 754 binary16 with round-to-nearest-even; NaN maps to a quiet NaN.
   Integer arithmetic on the double's bits: no allocation, since World maps
   convert millions of channels. A mantissa carry rolls into the exponent
   (and past 65504 into infinity) by plain addition. *)
let half_of_float x=
  let bits=Int64.bits_of_float x in
  let sign=if Int64.compare bits 0L<0 then 0x8000 else 0 in
  let e=Int64.to_int(Int64.shift_right_logical bits 52)land 0x7ff
  and m=Int64.to_int(Int64.logand bits 0xfffffffffffffL)in
  let round v shift=let q=v lsr shift and rest=v land((1 lsl shift)-1)
    and half=1 lsl(shift-1)in
    if rest>half||(rest=half&&q land 1=1)then q+1 else q in
  if e=0x7ff then sign lor(if m=0 then 0x7c00 else 0x7e00)
  else if e-1008>=31 then sign lor 0x7c00
  else if e-1008>0 then sign lor(((e-1008)lsl 10)+round m 42)
  else if 1051-e>=54 then sign
  else sign lor round(m lor(1 lsl 52))(1051-e)
let validate_sampler value=
  let operation="Ogpu.Types.validate_sampler"in match Validation.validate_label~operation value.label with Error _ as failure->failure|Ok()->
  if not(Float.is_finite value.lod_min)||not(Float.is_finite value.lod_max)||value.lod_min<0.||value.lod_max<value.lod_min||value.max_anisotropy<1||value.max_anisotropy>16
  then Error(Error.make operation Error.Invalid_argument"sampler LOD/anisotropy limits are invalid")else Ok()
