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
val owner_count : Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val owner_name : Pdk_core.Attribute.owner -> string
val group_owner : Pdk_core.Attribute.owner -> Pdk_core.Group.owner option
val finite : string -> float -> (unit, string) result
val nonblank : string option -> string option
val numeric_of_attribute : Pdk_core.Attribute.t -> (numeric, string) result
val find_numeric :
  owner:Pdk_core.Attribute.owner ->
  String.t -> Pdk_core.Geometry.t -> (numeric option, string) result
val numeric_width : numeric -> int
val numeric_component : numeric -> int -> int -> float
val numeric_length : numeric -> int -> float
val destination_kind_of_numeric : numeric -> destination_kind
val destination_width : destination_kind -> int
val selected_elements :
  Pdk_core.Attribute.owner ->
  Pdk_core.Group.t option ->
  Pdk_core.Geometry.t -> (int * (int -> int), string) result
val mapping_element : correspondence -> int -> int
val find_text_match :
  owner:Pdk_core.Attribute.owner ->
  string -> Pdk_core.Geometry.t -> string array option
val hash_capacity : int -> (int, string) result
val integer_hash : int -> int -> int
val integer_highest_map :
  ?cancel:Pdk_core.Cancel.t -> int array -> (int -> int, string) result
val string_highest_map :
  ?cancel:Pdk_core.Cancel.t ->
  String.t array -> (String.t -> int, string) result
val fill_mapping :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> int -> 'a array -> ('a -> int) -> correspondence
val create_correspondence :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:Pdk_core.Attribute.owner ->
  match_attribute:String.t option ->
  primary:Pdk_core.Geometry.t ->
  source:Pdk_core.Geometry.t -> unit -> (correspondence, string) result
val source_value : numeric -> int -> int -> int -> float
val blend_value : numeric -> int -> float
val clamp_01 : float -> float
val process_value : process -> float -> float
val combine_value : operation -> Float.t -> Float.t -> Float.t
val post_identity :
  overall_scale:float ->
  threshold:'a option -> minimum:'b option -> maximum:'c option -> bool
val validate_layer : int -> layer -> (unit, string) result
val destination_numeric :
  owner:Pdk_core.Attribute.owner ->
  destination:String.t ->
  Pdk_core.Geometry.t -> (numeric option, string) result
val infer_destination_kind :
  owner:Pdk_core.Attribute.owner ->
  destination:String.t ->
  create_missing:bool ->
  create_missing_as_scalar:bool ->
  layers:layer list ->
  Pdk_core.Geometry.t array ->
  (destination_kind * numeric option, string) result
val initialize_output :
  destination_kind -> numeric option -> int -> float array array
val compile_layers :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:Pdk_core.Attribute.owner ->
  destination:String.t ->
  error_on_missing:bool ->
  match_attribute:String.t option ->
  Pdk_core.Geometry.t array ->
  layer list -> (compiled_layer array, string) result
val source_at :
  source_binding ->
  destination:int -> width:int -> component:int -> float array array -> float
val blend_at : blend_binding -> destination:int -> float array array -> float
val storage_of_output :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  selected_count:int ->
  selected_element:(int -> int) ->
  existing:numeric option ->
  destination_kind ->
  float array array -> (Pdk_core.Attribute.storage, string) result
val install_result :
  owner:Pdk_core.Attribute.owner ->
  destination:String.t ->
  delete_sources:bool ->
  layers:layer list ->
  Pdk_core.Attribute.storage ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
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
