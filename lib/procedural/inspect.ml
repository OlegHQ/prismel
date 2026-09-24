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

let attribute value = {
  owner = Pdk.Attribute.owner value;
  name = Pdk.Attribute.name value;
  kind = Pdk.Attribute.kind_name value;
  length = Pdk.Attribute.length value;
  data_id = Pdk.Attribute.data_id value;
}

let group value = {
  owner = Pdk.Group.owner value;
  name = Pdk.Group.name value;
  members = Pdk.Group.cardinality value;
  length = Pdk.Group.length value;
  data_id = Pdk.Group.data_id value;
}

let edge_group value = {
  name = Pdk.Edge_group.name value;
  members = Pdk.Edge_group.cardinality value;
  length = Pdk.Edge_group.length value;
  data_id = Pdk.Edge_group.data_id value;
}

let geometry value = {
  data_id = Pdk.Geometry.data_id value;
  points = Pdk.Geometry.point_count value;
  vertices = Pdk.Geometry.vertex_count value;
  primitives = Pdk.Geometry.primitive_count value;
  payload_bytes = Pdk.Geometry.payload_bytes value;
  bounds = Pdk.Analysis.bounds value;
  attributes = List.map attribute (Pdk.Geometry.attributes value);
  groups = List.map group (Pdk.Geometry.groups value);
  edge_groups = List.map edge_group (Pdk.Geometry.edge_groups value);
}

let output value = geometry value.Session.geometry
let cook ~context ~session value = {
  geometry = output value;
  diagnostics = value.Session.diagnostics;
  domains = Context.domains context;
  grain = Context.grain context;
  cache = Session.stats session;
}

let attribute_owner = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Detail -> "detail"

let group_owner = function
  | Pdk.Group.Point -> "point"
  | Pdk.Group.Vertex -> "vertex"
  | Pdk.Group.Primitive -> "primitive"

let format_geometry value =
  let buffer = Buffer.create 256 in
  Printf.bprintf buffer "geometry #%d: %d points, %d vertices, %d primitives, %d bytes\n"
    value.data_id value.points value.vertices value.primitives value.payload_bytes;
  (match value.bounds with
   | None -> Buffer.add_string buffer "bounds: empty\n"
   | Some bounds -> Printf.bprintf buffer
       "bounds: min=(%g,%g,%g) max=(%g,%g,%g)\n"
       bounds.min.Prismel.Vec3.x bounds.min.y bounds.min.z
       bounds.max.x bounds.max.y bounds.max.z);
  List.iter (fun (attribute : attribute) -> Printf.bprintf buffer
    "attribute %s %s: %s[%d] #%d\n" (attribute_owner attribute.owner)
    attribute.name attribute.kind attribute.length attribute.data_id) value.attributes;
  List.iter (fun (group : group) -> Printf.bprintf buffer
    "group %s %s: %d/%d #%d\n" (group_owner group.owner) group.name
    group.members group.length group.data_id) value.groups;
  List.iter (fun (group : edge_group) -> Printf.bprintf buffer
    "edge group %s: %d/%d #%d\n" group.name group.members group.length
    group.data_id) value.edge_groups;
  Buffer.contents buffer

let format_output value = format_geometry (output value)

let format_cook value =
  let buffer = Buffer.create 384 in
  Buffer.add_string buffer (format_geometry value.geometry);
  Printf.bprintf buffer
    "cook: domains=%d grain=%d diagnostics=%d hits=%d misses=%d retained=%d bytes\n"
    value.domains value.grain (List.length value.diagnostics) value.cache.hits
    value.cache.misses value.cache.retained_payload_bytes;
  (match value.cache.last_node with
   | None -> ()
   | Some timing -> Printf.bprintf buffer "last: %s (%s) %.6fs cache_hit=%b\n"
       timing.label timing.operation timing.seconds timing.cache_hit);
  Buffer.contents buffer
