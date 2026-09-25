(** Packed point and vertex normals. *)
type weighting = Vertex_angle | Each_vertex | Face_area

val run :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Element_selection.t ->
  ?primitives:Group.t -> ?owner:Attribute.owner -> ?weighting:weighting ->
  ?cusp_angle:float -> ?keep_original_zero:bool -> ?reverse:bool ->
  ?attribute:string -> Geometry.t -> (Geometry.t, string) result

val run_checked :
  ?cancel:Cancel.t -> ?grain:int -> ?selection:Element_selection.t ->
  ?primitives:Group.t -> ?owner:Attribute.owner -> ?weighting:weighting ->
  ?cusp_angle:float -> ?keep_original_zero:bool -> ?reverse:bool ->
  ?attribute:string -> Geometry.t -> (Geometry.t, Error.t) result
(** The public typed boundary for [run], preserving its validation message and
    mapping cancellation to the stable [cancelled] code. *)
