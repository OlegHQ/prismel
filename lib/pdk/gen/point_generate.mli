type mode =
    Generate_total of int
  | Generate_per_point of { points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string; }
exception Cardinality_error of string
val error : string -> ('a, string) result
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?count_ids:int array ->
  ?keep_input:bool ->
  ?seed:Prismel_math.Rand.t ->
  ?generated_group:string ->
  ?source_point_attribute:String.t ->
  ?source_index_attribute:String.t ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  mode:mode -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

val run_checked :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?keep_input:bool ->
  ?seed:Prismel_math.Rand.t ->
  ?generated_group:string ->
  ?source_point_attribute:String.t ->
  ?source_index_attribute:String.t ->
  ?copy_point_attributes:string ->
  ?copy_detail_attributes:string ->
  mode:mode -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
