open Prismel
open Pdk

let get = function Ok value -> value | Error error ->
  failwith (Error.to_string error)

let check condition message = if not condition then failwith message

let snapshot geometry =
  let positions = Geometry.positions geometry
  and topology = Geometry.topology geometry in
  let payload attribute =
    match Attribute.storage attribute with
    | Attribute.Float2 values ->
        Array.init (Packed.Float2.length values) (fun index ->
          let x, y = Packed.Float2.get values index in [x; y])
    | Attribute.Float3 values ->
        Array.init (Packed.Float3.length values) (fun index ->
          let x, y, z = Packed.Float3.get values index in [x; y; z])
    | Attribute.Float4 values ->
        Array.init (Packed.Float4.length values) (fun index ->
          let x, y, z, w = Packed.Float4.get values index in [x; y; z; w])
    | _ -> failwith "unexpected subdivision attribute" in
  Array.init (Geometry.point_count geometry) (Packed.Float3.get positions),
  Array.init (Geometry.vertex_count geometry)
    (Topology.point_of_vertex topology),
  Array.of_list (List.map (fun attribute ->
    Attribute.name attribute, payload attribute)
    (Geometry.attributes geometry))

let run () =
  let open_triangle =
    Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0; 1; 2]
      ~colors:[Color.red; Color.green; Color.blue]
      ~tex_coords:[Vec2.create 0. 0.; Vec2.create 1. 0.;
                   Vec2.create 0. 1.]
      [Vec3.create 0. 0. 0.; Vec3.create 1. 0. 0.;
       Vec3.create 0. 1. 0.]
    |> Pdk_prismel.Prismel_mesh.of_mesh |> get in
  let closed =
    Mesh.icosahedron ~radius:1.
    |> Pdk_prismel.Prismel_mesh.of_mesh |> get in
  let verify name operation source points triangles =
    let run domains = Parallel.run ~domains (fun () ->
      operation source |> get) in
    let one = run 1 and four = run 4 in
    check (Geometry.point_count one = points) (name ^ " point count");
    check (Geometry.primitive_count one = triangles) (name ^ " face count");
    check (snapshot one = snapshot four) (name ^ " domain parity")
  in
  verify "Butterfly open" Subdivision_extra.butterfly open_triangle 6 4;
  verify "Doo-Sabin open" Subdivision_extra.doo_sabin open_triangle 3 1;
  verify "Butterfly closed" Subdivision_extra.butterfly closed 42 80;
  verify "Doo-Sabin closed" Subdivision_extra.doo_sabin closed 60 116;
  let unsupported = Geometry.with_group
      (Group.ordered ~owner:Group.Point ~name:"marked" ~length:3 [|0|]
        |> Result.get_ok) open_triangle |> Result.get_ok in
  (match Subdivision_extra.butterfly unsupported with
   | Error _ -> () | Ok _ -> failwith "Butterfly silently dropped point group");
  let empty = Geometry.create
      ~positions:(Packed.Float3.of_owned ~x:[||] ~y:[||] ~z:[||]
        |> Result.get_ok)
      ~topology:(Topology.empty ~point_count:0) ()
    |> Result.get_ok in
  (match Subdivision_extra.butterfly empty with
   | Error _ -> () | Ok _ -> failwith "empty Butterfly input accepted");
  (match Subdivision_extra.doo_sabin empty with
   | Error _ -> () | Ok _ -> failwith "empty Doo-Sabin input accepted");
  let cancel = Cancel.create () in
  Cancel.cancel cancel;
  (match Subdivision_extra.butterfly ~cancel closed with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled Butterfly succeeded");
  (match Subdivision_extra.doo_sabin ~cancel closed with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> failwith "cancelled Doo-Sabin succeeded");
  print_endline "PDK Butterfly/Doo-Sabin fixtures passed"
