type scalar = Constant of float | Floats of float array | Ints of int array
type ramp = { positions : float array; values : float array; }
val fail : string -> ('a, string) result
val ( let* ) : ('a, 'b) result -> ('a -> ('c, 'b) result) -> ('c, 'b) result
val block_count : int -> int -> int
val block_bounds : int -> int -> int -> int * int
val scalar_get : scalar -> int -> float
val compile_ramp : string -> (float * float) list -> (ramp, string) result
val sample : ramp -> float -> float
val validate_points : int -> Pdk_core.Group.t option -> (unit, string) result
val validate_reference :
  string -> int -> Pdk_core.Geometry.t option -> (unit, string) result
val point_scalar :
  label:string ->
  default:float ->
  string option -> Pdk_core.Geometry.t -> (scalar, string) result
val fade_source :
  string -> Pdk_core.Geometry.t -> (scalar * bool, string) result
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
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result

val fade_checked :
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
(** Typed boundary for [fade], preserving its validation message and stable
    cancellation code. *)
