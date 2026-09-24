open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let source () =
  let curves = 19 and points_per_curve = 97 in
  let point_count = curves * points_per_curve in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        let local = point mod points_per_curve in
        -2.2 +. (4.4 *. float_of_int local /. float_of_int (points_per_curve - 1))))
      ~y:(Array.init point_count (fun point ->
        let curve = point / points_per_curve in
        -1.1 +. (2.2 *. float_of_int curve /. float_of_int (curves - 1))))
      ~z:(Array.init point_count (fun point ->
        let curve = point / points_per_curve
        and local = point mod points_per_curve in
        0.16 *. sin (float_of_int local *. 0.19 +. float_of_int curve *. 0.31))) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curves + 1) (fun primitive ->
        primitive * points_per_curve))
      ~primitive_kinds:(Array.make curves Pdk.Topology.Open_polyline)
      |> Result.get_ok in
  let signal = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"signal" (Pdk.Attribute.Float (Array.init point_count (fun point ->
        let curve = point / points_per_curve
        and local = point mod points_per_curve in
        sin (float_of_int local *. 0.31 +. float_of_int curve *. 0.23))))
      |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[signal] ()
  |> Result.get_ok

let cut_graph () = Sop.snapshot (source ())
    |> Sop.poly_cut ~element:Pdk.Ops.Poly_cut_points
         ~strategy:Pdk.Ops.Poly_cut_remove
         ~detection:(Pdk.Ops.Poly_cut_crossing {attribute="signal"; value=0.})
         ~keep_closed:false
    |> Sop.polywire ~sides:8 ~radius:0.025 ~caps:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")

let control_graph () = Sop.snapshot (source ())
    |> Sop.polywire ~sides:8 ~radius:0.025 ~caps:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:(96 * 1024 * 1024)
      |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:257 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 0. 0.3 5.2)
      ~target:Vec3.zero () in
  let lights = [
    Light.directional ~direction:(Vec3.create (-1.) (-1.5) (-2.))
      ~ambient:(Color.hex_exn "#1e293b") ();
    Light.directional ~direction:(Vec3.create 1. 0.5 (-1.))
      ~diffuse:(Color.hex_exn "#bae6fd") ~intensity:0.45 ();
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
  Sketch.export ~config ~directory ~prefix ~frames:1 (fun _ -> scene (cook domains graph))

let read_file filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-poly-cut-render-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one"
  and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "cut-000000.png"
  and four_file = Filename.concat four "cut-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "PolyCut render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "cut" 1 (cut_graph ());
      render four "cut" 4 (cut_graph ());
      render control "control" 1 (control_graph ());
      let one_png = read_file one_file
      and four_png = read_file four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "PolyCut one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then
        failwith "PolyCut visual output equals the uncut control";
      if String.length one_png < 1_000 then
        failwith "PolyCut PNG is unexpectedly empty");
  print_endline "PolyCut render smoke passed"
