open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let graph ~transported ~direction =
  let surface = Sop.grid ~columns:25 ~rows:15 ~size:4. () in
  let surface = if transported then
      surface
      |> Sop.edge_transport ~direction ~operation:Pdk.Ops.Transport_total
           ~integrate_constant:true ~scale_by_edge_length:true
           ~normalization:Pdk.Ops.Transport_normalize_global
           ~attribute:"distance"
      |> Sop.peak ~mask_attribute:"distance" ~distance:0.85
           ~recompute_normals:true
    else surface in
  surface
  |> Sop.normals ~owner:Pdk.Attribute.Vertex
  |> Sop.set_color ~owner:Pdk.Attribute.Point
       (if transported then Color.hex_exn "#22d3ee" else Color.hex_exn "#f97316")

let cook domains graph =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(64 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:17 () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 4.2 3.4 5.2)
      ~target:(Vec3.create 0. 0.35 0.) () in
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
  let root = Filename.temp_file "prismel-edge-transport-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "forward-one"
  and four = Filename.concat root "forward-four"
  and backward_one = Filename.concat root "backward-one"
  and backward_four = Filename.concat root "backward-four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "forward-000000.png"
  and four_file = Filename.concat four "forward-000000.png"
  and backward_one_file = Filename.concat backward_one "backward-000000.png"
  and backward_four_file = Filename.concat backward_four "backward-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Edge Transport render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;backward_one_file;backward_four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then Unix.rmdir directory)
        [one;four;backward_one;backward_four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "forward" 1 (graph ~transported:true
        ~direction:Pdk.Ops.Transport_forward);
      render four "forward" 4 (graph ~transported:true
        ~direction:Pdk.Ops.Transport_forward);
      render backward_one "backward" 1 (graph ~transported:true
        ~direction:Pdk.Ops.Transport_backward);
      render backward_four "backward" 4 (graph ~transported:true
        ~direction:Pdk.Ops.Transport_backward);
      render control "control" 1 (graph ~transported:false
        ~direction:Pdk.Ops.Transport_forward);
      let one_png = read_file one_file and four_png = read_file four_file
      and backward_one_png = read_file backward_one_file
      and backward_four_png = read_file backward_four_file
      and control_png = read_file control_file in
      if not (String.equal one_png four_png) then
        failwith "Edge Transport forward one/four-domain pixels differ";
      if not (String.equal backward_one_png backward_four_png) then
        failwith "Edge Transport backward one/four-domain pixels differ";
      if String.equal one_png control_png then
        failwith "Edge Transport visual output equals the flat control";
      if String.equal backward_one_png control_png then
        failwith "Edge Transport backward output equals the flat control";
      if String.equal one_png backward_one_png then
        failwith "Edge Transport forward and backward outputs are identical";
      if String.length one_png < 1_000 then
        failwith "Edge Transport PNG is unexpectedly empty");
  print_endline "Edge Transport render smoke passed"
