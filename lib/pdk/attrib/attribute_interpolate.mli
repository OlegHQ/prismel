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
val owner_count : Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val owner_name : Pdk_core.Attribute.owner -> string
val group_owner : Pdk_core.Attribute.owner -> Pdk_core.Group.owner option
val attribute_owner_of_group :
  Pdk_core.Group.owner -> Pdk_core.Attribute.owner
val bit_mem : bytes -> int -> bool
val bit_set : bytes -> int -> bool -> unit
val create_group_jobs :
  target_owner:Pdk_core.Attribute.owner ->
  target:Pdk_core.Geometry.t ->
  group_spec list -> (group_job array, string) result
val selection_elements :
  Pdk_core.Attribute.owner ->
  Pdk_core.Group.t option ->
  Pdk_core.Geometry.t -> (int * (int -> int), string) result
val source_storage :
  Pdk_core.Attribute.owner ->
  String.t ->
  Pdk_core.Geometry.t -> (Pdk_core.Attribute.storage, string) result
val target_storage :
  Pdk_core.Attribute.owner ->
  String.t -> Pdk_core.Geometry.t -> Pdk_core.Attribute.storage option
val kind_matches :
  Pdk_core.Attribute.storage -> Pdk_core.Attribute.storage -> bool
val copy_or_zero_float :
  int -> Pdk_core.Attribute.storage option -> float array
val copy_or_zero_int : int -> Pdk_core.Attribute.storage option -> int array
val copy_or_empty_text :
  int -> Pdk_core.Attribute.storage option -> string array
val create_job :
  target_owner:Pdk_core.Attribute.owner ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> spec -> (job, string) result
val polygon_weight : int -> float -> float -> int -> float
val curve_weight : closed:bool -> int -> float -> int -> float
val zero_numeric : job -> int -> unit
val add_numeric : job -> int -> int -> float -> unit
val set_discrete : job -> int -> int -> unit
val set_numeric : job -> int -> int -> unit
val is_numeric : job -> bool
val select_jobs : job array -> Pdk_core.Attribute.owner -> bool -> job array
val old_float : float array option -> int -> float
val blend_job : job -> int -> float -> unit
val default_job : job -> int -> unit
val array_offsets :
  ?cancel:Pdk_core.Cancel.t ->
  operation:string ->
  source_offsets:int array ->
  existing_offsets:int array option -> int array -> int array
val materialize_int_array :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Packed.Int_array.Private.view ->
  Pdk_core.Packed.Int_array.Private.view option ->
  int array -> Pdk_core.Packed.Int_array.t
val materialize_float_array :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  Pdk_core.Packed.Float_array.Private.view ->
  Pdk_core.Packed.Float_array.Private.view option ->
  int array -> Pdk_core.Packed.Float_array.t
val storage_of_job :
  ?cancel:Pdk_core.Cancel.t -> grain:int -> job -> Pdk_core.Attribute.storage
val groups_of_jobs : group_job array -> Pdk_core.Group.t array
val existing_group_value : group_job -> int -> float
val commit_group_score : group_job -> int -> blend:float -> float -> unit
val interpolate_primitive_groups :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  unmatched:unmatched ->
  blend:float ->
  pre_scale:float ->
  primitive_numbers:int array ->
  uvw:Pdk_core.Packed.Float3.Private.view ->
  topology:Pdk_core.Topology.Private.view ->
  primitive_count:int -> group_job array -> unit
val install :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  ?extra:Pdk_core.Attribute.t array ->
  ?groups:Pdk_core.Group.t array ->
  job array -> Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val compute_primitive_weights :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  unmatched:unmatched ->
  target_owner:Pdk_core.Attribute.owner ->
  computed:computed ->
  primitive_numbers:int array ->
  uvw:Pdk_core.Packed.Float3.Private.view ->
  pre_scale:float ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t ->
  unit -> (Pdk_core.Attribute.t array, string) result
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
val weighted_owner_name : weighted_source -> string
val weighted_source_count : Pdk_core.Geometry.t -> weighted_source -> int
val weighted_owner_supported :
  weighted_source -> Pdk_core.Attribute.owner -> bool
val interpolate_weighted_groups :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?selection:Pdk_core.Group.t ->
  unmatched:unmatched ->
  blend:float ->
  pre_scale:float ->
  normalize_weights:bool ->
  threshold:float ->
  weighted_owner:weighted_source ->
  numbers:Pdk_core.Packed.Int_array.Private.view ->
  weights:Pdk_core.Packed.Float_array.Private.view ->
  topology:Pdk_core.Topology.Private.view ->
  primitive_of_vertex:int array -> group_job array -> unit
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
