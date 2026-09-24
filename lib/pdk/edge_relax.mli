type selection = Relax_points of Group.t | Relax_primitives of Group.t
type target_mode = Individual_lengths | Scale_independent_distribution

val relax :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?selection:selection ->
  ?pin_points:Group.t ->
  ?iterations:int ->
  ?step_size:float ->
  ?target_mode:target_mode ->
  ?only_shorten:bool ->
  ?tolerance:float ->
  reference:Geometry.t ->
  Geometry.t ->
  (Geometry.t, string) result
