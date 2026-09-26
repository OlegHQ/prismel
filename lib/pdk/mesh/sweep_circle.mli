(** Circular sweeps of polygon curves: the compatible option set takes the
    fast path, everything else goes through [Polywire]. *)

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?sides:int ->
  ?divisions_attribute:string -> ?segments:int -> ?segments_attribute:string ->
  ?segment_scales:(float * float) -> ?segment_scales_attribute:string ->
  ?prevent_joint_buckling:bool -> ?maximum_joint_scale:float ->
  ?maximum_joint_scale_attribute:string -> ?smooth_point:bool ->
  ?smooth_attribute:string -> ?max_valence:int -> ?scale_attribute:string ->
  ?seam_offset:int -> ?seam_attribute:string ->
  ?segment_seam_attribute:string -> ?v_attribute:string -> ?generate_uv:bool ->
  ?u_range:(float * float) -> ?v_range:(float * float) ->
  ?uv_range_attribute:string -> ?up_attribute:string -> ?caps:bool ->
  ?cap_group:string -> radius:float -> Geometry.t ->
  (Geometry.t, Error.t) result
