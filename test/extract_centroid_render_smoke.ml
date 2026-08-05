open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let marker = Sop.uv_sphere ~segments:12 ~rings:6 ~radius:0.16 ()
    |> Sop.normals ~owner:Pdk.Attribute.Vertex

let extracted_targets () =
  Sop.box ~size:(Vec3.create 2. 2. 2.) ~connectivity:Pdk.Ops.Box_quads
    ~consolidate_points:true ()
  |> Sop.extract_centroid ~run_over:Pdk.Ops.Centroid_primitives
    ~method_:Pdk.Ops.Centroid_bounding_box

let reference_targets () = Sop.points [|
  -1.,0.,0.; 1.,0.,0.; 0.,-1.,0.; 0.,1.,0.; 0.,0.,-1.; 0.,0.,1.
|]

let graph targets = Sop.copy_to_points ~source:marker ~targets ()

let cook domains node =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(16 * 1024 * 1024) |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:1 () |> get in
    match Bridge.cook_to_mesh session ~context node with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 3.4 2.8 4.2)
      ~target:Vec3.zero () in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit (Color.hex_exn "#f59e0b")) mesh])]

let render directory prefix domains node =
  let config = { Sketch.default_config with width = 320; height = 240;
    domains = Some domains } in
  let mesh = cook domains node in
  if Mesh.Private.triangle_count mesh <> 6 * 120 then
    failwith (Printf.sprintf "centroid marker fixture has %d triangles"
      (Mesh.Private.triangle_count mesh));
  Sketch.export ~config ~directory ~prefix ~frames:1 (fun _ -> scene mesh)

let read filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-extract-centroid-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and reference = Filename.concat root "reference" in
  let one_file = Filename.concat one "centers-000000.png"
  and four_file = Filename.concat four "centers-000000.png"
  and reference_file = Filename.concat reference "reference-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Extract Centroid render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;reference_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;reference];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "centers" 1 (graph (extracted_targets ()));
      render four "centers" 4 (graph (extracted_targets ()));
      render reference "reference" 1 (graph (reference_targets ()));
      let one_png = read one_file and four_png = read four_file
      and reference_png = read reference_file in
      if one_png <> four_png then
        failwith "Extract Centroid one/four-domain framebuffer differs";
      if one_png <> reference_png then
        failwith "Extract Centroid framebuffer differs from explicit centers";
      if String.length one_png < 1_000 then failwith "centroid PNG is empty");
  print_endline "Extract Centroid render smoke passed"
