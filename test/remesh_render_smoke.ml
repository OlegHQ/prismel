open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let sculpted_grid () =
  let geometry = Pdk.Ops.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:18 ~rows:14 ~size:4. () |> function
    | Ok value -> value
    | Error error -> failwith (Pdk.Error.to_string error) in
  let source = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  let x = Array.copy source.x and z = Array.copy source.z in
  let y = Array.init (Array.length x) (fun point ->
    0.34 *. sin (2.3 *. x.(point)) *. cos (1.8 *. z.(point))) in
  let geometry = Pdk.Geometry.with_positions
      (Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry
    |> Result.get_ok in
  let color = Pdk.Packed.Float4.of_owned
      ~x:(Array.init (Array.length x) (fun point -> 0.45 +. 0.1 *. x.(point)))
      ~y:(Array.init (Array.length x) (fun point -> 0.55 +. 0.08 *. z.(point)))
      ~z:(Array.make (Array.length x) 0.95)
      ~w:(Array.make (Array.length x) 1.) |> Result.get_ok in
  let color = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"Cd"
      (Pdk.Attribute.Float4 color) |> Result.get_ok in
  Pdk.Geometry.with_attribute color geometry |> Result.get_ok

let graph remeshed =
  let source = Sop.snapshot (sculpted_grid ()) in
  let source = if remeshed then source |> Sop.remesh ~target_length:0.16
      ~iterations:2 ~smoothing:0.45 ~project:true
      ~output_quality:"mesh_quality" else source in
  source |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:1.1

let cook domains graph =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(128 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:31 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.6 3.8 5.4)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.) (-2.))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.4 (-1.))
      ~diffuse:Color.white ~intensity:0.85 ();
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
  let root = Filename.temp_file "prismel-remesh-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and source = Filename.concat root "source" in
  let one_file = Filename.concat one "remesh-000000.png"
  and four_file = Filename.concat four "remesh-000000.png"
  and source_file = Filename.concat source "source-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Remesh render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;source_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one;four;source];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "remesh" 1 (graph true);
      render four "remesh" 4 (graph true);
      render source "source" 1 (graph false);
      let one_png = read_file one_file and four_png = read_file four_file
      and source_png = read_file source_file in
      if not (String.equal one_png four_png) then
        failwith "Remesh one/four-domain framebuffer pixels differ";
      if String.equal one_png source_png then
        failwith "Remesh visual output equals its source";
      if String.length one_png < 1_000 then
        failwith "Remesh PNG is unexpectedly empty");
  print_endline "Remesh render smoke passed"
