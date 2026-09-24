open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let curve () = Sop.polyline
    [|(-2.2,-0.5,0.); (-1.8,0.65,0.); (-0.15,-0.3,0.);
      (0.35,0.8,0.); (2.1,-0.15,0.)|]

let graph ~equalized =
  let curve = curve () |> Sop.group_edges ~name:"uneven_edges" in
  let curve = if equalized then
      curve |> Sop.edge_equalize ~group:"uneven_edges"
        ~method_:Pdk.Ops.Equalize_average ~iterations:160 ~tolerance:1e-7
        ~output_group:"equalized_edges"
    else curve in
  curve
  |> Sop.polywire ~sides:10 ~caps:true ~radius:0.075
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
  |> Sop.set_color ~owner:Pdk.Attribute.Point
       (if equalized then Color.hex_exn "#38bdf8" else Color.hex_exn "#f97316")

let cook domains graph =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(64 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:17 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 0. 0.4 6.)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.) (-2.))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
      ~diffuse:Color.white ~intensity:0.65 ();
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
  let root = Filename.temp_file "prismel-edge-equalize-render-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one"
  and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "equalized-000000.png"
  and four_file = Filename.concat four "equalized-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Edge Equalize render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "equalized" 1 (graph ~equalized:true);
      render four "equalized" 4 (graph ~equalized:true);
      render control "control" 1 (graph ~equalized:false);
      let one_png = read_file one_file
      and four_png = read_file four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "Edge Equalize one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then
        failwith "Edge Equalize visual output equals the uneven control";
      if String.length one_png < 1_000 then
        failwith "Edge Equalize PNG is unexpectedly empty");
  print_endline "Edge Equalize render smoke passed"
