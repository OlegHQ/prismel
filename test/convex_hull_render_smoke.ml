open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let hull_graph () =
  Sop.points [|
    -1.,-1.,-1.; 1.,-1.,-1.; 1.,1.,-1.; -1.,1.,-1.;
    -1.,-1.,1.; 1.,-1.,1.; 1.,1.,1.; -1.,1.,1.;
    0.,0.,0.; 0.3,-0.2,0.1
  |]
  |> Sop.convex_hull
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.1

let box_graph () =
  Sop.box ~size:(Vec3.create 2. 2. 2.)
    ~connectivity:Pdk.Ops.Box_triangles ~consolidate_points:true ()
  |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.1

let cook domains graph =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(16 * 1024 * 1024) |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:2 () |> get in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 3.4 2.8 4.2)
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
        ~material:(Material.unlit (Color.hex_exn "#a5b4fc")) mesh])]

let render directory prefix domains graph =
  let config = { Sketch.default_config with width = 320; height = 240;
    domains = Some domains } in
  let mesh = cook domains graph in
  if Mesh.Private.triangle_count mesh <> 12 then
    failwith (Printf.sprintf "Convex Hull visual fixture has %d triangles"
      (Mesh.Private.triangle_count mesh));
  Sketch.export ~config ~directory ~prefix ~frames:1
    (fun _ -> scene mesh)

let read_file filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-convex-hull-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and reference = Filename.concat root "reference" in
  let one_file = Filename.concat one "hull-000000.png"
  and four_file = Filename.concat four "hull-000000.png"
  and reference_file = Filename.concat reference "box-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Convex Hull render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file; four_file; reference_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one; four; reference];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "hull" 1 (hull_graph ());
      render four "hull" 4 (hull_graph ());
      render reference "box" 1 (box_graph ());
      let one_png = read_file one_file and four_png = read_file four_file
      and reference_png = read_file reference_file in
      if not (String.equal one_png four_png) then
        failwith "Convex Hull one/four-domain framebuffer pixels differ";
      if not (String.equal one_png reference_png) then
        failwith "Convex Hull framebuffer differs from the explicit box reference";
      if String.length one_png < 1_000 then
        failwith "Convex Hull PNG is unexpectedly empty");
  print_endline "Convex Hull render smoke passed"
