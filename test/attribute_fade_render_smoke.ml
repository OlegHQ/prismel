open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let source () =
  let geometry = Pdk.Ops.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:64 ~rows:64 ~size:2. () |> Result.get_ok in
  let point_count = Pdk.Geometry.point_count geometry in
  let start = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"start"
      (Pdk.Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point mod 65) *. 0.15))) |> Result.get_ok in
  Pdk.Geometry.with_attribute start geometry |> Result.get_ok

let faded_graph () = Sop.snapshot (source ())
    |> Sop.attribute_fade ~start_attribute:"start" ~fade_in:2. ~fade_hold:2.
         ~fade_out:2. ~fade_in_ramp:[0.,0.;0.35,0.1;0.75,0.92;1.,1.]
         ~fade_out_ramp:[0.,1.;0.25,0.94;0.7,0.1;1.,0.] ~visualize:true
    |> Sop.peak ~mask_attribute:"fade" ~distance:0.5 ~recompute_normals:true

let control_graph () = Sop.snapshot (source ())
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2563eb")

let cook domains graph =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:(64 * 1024 * 1024)
      |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~frame:5L ~domains ~grain:257 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 2.8 2.3 3.2)
      ~target:(Vec3.create 0. 0.18 0.) () in
  let lights = [Light.directional ~direction:(Vec3.create (-1.) (-2.) (-1.))
      ~ambient:(Color.hex_exn "#334155") ()] in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 ~lights [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.create ~diffuse:Color.white ()) mesh;
    ]);
  ]

let render directory prefix domains graph =
  let config = { Sketch.default_config with width = 320; height = 240;
    domains = Some domains } in
  let mesh = cook domains graph in
  Sketch.export ~config ~directory ~prefix ~frames:1 (fun _ -> scene mesh)

let read_file filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-attribute-fade-render-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one"
  and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "fade-000000.png"
  and four_file = Filename.concat four "fade-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect
    ~finally:(fun () ->
      if keep then Printf.printf "attribute fade render artifacts: %s\n%!" root
      else begin
        List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
          [one_file;four_file;control_file];
        List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
          [one;four;control];
        if Sys.file_exists root then Unix.rmdir root
      end)
    (fun () ->
      render one "fade" 1 (faded_graph ());
      render four "fade" 4 (faded_graph ());
      render control "control" 1 (control_graph ());
      let one_png = read_file one_file
      and four_png = read_file four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "Attribute Fade one/four-domain framebuffer pixels differ";
      if String.equal one_png control_png then
        failwith "Attribute Fade visual output equals the unfaded control";
      if String.length one_png < 1_000 then
        failwith "Attribute Fade PNG is unexpectedly empty");
  print_endline "attribute fade render smoke passed"
