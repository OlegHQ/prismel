open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let source () =
  let random_count = 96 and point_count = 100 in
  let points = Array.init point_count (fun point ->
      if point < random_count then begin
        let state = Rand.seed ((point * 37) + 11) in
        let x,state = Rand.float state in
        let y,_ = Rand.float state in
        (x *. 290.) +. 15.,(y *. 190.) +. 15.,0.
      end else match point - random_count with
        | 0 -> 20.,20.,0. | 1 -> 300.,20.,0.
        | 2 -> 300.,200.,0. | _ -> 20.,200.,0.) in
  let positions = Pdk.Geometry.positions (Pdk.Ops.points points) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:[|96;97;98;99; 96;98; 97;99|]
      ~primitive_offsets:[|0;4;6;8|]
      ~primitive_kinds:[|Pdk.Topology.Polygon;
        Pdk.Topology.Open_polyline;Pdk.Topology.Open_polyline|]
      |> Result.get_ok in
  let geometry = Pdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let constraints = Pdk.Group.init ~owner:Pdk.Group.Primitive
      ~name:"constraints" 3 (fun _ -> true) in
  let geometry = Pdk.Geometry.with_group constraints geometry |> Result.get_ok in
  Sop.snapshot geometry
  |> Sop.triangulate_2d ~projection:Pdk.Ops.Triangulate_2d_xy
      ~constraint_primitive_group:"constraints"
      ~split_crossing_constraints:true ~flood_from_hull_boundary:true
      ~remove_outside_constraint_polygons:true
      ~silhouette_constraints:true ~remove_outside_silhouette:true
      ~ignore_non_constraint_points:true ~remove_unused_points:true
      ~refine:true ~minimum_angle:(Float.pi /. 18.) ~maximum_area:1_500.
      ~maximum_new_points:96 ~regularization_steps:2
      ~split_point_group:"crossings"
      ~refinement_point_group:"refined"

let cook domains =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:4_000_000 |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:11 () |> get in
    match Session.cook session ~context (source ()) with
    | Ok output -> output.Session.geometry
    | Error error -> failwith (Diagnostic.error_to_string error))

let palette = [|
  Color.hex_exn "#164e63"; Color.hex_exn "#831843";
  Color.hex_exn "#713f12"; Color.hex_exn "#4c1d95" |]

let scene geometry =
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry)
  and topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  let triangles = List.init (Pdk.Geometry.primitive_count geometry) (fun primitive ->
      let vertex = topology.primitive_offsets.(primitive) in
      let point local =
        let point = topology.vertex_points.(vertex + local) in
        int_of_float positions.x.(point),int_of_float positions.y.(point) in
      Scene.triangle (point 0) (point 1) (point 2)
        ~fill:palette.(primitive mod Array.length palette)
        ~stroke:(Color.hex_exn "#67e8f9") ()) in
  Scene.clear (Color.hex_exn "#020617") :: triangles

let export directory prefix domains scene =
  let config = {Sketch.default_config with width=320; height=220;
    domains=Some domains} in
  Sketch.export ~config ~directory ~prefix ~frames:1 (fun _ -> scene)

let read filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value) ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-triangulate2d-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "triangulation-000000.png"
  and four_file = Filename.concat four "triangulation-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Triangulate 2D render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      let one_geometry = cook 1 and four_geometry = cook 4 in
      export one "triangulation" 1 (scene one_geometry);
      export four "triangulation" 4 (scene four_geometry);
      export control "control" 1 [Scene.clear (Color.hex_exn "#020617")];
      let one_png = read one_file and four_png = read four_file
      and control_png = read control_file in
      if one_png <> four_png then
        failwith "Triangulate 2D one/four-domain framebuffer differs";
      if one_png = control_png then
        failwith "Triangulate 2D framebuffer equals empty control";
      if String.length one_png < 1_000 then failwith "Triangulate 2D PNG is empty");
  print_endline "Triangulate 2D render smoke passed"
