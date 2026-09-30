(* A workspace document in the editor: the graph pane draws it with zones,
   rails and iteration selectors.  FLOW_CASE picks bloom (default),
   sunflower, orrery or garden (W8, a loop over points).  FLOW_SCROLL=<n> is the one wheel step at frame 12 (the pane zoom; default two steps of 5).
   FLOW_ADD=1 adds a box from the Tab menu.  FLOW_EXPORT=<dir> renders the editor's UI to PNG
   frames instead of opening a window (a check of the graph pane).
   FLOW_TEXT=selection|graph|document|edit|error|binding shows the text pane (Space l
   twice) after the click that selects r: a tab, or an edit typed into the
   Document tab (a valid one applied, or an invalid one applied and refused). *)
open Prismel
module E3 = Prismel_editor.Editor3

let workspace =
  let text = match Sys.getenv_opt "FLOW_CASE" with
    | Some "sunflower" -> Cases.sunflower | Some "orrery" -> Cases.orrery
    | Some "garden" -> Cases.garden | _ -> Cases.bloom in
  let catalog = Flow_sop.Catalog.of_factories ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  match Prismel_editor.Workspace_doc.of_text catalog text with
  | Ok workspace -> workspace
  | Error ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))

let config = { Sketch.default_config with width = 1400; height = 800; title = "Prismel workspace" }
let prepare _ output = Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
  |> Result.map_error Pdk.Error.to_string
let scene3 _ mesh = Scene3.create [ Scene3.mesh ~cull:Scene3.Cull_none mesh ]
let lights = [ Light.directional ~direction:(Vec3.create (-1.) (-1.4) (-0.8)) ~diffuse:Color.white () ]
let camera = Easy_camera.create ~target:Vec3.zero ~distance:(if Sys.getenv_opt "FLOW_CASE" = Some "sunflower" then 2.2 else 3.6) ~azimuth:0.4 ~elevation:0.6 ()
let create () = match E3.create ~lights ~camera ~workspace ~prepare ~scene3 () with
  | Ok e -> e | Error m -> failwith m

let () = match Sys.getenv_opt "FLOW_EXPORT" with
  | None -> E3.run ~config ~lights ~camera ~workspace ~prepare ~scene3 ()
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
          | (26 | 32) as n when Sys.getenv_opt "FLOW_PICK" <> None ->
              (* FLOW_PICK=x,y[;x,y] clicks the view at frame 26 (and again at 32): the
                 pick and its highlight, then a second pick or a miss *)
              (match List.nth_opt (String.split_on_char ';' (Sys.getenv "FLOW_PICK")) ((n - 26) / 6) with
               | Some p -> (match String.split_on_char ',' p with
                   | [ x; y ] -> click (float_of_string x, float_of_string y) | _ -> [])
               | None -> [])
          | 20 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Tab ]
          | 22 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.TextInput "box" ]
          | 24 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Enter ]
          | 30 when Sys.getenv_opt "FLOW_ADD" <> None -> click (1240., 178.)
          | 20 | 22 when Sys.getenv_opt "FLOW_TEXT" <> None ->
              [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'l') ]
          | 26 when Sys.getenv_opt "FLOW_TEXT" = Some "graph" -> click (735., 34.)
          | 26 when List.mem (Sys.getenv_opt "FLOW_TEXT") [ Some "edit"; Some "error" ] -> click (810., 34.)
          | 28 when List.mem (Sys.getenv_opt "FLOW_TEXT") [ Some "edit"; Some "error" ] -> click (900., 300.)
          | 28 when Sys.getenv_opt "FLOW_TEXT" = Some "binding" -> click (900., 600.)
          | 30 when List.mem (Sys.getenv_opt "FLOW_TEXT") [ Some "edit"; Some "error"; Some "binding" ] ->
              [ Event.KeyPressed (Input.KeyChar 'a') ]
          | 32 when Sys.getenv_opt "FLOW_TEXT" = Some "binding" -> [ Event.TextInput "(* spread (sqrt (+ i 1)))" ]
          | 32 when List.mem (Sys.getenv_opt "FLOW_TEXT") [ Some "edit"; Some "error" ] ->
              let text = fst (Flow.Lisp.print workspace.Prismel_editor.Workspace_doc.source) in
              let replace from by =
                let n = String.length from in
                let rec at i = if i + n > String.length text then None
                  else if String.sub text i n = from then Some i else at (i + 1) in
                match at 0 with
                | Some i -> String.sub text 0 i ^ by ^ String.sub text (i + n) (String.length text - i - n)
                | None -> text in
              [ Event.TextInput (if Sys.getenv_opt "FLOW_TEXT" = Some "edit"
                  then replace "(seeds : int 240)" "(seeds : int 60)"
                  else replace "(sqrt i)" "(sqrt nosuch)") ]
          | 36 when List.mem (Sys.getenv_opt "FLOW_TEXT") [ Some "edit"; Some "error"; Some "binding" ] -> click (690., 764.)
          | n when n >= 12 && n mod 2 = 0 && n <= (if Sys.getenv_opt "FLOW_SCROLL" = None then 14 else 12) -> [ Event.MouseMoved (780., 380.);
                  Event.MouseScrolled (0., Option.fold ~none:5. ~some:float_of_string (Sys.getenv_opt "FLOW_SCROLL")) ]
          | _ -> [] in
        { frame with events = events @ frame.events;
          keys = if frame.count = 30 then Input.Meta :: frame.keys else frame.keys } in
      ignore (Sketch.export_state ~config ~directory ~prefix:"workspace" ~frames:(if Sys.getenv_opt "FLOW_TEXT" = None then 40 else 48)
        ~init:(fun _ -> create ()) ~update:(fun e frame -> E3.update e (script frame))
        ~view:E3.scene ~on_stop:E3.close ())
