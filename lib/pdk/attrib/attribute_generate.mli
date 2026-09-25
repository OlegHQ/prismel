type numeric_value =
    Scalar of float
  | Vec2 of Prismel_math.Vec2.t
  | Vec3 of Prismel_math.Vec3.t
  | Vec4 of float * float * float * float
type random_operation =
    Random_set
  | Random_add
  | Random_minimum
  | Random_maximum
  | Random_multiply
type noise_kind = Noise_float | Noise_vector | Noise_quaternion
type noise_location =
    Noise_position
  | Noise_element_number
  | Noise_attribute of string
type noise_range =
    Noise_positive
  | Noise_zero_centered
  | Noise_min_max of numeric_value * numeric_value
type noise_operation =
    Noise_set_initial
  | Noise_set
  | Noise_add
  | Noise_subtract
  | Noise_multiply
  | Noise_minimum
  | Noise_maximum
type random_selection =
    Random_points of Pdk_core.Group.t
  | Random_vertices of Pdk_core.Group.t
  | Random_primitives of Pdk_core.Group.t
  | Random_edges of Pdk_core.Edge_group.t
type random_distribution =
    Random_constant of numeric_value
  | Random_two_values of { a : numeric_value; b : numeric_value;
      probability_b : float;
    }
  | Random_uniform of { min : numeric_value; max : numeric_value; }
  | Random_uniform_discrete of { min : numeric_value; max : numeric_value;
      step : numeric_value;
    }
  | Random_normal of { middle : numeric_value; scale : numeric_value; }
  | Random_exponential of { median : numeric_value; }
  | Random_log_normal of { median : numeric_value; stddev : numeric_value; }
  | Random_cauchy of { median : numeric_value; scale : numeric_value; }
  | Random_direction of { direction : numeric_value; cone_angle : float; }
  | Random_inside_sphere of { dimensions : int; }
  | Random_inside_sphere_cone of { direction : numeric_value;
      cone_angle : float;
    }
  | Random_custom_ramp of { ramp : (float * float) list;
      fit_min : numeric_value; fit_max : numeric_value;
    }
  | Random_custom_discrete of (numeric_value * float) list
  | Random_custom_discrete_text of (string * float) list
type remap_input =
    Remap_explicit of { min : numeric_value; max : numeric_value; }
  | Remap_auto
type remap_policy = Remap_clamp | Remap_cycle | Remap_extrapolate
type storage_kind = Position | Float | Float2 | Float3 | Float4
val value_array : numeric_value -> float array
val finite_array : float array -> bool
val same_dimensions : string -> float array array -> (int, string) result
type direction_plan = {
  axis : float array;
  householder : float array;
  householder_norm2 : float;
  cap_angle : float;
  bias : float;
}
type prepared_distribution =
    Prepared_constant of float array
  | Prepared_two_values of { a : float array; b : float array;
      probability_b : float;
    }
  | Prepared_uniform of { min : float array; span : float array; }
  | Prepared_uniform_discrete of { min : float array; max : float array;
      step : float array; choices : float array;
    }
  | Prepared_normal of { middle : float array; scale : float array; }
  | Prepared_exponential of { median : float array; }
  | Prepared_log_normal of { median : float array; sigma : float array; }
  | Prepared_cauchy of { median : float array; scale : float;
      direction : direction_plan option;
    }
  | Prepared_direction of direction_plan
  | Prepared_inside_sphere of { dimensions : int; }
  | Prepared_inside_sphere_cone of direction_plan
  | Prepared_custom_ramp of { knots : (float * float) array;
      fit_min : float array; fit_span : float array;
    }
  | Prepared_custom_discrete of { values : float array array;
      cumulative : float array; total : float; last_positive : int;
    }
  | Prepared_custom_discrete_text of { values : string array;
      cumulative : float array; total : float; last_positive : int;
    }
val validate_knots :
  string -> (float * float) list -> ((float * float) array, string) result
val max_abs : float array -> float
val prepare_direction_plan :
  orientation:bool ->
  bias:float -> numeric_value -> float -> (direction_plan, string) result
val prepare_distribution :
  direction_bias:float ->
  random_distribution -> (prepared_distribution, string) result
val prepared_dimension : prepared_distribution -> int
val owner_count : Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val group_owner : Pdk_core.Attribute.owner -> Pdk_core.Group.owner option
val validate_selection :
  string ->
  Pdk_core.Attribute.owner ->
  int -> Pdk_core.Group.t option -> (unit, string) result
val random_selection_element :
  random_selection -> Pdk_core.Element_selection.t
val random_selection_destination :
  Pdk_core.Attribute.owner -> Pdk_core.Group.owner option
val resolve_random_selection :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:Pdk_core.Attribute.owner ->
  count:int ->
  geometry:Pdk_core.Geometry.t ->
  Pdk_core.Group.t option ->
  random_selection option -> (Pdk_core.Group.t option, string) result
type sample_limits =
    No_limits
  | Minimum_only of float array
  | Maximum_only of float array
  | Minimum_and_maximum of float array * float array
val prepare_limits :
  int ->
  numeric_value option ->
  numeric_value option -> (sample_limits, string) result
val limit_sample : sample_limits -> int -> Float.t -> Float.t
val kind_dimension : storage_kind -> int
val kind_of_dimension : int -> storage_kind
val planes_of_storage :
  Pdk_core.Attribute.storage ->
  (storage_kind * float array array, string) result
val source_planes :
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  Pdk_core.Geometry.t -> (storage_kind * float array array, string) result
val existing_planes :
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  Pdk_core.Geometry.t -> (storage_kind * float array array) option
val install :
  owner:Pdk_core.Attribute.owner ->
  name:string ->
  storage_kind ->
  float array array ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val remove_stale_normals : Pdk_core.Geometry.t -> Pdk_core.Geometry.t
val changed : float array array -> float array array -> bool
val seed_values :
  Pdk_core.Attribute.owner ->
  string option -> Pdk_core.Geometry.t -> (int array option, string) result
val expected_fraction_dimension : prepared_distribution -> int
val fraction_values :
  Pdk_core.Attribute.owner ->
  String.t option ->
  int -> Pdk_core.Geometry.t -> (float array array option, string) result
val sample_linear_knots : (float * float) array -> float -> float
val normal_quantile : float -> float
val indexed_uniform :
  float array array option ->
  Prismel_math.Rand.t -> int -> int -> int -> float
val choice_uniform :
  float array array option -> Prismel_math.Rand.t -> int -> int -> float
val weighted_choice : float array -> float -> int -> float -> int
val standard_normal : Prismel_math.Rand.t -> int -> int -> float
val cauchy_radius_quantile : int -> float -> float
val cap4_angle : float -> float -> float
val sample_direction :
  float array array option ->
  Prismel_math.Rand.t ->
  int ->
  int ->
  float array ->
  float array -> float -> float -> float -> float array -> unit
val sample_inside_sphere :
  float array array option ->
  Prismel_math.Rand.t -> int -> int -> int -> float array -> unit
val sample_prepared :
  prepared_distribution ->
  float array array option ->
  Prismel_math.Rand.t -> int -> int -> Float.t array -> unit
val randomize_text :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selection:Pdk_core.Group.t option ->
  ?seed_attribute:string ->
  ?fraction_attribute:String.t ->
  seed:Prismel_math.Rand.t ->
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  operation:random_operation ->
  scale:float ->
  minimum:'a option ->
  maximum:'b option ->
  values:String.t array ->
  cumulative:float array ->
  total:float ->
  last_positive:int ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val randomize :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?element_selection:random_selection ->
  ?seed_attribute:string ->
  ?fraction_attribute:String.t ->
  ?minimum:numeric_value ->
  ?maximum:numeric_value ->
  direction_bias:float ->
  seed:Prismel_math.Rand.t ->
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  operation:random_operation ->
  scale:float ->
  random_distribution ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
type noise_coordinates = {
  nx : float array;
  ny : float array;
  nz : float array;
}
val noise_coordinates :
  owner:Pdk_core.Attribute.owner ->
  location:noise_location ->
  Pdk_core.Geometry.t -> (noise_coordinates, string) result
val noise :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:Pdk_core.Group.t ->
  seed:int ->
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  kind:noise_kind ->
  location:noise_location ->
  range:noise_range ->
  operation:noise_operation ->
  blend:float ->
  frequency:Prismel_math.Vec3.t ->
  offset:Prismel_math.Vec3.t ->
  octaves:int ->
  lacunarity:float ->
  roughness:float ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val validate_ramp :
  (float * float) list -> ((float * float) array option, string) result
val ramp_sample : (float * float) array -> float -> float
val remap :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?selection:Pdk_core.Group.t ->
  owner:Pdk_core.Attribute.owner ->
  name:String.t ->
  ?into:String.t ->
  input:remap_input ->
  output_min:numeric_value ->
  output_max:numeric_value ->
  policy:remap_policy ->
  ramp:(float * float) list ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
