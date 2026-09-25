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

let () =
  if instances "view" <= instances "other" then
    failwith "focused leader bindings were not drawn";
  print_endline "pxui shell which-key tests passed"
