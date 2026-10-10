open Rays
open Rdk
open Rdk_test_support

let owner_count geometry = function
  | Group.Point -> Geometry.point_count geometry
  | Group.Vertex -> Geometry.vertex_count geometry
  | Group.Primitive -> Geometry.primitive_count geometry

let with_group owner name predicate geometry =
  Geometry.with_group (Group.init ~grain:1 ~owner ~name
      (owner_count geometry owner) predicate) geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let with_int owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Int values)
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let group owner name geometry = match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge_group name geometry = match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let int_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("non-integer attribute " ^ name))
  | None -> fail ("missing attribute " ^ name)

let promote ?name ?keep_original ?output_attribute ?attributes ?tolerance
    ?include_unshared_edges ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~group geometry =
  Group_ops.group_promote_boundary ~grain:1 ?name ?keep_original ?output_attribute
    ?attributes ?tolerance ?include_unshared_edges
    ?include_all_unshared_curve_edges
    ?include_all_primitives_sharing_boundary_points
    ~source ~destination ~group geometry |> get_ok

let test_curve_unshared_policy () =
  let positions = [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.);
    (3., 0., 0.)|] in
  let geometry = Line_geometry.polyline ~closed:false positions |> get_ok
      |> with_group Group.Primitive "curve" (fun _ -> true) in
  let ends = promote ~keep_original:true ~include_unshared_edges:true
      ~name:"ends" ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
      ~group:"curve" geometry
  and all = promote ~keep_original:true ~include_unshared_edges:true
      ~include_all_unshared_curve_edges:true ~name:"all"
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
      ~group:"curve" geometry in
  check (Edge_group.cardinality (edge_group "ends" ends) = 2)
    "Group Promote Boundary open-curve endpoint policy";
  check (Edge_group.cardinality (edge_group "all" all) = 3)
    "Group Promote Boundary all open-curve edges policy"

let same_group left right =
  Bytes.equal (Group.Private.bits_view left) (Group.Private.bits_view right)

let same_edge_group left right =
  Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
     done;
     !equal

let test_parallel_exactness () =
  let base = Plane_generators.grid ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let source = with_group Group.Primitive "left_half"
      (fun primitive -> primitive mod 1_200 < 600) base in
  let run domains = Parallel.run ~domains (fun () ->
    source
    |> Group_ops.group_promote_boundary ~grain:1_009 ~keep_original:true
         ~include_unshared_edges:true ~name:"outline"
         ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
         ~group:"left_half" |> get_ok
    |> Group_ops.group_promote_boundary ~grain:1_009 ~keep_original:true
         ~include_unshared_edges:true ~name:"outline_points"
         ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_points
         ~group:"left_half" |> get_ok) in
  let one = run 1 and four = run 4 in
  check (same_edge_group (edge_group "outline" one) (edge_group "outline" four))
    "Group Promote Boundary edge output differs by domain count";
  check (same_group (group Group.Point "outline_points" one)
      (group Group.Point "outline_points" four))
    "Group Promote Boundary point output differs by domain count"

let run () =
  test_curve_unshared_policy ();
  test_parallel_exactness ();
  print_endline "group promote boundary tests passed"
