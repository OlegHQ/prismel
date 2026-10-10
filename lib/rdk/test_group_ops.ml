open Rdk
open Rdk_test_support

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok value -> value | Error message -> fail message

let with_group owner name members geometry =
  let count = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group
    (Group.init ~grain:1 ~owner ~name count (fun index -> members index))
    geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let group owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge_group name geometry =
  match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let int_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("non-integer attribute " ^ name))
  | None -> fail ("missing attribute " ^ name)

let same_group left right =
  Group.owner left = Group.owner right
  && Group.length left = Group.length right
  && let equal = ref true in
     for index = 0 to Group.length left - 1 do
       if Group.mem index left <> Group.mem index right then equal := false
     done;
     !equal
  && Group.ordered_elements left = Group.ordered_elements right

let same_edge_group left right =
  Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
     done;
     !equal

let expand ?name ?steps ?flood ?primitive_connectivity ?normal_spread
    ?normal_attribute ?connectivity_attributes ?connectivity_tolerance ?collision
    ~owner ~group geometry =
  Group_ops.expand ~grain:1 ?name ?steps ?flood ?primitive_connectivity
    ?normal_spread ?normal_attribute ?connectivity_attributes
    ?connectivity_tolerance ?collision ~owner ~group geometry |> get_ok

let run () =
  print_endline "group operation tests passed"
