type scalar = Constant of float | Floats of float array | Ints of int array
type ramp = { positions : float array; values : float array; }
val fade :
  ?cancel:Rdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Rdk_core.Group.t ->
  ?start_source:Rdk_core.Geometry.t ->
  ?hold_source:Rdk_core.Geometry.t ->
  ?fade_attribute:String.t ->
  ?start_attribute:string ->
  ?start_retime:float * float ->
  ?hold_scale_attribute:string ->
  frame:float ->
  ?frame_offset:float ->
  ?fade_in:float ->
  ?fade_hold:float ->
  ?fade_out:float ->
  ?fade_in_ramp:(float * float) list ->
  ?fade_out_ramp:(float * float) list ->
  ?visualize:bool ->
  Rdk_core.Geometry.t -> (Rdk_core.Geometry.t, Rdk_core.Error.t) result
