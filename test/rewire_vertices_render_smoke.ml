open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let sculpted_grid () =
  let columns = 36 and rows = 24 in
  let geometry = Pdk.Ops.grid
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns ~rows ~size:4. () |> function
    | Ok value -> value
    | Error error -> failwith (Pdk.Error.to_string error) in
  let source = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  let count = Pdk.Geometry.point_count geometry in
  let x = Array.copy source.x and z = Array.copy source.z
  and y = Array.init count (fun point ->
    0.42 *. sin (source.x.(point) *. 2.1)
    *. cos (source.z.(point) *. 1.7)) in
  let geometry = Pdk.Geometry.with_positions
      (Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry
    |> Result.get_ok in
  let width = columns + 1 in
  let selected point =
    let column = point mod width in
    column mod 5 = 1 && column + 2 <= columns in
  let target = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"targetpt" (Pdk.Attribute.Int (Array.init count (fun point ->
        if selected point then point + 2 else -1))) |> Result.get_ok
  and color = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"Cd"
      (Pdk.Attribute.Float4 (Pdk.Packed.Float4.of_owned
        ~x:(Array.init count (fun point ->
          0.25 +. 0.65 *. float_of_int (point mod width) /. float_of_int columns))
        ~y:(Array.init count (fun point ->
          0.2 +. 0.6 *. float_of_int (point / width) /. float_of_int rows))
        ~z:(Array.init count (fun point ->
          0.9 -. 0.5 *. float_of_int (point mod width) /. float_of_int columns))
        ~w:(Array.make count 1.) |> Result.get_ok)) |> Result.get_ok
  and group = Pdk.Group.init ~owner:Pdk.Group.Point ~name:"rewire_points"
      count selected in
  geometry |> Pdk.Geometry.with_attribute target |> Result.get_ok
  |> Pdk.Geometry.with_attribute color |> Result.get_ok
  |> Pdk.Geometry.with_group group |> Result.get_ok

let graph rewired =
  let source = Sop.snapshot (sculpted_grid ()) in
  let source = if rewired then
      source |> Sop.rewire_vertices
        ~selection:(Sop.Point_group "rewire_points")
        ~delete_target_attribute:true ~original_point_attribute:"origpt"
        ~owner:Pdk.Attribute.Point ~target_attribute:"targetpt"
    else source in
  source |> Sop.normals ~owner:Pdk.Attribute.Vertex

let cook domains graph =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(64 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:17 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.5 3.5 5.3)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.) (-2.))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
      ~diffuse:Color.white ~intensity:0.8 ();
  ] in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 ~lights [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.create ~diffuse:Color.white ()) mesh])]

let render directory prefix domains graph =
  let config = { Sketch.default_config with width = 360; height = 240;
    domains = Some domains } in
  Sketch.export ~config ~directory ~prefix ~frames:1
    (fun _ -> scene (cook domains graph))

let read_file filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-rewire-vertices-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and source = Filename.concat root "source" in
  let one_file = Filename.concat one "rewire-000000.png"
  and four_file = Filename.concat four "rewire-000000.png"
  and source_file = Filename.concat source "source-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Rewire Vertices render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;source_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one;four;source];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "rewire" 1 (graph true);
      render four "rewire" 4 (graph true);
      render source "source" 1 (graph false);
      let one_png = read_file one_file and four_png = read_file four_file
      and source_png = read_file source_file in
      if not (String.equal one_png four_png) then
        failwith "Rewire Vertices one/four-domain framebuffer pixels differ";
      if String.equal one_png source_png then
        failwith "Rewire Vertices visual output equals its source";
      if String.length one_png < 1_000 then
        failwith "Rewire Vertices PNG is unexpectedly empty");
  print_endline "Rewire Vertices render smoke passed"
