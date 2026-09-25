type cut =
  | Extract_cut_constant of float
  | Extract_cut_primitive_attribute of string

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?cut:cut ->
  ?point_attributes:string ->
  ?copy_primitive_attributes:bool ->
  ?primitive_attributes:string ->
  ?curve_u_attribute:string ->
  ?number_cuts_attribute:string ->
  ?curve_number_attribute:string ->
  distance_attribute:string ->
  Geometry.t ->
  (Geometry.t, string) result
