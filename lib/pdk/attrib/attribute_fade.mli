type scalar = Constant of float | Floats of float array | Ints of int array
type ramp = { positions : float array; values : float array; }
val error_message : int -> int -> string
val fade :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?points:Pdk_core.Group.t ->
  ?start_source:Pdk_core.Geometry.t ->
  ?hold_source:Pdk_core.Geometry.t ->
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
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, Pdk_core.Error.t) result
