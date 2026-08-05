open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let box piece color x =
  Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
    ~normals:Pdk.Ops.Box_vertex_normals ~size:(Vec3.create 0.9 0.9 0.9) ()
  |> Sop.transform (Mat4.translation (Vec3.create x 0. 0.))
  |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"piece" piece
  |> Sop.set_color ~owner:Pdk.Attribute.Point color

let source_graph () = Sop.merge [
    box 10 (Color.hex_exn "#38bdf8") (-0.12);
    box 20 (Color.hex_exn "#f97316") 0.;
    box 30 (Color.hex_exn "#a3e635") 0.12;
  ]

let separated_graph () = source_graph ()
    |> Sop.separate_pieces ~owner:Pdk.Attribute.Primitive
         ~piece_attribute:"piece" ~translation_attribute:"separation"
         ~axis:Vec3.unit_x ~gap:0.28

let cook domains graph =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(64 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:257 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 2.0 2.6 5.2)
      ~target:(Vec3.create 1.0 0. 0.) () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
      ~ambient:(Color.hex_exn "#1e293b") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
      ~diffuse:(Color.hex_exn "#f8fafc") ~intensity:0.5 ();
  ] in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 ~lights [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.create ~diffuse:Color.white ()) mesh;
    ]);
  ]

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
  let root = Filename.temp_file "prismel-separate-pieces-render-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one"
  and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "separate-000000.png"
  and four_file = Filename.concat four "separate-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Separate Pieces render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "separate" 1 (separated_graph ());
      render four "separate" 4 (separated_graph ());
      render control "control" 1 (source_graph ());
      let one_png = read_file one_file
      and four_png = read_file four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "Separate Pieces one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then
        failwith "Separate Pieces visual output equals the overlapping control";
      if String.length one_png < 1_000 then
        failwith "Separate Pieces PNG is unexpectedly empty");
  print_endline "Separate Pieces render smoke passed"
