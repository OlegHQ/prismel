(** Legacy circular sweep fast path; the public wrapper selects this path only
    for its compatible option set. *)

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?sides:int ->
  ?scale_attribute:string -> ?seam_offset:int -> ?seam_attribute:string ->
  ?v_attribute:string -> ?up_attribute:string -> ?caps:bool ->
  ?cap_group:string -> radius:float -> Geometry.t ->
  (Geometry.t, string) result
