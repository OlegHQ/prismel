type minimize = Two_point_distance | Three_point_distance
type output = Triangles | Polygons

val run :
  ?cancel:Cancel.t ->
  ?grain:int ->
  ?primitives:Group.t ->
  ?rest:Geometry.t ->
  ?connect_closest_ends:bool ->
  ?minimize:minimize ->
  ?u_wrap:bool ->
  ?v_wrap:bool ->
  ?keep_primitives:bool ->
  ?output_group:string ->
  ?collinearity_tolerance:float ->
  ?recompute_normals:bool ->
  ?output:output ->
  ?operation:string ->
  Geometry.t ->
  (Geometry.t, string) result

module Private : sig
  type plan

  val build_polygon_plan_indexed :
    ?cancel:Cancel.t ->
    connect_closest:bool ->
    minimize:minimize ->
    tolerance:float ->
    Packed.Float3.Private.view ->
    Topology.Private.view ->
    a_vertices:int array ->
    a_primitive:int ->
    a_closed:bool ->
    b_vertices:int array ->
    b_primitive:int ->
    b_closed:bool ->
    pairing_shift:int ->
    plan
  val corners : plan -> int array
  val arity : plan -> int
  val primitive_count : plan -> int
  val corner_count : plan -> int
  val source_primitive : plan -> int

  val align_indexed :
    ?cancel:Cancel.t ->
    connect_closest:bool ->
    Packed.Float3.Private.view ->
    Topology.Private.view ->
    a_vertices:int array ->
    a_primitive:int ->
    a_closed:bool ->
    b_vertices:int array ->
    b_primitive:int ->
    b_closed:bool ->
    pairing_shift:int ->
    int array * int array
end
