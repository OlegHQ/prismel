type mode =
    Generate_total of int
  | Generate_per_point of { points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string; }
exception Cardinality_error of string
val error : string -> ('a, string) result
val run :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?count_ids:int array ->
  ?keep_input:bool ->
  ?seed:Rays_math.Rand.t ->
  ?generated_group:string ->
  ?source_point_attribute:String.t ->
  ?source_index_attribute:String.t ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  mode:mode -> Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Error.t) result
