open Prismel

let frame : Frame.t = {
  width = 400; height = 300; size = 400, 300;
  drawable_width = 400; drawable_height = 300;
  drawable_size = 400, 300; pixel_scale = 1., 1.;
  time = 0.; dt = 0.; fps = 0.; count = 0; mouse = 0., 0.;
  mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [];
}

let bindings = Editor_core.[
  Command.make ~id:"save" ~label:"Save" ~trigger:(Keymap.Leader "s") "save";
  Command.make ~id:"view" ~label:"View" ~trigger:(Keymap.Leader "v") ~scope:"view" "view";]

let instances focus =
  let ui = Pxui.Ui.create () in
  ignore (Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Which_key.panel ui bindings ~prefix:"" ~focus ~focus_name:"View"));
  match Scene.Private.stage_native ~width:400 ~height:300 (Pxui.Ui.scene ui) with
  | Error message -> failwith message
  | Ok staged -> List.fold_left (fun total -> function
      | Scene.Private.Ui_layer (batch, _) ->
          total + Scene_command.Ui_batch.count batch
      | _ -> total) 0 staged.layers

let status_instances height =
  let ui = Pxui.Ui.create () in
  ignore (Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Status_bar.draw ui ~bounds:(0, 272, 400, height)
      ~text:"Cook complete" ~fps:(Some 60)));
  match Scene.Private.stage_native ~width:400 ~height:300 (Pxui.Ui.scene ui) with
  | Error message -> failwith message
  | Ok staged -> List.fold_left (fun total -> function
      | Scene.Private.Ui_layer (batch, _) ->
          total + Scene_command.Ui_batch.count batch
      | _ -> total) 0 staged.layers

let () =
  let ui = Pxui.Ui.create () in
  let pane events = Pxui.Ui.frame ui { frame with events } (fun ui ->
    let root = Pxui_shell.Chrome.pane_root ui frame
      ~bounds:(100, 20, 100, 80) "pane" in
    let child = Pxui.Ui.within ui root (fun () ->
      Pxui.Ui.box ui ~flags:Pxui.Ui.clickable
        ~w:(Pxui.Ui.Px 20.) ~h:(Pxui.Ui.Px 20.)
        ~at:(110., 30.) "child") in
    Pxui.Ui.signal ui root, Pxui.Ui.signal ui child) in
  ignore (pane []);
  let root, child = pane [Event.MousePressed (Input.LeftButton, (115., 35.))] in
  if root.subtree_press <> Some 0 || not child.pressed then
    failwith "pane root missed its child control press";
  let root, _ = pane [Event.MouseReleased (Input.LeftButton, (115., 35.));
    Event.MousePressed (Input.LeftButton, (5., 5.))] in
  if root.subtree_press <> None then
    failwith "pane root accepted a press outside its hit bounds";
  Pxui.Ui.destroy ui;
  let layout = Pxui_shell.Layout.default in
  let wide_frame = { frame with width = 1000; size = 1000, 300;
    drawable_width = 1000; drawable_size = 1000, 300 } in
  let panes = Pxui_shell.Layout.(panes (geometry layout wide_frame)) in
  let _, _, view_width, _ = panes.view
  and _, _, graph_width, _ = panes.graph
  and _, _, inspector_width, _ = panes.inspector in
  if (view_width, graph_width, inspector_width) <> (449, 349, 200) then
    failwith "shell layout defaults are not 45/35/20";
  let divider_x = view_width in
  let hit_ui = Pxui.Ui.create () in
  let chrome events = ignore (Pxui.Ui.frame hit_ui { wide_frame with events }
    (fun ui -> ignore (Pxui_shell.Chrome.update layout ui wide_frame);
      Pxui_shell.Chrome.splitters layout ui wide_frame)) in
  chrome [];
  chrome [Prismel.Event.MouseMoved (float (divider_x - 2), 100.)];
  if Pxui.Ui.cursor hit_ui <> Some `Horizontal_resize then
    failwith "thin splitter lost its wider resize hit area";
  Pxui.Ui.destroy hit_ui;
  let inspector_hidden = [Pxui_shell.Layout.Timeline; Inspector] in
  let _, _, inspector_width, _ =
    (Pxui_shell.Layout.(panes (geometry ~hidden:inspector_hidden layout wide_frame))).inspector in
  let hidden_both = Pxui_shell.Layout.[Timeline; Inspector; Graph] in
  let _, _, view_width, _ = (Pxui_shell.Layout.(panes (geometry ~hidden:hidden_both layout wide_frame))).view in
  if inspector_width <> 0 || view_width <> 1000 then
    failwith "collapsed graph and inspector did not vanish";
  (* the default three columns match the retired fixed layout at these sizes and states *)
  let golden (w, h) hidden (view, graph_w, inspector_w, status, timeline) =
    let f = { frame with width = w; height = h; size = w, h; drawable_width = w;
      drawable_height = h; drawable_size = w, h } in
    let p = Pxui_shell.Layout.(panes (geometry ~hidden layout f)) in
    let width (_, _, w, _) = w in
    if p.view <> view || width p.graph <> graph_w || width p.inspector <> inspector_w
       || p.status <> status || p.timeline <> timeline then
      failwith (Printf.sprintf "default layout changed at %dx%d" w h) in
  let module L = Pxui_shell.Layout in
  golden (800, 600) [L.Timeline] ((0, 22, 359, 550), 279, 160, (0, 572, 359, 28), (0, 600, 800, 0));
  golden (1280, 800) [L.Timeline; Graph] ((0, 22, 885, 750), 0, 394, (0, 772, 885, 28), (0, 800, 1280, 0));
  golden (1920, 1080) [L.View "main"] ((0, 22, 28, 1000), 1202, 688, (0, 1022, 28, 28), (0, 1050, 1920, 30));
  golden (1000, 300) [L.Inspector] ((0, 22, 561, 220), 438, 0, (0, 242, 561, 28), (0, 270, 1000, 30));
  golden (500, 400) [L.Timeline] ((0, 22, 224, 350), 174, 100, (0, 372, 224, 28), (0, 400, 500, 0));
  (* every tree covers the area above the timeline exactly once, gutters included *)
  let views n = L.Tile (List.init n (fun i -> L.Leaf (L.View (string_of_int i)))) in
  let trees = [
    "default", L.default;
    "sheet", L.Split { axis = `V; ratio = 0.13; a = Leaf Outline; b =
      Split { axis = `H; ratio = 0.5; a = Split { axis = `V; ratio = 0.58; a = Leaf Graph; b = Leaf Lisp };
              b = views 4 } };
    "tile of five", views 5;
    "vertical stack", Split { axis = `V; ratio = 0.3; a = Leaf Graph; b =
      Split { axis = `V; ratio = 0.5; a = Leaf Inspector; b = Leaf List } };
    "nested", Split { axis = `H; ratio = 0.3; a = Split { axis = `V; ratio = 0.4; a = Leaf Graph;
      b = Leaf List }; b = Split { axis = `H; ratio = 0.5; a = Leaf Inspector; b = Leaf (View "z") } } ] in
  List.iter (fun (name, tree) ->
    List.iter (fun (w, h) ->
      let f = { frame with width = w; height = h; size = w, h } in
      let g = L.geometry tree f in
      let seen = Array.make_matrix w h 0 in
      let cover (x, y, cw, ch) = for i = x to x + cw - 1 do for j = y to y + ch - 1 do
        if i >= 0 && j >= 0 && i < w && j < h then seen.(i).(j) <- seen.(i).(j) + 1
        else failwith (name ^ ": a rectangle leaves the frame") done done in
      List.iter (fun (l : L.leaf) ->
        let hx, hy, hw, hh = l.header and bx, by, bw, bh = l.body in
        cover (hx, hy, hw, hh); cover (bx, by, bw, bh)) g.leaves;
      cover g.status_at;
      List.iter (fun (s : L.splitter) -> cover s.bounds) g.splitters;
      Array.iter (Array.iter (fun n -> if n <> 1 then
        failwith (Printf.sprintf "%s at %dx%d: a point is covered %d times" name w h n))) seen)
      [ 1000, 600; 640, 480; 333, 217 ]) trees;
  (* floats overlay the rectangle of their parent and come last *)
  let floated = L.Split { axis = `H; ratio = 0.5; a = Leaf Graph; b = Float (Leaf Inspector) } in
  let g = L.geometry floated wide_frame in
  (match List.map (fun (l : L.leaf) -> l.panel) g.leaves, List.rev g.leaves with
   | [ Graph; Inspector ], { body = bx, by, bw, bh; _ } :: _ ->
       let gx, _, gw, _ = (Option.get (L.find g Graph)).body in
       if gx <> 0 || gw <> 1000 || bx <= 0 || bx + bw >= 1000 || by <= 22 || bh <= 0 then
         failwith "a float is not an inset overlay over a full-size sibling"
   | _ -> failwith "float leaves are not last");
  (* a nested split takes its share of what its parent leaves it *)
  (match (L.geometry (L.Split { axis = `V; ratio = 0.25; a = Leaf Graph; b = Leaf Lisp })
      wide_frame).leaves with
   | [ a; b ] -> let _, _, _, ah = a.body and _, _, _, bh = b.body in
       if ah + 22 >= bh + 22 then failwith "a vertical split ignored its ratio"
   | _ -> failwith "vertical split lost a panel");
  (* dragging a splitter reports a ratio, and the header menu reports its intents *)
  let drag_ui = Pxui.Ui.create () in
  let chrome tree ?(mouse = 0., 0.) events =
    let f = { wide_frame with events; mouse } in
    Pxui.Ui.frame drag_ui f (fun ui -> let a = Pxui_shell.Chrome.update tree ui f in
      a @ Pxui_shell.Chrome.splitters tree ui f) in
  ignore (chrome L.default []);
  let x = 449. in
  ignore (chrome L.default ~mouse:(x, 100.) [Event.MouseMoved (x, 100.)]);
  ignore (chrome L.default ~mouse:(x, 100.) [Event.MousePressed (Input.LeftButton, (x, 100.))]);
  let moved = chrome L.default ~mouse:(300., 100.) [Event.MouseMoved (300., 100.)] in
  (match moved with
   | [ Pxui_shell.Chrome.Resize { node = []; ratio } ] ->
       if Float.abs (ratio -. 0.3) > 0.01 then failwith "splitter ratio does not follow the pointer"
   | _ -> failwith "a drag did not report one resize of the outer split");
  let released = chrome L.default ~mouse:(300., 100.) [Event.MouseReleased (Input.LeftButton, (300., 100.))] in
  if not (List.mem Pxui_shell.Chrome.Settled released) then failwith "a drag did not settle";
  ignore (chrome L.default ~mouse:(600., 10.) [Event.MouseMoved (600., 10.)]);
  ignore (chrome L.default ~mouse:(600., 10.) [Event.MousePressed (Input.RightButton, (600., 10.))]);
  ignore (chrome L.default ~mouse:(600., 10.) [Event.MouseReleased (Input.RightButton, (600., 10.))]);
  ignore (chrome L.default ~mouse:(470., 34.) [Event.MouseMoved (470., 34.)]);
  let pick = [Event.MousePressed (Input.LeftButton, (470., 34.));
    Event.MouseReleased (Input.LeftButton, (470., 34.))] in
  (match chrome L.default ~mouse:(470., 34.) pick with
   | [ Pxui_shell.Chrome.Split_panel ([ 1; 0 ], `H) ] -> ()
   | _ -> failwith "the header menu did not split the graph panel");
  let collapse = [Event.MousePressed (Input.LeftButton, (985., 10.));
    Event.MouseReleased (Input.LeftButton, (985., 10.))] in
  ignore (chrome L.default ~mouse:(985., 10.) [Event.MouseMoved (985., 10.)]);
  if not (List.mem (Pxui_shell.Chrome.Toggle L.Inspector) (chrome L.default ~mouse:(985., 10.) collapse)) then
    failwith "the collapse button did not toggle the inspector";
  Pxui.Ui.destroy drag_ui;
  if instances "view" <= instances "other" then
    failwith "focused leader bindings were not drawn";
  if status_instances 28 <= 0 || status_instances 0 <> 0 then
    failwith "status strip visibility or drawing failed";
  let ui = Pxui.Ui.create () in
  let intents = Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Timeline_bar.draw ui ~bounds:(0, 270, 400, 30)
      ~playing:false ~frame:12L ~time:0.2 ~max_frame:240) in
  if intents <> [] then failwith "idle timeline emitted a playback request";
  let query = Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Prompt.name ui ~key:"name" ~title:"Save" ~label:"Name"
      ~query:"draft") in
  if query <> Some ("draft", `None) then
    failwith "name prompt lost its initial query";
  (* the make-macro dialog keeps the host's state until something is pressed *)
  let macro = { Pxui_shell.Prompt.name = "shifted"; holes = [| true, "p1"; false, "p2"; true, "p3" |] } in
  let answer = Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Prompt.macro ui ~key:"macro" ~title:"Make a macro" ~literals:[| "0.5"; "12"; "\"a\"" |]
      ~free:[ "seed" ] macro) in
  if answer <> Some (macro, `None) then failwith "macro prompt changed its state or submitted on its own";
  let shell = Pxui.Ui.create () in
  if Pxui_shell.Shell.frame shell frame ~visible:false
      ~body:(fun _ -> 7) ~overlay:None <> None then
    failwith "hidden shell built editor content";
  if Pxui_shell.Shell.frame shell frame ~visible:true
      ~body:(fun _ -> 7) ~overlay:None <> Some 7 then
    failwith "visible shell lost editor result";
  let controls ui =
    let box = Pxui.Ui.box ui ~flags:Pxui.Ui.(clickable + focusable)
      ~at:(10., 10.) ~w:(Pxui.Ui.Px 50.) ~h:(Pxui.Ui.Px 50.) "focused-control" in
    Pxui.Ui.signal ui box in
  let show events = Pxui_shell.Shell.frame shell { frame with events }
    ~visible:true ~body:controls ~overlay:None in
  let hide events = Pxui_shell.Shell.frame shell { frame with events }
    ~visible:false ~body:controls ~overlay:None in
  ignore (show []);
  let captured = show [Event.MousePressed (Input.LeftButton, (20., 20.))] |> Option.get in
  if not captured.held || not (Pxui.Ui.text_input_focused shell) then
    failwith "shell did not establish focus and capture";
  ignore (hide [Event.WindowFocusLost]);
  if Pxui.Ui.text_input_focused shell || Pxui.Ui.wants_pointer shell then
    failwith "hidden shell did not process focus-loss cancellation";
  ignore (show []);
  ignore (show [Event.MousePressed (Input.LeftButton, (20., 20.))]);
  ignore (hide []);
  if Pxui.Ui.text_input_focused shell || Pxui.Ui.wants_pointer shell then
    failwith "hidden shell did not prune removed controls";
  let returned = show [Event.MouseReleased (Input.LeftButton, (20., 20.))] |> Option.get in
  if returned.clicked || returned.held then failwith "hidden control committed after disappearing";
  Pxui.Ui.destroy shell;
  let hidden = Pxui.Ui.create () in
  ignore (Pxui_shell.Shell.frame hidden frame ~visible:false
    ~body:(fun _ -> ())
    ~overlay:(Some (fun ui -> Pxui_shell.Status_bar.draw ui
      ~bounds:(0, 272, 400, 28) ~text:"Overlay" ~fps:None)));
  if Pxui.Ui.scene hidden = [] then
    failwith "hidden shell did not draw its pending overlay";
  if Sys.getenv_opt "PRISMEL_BENCH_LAYOUT" = Some "1" then begin
    let benchmark_frame = { frame with width = 1000; size = 1000, 300 } in
    let start_alloc = Gc.allocated_bytes () and start = Sys.time () in
    let width_sum = ref 0 in
    for _ = 1 to 200_000 do
      let panes = Pxui_shell.Layout.(panes (geometry layout benchmark_frame)) in
      let _, _, width, _ = panes.view in
      width_sum := !width_sum + width
    done;
    Printf.printf "layout geometry: %.4fs %.0f bytes %d\n%!"
      (Sys.time () -. start) (Gc.allocated_bytes () -. start_alloc) !width_sum
  end;
  (* Inspector.record: a plain sketch record edited through its schema. *)
  let schema = Editor_core.Param.(schema ~name:"look" ~default:false
    [ field ~name:"on" ~label:"On" ~kind:Toggle ~default:false
        ~get:Fun.id ~set:(fun on _ -> on) () ]) in
  let ui = Pxui.Ui.create () in
  let click = [ Event.MousePressed (Input.LeftButton, (115., 15.));
                Event.MouseReleased (Input.LeftButton, (115., 15.)) ] in
  let record events value = Pxui.Ui.frame ui { frame with events } (fun ui ->
    Pxui.Ui.panel ui ~x:0. ~y:0. ~width:260. "record" (fun () ->
      Pxui_shell.Inspector.record ui schema value)) in
  (match record [] false with
   | Ok (false, effects) when not (Editor_core.Param.has_effects effects) -> ()
   | _ -> failwith "idle inspector frame changed the record");
  (match record click false with
   | Ok (true, effects) when effects.cook -> ()
   | _ -> failwith "inspector toggle did not edit the record");
  Pxui.Ui.destroy ui;
  (* Tree: WAI-ARIA keys through [run_command], and pointer gestures (dead
     zone, before/inside/after drops, toggle paint, double-click). *)
  let module T = Pxui_shell.Tree in
  let row id depth label = { T.id; depth; label; detail = ""; badge = "S", Color.gray 90; link = false;
    ghost = false; flags = [true] } in
  let rows = [| row 1 0 "a"; row 2 1 "b"; row 3 1 "c"; row 4 0 "d" |] in
  let expect name got want = if got <> want then failwith ("tree: " ^ name) in
  let run t command = T.run_command t rows ~selected:[] command in
  let t, intents = run (T.create ()) T.Down in
  expect "Down from nothing selects the first row" intents [T.Select [1]];
  let t, intents = run t T.Down in
  expect "Down moves to the child" intents [T.Select [2]];
  let t2, intents = run t T.Extend_down in
  expect "Shift-Down extends from the anchor" intents [T.Select [3; 2]];
  ignore t2;
  let t, intents = run t T.Collapse in
  expect "Left on a leaf goes to its parent" intents [T.Select [1]];
  let t, intents = run t T.Collapse in
  expect "Left on an open parent folds it" intents [];
  let t, intents = run t T.Down in
  expect "a folded parent hides its children" intents [T.Select [4]];
  let t, _ = run t T.Up in
  let t, intents = run t T.Expand in
  expect "Right unfolds" intents [];
  let t, intents = run t T.Expand in
  expect "Right on an open parent goes to its first child" intents [T.Select [2]];
  let _, intents = run t T.Last in
  expect "End selects the last row" intents [T.Select [4]];
  let _, intents = T.run_command t rows ~selected:[2; 3] T.Indent_rows in
  expect "Tab reparents the selection" intents [T.Indent [2; 3]];
  let _, intents = run t T.Outdent_rows in
  expect "Shift-Tab outdents the focus" intents [T.Outdent [2]];
  let _, intents = run t T.Move_up in
  expect "Alt-Up reorders" intents [T.Reorder { ids = [2]; delta = -1 }];
  let _, intents = run t T.Hide in
  expect "h hides the focused row" intents [T.Flag { ids = [2]; column = 0; value = false }];
  let _, intents = run t T.Activate_row in
  expect "the enter key activates" intents [T.Activate 2];
  let filtering, _ = run t T.Filter in
  expect "/ opens the filter" (T.editing filtering) true;
  let ui = Pxui.Ui.create () in
  let center k = 200., 24. +. (24. *. float_of_int k) +. 12. in
  let step t ?(mouse = 0., 0.) events =
    Pxui.Ui.frame ui { frame with events; mouse } (fun ui ->
      T.update t ui { frame with events; mouse } ~bounds:(0, 0, 400, 300)
        ~columns:["vis"] rows ~selected:[]) in
  let gesture t from_ to_ =
    let t, _ = step t ~mouse:from_ [] in
    let t, pressed = step t ~mouse:from_ [Event.MousePressed (Input.LeftButton, from_)] in
    let t, moved = step t ~mouse:to_ [Event.MouseMoved to_] in
    let t, released = step t ~mouse:to_ [Event.MouseReleased (Input.LeftButton, to_)] in
    t, pressed @ moved @ released in
  let moves intents = List.filter (function T.Move _ -> true | _ -> false) intents in
  let chevron = 13., snd (center 0) in
  let t, _ = step (T.create ()) [] in
  let t, intents = step t ~mouse:chevron
      [Event.MousePressed (Input.LeftButton, chevron);
       Event.MouseReleased (Input.LeftButton, chevron)] in
  expect "chevron click does not select or drag" intents [];
  let t, _ = run t T.Down in
  let _, intents = run t T.Down in
  expect "chevron click folds children" intents [T.Select [4]];
  let x, y = center 0 in
  let t, intents = gesture (T.create ()) (x, y) (x +. 2., y +. 1.) in
  expect "a 2-point drag stays inside the dead zone" (moves intents) [];
  let drop k fraction = let x, y = center k in x, y -. 12. +. (24. *. fraction) in
  let t, intents = gesture t (center 1) (drop 3 0.5) in
  expect "the middle of a row drops inside"
    (moves intents) [T.Move { ids = [2]; target = 4; drop = T.Inside }];
  let t, intents = gesture t (center 1) (drop 3 0.1) in
  expect "the top quarter drops before"
    (moves intents) [T.Move { ids = [2]; target = 4; drop = T.Before }];
  let t, intents = gesture t (center 1) (drop 3 0.9) in
  expect "the bottom quarter drops after"
    (moves intents) [T.Move { ids = [2]; target = 4; drop = T.After }];
  let flag k = 386., snd (center k) in
  let t, intents = gesture t (flag 0) (flag 2) in
  expect "dragging down a toggle column paints each row it passes"
    (List.filter (function T.Flag _ -> true | _ -> false) intents)
    [T.Flag { ids = [1]; column = 0; value = false };
     T.Flag { ids = [3]; column = 0; value = false }];
  let click = [Event.MousePressed (Input.LeftButton, center 3);
    Event.MouseReleased (Input.LeftButton, center 3)] in
  let t, _ = step t ~mouse:(center 3) click in
  let _, intents = step t ~mouse:(center 3) click in
  expect "a double-click activates the row"
    (List.filter (function T.Activate _ -> true | _ -> false) intents) [T.Activate 4];
  let scroll_rows = Array.init 20 (fun index -> row (index + 1) 0
      (string_of_int (index + 1))) in
  let scroll_ui = Pxui.Ui.create () in
  let scroll_step t events = Pxui.Ui.frame scroll_ui { frame with events;
      mouse = 200., 60. } (fun ui ->
    T.update t ui frame ~bounds:(0, 0, 400, 96)
      ~columns:[] scroll_rows ~selected:[]) in
  let t, _ = scroll_step (T.create ()) [] in
  let t, _ = scroll_step t [Event.MouseMoved (200., 60.);
    Event.MouseScrolled (0., -2.)] in
  let t, _ = scroll_step t [] in
  let _, intents = scroll_step t [Event.MousePressed (Input.LeftButton, (200., 60.))] in
  expect "list uses shared scroll for row hits" intents [T.Select [4]];
  Pxui.Ui.destroy scroll_ui;
  let t, _ = step (T.create ()) [] in
  let t, _ = step t ~mouse:(center 0) [Event.MousePressed (Input.LeftButton, center 0);
    Event.MouseReleased (Input.LeftButton, center 0)] in
  let _, intents = step t ~mouse:(center 2) [Event.KeyPressed Input.Shift;
    Event.MousePressed (Input.LeftButton, center 2); Event.KeyReleased Input.Shift;
    Event.MouseReleased (Input.LeftButton, center 2)] in
  expect "Shift selection uses the captured press keys" intents [T.Select [3; 1; 2]];
  Pxui.Ui.destroy ui;
  print_endline "pxui shell tests passed"
