exception Cardinality_error of string
type seam_storage =
    Seam_float of float array
  | Seam_int of int array
  | Seam_text of string array
  | Seam_float2 of Pdk_core.Packed.Float2.Private.view
  | Seam_float3 of Pdk_core.Packed.Float3.Private.view
  | Seam_float4 of Pdk_core.Packed.Float4.Private.view
  | Seam_int_array of Pdk_core.Packed.Int_array.Private.view
  | Seam_float_array of Pdk_core.Packed.Float_array.Private.view
  | Seam_group of bytes
type seam = {
  name : string;
  owner : Pdk_core.Attribute.owner;
  storage : seam_storage;
}
type numeric_component =
    Component_float of seam
  | Component_float2 of seam * int
  | Component_float3 of seam * int
  | Component_float4 of seam * int
val element : int array -> seam -> int -> int
val float_equal : float -> float -> float -> bool
val group_mem : bytes -> int -> bool
val row_equal_int :
  Pdk_core.Packed.Int_array.Private.view ->
  int -> Pdk_core.Packed.Int_array.Private.view -> int -> bool
val row_equal_float :
  float ->
  Pdk_core.Packed.Float_array.Private.view ->
  int -> Pdk_core.Packed.Float_array.Private.view -> int -> bool
val seam_equal :
  tolerance:float ->
  primitive_of_vertex:int array -> seam array -> int -> int -> bool
val compare_int_rows :
  Pdk_core.Packed.Int_array.Private.view -> int -> int -> int
val compare_float_rows :
  Pdk_core.Packed.Float_array.Private.view -> int -> int -> int
val seam_compare :
  primitive_of_vertex:int array -> seam array -> int -> int -> int
val component_value : int array -> numeric_component -> int -> float
val sift_down : ('a -> 'a -> int) -> 'a array -> int -> int -> int -> unit
val sort_range : ('a -> 'a -> int) -> 'a array -> int -> int -> unit
val seam_of_attribute : Pdk_core.Attribute.t -> seam
val numeric_components : seam array -> numeric_component array
val validate_finite : seam -> (unit, string) result
val checked_add : string -> int -> int -> (int, string) result
val select_float :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int -> int array -> float array -> float array
val promote_attribute :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  primitive_of_vertex:int array ->
  point_representative:int array -> seam -> Pdk_core.Attribute.t
val run :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Element_selection.t ->
  ?attributes:string ->
  ?tolerance:float ->
  ?promote_attributes:bool ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
