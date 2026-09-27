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
  let layout = Pxui_shell.Layout.create Pxui_shell.Layout.default in
  let panes = Pxui_shell.Layout.geometry layout { frame with width = 1000;
    size = 1000, 300; drawable_width = 1000; drawable_size = 1000, 300 } in
  let _, _, view_width, _ = panes.view
  and _, _, graph_width, _ = panes.graph
  and _, _, inspector_width, _ = panes.inspector in
  if (view_width, graph_width, inspector_width) <> (444, 345, 199) then
    failwith "shell layout defaults are not 45/35/20";
  let collapsed = Pxui_shell.Layout.toggle Pxui_shell.Layout.Inspector layout in
  if not (Pxui_shell.Layout.collapsed collapsed Pxui_shell.Layout.Inspector) then
    failwith "shell layout did not collapse inspector";
  let wide = { frame with width = 1000; size = 1000, 300;
    drawable_width = 1000; drawable_size = 1000, 300 } in
  let _, _, inspector_width, _ = (Pxui_shell.Layout.geometry collapsed wide).inspector in
  let hidden_both = Pxui_shell.Layout.toggle Pxui_shell.Layout.Graph collapsed in
  let _, _, view_width, _ = (Pxui_shell.Layout.geometry hidden_both wide).view in
  if inspector_width <> 0 || view_width <> 1000 then
    failwith "collapsed graph and inspector did not vanish";
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
      let panes = Pxui_shell.Layout.geometry layout benchmark_frame in
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
  let click = [ Event.MousePressed (Input.LeftButton, (230., 15.));
                Event.MouseReleased (Input.LeftButton, (230., 15.)) ] in
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
  let t, _ = step (T.create ()) [] in
  let t, _ = step t ~mouse:(center 0) [Event.MousePressed (Input.LeftButton, center 0);
    Event.MouseReleased (Input.LeftButton, center 0)] in
  let _, intents = step t ~mouse:(center 2) [Event.KeyPressed Input.Shift;
    Event.MousePressed (Input.LeftButton, center 2); Event.KeyReleased Input.Shift;
    Event.MouseReleased (Input.LeftButton, center 2)] in
  expect "Shift selection uses the captured press keys" intents [T.Select [3; 1; 2]];
  Pxui.Ui.destroy ui;
  print_endline "pxui shell tests passed"
