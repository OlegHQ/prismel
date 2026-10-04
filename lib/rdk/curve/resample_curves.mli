val run :
  ?cancel:Cancel.t -> ?grain:int -> ?primitives:Group.t -> ?segments:int ->
  ?maximum_segment_length:float -> ?segment_length_attribute:string ->
  ?segments_attribute:string -> ?even_last_segment:bool ->
  ?curve_u_attribute:string -> ?curve_number_attribute:string ->
  ?distance_attribute:string -> ?tangent_attribute:string -> Geometry.t ->
  (Geometry.t, Error.t) result
