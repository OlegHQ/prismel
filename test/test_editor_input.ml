open Prismel

let check condition message = if not condition then failwith message
let key k = Event.KeyPressed k
let char c = key (Input.KeyChar c)
let palette = [key Input.Space; char '/']
let wheel point = [Event.MouseMoved point; Event.MouseScrolled (0., 1.)]

let frame ?(buttons = []) ?(keys = []) ?(delta = (0., 0.)) mouse events count : Frame.t = {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse; mouse_delta = delta; keys; mouse_buttons = buttons; events }

let run () =
  let exercise ~name ~scene_level ~create ~update ~close ~camera ~dump ~panes ~graph_nodes =
    let current = ref (create ()) and count = ref 0 in
    let directory = Filename.temp_dir "prismel-input-contract" "" in
    Fun.protect ~finally:(fun () -> close !current;
      Array.iter (fun file -> Sys.remove (Filename.concat directory file)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
    let step ?buttons ?keys ?delta ?(mouse = (100., 300.)) events =
      incr count;
      current := update !current (frame ?buttons ?keys ?delta mouse events !count) in
    let snapshot () =
      dump !current directory;
      Yojson.Safe.from_file (Filename.concat directory "document.json") in
    let still before message = check (snapshot () = before) (name ^ ": " ^ message) in
    let modal_gestures () =
      step ~mouse:(330., 300.) (wheel (330., 300.));
      List.iter (fun button ->
        step ~buttons:[button] ~mouse:(100., 300.) [Event.MousePressed (button, (100., 300.))];
        step ~buttons:[button] ~keys:[Input.Shift] ~delta:(70., 20.) ~mouse:(170., 320.)
          [Event.MouseMoved (170., 320.)];
        step ~mouse:(170., 320.) [Event.MouseReleased (button, (170., 320.))];
        step palette; step [])
        [Input.LeftButton; Input.RightButton; Input.MiddleButton] in
    step [];
    let before_wheel = camera !current in
    step ~mouse:(800., 300.) [Event.MouseMoved (100., 300.);
      Event.MouseScrolled (0., 1.); Event.MouseMoved (800., 300.)];
    check (camera !current <> before_wheel)
      (name ^ ": a later pane crossing discarded an owned wheel event");
    let after_wheel = camera !current in
    step ~mouse:(100., 300.) [Event.MouseMoved (800., 300.);
      Event.MouseScrolled (0., 1.); Event.MouseMoved (100., 300.)];
    check (camera !current = after_wheel)
      (name ^ ": an inspector-owned wheel reached the viewport after crossing");
    let original = snapshot () in
    step palette; step [];
    modal_gestures ();
    still original "modal wheel/pointer/Shift-World gestures changed document or camera";
    step [key Input.Escape]; step [];
    let original = snapshot () in
    (* Newly opened and dismissed popups own all remaining pointer events
       even when the whole transition happens in one frame. *)
    step ~mouse:(330., 300.) (palette @ wheel (330., 300.));
    still original "same-frame popup opening leaked a wheel";
    step ~mouse:(100., 300.) ([key Input.Escape;
      Event.MousePressed (Input.RightButton, (100., 300.)); Event.MouseMoved (170., 320.);
      Event.MouseReleased (Input.RightButton, (170., 320.))] @ wheel (100., 300.));
    still original "same-frame popup dismissal leaked a press/move/release/wheel";
    step [];
    let rotation () =
      let open Yojson.Safe.Util in
      let world = snapshot () |> member "sections" |> member "graph"
        |> member "scene" |> member "nodes" |> to_list
        |> List.find (fun node -> member "factory_key" node = `String "world") in
      world |> member "params" |> to_list
        |> List.find_map (function
          | `List [`String "rotation"; value] -> Some (member "float" value |> to_number)
          | _ -> None) |> Option.get in
    let original = snapshot () and before = camera !current in
    step ~mouse:(140., 300.) [key Input.Shift;
      Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseMoved (130., 300.); Event.KeyReleased Input.Shift;
      Event.MouseReleased (Input.LeftButton, (140., 300.))];
    check (rotation () = 20. && camera !current = before)
      (name ^ ": same-frame World drag lost ordered movement or also navigated");
    step ~keys:[Input.Meta] [char 'z'];
    still original "one same-frame World drag did not undo as one operation";
    step ~buttons:[Input.LeftButton] ~keys:[Input.Shift] ~mouse:(120., 300.)
      [Event.MousePressed (Input.LeftButton, (100., 300.)); Event.MouseMoved (120., 300.)];
    check (rotation () = 10.) (name ^ ": first-frame held World movement was lost");
    step ~buttons:[Input.LeftButton] ~mouse:(150., 300.)
      [Event.KeyReleased Input.Shift; Event.MouseMoved (150., 300.)];
    check (rotation () = 25. && camera !current = before)
      (name ^ ": releasing Shift changed the operation during a World drag");
    step ~mouse:(160., 300.) [Event.MouseReleased (Input.LeftButton, (160., 300.))];
    check (rotation () = 30.) (name ^ ": World drag dropped its final release position");
    let first_drag = snapshot () in
    step ~mouse:(120., 300.) [key Input.Shift;
      Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseReleased (Input.LeftButton, (120., 300.)); Event.KeyReleased Input.Shift];
    check (rotation () = 40.) (name ^ ": second World drag did not apply");
    step ~keys:[Input.Meta] [char 'z'];
    still first_drag "two separate World drags merged in history";
    step ~keys:[Input.Meta] [char 'z'];
    still original "release-frame movement split one World drag into multiple undo entries";
    step ~buttons:[Input.LeftButton] ~keys:[Input.Shift]
      [Event.MousePressed (Input.LeftButton, (100., 300.))];
    step ~buttons:[Input.LeftButton] palette;
    step [key Input.Escape]; step [];
    step ~mouse:(200., 300.) [Event.MouseMoved (200., 300.)];
    still original "a popup-cancelled World drag resumed on movement";
    List.iter (fun cancellation ->
      step ~buttons:[Input.LeftButton] ~keys:[Input.Shift]
        [Event.MousePressed (Input.LeftButton, (100., 300.))];
      step [cancellation];
      step ~mouse:(220., 300.) [Event.MouseMoved (220., 300.)];
      still original "a cancelled World drag resumed on movement")
      [Event.WindowFocusLost; Event.PointerCancelled Input.LeftButton];
    step ~buttons:[Input.LeftButton] ~keys:[Input.Shift] ~mouse:(360., 300.)
      [Event.MousePressed (Input.LeftButton, (360., 300.))];
    step ~buttons:[Input.LeftButton] ~keys:[Input.Shift] ~mouse:(430., 300.)
      [Event.MouseMoved (430., 300.)];
    check (rotation () = 35. && camera !current = before)
      (name ^ ": a World drag lost ownership at a pane crossing");
    step ~mouse:(430., 300.) [Event.MouseReleased (Input.LeftButton, (430., 300.))];
    step ~keys:[Input.Meta] [char 'z'];
    still original "cross-pane World drag did not undo as one operation";
    step ~mouse:(-2300., 300.) [key Input.Shift;
      Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseReleased (Input.LeftButton, (-2300., 300.)); Event.KeyReleased Input.Shift];
    check (rotation () = -120.) (name ^ ": a large negative World drag did not wrap rotation");
    step ~keys:[Input.Meta] [char 'z'];
    still original "large negative World drag did not undo in one entry";
    step ~mouse:(140., 300.) [key Input.Shift;
      Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseReleased (Input.LeftButton, (120., 300.));
      Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseReleased (Input.LeftButton, (140., 300.)); Event.KeyReleased Input.Shift];
    check (rotation () = 30.) (name ^ ": batched World gestures lost an operation");
    step ~keys:[Input.Meta] [char 'z'];
    check (rotation () = 10.) (name ^ ": batched World gestures merged in history");
    step ~keys:[Input.Meta] [char 'z'];
    still original "batched World gesture undo did not restore the original";
    step ~keys:[Input.Shift] [];
    step ~mouse:(140., 300.) [Event.MousePressed (Input.LeftButton, (100., 300.));
      Event.MouseMoved (140., 300.); Event.WindowFocusLost];
    check (rotation () = 20.)
      (name ^ ": final focus loss erased Shift from earlier World events");
    step ~keys:[Input.Meta] [char 'z'];
    still original "focus-cancelled World drag did not undo in one entry";
    (* Start in the view, cross both other panes, and finish outside it. *)
    let before = camera !current in
    step ~buttons:[Input.RightButton] [Event.MousePressed (Input.RightButton, (100., 300.))];
    step ~buttons:[Input.RightButton] ~mouse:(500., 320.) [Event.MouseMoved (500., 320.)];
    let across_graph = camera !current in
    check (across_graph <> before) (name ^ ": viewport drag stopped at the graph pane");
    step ~buttons:[Input.RightButton] ~mouse:(800., 350.) [Event.MouseMoved (800., 350.)];
    check (camera !current <> across_graph) (name ^ ": viewport drag stopped at the inspector pane");
    step ~mouse:(800., 350.) [Event.MouseReleased (Input.RightButton, (800., 350.))];
    let released = camera !current in
    step [Event.MouseMoved (110., 300.)];
    check (camera !current = released) (name ^ ": released drag resumed on re-entry");
    step ~buttons:[Input.RightButton] [Event.MousePressed (Input.RightButton, (100., 300.))];
    step [Event.WindowFocusLost];
    let cancelled = camera !current in
    step [Event.MouseMoved (140., 330.)];
    check (camera !current = cancelled) (name ^ ": focus loss did not end the viewport drag");
    step ~buttons:[Input.RightButton] [Event.MousePressed (Input.RightButton, (100., 300.))];
    step ~buttons:[Input.RightButton] palette;
    step [key Input.Escape]; step [];
    let cancelled = camera !current in
    step [Event.MouseMoved (190., 350.)];
    check (camera !current = cancelled) (name ^ ": popup did not cancel an existing drag");
    if scene_level then step [key Input.Space; char 'l'];
    step [];
    let gx, gy, _, _ = (panes !current (frame (0., 0.) [] 0)).Pxui_shell.Layout.graph in
    let point = float (gx + 25), float (gy + 300) in
    let before = camera !current in
    step ~buttons:[Input.MiddleButton] ~mouse:point [Event.MousePressed (Input.MiddleButton, point)];
    step ~buttons:[Input.MiddleButton] [Event.MouseMoved (100., 300.)];
    step [Event.MouseReleased (Input.MiddleButton, (100., 300.))];
    check (camera !current = before) (name ^ ": graph-owned pan began viewport navigation");
    step ~mouse:point [key Input.Home];
    step [];
    let tile = List.hd (graph_nodes !current) in
    let tx, ty, tw, th = tile.Pxui_graph.bounds in
    let point = float (tx + tw / 2), float (ty + th / 2) in
    step ~buttons:[Input.LeftButton] ~mouse:point [Event.MousePressed (Input.LeftButton, point)];
    step ~buttons:[Input.LeftButton] [Event.MouseMoved (100., 300.)];
    step [Event.MouseReleased (Input.LeftButton, (100., 300.))];
    check (camera !current = before) (name ^ ": graph tile drag reached viewport navigation");
    step ~mouse:point [key Input.Home]; step [];
    count := !count + 30; (* past the double-click interval *)
    let tile = List.hd (graph_nodes !current) in
    let tx, ty, tw, th = tile.Pxui_graph.bounds in
    let point = float (tx + tw / 2), float (ty + th / 2) in
    let original = snapshot () in
    step ~buttons:[Input.LeftButton] ~mouse:point [Event.MousePressed (Input.LeftButton, point)];
    let moved_point = fst point +. 20., snd point in
    step ~buttons:[Input.LeftButton] ~mouse:moved_point [Event.MouseMoved moved_point];
    let moved = snapshot () in
    check (moved <> original) (name ^ ": graph move did not change the saved document");
    step ~buttons:[Input.LeftButton] ~keys:[Input.Meta] ~mouse:moved_point [char 'd'];
    check (snapshot () <> moved) (name ^ ": duplicate during a drag did not edit the document");
    step ~mouse:moved_point [Event.MouseReleased (Input.LeftButton, moved_point)];
    step ~keys:[Input.Meta] [char 'z'];
    still moved "an unrelated command merged with a held tile drag";
    step ~keys:[Input.Meta] [char 'z'];
    still original "undo/history present did not restore the preceding tile drag";
    let _, _, width, _ = (panes !current (frame (0., 0.) [] 0)).Pxui_shell.Layout.view in
    step [key Input.Tab; key Input.Space];
    let _, _, collapsed, _ = (panes !current (frame (0., 0.) [] 0)).Pxui_shell.Layout.view in
    check (collapsed < width) (name ^ ": same-frame Tab/Space did not activate the pane header")) in
  let graph = Procedural.Sop.box ~size:(Vec3.create 1. 1. 1.) () in
  let world = { World.default with layers = []; background = World.Transparent } in
  let module E3 = Prismel_editor.Editor3 in
  exercise ~name:"Editor3" ~scene_level:true
    ~create:(fun () -> E3.create ~graph ~world ~camera:(Easy_camera.create ~inertia:false ())
      ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ _ -> Scene3.empty) () |> Result.get_ok)
    ~update:E3.update ~close:E3.close ~dump:E3.crash_dump ~panes:E3.panes ~graph_nodes:E3.graph_nodes
    ~camera:(fun env -> let camera = E3.camera env in
      Camera.position (Easy_camera.camera camera), Camera.target (Easy_camera.camera camera),
      Easy_camera.distance camera);
  let module E2 = Prismel_editor.Editor2 in
  exercise ~name:"Editor2" ~scene_level:false
    ~create:(fun () -> E2.create ~graph ~world ~camera:(Easy_camera2.create ~inertia:false ())
      ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ _ -> []) () |> Result.get_ok)
    ~update:E2.update ~close:E2.close ~dump:E2.crash_dump ~panes:E2.panes ~graph_nodes:E2.graph_nodes
    ~camera:(fun env -> let camera = E2.camera env in
      Easy_camera2.center camera, Easy_camera2.zoom camera, Easy_camera2.rotation camera);
  print_endline "editor input: both hosts shield popups/World edits and retain viewport/graph gesture owners"
