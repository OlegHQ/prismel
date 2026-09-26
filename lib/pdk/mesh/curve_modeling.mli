(** Checked packed curve modeling operations. *)

val resample_curves_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?segments:int ->
  ?maximum_segment_length:float -> ?segment_length_attribute:string ->
  ?segments_attribute:string -> ?even_last_segment:bool ->
  ?curve_u_attribute:string -> ?curve_number_attribute:string ->
  ?distance_attribute:string -> ?tangent_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result

type carve_keep = Keep_inside | Keep_outside | Keep_inside_and_outside
type carve_attribute_mode = Attribute_replace | Attribute_scale

val carve_curves_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t ->
  ?relative_arc_length:bool -> ?first:float -> ?last:float ->
  ?first_attribute:string -> ?last_attribute:string ->
  ?attribute_mode:carve_attribute_mode -> ?only_at_breakpoints:bool ->
  ?cut_at_all_internal_breakpoints:bool -> ?keep:carve_keep ->
  ?extract_points:bool -> ?divisions:int -> ?keep_original:bool ->
  Geometry.t -> (Geometry.t, Error.t) result

val sweep_circle_checked :
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
