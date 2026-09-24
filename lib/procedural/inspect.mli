(** Human-readable cooked geometry inspection without renderer access. *)

type attribute = {
  owner : Pdk.Attribute.owner;
  name : string;
  kind : string;
  length : int;
  data_id : int;
}

type group = {
  owner : Pdk.Group.owner;
  name : string;
  members : int;
  length : int;
  data_id : int;
}

type edge_group = {
  name : string;
  members : int;
  length : int;
  data_id : int;
}

type geometry = {
  data_id : int;
  points : int;
  vertices : int;
  primitives : int;
  payload_bytes : int;
  bounds : Pdk.Analysis.bounds option;
  attributes : attribute list;
  groups : group list;
  edge_groups : edge_group list;
}

type cook = {
  geometry : geometry;
  diagnostics : Diagnostic.t list;
  domains : int;
  grain : int;
  cache : Session.stats;
}

val geometry : Pdk.Geometry.t -> geometry
val output : Session.output -> geometry
val cook : context:Context.t -> session:Session.t -> Session.output -> cook
val format_geometry : geometry -> string
val format_output : Session.output -> string
val format_cook : cook -> string
