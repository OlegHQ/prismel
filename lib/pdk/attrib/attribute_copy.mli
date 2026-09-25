type match_mode =
    Cyclic
  | By_values of { source_attribute : string; target_attribute : string; }
  | To_element of { target_attribute : string; }
type rule = {
  copy_owner : Pdk_core.Attribute.owner;
  copy_pattern : string;
  copy_into : string option;
}
type payload = Position | Ordinary of Pdk_core.Attribute.t
type selected = {
  source_owner : Pdk_core.Attribute.owner;
  source_name : string;
  target_name : string;
  payload : payload;
}
type mapping_kind = No_match | Identity | General
type selector =
    Select of Pdk_core.Attribute_pattern.t
  | Rewrite of Pdk_core.Attribute_pattern.rewrite
module Int_table :
  sig
    type key = int
    type !'a t
    val create : int -> 'a t
    val clear : 'a t -> unit
    val reset : 'a t -> unit
    val copy : 'a t -> 'a t
    val add : 'a t -> key -> 'a -> unit
    val remove : 'a t -> key -> unit
    val find : 'a t -> key -> 'a
    val find_opt : 'a t -> key -> 'a option
    val find_all : 'a t -> key -> 'a list
    val replace : 'a t -> key -> 'a -> unit
    val mem : 'a t -> key -> bool
    val iter : (key -> 'a -> unit) -> 'a t -> unit
    val filter_map_inplace : (key -> 'a -> 'a option) -> 'a t -> unit
    val fold : (key -> 'a -> 'acc -> 'acc) -> 'a t -> 'acc -> 'acc
    val length : 'a t -> int
    val stats : 'a t -> Hashtbl.statistics
    val to_seq : 'a t -> (key * 'a) Seq.t
    val to_seq_keys : 'a t -> key Seq.t
    val to_seq_values : 'a t -> 'a Seq.t
    val add_seq : 'a t -> (key * 'a) Seq.t -> unit
    val replace_seq : 'a t -> (key * 'a) Seq.t -> unit
    val of_seq : (key * 'a) Seq.t -> 'a t
  end
module String_table :
  sig
    type key = string
    type !'a t
    val create : int -> 'a t
    val clear : 'a t -> unit
    val reset : 'a t -> unit
    val copy : 'a t -> 'a t
    val add : 'a t -> key -> 'a -> unit
    val remove : 'a t -> key -> unit
    val find : 'a t -> key -> 'a
    val find_opt : 'a t -> key -> 'a option
    val find_all : 'a t -> key -> 'a list
    val replace : 'a t -> key -> 'a -> unit
    val mem : 'a t -> key -> bool
    val iter : (key -> 'a -> unit) -> 'a t -> unit
    val filter_map_inplace : (key -> 'a -> 'a option) -> 'a t -> unit
    val fold : (key -> 'a -> 'acc -> 'acc) -> 'a t -> 'acc -> 'acc
    val length : 'a t -> int
    val stats : 'a t -> Hashtbl.statistics
    val to_seq : 'a t -> (key * 'a) Seq.t
    val to_seq_keys : 'a t -> key Seq.t
    val to_seq_values : 'a t -> 'a Seq.t
    val add_seq : 'a t -> (key * 'a) Seq.t -> unit
    val replace_seq : 'a t -> (key * 'a) Seq.t -> unit
    val of_seq : (key * 'a) Seq.t -> 'a t
  end
val owner_count : Pdk_core.Geometry.t -> Pdk_core.Attribute.owner -> int
val group_count : Pdk_core.Geometry.t -> Pdk_core.Group.owner -> int
val group_name : Pdk_core.Group.owner -> string
val owner_index : Pdk_core.Attribute.owner -> int
val selected_elements : int -> Pdk_core.Group.t option -> int array
val validate_group :
  label:string ->
  Pdk_core.Group.owner ->
  int -> Pdk_core.Group.t option -> (unit, string) result
val find_match_attribute :
  label:string ->
  owner:Pdk_core.Attribute.owner ->
  name:string -> Pdk_core.Geometry.t -> (Pdk_core.Attribute.t, string) result
val cyclic_mapping :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  source_elements:int array -> target_elements:int array -> int -> int array
val base_mapping :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  owner:Pdk_core.Group.owner ->
  match_:match_mode ->
  source_group:Pdk_core.Group.t option ->
  target_group:Pdk_core.Group.t option ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t ->
  unit -> (int array * int array, string) result
val compile_rule : rule -> (rule * selector, string) result
val select_attributes :
  allow_position:bool ->
  rules:rule list -> Pdk_core.Geometry.t -> (selected array, string) result
val related_count :
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view option ->
  Pdk_core.Group.owner -> Pdk_core.Attribute.owner -> int -> int
val related_element :
  Pdk_core.Topology.Private.view ->
  Pdk_core.Topology_index.Private.view option ->
  Pdk_core.Group.owner -> Pdk_core.Attribute.owner -> int -> int -> int
val projection_is_disjoint :
  Pdk_core.Group.owner -> Pdk_core.Attribute.owner -> bool
val project_mapping :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  base_owner:Pdk_core.Group.owner ->
  attribute_owner:Pdk_core.Attribute.owner ->
  base_mapping:int array ->
  target_elements:int array ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> int array
val same_storage_kind : Pdk_core.Attribute.t -> Pdk_core.Attribute.t -> bool
val initial_storage :
  Pdk_core.Attribute.t ->
  Pdk_core.Attribute.t option -> int -> Pdk_core.Attribute.storage
val copy_storage :
  ?cancel:Pdk_core.Cancel.t ->
  grain:int ->
  mapping:int array ->
  Pdk_core.Attribute.t ->
  Pdk_core.Attribute.storage -> Pdk_core.Attribute.storage
val classify_mapping :
  ?cancel:Pdk_core.Cancel.t -> source_count:int -> int array -> mapping_kind
val attribute_owner_of_group :
  Pdk_core.Group.owner -> Pdk_core.Attribute.owner
val install_identity_selection :
  source:Pdk_core.Geometry.t ->
  selected array ->
  Pdk_core.Geometry.t -> (Pdk_core.Geometry.t, string) result
val copy :
  ?cancel:Pdk_core.Cancel.t ->
  ?grain:int ->
  ?source_group:Pdk_core.Group.t ->
  ?target_group:Pdk_core.Group.t ->
  ?match_:match_mode ->
  ?allow_position:bool ->
  group_owner:Pdk_core.Group.owner ->
  rules:rule list ->
  source:Pdk_core.Geometry.t ->
  target:Pdk_core.Geometry.t -> unit -> (Pdk_core.Geometry.t, string) result
