open Prismel
open Procedural

let get = function Ok value -> value | Error message -> failwith message

let graph () =
  let source = Pdk.Ops.torus ~connectivity:Pdk.Ops.Torus_alternating_triangles
      ~rows:24 ~columns:16 ~major_radius:2. ~minor_radius:0.75 ()
      |> Result.get_ok |> Sop.snapshot in
  Sop.measure_curvature source

let cook domains node =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:17 () |> get in
    match Session.cook session ~context node with
    | Ok output ->
        (match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point
            "curvature" output.geometry with
         | Some attribute ->
             (match Pdk.Attribute.Private.storage attribute with
              | Pdk.Attribute.Float values -> Array.copy values
              | _ -> failwith "Measure Curvature render output has wrong storage")
         | None -> failwith "Measure Curvature render output is missing")
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene values =
  let minimum = Array.fold_left min infinity values
  and maximum = Array.fold_left max neg_infinity values in
  let extent = maximum -. minimum in
  Scene.clear (Color.hex_exn "#020617") ::
  Array.to_list (Array.mapi (fun point value ->
    let u = if extent = 0. then 0.5 else (value -. minimum) /. extent in
    let red = int_of_float (Float.round (255. *. u))
    and blue = int_of_float (Float.round (255. *. (1. -. u))) in
    let column = point mod 24 and row = point / 24 in
    Scene.rect ~at:(12 + (column * 11), 12 + (row * 11)) ~w:10 ~h:10
      ~fill:(Color.rgb red 48 blue) ()) values)

let control_scene count =
  Scene.clear (Color.hex_exn "#020617") ::
  List.init count (fun point ->
    let column = point mod 24 and row = point / 24 in
    Scene.rect ~at:(12 + (column * 11), 12 + (row * 11)) ~w:10 ~h:10
      ~fill:(Color.hex_exn "#334155") ())

let export directory prefix domains scene =
  let config = {Sketch.default_config with width=288; height=200;
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
  let root = Filename.temp_file "prismel-curvature-render-" "" in
  Sys.remove root; Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four"
  and control = Filename.concat root "control" in
  let one_file = Filename.concat one "curvature-000000.png"
  and four_file = Filename.concat four "curvature-000000.png"
  and control_file = Filename.concat control "control-000000.png" in
  Fun.protect ~finally:(fun () ->
    if keep then Printf.printf "Measure Curvature render artifacts: %s\n%!" root
    else begin
      List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [one_file;four_file;control_file];
      List.iter (fun directory -> if Sys.file_exists directory then
          Unix.rmdir directory) [one;four;control];
      if Sys.file_exists root then Unix.rmdir root
    end) (fun () ->
      let one_values = cook 1 (graph ()) and four_values = cook 4 (graph ()) in
      if one_values <> four_values then
        failwith "Measure Curvature one/four-domain values differ";
      export one "curvature" 1 (scene one_values);
      export four "curvature" 4 (scene four_values);
      export control "control" 1 (control_scene (Array.length one_values));
      let one_png = read one_file and four_png = read four_file
      and control_png = read control_file in
      if one_png <> four_png then
        failwith "Measure Curvature one/four-domain framebuffer differs";
      if one_png = control_png then
        failwith "Measure Curvature framebuffer equals its control";
      if String.length one_png < 1_000 then
        failwith "Measure Curvature PNG is empty");
  print_endline "Measure Curvature render smoke passed"
