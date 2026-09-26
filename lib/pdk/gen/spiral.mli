exception Invalid_spiral of string
type extent =
    Spiral_turns of { turns : float; height : float; }
  | Spiral_height_pitch of { height : float; pitch : float; }
type radius =
    Spiral_archimedean_change of { start_radius : float;
      increase_per_turn : float;
    }
  | Spiral_archimedean_end of { start_radius : float; end_radius : float; }
  | Spiral_logarithmic_change of { start_radius : float;
      scale_per_turn : float;
    }
  | Spiral_logarithmic_end of { start_radius : float; end_radius : float; }
type direction = Spiral_counterclockwise | Spiral_clockwise
type divisions =
    Spiral_divisions_per_curve of int
  | Spiral_divisions_per_turn of int
type orientation =
    Spiral_x
  | Spiral_y
  | Spiral_z
  | Spiral_axis of Prismel_math.Vec3.t
type rotation_order =
    Spiral_xyz
  | Spiral_xzy
  | Spiral_yxz
  | Spiral_yzx
  | Spiral_zxy
  | Spiral_zyx
type ramp = {
  positions : float array;
  values : float array;
  slopes : float array;
}
type profile = {
  turns : float;
  height : float;
  angular_rate : float;
  radius : radius;
  radius_scale : float;
  height_ramp : ramp option;
  radius_ramp : ramp option;
  uniform_scale : float;
}
val get_ok : ('a, string) result -> 'a

val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?extent:extent ->
  ?radius:radius ->
  ?height_ramp:(float * float) list ->
  ?radius_scale:float ->
  ?radius_ramp:(float * float) list ->
  ?direction:direction ->
  ?start_angle:float ->
  ?divisions:divisions ->
  ?uniform_angle:bool ->
  ?spiral_count:int ->
  ?orientation:orientation ->
  ?center:Prismel_math.Vec3.t ->
  ?rotation:Prismel_math.Vec3.t ->
  ?rotation_order:rotation_order ->
  ?uniform_scale:float ->
  ?angle_attribute:String.t ->
  ?x_axis_attribute:String.t ->
  ?y_axis_attribute:String.t ->
  ?tangent_attribute:String.t ->
  ?orient_attribute:String.t ->
  ?distance_attribute:String.t ->
  unit -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
