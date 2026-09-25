open Prismel
open Pdk

let get = function Ok value -> value
  | Error error -> failwith (Error.to_string error)
let check condition message = if not condition then failwith message

let snapshot geometry =
  let positions = Geometry.positions geometry
  and topology = Geometry.topology geometry in
  Array.init (Geometry.point_count geometry) (Packed.Float3.get positions),
  Array.init (Geometry.vertex_count geometry)
    (Topology.point_of_vertex topology)

let to_geometry mesh = Pdk_prismel.Prismel_mesh.of_mesh mesh |> get

let run () =
  let closed = Mesh.icosahedron ~radius:1. |> to_geometry in
  let report = Repair_mesh.analyze closed |> get in
  check (report.faces = 20 && report.components = 1
    && Repair_mesh.is_closed report && Repair_mesh.is_manifold report)
    "closed manifold report";
  let open_triangle =
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0; 1; 2]
      [Vec3.create 0. 0. 0.; Vec3.create 2. 0. 0.;
       Vec3.create 0. 2. 0.; Vec3.create 1. 0. 0.;
       Vec3.create 1. 1. 0.; Vec3.create 0. 1. 0.]
    |> to_geometry in
  let run domains = Parallel.run ~domains (fun () ->
    Repair_mesh.repair_t_junctions open_triangle |> get) in
  let one = run 1 and four = run 4 in
  check (snapshot one = snapshot four) "T-junction domain parity";
  let _, indices = snapshot one in
  check (Array.to_list indices = [2; 5; 3; 5; 0; 3; 1; 4; 3; 4; 2; 3])
    "T-junction ordered baseline";
  check (Geometry.primitive_count one = 4) "T-junction cardinality";
  let point_group = Group.ordered ~owner:Group.Point ~name:"marked"
      ~length:(Geometry.point_count open_triangle) [|0; 3|]
    |> Result.get_ok in
  let grouped = Geometry.with_group point_group open_triangle
    |> Result.get_ok in
  let grouped_output = Repair_mesh.repair_t_junctions grouped |> get in
  check (Geometry.find_group ~owner:Group.Point "marked" grouped_output
    |> Option.map Group.ordered_elements
    = Some (Some [|0; 3|])) "repair lost point group";
  let primitive_group = Group.ordered ~owner:Group.Primitive
      ~name:"unsupported" ~length:1 [|0|] |> Result.get_ok in
  let unsupported = Geometry.with_group primitive_group open_triangle
    |> Result.get_ok in
  (match Repair_mesh.repair_t_junctions unsupported with
   | Error _ -> () | Ok _ -> failwith "repair silently dropped primitive group");
  let flipped_mesh =
    let mesh = Mesh.icosahedron ~radius:1. in
    let indices = Mesh.indices mesh in
    let reversed = match indices with
      | a :: b :: c :: rest -> a :: c :: b :: rest
      | _ -> assert false in
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:reversed
      (Mesh.vertices mesh) in
  let flipped = to_geometry flipped_mesh in
  let orient domains = Parallel.run ~domains (fun () ->
    Repair_mesh.orient_consistently flipped |> get) in
  let oriented = orient 1 in
  check (snapshot oriented = snapshot (orient 4))
    "orientation domain parity";
  check (Geometry.primitive_count oriented = 20)
    "orientation cardinality";
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Repair_mesh.analyze ~cancel closed with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled report succeeded");
  (match Repair_mesh.repair_t_junctions ~cancel open_triangle with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled T-junction repair succeeded");
  (match Repair_mesh.orient_consistently ~cancel closed with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled orientation succeeded");
  (match Repair_mesh.repair_t_junctions ~epsilon:0. open_triangle with
   | Error _ -> () | Ok _ -> failwith "zero T-junction epsilon accepted");
  let points = Mesh.create_exn ~mode:Mesh.Points [Vec3.zero]
    |> to_geometry in
  (match Repair_mesh.orient_consistently points with
   | Error _ -> () | Ok _ -> failwith "empty orientation accepted");
  print_endline "PDK mesh repair fixtures passed"
