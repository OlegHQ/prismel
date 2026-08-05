type mode = Blend_normalized | Blend_differencing
type masking = Blend_no_mask | Blend_set_from_attribute
  | Blend_scale_from_attribute
type mask_source = Blend_mask_first_input | Blend_mask_shape

type shape

val shape :
  ?mask_attribute:string ->
  ?mask_source:mask_source ->
  weight:float ->
  Geometry.t ->
  shape

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?points:Group.t ->
  ?mode:mode ->
  ?masking:masking ->
  ?mask_attribute:string ->
  ?point_id_attribute:string ->
  ?attributes:string ->
  shapes:shape list ->
  Geometry.t ->
  (Geometry.t, string) result
