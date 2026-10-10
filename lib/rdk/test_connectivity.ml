open Rdk
open Rdk_test_support

let with_group owner name predicate geometry =
  let length = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group (Group.init ~grain:1 ~owner ~name length predicate) geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let shared_edge geometry =
  let topology = Geometry.topology geometry in
  let index = Topology_index.create topology in
  match Topology_index.find_edge index ~a:1 ~b:4 with
  | None -> fail "fixture has no shared edge"
  | Some shared ->
      Edge_group.init ~grain:1 ~topology ~index ~name:"seam"
        (fun edge -> edge = shared)

let with_uv name values geometry =
  let packed = Packed.Float2.of_owned
      ~x:(Array.map fst values) ~y:(Array.map snd values)
    |> function Ok packed -> packed | Error message -> fail message in
  let attribute = Attribute.create_owned ~name ~owner:Attribute.Vertex
      (Attribute.Float2 packed)
    |> function Ok attribute -> attribute | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let expect_error code = function
  | Error error -> check (Error.code error = code)
      (Printf.sprintf "expected error %S, got %S" code (Error.code error))
  | Ok _ -> fail ("expected error " ^ code)

let run () =
  print_endline "connectivity tests passed"
