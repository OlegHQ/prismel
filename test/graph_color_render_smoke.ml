open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let graph () =
  let source = Pdk.Ops.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:12 ~rows:8 ~size:2. () |> Result.get_ok |> Sop.snapshot in
  Sop.graph_color ~connectivity:Pdk.Ops.Graph_primitives_by_point source

let cook domains node =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:2_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:7 () |> get in
    match Session.cook session ~context node with
    | Ok output ->
        (match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
            "color" output.geometry with
         | Some attribute ->
             (match Pdk.Attribute.Private.storage attribute with
              | Pdk.Attribute.Int values -> Array.copy values
              | _ -> failwith "Graph Color render output has wrong storage")
         | None -> failwith "Graph Color render output is missing")
    | Error error -> failwith (Diagnostic.error_to_string error))

let palette = [|
  Color.hex_exn "#22d3ee"; Color.hex_exn "#f472b6";
  Color.hex_exn "#facc15"; Color.hex_exn "#a78bfa";
  Color.hex_exn "#4ade80"; Color.hex_exn "#fb923c" |]

let scene colors =
  let cells = Array.to_list (Array.mapi (fun primitive color ->
      let column = primitive mod 12 and row = primitive / 12 in
      Scene.rect ~at:(16 + (column * 25), 16 + (row * 25)) ~w:22 ~h:22
        ~fill:palette.(color mod Array.length palette) ()) colors) in
  Scene.clear (Color.hex_exn "#020617") :: cells

let control_scene () =
  Scene.clear (Color.hex_exn "#020617") ::
  List.init 96 (fun primitive ->
    let column = primitive mod 12 and row = primitive / 12 in
    Scene.rect ~at:(16 + (column * 25), 16 + (row * 25)) ~w:22 ~h:22
      ~fill:(Color.hex_exn "#334155") ())

let export directory prefix domains scene =
  let config = {Sketch.default_config with width=332; height=232;
    domains=Some domains} in
  Sketch.export ~config ~directory ~prefix ~frames:1 (fun _ -> scene)

let read filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let () =
  let keep = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1";"true";"yes";"on"]
    | None -> false in
  let root = Filename.temp_file "prismel-graph-color-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "graph-000000.png"
  and four_file = Filename.concat four "graph-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Graph Color render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then
          Unix.rmdir directory) [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      let one_colors = cook 1 (graph ()) and four_colors = cook 4 (graph ()) in
      if one_colors <> four_colors then
        failwith "Graph Color one/four-domain values differ";
      export one "graph" 1 (scene one_colors);
      export four "graph" 4 (scene four_colors);
      export control "control" 1 (control_scene ());
      let one_png = read one_file and four_png = read four_file
      and control_png = read control_file in
      if one_png <> four_png then
        failwith "Graph Color one/four-domain framebuffer differs";
      if one_png = control_png then
        failwith "Graph Color framebuffer equals its uncolored control";
      if String.length one_png < 1_000 then failwith "Graph Color PNG is empty");
  print_endline "Graph Color render smoke passed"
