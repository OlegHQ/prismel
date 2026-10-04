module Preset = Rays_editor.Private.Preset
module Document = Rays_editor.Private.Document
let frame events count : Rays.Frame.t = {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse = 450., 320.; mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events }
let () =
  let root = Filename.temp_dir "rays-preset-audit" "" in
  let source = Filename.concat root "source.json" in
  let graph = Procedural.Sop.points [||] in
  let node = `Assoc ["id", `Int 10; "factory_key", `String "geometry";
    "label", `String "geo1"; "inputs", `List [`Null]; "params", `List []] in
  let geometry = `Assoc ["nodes", `List [node]; "display", `Int 10] in
  let empty = `Assoc ["nodes", `List []; "display", `Int 999] in
  let write networks = Yojson.Safe.to_file source (`Assoc ["version", `Int 2;
    "scene", geometry; "networks", `List networks]) in
  let load path = Preset.load ~path ~code:graph ~factories:[]
      ~settings:Rays_editor.Settings.none in
  write [];
  (match load source with
   | Error message -> Printf.printf "missing network rejected: %s\n" message
   | Ok loaded ->
       let id = (List.hd (Procedural.Edit_graph.inspect (Document.scene_graph loaded.doc))).id in
       Printf.printf "missing network accepted; geometry has network=%b\n"
         (Option.is_some (Document.object_network loaded.doc id)));
  let module E = Rays_editor.Editor2 in
  let env = E.create ~graph ~presets:root ~prepare:(fun _ _ -> Ok ())
      ~scene2:(fun _ _ -> []) () |> Result.get_ok in
  let current = ref env in
  Fun.protect ~finally:(fun () -> E.close !current) (fun () ->
    let key k = Rays.Event.KeyPressed k in
    try
      current := E.update !current (frame [] 0);
      current := E.update !current (frame [key Rays.Input.Space; key (Rays.Input.KeyChar 'b')] 1);
      current := E.update !current (frame [Rays.Event.TextInput "source"; key Rays.Input.Enter] 2);
      current := E.update !current (frame [] 3);
      print_endline "Editor2 missing-network load did not raise"
    with exn -> Printf.printf "Editor2 missing-network load raised: %s\n" (Printexc.to_string exn));
  (match Rays_editor__Preset.load ~path:source ~code:graph ~factories:[]
      ~settings:Rays_editor__Settings.none with
   | Error message -> failwith message
   | Ok loaded ->
       let doc = { loaded.doc with scene =
         { loaded.doc.scene with graph = Procedural.Edit_graph.empty } } in
       let saved = Rays_editor__Preset.save ~directory:root ~name:"empty-scene"
         ~sketch:"audit" ~doc ~view:`Null |> Result.get_ok in
       (match load saved with
        | Ok _ -> print_endline "saved empty scene round-tripped"
        | Error message -> Printf.printf "saved empty scene rejected: %s\n" message));
  write [`Assoc ["object", `Int 10; "network", empty]];
  (match load source with
   | Ok _ -> print_endline "empty SOP network accepted"
   | Error message -> Printf.printf "empty SOP network rejected: %s\n" message);
  (match load source with
   | Ok loaded -> ignore (Preset.save ~directory:root ~name:"roundtrip" ~sketch:"audit"
       ~doc:loaded.doc ~view:`Null)
   | Error _ -> ());
  Array.iter (fun filename -> Sys.remove (Filename.concat root filename)) (Sys.readdir root);
  Unix.rmdir root
