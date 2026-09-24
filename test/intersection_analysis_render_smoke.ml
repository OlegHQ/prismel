open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let panels () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:48 ~rows:36 ~size:4. () in
  let collision = source
      |> Sop.transform (Mat4.rotation_x (Float.pi /. 2.45)) in
  source, collision

let curves () =
  let source = Sop.polyline [|-2.2,1.25,1.1; 2.2,1.25,1.1|]
  and collision = Sop.polyline [|0.,-1.6,1.1; 0.,2.3,1.1|] in
  source, collision

let surfaces () =
  let source, collision = panels () in
  Sop.merge [
    source |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#1e3a8a");
    collision |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#0f766e")]

let markers points =
  let marker = Sop.uv_sphere ~connectivity:Pdk.Ops.Sphere_triangles
      ~segments:8 ~rings:5 ~radius:0.055 ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb923c") in
  Sop.copy_to_points ~source:marker ~targets:points ()

let surface_analyzed_graph () =
  let source, collision = panels () in
  let points = Sop.intersection_analysis ~collision ~include_coplanar:false
      source in
  Sop.merge [surfaces (); markers points]

let curve_analyzed_graph () =
  let source, collision = curves () in
  let points = Sop.intersection_analysis ~collision source in
  Sop.merge [surfaces (); markers points]

let cook domains graph =
  let session = Session.create ~max_entries:12
      ~max_payload_bytes:(128 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:127 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.8 3.8 5.6)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
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
  let root = Filename.temp_file "prismel-intersection-analysis-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and curve_one = Filename.concat root "curve-one"
  and curve_four = Filename.concat root "curve-four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "analysis-000000.png"
  and four_file = Filename.concat four "analysis-000000.png"
  and curve_one_file = Filename.concat curve_one "curve-000000.png"
  and curve_four_file = Filename.concat curve_four "curve-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Intersection Analysis render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file; four_file; curve_one_file; curve_four_file; control_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one; four; curve_one; curve_four; control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "analysis" 1 (surface_analyzed_graph ());
      render four "analysis" 4 (surface_analyzed_graph ());
      render curve_one "curve" 1 (curve_analyzed_graph ());
      render curve_four "curve" 4 (curve_analyzed_graph ());
      render control "control" 1 (surfaces ());
      let one_png = read_file one_file and four_png = read_file four_file
      and curve_one_png = read_file curve_one_file
      and curve_four_png = read_file curve_four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then failwith
          "Intersection Analysis one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then failwith
          "Intersection Analysis marker output equals its control";
      if not (String.equal curve_one_png curve_four_png) then failwith
          "Intersection Analysis curve one/four-domain framebuffer pixels differ";
      if String.equal curve_one_png control_png then failwith
          "Intersection Analysis curve marker output equals its control";
      if String.length one_png < 1_000 then failwith
          "Intersection Analysis PNG is unexpectedly empty");
  print_endline "Intersection Analysis render smoke passed"
