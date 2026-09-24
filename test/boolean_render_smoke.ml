open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let source_raw () =
  Sop.box ~size:(Vec3.create 2.8 2.2 2.2)
    ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
    ~normals:Pdk.Ops.Box_no_normals ()
  |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")

let source () = source_raw ()
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:1.0

let boolean_graph () =
  let left = source_raw ()
  and right = Sop.box ~size:(Vec3.create 2.2 1.15 1.15)
      ~center:(Vec3.create 0.85 0. 0.)
      ~rotation:(Vec3.create 0.35 0.42 0.12)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals () in
  Sop.boolean ~operation:Pdk.Boolean.Difference
    ~detriangulation:Pdk.Boolean.All_polygons ~right left
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:1.0

let cook domains graph =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(96 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:1 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.6 3.5 5.2)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-0.8) (-1.2) (-1.6))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.4 (-1.))
      ~diffuse:Color.white ~intensity:0.65 ();
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
  let root = Filename.temp_file "prismel-boolean-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and source_dir = Filename.concat root "source" in
  let one_file = Filename.concat one "boolean-000000.png"
  and four_file = Filename.concat four "boolean-000000.png"
  and source_file = Filename.concat source_dir "source-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Boolean render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file; four_file; source_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one; four; source_dir];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "boolean" 1 (boolean_graph ());
      render four "boolean" 4 (boolean_graph ());
      render source_dir "source" 1 (source ());
      let one_png = read_file one_file and four_png = read_file four_file
      and source_png = read_file source_file in
      if not (String.equal one_png four_png) then
        failwith "Boolean one/four-domain framebuffer pixels differ";
      if String.equal one_png source_png then
        failwith "Boolean visual output equals its unsubtracted source";
      if String.length one_png < 1_000 then
        failwith "Boolean PNG is unexpectedly empty");
  print_endline "Boolean render smoke passed"
