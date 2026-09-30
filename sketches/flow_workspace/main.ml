(* A workspace document in the editor: the graph pane draws it with zones,
   rails and iteration selectors.  FLOW_CASE picks bloom (default),
   sunflower or orrery.  FLOW_ADD=1 adds a box from the Tab menu.  FLOW_EXPORT=<dir> renders the editor's UI to PNG
   frames instead of opening a window (a check of the graph pane). *)
open Prismel
module E3 = Prismel_editor.Editor3

let workspace =
  let text = match Sys.getenv_opt "FLOW_CASE" with
    | Some "sunflower" -> Cases.sunflower | Some "orrery" -> Cases.orrery | _ -> Cases.bloom in
  let catalog = Flow_sop.Catalog.of_factories ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  match Prismel_editor.Workspace_doc.of_text catalog text with
  | Ok workspace -> workspace
  | Error ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))

let config = { Sketch.default_config with width = 1400; height = 800; title = "Prismel workspace" }
let prepare _ output = Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
  |> Result.map_error Pdk.Error.to_string
let scene3 _ mesh = Scene3.create [ Scene3.mesh ~cull:Scene3.Cull_none mesh ]
let create () = match E3.create ~workspace ~prepare ~scene3 () with
  | Ok e -> e | Error m -> failwith m

let () = match Sys.getenv_opt "FLOW_EXPORT" with
  | None -> E3.run ~config ~workspace ~prepare ~scene3 ()
  | Some directory ->
      (* enter the first object: click the graph pane, select a row, press i *)
      let script (frame : Frame.t) =
        let click p = [ Event.MouseMoved p; Event.MousePressed (Input.LeftButton, p);
                        Event.MouseReleased (Input.LeftButton, p) ] in
        let events = match frame.count with
          | 4 -> click (900., 300.)
          | 6 -> [ Event.KeyPressed (Input.KeyChar 'j') ]
          | 8 -> [ Event.KeyPressed (Input.KeyChar (Char.chr 105)) ]
          | 16 -> click (960., 466.)
          | 20 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Tab ]
          | 22 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.TextInput "box" ]
          | 24 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Enter ]
          | 30 when Sys.getenv_opt "FLOW_ADD" <> None -> click (1240., 178.)
          | n when n >= 12 && n mod 2 = 0 && n <= 14 -> [ Event.MouseMoved (780., 380.); Event.MouseScrolled (0., 5.) ]
          | _ -> [] in
        { frame with events = events @ frame.events } in
      ignore (Sketch.export_state ~config ~directory ~prefix:"workspace" ~frames:40
        ~init:(fun _ -> create ()) ~update:(fun e frame -> E3.update e (script frame))
        ~view:E3.scene ~on_stop:E3.close ())
