open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let source () =
  let rows = 3 and columns = 5 in
  let point_count = rows * columns in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        Float.of_int ((point mod columns) - 2)))
      ~y:(Array.init point_count (fun point ->
        Float.of_int ((point / columns) - 1)))
      ~z:(Array.make point_count 0.) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (rows + 1) (fun row -> row * columns))
      ~primitive_kinds:(Array.make rows Pdk.Topology.Open_polyline)
      |> Result.get_ok in
  let values = [|-1.;1.;0.;-1.;1.|] in
  let signal = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"signal" (Pdk.Attribute.Float (Array.init point_count
        (fun point -> values.(point mod columns)))) |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[signal] ()
  |> Result.get_ok

let extracted_targets () = Sop.snapshot (source ())
    |> Sop.extract_point_from_curve ~distance_attribute:"signal"

let reference_targets () = Sop.points [|
  -1.5,-1.,0.; 0.,-1.,0.; 1.5,-1.,0.;
  -1.5,0.,0.; 0.,0.,0.; 1.5,0.,0.;
  -1.5,1.,0.; 0.,1.,0.; 1.5,1.,0.
|]

let marker = Sop.uv_sphere ~segments:12 ~rings:6 ~radius:0.13 ()
    |> Sop.normals ~owner:Pdk.Attribute.Vertex

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
  let camera = Camera.perspective ~at:(Vec3.create 0. 0. 6.)
      ~target:Vec3.zero () in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit (Color.hex_exn "#22d3ee")) mesh])]

let render directory prefix domains node =
  let config = { Sketch.default_config with width = 320; height = 240;
    domains = Some domains } in
  let mesh = cook domains node in
  if Mesh.Private.triangle_count mesh <> 9 * 120 then
    failwith (Printf.sprintf "extract marker fixture has %d triangles"
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
  let root = Filename.temp_file "prismel-extract-point-curve-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and reference = Filename.concat root "reference" in
  let one_file = Filename.concat one "cuts-000000.png"
  and four_file = Filename.concat four "cuts-000000.png"
  and reference_file = Filename.concat reference "reference-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Extract Point from Curve render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;reference_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;reference];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "cuts" 1 (graph (extracted_targets ()));
      render four "cuts" 4 (graph (extracted_targets ()));
      render reference "reference" 1 (graph (reference_targets ()));
      let one_png = read one_file and four_png = read four_file
      and reference_png = read reference_file in
      if one_png <> four_png then
        failwith "Extract Point from Curve one/four-domain framebuffer differs";
      if one_png <> reference_png then
        failwith "Extract Point from Curve differs from explicit cut positions";
      if String.length one_png < 1_000 then failwith "extract-point PNG is empty");
  print_endline "Extract Point from Curve render smoke passed"
