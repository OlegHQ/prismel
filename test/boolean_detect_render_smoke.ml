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

let detected_graph () =
  let source, collision = panels () in
  let detected = Sop.boolean_detect ~collision ~include_coplanar:false
      ~intersecting_group:(Some "crossing_faces") source in
  let regular = detected
      |> Sop.blast ~owner:Pdk.Group.Primitive ~group:"crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2563eb")
  and crossing = detected
      |> Sop.blast ~selected:false ~owner:Pdk.Group.Primitive
           ~group:"crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
  and collision = collision
      |> Sop.group ~name:"crossing_faces" Select.all_primitives
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#14b8a6") in
  Sop.merge [regular; crossing; collision]

let control_graph () =
  let source, collision = panels () in
  Sop.merge [
    source |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#2563eb");
    collision |> Sop.set_color ~owner:Pdk.Attribute.Point
      (Color.hex_exn "#14b8a6")]

let self_detected_graph () =
  let source, collision = panels () in
  let detected = Sop.merge [source; collision]
      |> Sop.boolean_detect ~include_coplanar:false
           ~self_intersecting_group:(Some "self_crossing_faces") in
  let regular = detected
      |> Sop.blast ~owner:Pdk.Group.Primitive ~group:"self_crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2563eb")
  and crossing = detected
      |> Sop.blast ~selected:false ~owner:Pdk.Group.Primitive
           ~group:"self_crossing_faces"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316") in
  Sop.merge [regular; crossing]

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
  let root = Filename.temp_file "prismel-boolean-detect-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and self_one = Filename.concat root "self-one"
  and self_four = Filename.concat root "self-four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "detect-000000.png"
  and four_file = Filename.concat four "detect-000000.png"
  and self_one_file = Filename.concat self_one "self-000000.png"
  and self_four_file = Filename.concat self_four "self-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Boolean Detect render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file; four_file; self_one_file; self_four_file; control_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one; four; self_one; self_four; control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "detect" 1 (detected_graph ());
      render four "detect" 4 (detected_graph ());
      render self_one "self" 1 (self_detected_graph ());
      render self_four "self" 4 (self_detected_graph ());
      render control "control" 1 (control_graph ());
      let one_png = read_file one_file and four_png = read_file four_file
      and self_one_png = read_file self_one_file
      and self_four_png = read_file self_four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "Boolean Detect one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then
        failwith "Boolean Detect visual output equals its control";
      if not (String.equal self_one_png self_four_png) then
        failwith "Boolean Detect AxA one/four-domain framebuffer pixels differ";
      if String.equal self_one_png control_png then
        failwith "Boolean Detect AxA visual output equals its control";
      if String.length one_png < 1_000 then
        failwith "Boolean Detect PNG is unexpectedly empty");
  print_endline "Boolean Detect render smoke passed"
