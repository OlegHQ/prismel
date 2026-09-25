type mode =
    Generate_total of int
  | Generate_per_point of { points_per_point : float;
      scale_attribute : string option;
    }
  | Generate_probability of { attribute : string; }
exception Cardinality_error of string
val error : string -> ('a, string) result
val nonempty : string -> string -> (unit, string) result
val compile_optional_pattern :
  string -> string -> (Pdk_core.Attribute_pattern.t option, string) result
val point_float :
  string -> Pdk_core.Geometry.t -> (float array, string) result
val checked_add : string -> int -> int -> int
val selected : Pdk_core.Group.t option -> int -> bool
val plan_counts :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  seed:Prismel_math.Rand.t ->
  points:Pdk_core.Group.t option ->
  ?count_ids:int array ->
  mode -> Pdk_core.Geometry.t -> (int array option * int, string) result
val generated_maps :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  mode:mode ->
  counts:int array option ->
  generated_count:int -> unit -> int array * int array
val map_fixed :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> total:int -> (int -> int) -> 'a -> 'a array -> 'a array
val remap_point_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  total:int ->
  source_at:(int -> int) -> Pdk_core.Attribute.t -> Pdk_core.Attribute.t
val extend_group :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  total:int ->
  prefix:int -> generated_member:bool -> Pdk_core.Group.t -> Pdk_core.Group.t
val metadata_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  name:string ->
  prefix:int ->
  generated_values:int array -> Pdk_core.Geometry.t -> Pdk_core.Attribute.t
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
