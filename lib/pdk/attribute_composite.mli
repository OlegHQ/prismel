type operation =
  | Composite_mean
  | Composite_maximum
  | Composite_minimum
  | Composite_over
  | Composite_under

type input

val input : weight:float -> Geometry.t -> input

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?operation:operation ->
  ?weight:float ->
  ?detail_attributes:string ->
  ?primitive_attributes:string ->
  ?point_attributes:string ->
  ?vertex_attributes:string ->
  ?allow_position:bool ->
  ?alpha_attribute:string ->
  inputs:input list ->
  Geometry.t ->
  (Geometry.t, string) result
