open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let surface () = Sop.grid ~columns:28 ~rows:18 ~size:4. ()

let graph mode =
  let source = surface () in
  let geometry = match mode with
    | `Source -> source
    | `Target -> source |> Sop.bend ~length:4. ~bend_angle:1.15
    | `Blend ->
        let target = surface () |> Sop.bend ~length:4. ~bend_angle:1.15 in
        source |> Sop.blend_shapes ~attributes:"^*"
          ~shapes:[Sop.blend_shape ~weight:0.58 target] in
  geometry
  |> Sop.normals ~owner:Pdk.Attribute.Vertex
  |> Sop.set_color ~owner:Pdk.Attribute.Point
      (match mode with
       | `Source -> Color.hex_exn "#f97316"
       | `Target -> Color.hex_exn "#a855f7"
       | `Blend -> Color.hex_exn "#22d3ee")

let cook domains graph =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(64 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:17 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.4 3.5 5.4)
      ~target:(Vec3.create 0. 0.25 0.) () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.) (-2.))
      ~ambient:(Color.hex_exn "#172554") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
      ~diffuse:Color.white ~intensity:0.75 ();
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
  let root = Filename.temp_file "prismel-blend-shapes-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and source = Filename.concat root "source"
  and target = Filename.concat root "target" in
  let one_file = Filename.concat one "blend-000000.png"
  and four_file = Filename.concat four "blend-000000.png"
  and source_file = Filename.concat source "source-000000.png"
  and target_file = Filename.concat target "target-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Blend Shapes render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;source_file;target_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one;four;source;target];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "blend" 1 (graph `Blend);
      render four "blend" 4 (graph `Blend);
      render source "source" 1 (graph `Source);
      render target "target" 1 (graph `Target);
      let one_png = read_file one_file and four_png = read_file four_file
      and source_png = read_file source_file and target_png = read_file target_file in
      if not (String.equal one_png four_png) then
        failwith "Blend Shapes one/four-domain framebuffer pixels differ";
      if String.equal one_png source_png || String.equal one_png target_png then
        failwith "Blend Shapes visual output equals an endpoint";
      if String.length one_png < 1_000 then
        failwith "Blend Shapes PNG is unexpectedly empty");
  print_endline "Blend Shapes render smoke passed"
