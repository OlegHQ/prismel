open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let source () =
  let points = 24 in
  let x = Array.init points (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. float_of_int points in
      (1. +. (0.24 *. sin (5. *. angle))) *. cos angle)
  and y = Array.init points (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. float_of_int points in
      (0.72 +. (0.13 *. cos (3. *. angle))) *. sin angle)
  and z = Array.init points (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. float_of_int points in
      0.16 *. sin (2. *. angle)) in
  let topology = Pdk.Topology.create_owned ~point_count:points
      ~vertex_points:(Array.init points Fun.id)
      ~primitive_offsets:[|0;points|]
      ~primitive_kinds:[|Pdk.Topology.Closed_polyline|] |> Result.get_ok in
  Pdk.Geometry.create
    ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> Result.get_ok

let wire node = node |> Sop.polywire ~sides:6 ~radius:0.055 ~caps:false
    |> Sop.normals ~owner:Pdk.Attribute.Vertex

let graph () = Sop.snapshot (source ()) |> Sop.circle_from_edges ~radius:1.25
    ~scale:(Vec3.create 1. 0.7 1.) |> wire

let control () = Sop.snapshot (source ()) |> wire

let cook domains node =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(16 * 1024 * 1024) |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:7 () |> get in
    match Bridge.cook_to_mesh session ~context node with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene mesh =
  let camera = Camera.perspective ~at:(Vec3.create 0. 0.4 4.2)
      ~target:Vec3.zero () in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:4 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit (Color.hex_exn "#22d3ee")) mesh])]

let render directory prefix domains node =
  let config = { Sketch.default_config with width = 320; height = 240;
    domains = Some domains } in
  let mesh = cook domains node in
  if Mesh.Private.triangle_count mesh <> 24 * 6 * 2 then
    failwith (Printf.sprintf "circle wire fixture has %d triangles"
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
  let root = Filename.temp_file "prismel-circle-from-edges-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and control_dir = Filename.concat root "control" in
  let one_file = Filename.concat one "circle-000000.png"
  and four_file = Filename.concat four "circle-000000.png"
  and control_file = Filename.concat control_dir "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Circle from Edges render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then
          Unix.rmdir directory) [one;four;control_dir];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      render one "circle" 1 (graph ());
      render four "circle" 4 (graph ());
      render control_dir "control" 1 (control ());
      let one_png = read one_file and four_png = read four_file
      and control_png = read control_file in
      if one_png <> four_png then
        failwith "Circle from Edges one/four-domain framebuffer differs";
      if one_png = control_png then
        failwith "Circle from Edges framebuffer equals its distorted source";
      if String.length one_png < 1_000 then failwith "circle PNG is empty");
  print_endline "Circle from Edges render smoke passed"
