open Rdk
open Rdk_test_support

let group owner name length members =
  let builder = Group.Builder.create ~owner ~name length in
  List.iter (fun member -> Group.Builder.set builder member true) members;
  Group.Builder.freeze builder

let add ~owner ~name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let vertex_points geometry =
  (Topology.Private.view (Geometry.topology geometry)).vertex_points

let int_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing attribute " ^ name)

let scale_source count =
  let count = count - (count mod 3) in
  let primitive_count = count / 3 in
  let topology = Topology.polygons_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id)
      ~primitive_offsets:(Array.init (primitive_count + 1) (fun primitive ->
        primitive * 3)) |> Result.get_ok in
  Geometry.create
    ~positions:(Packed.Float3.Private.of_owned_exn
      ~x:(Array.init count float_of_int) ~y:(Array.make count 0.)
      ~z:(Array.make count 0.)) ~topology () |> Result.get_ok
  |> add ~owner:Attribute.Point ~name:"target"
       (Attribute.Int (Array.init count (fun point ->
          if point mod 3 = 0 then point + 1 else -1)))

let test_parallel_exactness () =
  let geometry = scale_source 300_000 in
  let run domains = Rays.Parallel.run ~domains (fun () ->
    Rewire_vertices.run ~grain:257 ~keep_unused_points:true
      ~original_point_attribute:"orig" ~owner:Attribute.Point
      ~target_attribute:"target" geometry |> get_ok) in
  let one = run 1 and four = run 4 in
  check (vertex_points one = vertex_points four
      && int_attribute Attribute.Vertex "orig" one
         = int_attribute Attribute.Vertex "orig" four)
    "Rewire Vertices differs across domain counts";
  check (Geometry.point_count one = Geometry.point_count geometry
      && Geometry.primitive_count one = Geometry.primitive_count geometry)
    "Rewire Vertices scale cardinality"

let run () =
  test_parallel_exactness ();
  print_endline "Rewire Vertices tests passed"
