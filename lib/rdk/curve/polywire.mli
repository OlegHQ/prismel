val run :
  ?cancel:Cancel.t ->
  grain:int ->
  primitives:Group.t option ->
  sides:int ->
  divisions_attribute:string option ->
  segments:int ->
  segments_attribute:string option ->
  segment_scales:(float * float) option ->
  segment_scales_attribute:string option ->
  prevent_joint_buckling:bool ->
  maximum_joint_scale:float ->
  maximum_joint_scale_attribute:string option ->
  smooth_point:bool ->
  smooth_attribute:string option ->
  max_valence:int option ->
  scale_attribute:string option ->
  seam_offset:int ->
  seam_attribute:string option ->
  segment_seam_attribute:string option ->
  v_attribute:string option ->
  generate_uv:bool ->
  u_range:(float * float) option ->
  v_range:(float * float) option ->
  uv_range_attribute:string option ->
  up_attribute:string option ->
  caps:bool ->
  cap_group:string option ->
  radius:float ->
  Geometry.t ->
  (Geometry.t, string) result
(** Variable-resolution circular wire kernel. Unselected primitives pass
    through, selected curves are replaced by zipper-connected polygon rings,
    and point/vertex payload is interpolated from explicit source ancestry.
    Segment placement and UV intervals may be constant or driven per source
    edge by its outgoing vertex; optional generated UVs are distinct from an
    authored source [uv] field, which remains ordinary interpolated payload.
    Optional joint buckling prevention uses an exact radial miter at source
    joints and a constant or point-authored maximum enlargement. Smooth-point
    and maximum-valence policy creates explicit uncapped run boundaries rather
    than zero-length or hidden connecting faces. Outgoing-corner integer seam
    offsets provide one snapped physical seam for every complete source edge. *)
