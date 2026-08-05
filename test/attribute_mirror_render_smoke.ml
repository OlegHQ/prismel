open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let asymmetric_surface () =
  let geometry = Pdk.Ops.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:36 ~rows:24 ~size:4. () |> function
    | Ok value -> value
    | Error error -> failwith (Pdk.Error.to_string error) in
  let positions = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions geometry) in
  let count = Pdk.Geometry.point_count geometry in
  let red = Array.make count 0. and green = Array.make count 0.
  and blue = Array.make count 0. and alpha = Array.make count 1. in
  for point = 0 to count - 1 do
    if positions.x.(point) < 0. then begin
      let stripe = 0.5 +. (0.5 *. sin (positions.z.(point) *. 8.)) in
      red.(point) <- 0.95;
      green.(point) <- 0.18 +. (0.55 *. stripe);
      blue.(point) <- 0.08 +. (0.16 *. stripe)
    end else begin
      red.(point) <- 0.03;
      green.(point) <- 0.05;
      blue.(point) <- 0.08
    end
  done;
  let color = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"Cd"
      (Pdk.Attribute.Float4 (Pdk.Packed.Float4.of_owned
        ~x:red ~y:green ~z:blue ~w:alpha |> Result.get_ok)) |> Result.get_ok in
  Pdk.Geometry.with_attribute color geometry |> Result.get_ok

let graph mirrored =
  let source = Sop.snapshot (asymmetric_surface ()) in
  let source = if mirrored then
      source |> Sop.attribute_mirror
        ~owner:Pdk.Ops.Mirror_point_attributes
        ~method_:(Sop.Attribute_mirror_plane {
          origin = Vec3.zero; normal = Vec3.unit_x;
          distance = 0.; tolerance = 1e-10 })
        ~attributes:"Cd"
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
  let camera = Camera.perspective ~at:(Vec3.create 4.5 3.4 5.2)
      ~target:Vec3.zero () in
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
  let root = Filename.temp_file "prismel-attribute-mirror-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and source = Filename.concat root "source" in
  let one_file = Filename.concat one "mirror-000000.png"
  and four_file = Filename.concat four "mirror-000000.png"
  and source_file = Filename.concat source "source-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Attribute Mirror render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;source_file];
      List.iter (fun directory -> if Sys.file_exists directory then
        Unix.rmdir directory) [one;four;source];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "mirror" 1 (graph true);
      render four "mirror" 4 (graph true);
      render source "source" 1 (graph false);
      let one_png = read_file one_file and four_png = read_file four_file
      and source_png = read_file source_file in
      if not (String.equal one_png four_png) then
        failwith "Attribute Mirror one/four-domain framebuffer pixels differ";
      if String.equal one_png source_png then
        failwith "Attribute Mirror visual output equals its asymmetric input";
      if String.length one_png < 1_000 then
        failwith "Attribute Mirror PNG is unexpectedly empty");
  print_endline "Attribute Mirror render smoke passed"
