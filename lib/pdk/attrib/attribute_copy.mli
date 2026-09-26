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
