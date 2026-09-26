type spec = {
  source_owner : Pdk_core.Attribute.owner;
  source_name : string;
  target_name : string;
}
type group_spec = {
  group_source_owner : Pdk_core.Attribute.owner;
  group_source : Pdk_core.Group.t;
}
type unmatched = Keep_target | Default_value
type weighted_source = Points | Vertices | Primitives
type computed = {
  computed_owner : weighted_source;
  computed_numbers_attribute : string;
  computed_weights_attribute : string;
}
type plane =
    Float_plane of { source : float array; output : float array;
      existing : float array option;
    }
  | Int_plane of { source : int array; output : int array;
      existing : int array option;
    }
  | Text_plane of { source : string array; output : string array;
      existing : string array option;
    }
  | Float2_plane of { source : Pdk_core.Packed.Float2.Private.view;
      output : Pdk_core.Packed.Float2.Private.view;
      existing : Pdk_core.Packed.Float2.Private.view option;
    }
  | Float3_plane of { source : Pdk_core.Packed.Float3.Private.view;
      output : Pdk_core.Packed.Float3.Private.view;
      existing : Pdk_core.Packed.Float3.Private.view option;
    }
  | Float4_plane of { source : Pdk_core.Packed.Float4.Private.view;
      output : Pdk_core.Packed.Float4.Private.view;
      existing : Pdk_core.Packed.Float4.Private.view option;
    }
  | Int_array_plane of { source : Pdk_core.Packed.Int_array.Private.view;
      existing : Pdk_core.Packed.Int_array.Private.view option;
      choices : int array;
    }
  | Float_array_plane of { source : Pdk_core.Packed.Float_array.Private.view;
      existing : Pdk_core.Packed.Float_array.Private.view option;
      choices : int array;
    }
type job = {
  source_owner : Pdk_core.Attribute.owner;
  target_owner : Pdk_core.Attribute.owner;
  target_name : string;
  position : bool;
  normalize : bool;
  plane : plane;
}
type group_job = {
  group_source_owner : Pdk_core.Attribute.owner;
  group_source_bits : bytes;
  group_target_owner : Pdk_core.Group.owner;
  group_target_name : string;
  group_existing_bits : bytes option;
  group_output_bits : bytes;
  group_target_count : int;
}
val interpolate_primitive :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?compute:computed ->
  ?primitive_attribute:String.t ->
  ?uvw_attribute:String.t ->
  ?pre_scale:float ->
  ?blend:float ->
  ?unmatched:unmatched ->
  target_owner:Pdk_core.Attribute.owner ->
  attributes:spec list ->
  groups:group_spec list ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> (Pdk_core.Geometry.t, string) result
val interpolate_weighted :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  ?numbers_attribute:string ->
  ?weights_attribute:string ->
  ?pre_scale:float ->
  ?normalize_weights:bool ->
  ?threshold:float ->
  ?blend:float ->
  ?unmatched:unmatched ->
  weighted_owner:weighted_source ->
  target_owner:Pdk_core.Attribute.owner ->
  attributes:spec list ->
  groups:group_spec list ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> (Pdk_core.Geometry.t, string) result
