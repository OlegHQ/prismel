(* A workspace document in the editor: the graph pane draws it with zones,
   rails and iteration selectors.  FLOW_CASE picks bloom (default),
   a workspace file path, sunflower, orrery, garden (W8, a loop over points), lamps (a loop of scene objects: copies of one template) or rosette (W9, macro calls and a bypassed node).  FLOW_W9 / FLOW_W9KEY / FLOW_W9TEXT script clicks, a key and typed text by frame (see the script).
   FLOW_SCROLL=<n> is the one wheel step at frame 12 (the pane zoom; default two steps of 5).
   FLOW_ADD=1 adds a box from the Tab menu.  FLOW_EXPORT=<dir> renders the editor's UI to PNG
   frames instead of opening a window (a check of the graph pane).
   FLOW_TEXT=selection|graph|document|edit|error|binding shows the text pane (Space l t)
   after the click that selects r: a tab, or an edit typed into the
   Document tab (a valid one applied, or an invalid one applied and refused). *)
open Prismel
module E3 = Prismel_editor.Editor3

let workspace =
  let text = match Sys.getenv_opt "FLOW_CASE" with
    | Some "sunflower" -> Cases.sunflower | Some "orrery" -> Cases.orrery
    | Some "garden" -> Cases.garden | Some "lamps" -> Cases.lamps | Some "rosette" -> Cases.rosette
    | Some "variations" -> Cases.variations
    | Some path when Sys.file_exists path -> In_channel.with_open_bin path In_channel.input_all
    | _ -> Cases.bloom in
  let catalog = Prismel_editor.workspace_catalog () |> Result.get_ok in
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
        let press p = [ Event.MouseMoved p; Event.MousePressed (Input.LeftButton, p) ]
        and move p = [ Event.MouseMoved p ]
        and release p = [ Event.MouseReleased (Input.LeftButton, p) ] in
        (* the header menu of the panel whose header holds (x, 10), which opens at the header's left
           edge (FLOW_MENUX): right-click, then a row *)
        let menux = Option.fold ~none:200. ~some:float_of_string (Sys.getenv_opt "FLOW_MENUX") in
        let menu x row = function
          | 6 -> [ Event.MouseMoved (x, 10.) ]
          | 7 -> [ Event.MousePressed (Input.RightButton, (x, 10.)) ]
          | 8 -> [ Event.MouseReleased (Input.RightButton, (x, 10.)) ]
          | 10 -> [ Event.MouseMoved (menux, 22. +. 3. +. (24. *. float_of_int row) +. 12.) ]
          | 12 -> click (menux, 22. +. 3. +. (24. *. float_of_int row) +. 12.)
          | _ -> [] in
        let shell = Sys.getenv_opt "FLOW_SHELL" in
        (* FLOW_DRAGX is the gutter to drag (default: the view | graph gutter of 1400 points) *)
        let dragx = Option.fold ~none:629.5 ~some:float_of_string (Sys.getenv_opt "FLOW_DRAGX") in
        let events = match shell, frame.count with
          | Some "drag", 6 -> press (dragx, 300.)
          | Some "drag", 8 -> move (dragx +. 90., 300.)
          | Some "drag", 10 -> move (dragx +. 180., 300.)
          | Some "drag", 12 -> release (dragx +. 180., 300.)
          | Some "split", n -> menu 700. 0 n
          | Some "close", n -> menu 700. 2 n
          | Some "retype", n -> menu 700. 5 n
          | Some "restore", 6 -> [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'z') ]
          | _ -> [] in
        let events = if events <> [] then events else match frame.count with
          | 4 when shell <> None -> []
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
          | n when n >= 20 && Sys.getenv_opt "FLOW_SCRIPT" <> None ->
              (* FLOW_SCRIPT=action@frame[;action@frame]... over the graph pane (W13): click x,y;
                 dbl x,y (a double-click); press x,y, move x,y, release x,y (a drag);
                 key Name (F2, Enter, Escape, Right); shiftkey c; text words *)
              List.concat_map (fun item -> match String.split_on_char '@' item with
                | [ what; f ] when int_of_string_opt f = Some n ->
                    let point v = match String.split_on_char ',' v with
                      | [ x; y ] -> (float_of_string x, float_of_string y) | _ -> (0., 0.) in
                    (match String.index_opt what ' ' with
                     | None -> []
                     | Some i ->
                         let verb = String.sub what 0 i and arg = String.sub what (i + 1) (String.length what - i - 1) in
                         (match verb with
                          | "click" -> click (point arg)
                          | "rclick" -> [ Event.MouseMoved (point arg); Event.MousePressed (Input.RightButton, point arg);
                                          Event.MouseReleased (Input.RightButton, point arg) ]
                          | "dbl" -> click (point arg) @ click (point arg)
                          | "press" -> press (point arg) | "move" -> move (point arg)
                          | "release" -> release (point arg)
                          | "text" -> [ Event.TextInput arg ]
                          | "shiftkey" -> [ Event.KeyPressed Input.Shift; Event.KeyPressed (Input.KeyChar arg.[0]) ]
                          | "key" -> [ Event.KeyPressed (match arg with
                              | "F2" -> Input.F2 | "Space" -> Input.Space | "Enter" -> Input.Enter | "Escape" -> Input.Escape
                              | "Right" -> Input.ArrowRight | "Left" -> Input.ArrowLeft
                              | "Down" -> Input.ArrowDown | "Up" -> Input.ArrowUp | "Delete" -> Input.Delete
                              | k -> Input.KeyChar k.[0]) ]
                          | _ -> []))
                | _ -> []) (String.split_on_char ';' (Sys.getenv "FLOW_SCRIPT"))
          | n when n >= 20 && Sys.getenv_opt "FLOW_W9" <> None ->
              (* FLOW_W9=x,y@frame[;x,y@frame]... clicks the graph pane at those frames (a
                 macro lens toggle, a step, a flag); FLOW_W9KEY=c@frame presses a key;
                 FLOW_W9TEXT=text@frame types it *)
              let at spec = List.filter_map (fun item -> match String.split_on_char '@' item with
                | [ what; f ] when int_of_string_opt f = Some n -> Some what | _ -> None)
                (String.split_on_char ';' spec) in
              List.concat_map (fun what -> match String.split_on_char ',' what with
                | [ x; y ] -> click (float_of_string x, float_of_string y) | _ -> [])
                (at (Sys.getenv "FLOW_W9"))
              @ List.concat_map (fun k -> if k = "Enter" then [ Event.KeyPressed Input.Enter ]
                                 else if String.length k = 1 then [ Event.KeyPressed (Input.KeyChar k.[0]) ] else [])
                  (at (Option.value ~default:"" (Sys.getenv_opt "FLOW_W9KEY")))
              @ List.map (fun text -> Event.TextInput text)
                  (at (Option.value ~default:"" (Sys.getenv_opt "FLOW_W9TEXT")))
          | 20 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Tab ]
          | 22 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.TextInput "box" ]
          | 24 when Sys.getenv_opt "FLOW_ADD" <> None -> [ Event.KeyPressed Input.Enter ]
          | 30 when Sys.getenv_opt "FLOW_ADD" <> None -> click (1240., 178.)
          | 20 when Sys.getenv_opt "FLOW_TEXT" <> None ->
              [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'l'); Event.KeyPressed (Input.KeyChar 't') ]
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
          keys = (if frame.count = 30 then [ Input.Meta ] else [])
            @ (if List.exists (fun item -> String.starts_with ~prefix:"shiftkey" item
                                && String.ends_with ~suffix:("@" ^ string_of_int frame.count) item)
                 (String.split_on_char ';' (Option.value ~default:"" (Sys.getenv_opt "FLOW_SCRIPT")))
               then [ Input.Shift ] else [])
            @ frame.keys } in
      ignore (Sketch.export_state ~config ~directory ~prefix:"workspace" ~frames:(if Sys.getenv_opt "FLOW_TEXT" = None then 40 else 48)
        ~init:(fun _ -> create ()) ~update:(fun e frame -> E3.update e (script frame))
        ~view:E3.scene ~on_stop:E3.close ())
