type operation =
    Combine_copy
  | Combine_add
  | Combine_subtract
  | Combine_multiply
  | Combine_divide
  | Combine_maximum
  | Combine_minimum
type process =
    Combine_process_none
  | Combine_reciprocal
  | Combine_clamp_01
  | Combine_complement_clamp_01
  | Combine_threshold_half
type layer = {
  source : string option;
  source_input : int;
  operation : operation;
  scale : float;
  add : float;
  process : process;
  blend : float;
  blend_attribute : string option;
  blend_input : int;
}
type numeric =
    Numeric_float of float array
  | Numeric_int of int array
  | Numeric_float2 of Pdk_core.Packed.Float2.Private.view
  | Numeric_float3 of Pdk_core.Packed.Float3.Private.view
  | Numeric_float4 of Pdk_core.Packed.Float4.Private.view
type destination_kind =
    Destination_float
  | Destination_int
  | Destination_float2
  | Destination_float3
  | Destination_float4
type correspondence = Direct of int | Mapped of int array
type source_binding =
    Implicit_zero
  | Source of numeric * correspondence
  | Self_source
type blend_binding =
    Constant_one
  | Blend of numeric * correspondence
  | Self_blend
type compiled_layer = {
  source_binding : source_binding;
  blend_binding : blend_binding;
  operation : operation;
  scale : float;
  add : float;
  process : process;
  blend : float;
}
val combine :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?match_attribute:string ->
  ?create_missing:bool ->
  ?create_missing_as_scalar:bool ->
  ?delete_sources:bool ->
  ?error_on_missing:bool ->
  ?overall_scale:float ->
  ?threshold:float ->
  ?minimum:Float.t ->
  ?maximum:Float.t ->
  owner:Pdk_core.Attribute.owner ->
  destination:String.t ->
  layers:layer list ->
  geometries:Pdk_core.Geometry.t array ->
  unit -> (Pdk_core.Geometry.t, string) result
