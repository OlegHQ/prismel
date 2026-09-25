open Prismel

let frame : Frame.t = {
  width = 400; height = 300; size = 400, 300;
  drawable_width = 400; drawable_height = 300;
  drawable_size = 400, 300; pixel_scale = 1., 1.;
  time = 0.; dt = 0.; fps = 0.; count = 0; mouse = 0., 0.;
  mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [];
}

let bindings : (string, string) Editor.Keymap.binding list = [
  { trigger = Editor.Keymap.Leader 's'; label = "Save"; scope = None; action = "save" };
  { trigger = Editor.Keymap.Leader 'v'; label = "View"; scope = Some "view"; action = "view" };
]

let instances focus =
  let ui = Pxui.Ui.create () in
  ignore (Pxui.Ui.frame ui frame (fun ui ->
    Pxui_shell.Which_key.panel ui bindings ~focus ~focus_name:"View"));
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
  let hidden = Pxui.Ui.create () in
  ignore (Pxui_shell.Shell.frame hidden frame ~visible:false
    ~body:(fun _ -> ())
    ~overlay:(Some (fun ui -> Pxui_shell.Status_bar.draw ui
      ~bounds:(0, 272, 400, 28) ~text:"Overlay" ~fps:None)));
  if Pxui.Ui.scene hidden = [] then
    failwith "hidden shell did not draw its pending overlay";
  print_endline "pxui shell tests passed"
