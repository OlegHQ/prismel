open Rays
module Ui = Pxui.Ui

let check condition message = if not condition then failwith message
let key value = Event.KeyPressed value
let frame ?(keys = []) events : Frame.t = {
  width = 500; height = 360; size = 500, 360;

  pixel_scale = 1., 1.; time = 1.; dt = 0.; fps = 60.; count = 0;
  mouse = -10., -10.; mouse_delta = 0., 0.; keys; mouse_buttons = []; events }

type model = { clicks : int; enabled : bool; text : string }

let run () =
  let ui = Ui.create ~font_size:11 () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
    let model = ref { clicks = 0; enabled = false; text = "old" } in
    let build ui = Ui.panel ui ~width:400. "controls" (fun () ->
      let clicks = !model.clicks + if Ui.button ui "Run" then 1 else 0 in
      let enabled = Ui.toggle ui "Enabled" !model.enabled in
      let text = Ui.text_field ui "Text" !model.text in
      { clicks; enabled; text }) in
    let step ?keys events = model := Ui.frame ui (frame ?keys events) build in
    step [];
    step [key Input.Shift; key Input.Tab; Event.KeyReleased Input.Shift; Event.TextInput "!"];
    check (!model.text = "old!") "same-frame Shift release changed backwards Tab traversal";
    step [key Input.Tab; key Input.Enter];
    check (!model.clicks = 1 && (Ui.input ui).events = [])
      "Tab/Enter did not activate the first control or leaked into the host";
    step [key Input.Tab; key Input.Space];
    check !model.enabled "Space did not toggle the focused control";
    step ~keys:[Input.Shift] [key Input.Tab; key Input.Tab; Event.TextInput "!"];
    check (!model.text = "old!!") "Shift-Tab did not enter the last text field";
    step [key Input.Meta; key (Input.KeyChar 'a'); Event.KeyReleased Input.Meta;
      Event.TextInput "new"];
    check (!model.text = "new") "same-frame Command release broke text select-all";
    step [key Input.Shift; key Input.ArrowLeft; Event.KeyReleased Input.Shift;
      key Input.Backspace];
    check (!model.text = "ne") "same-frame Shift release broke text selection";
    step [key Input.Tab; key Input.Enter];
    check (!model.clicks = 2) "Tab did not wrap to the first control";
    step [key Input.Escape];
    check (not (Ui.text_input_focused ui)) "Escape did not return control keys to the host";
    step [key Input.Tab];
    step [Event.WindowFocusLost; key Input.Enter];
    check (!model.clicks = 2 && not (Ui.text_input_focused ui))
      "focus loss did not cancel keyboard activation";
    let popup ui =
      let menu = Ui.context_menu ui ~at:(100., 100.) "menu"
        ["Disabled", false; "Enabled", true] in
      let background = Ui.panel ui "background" (fun () -> Ui.button ui "Background") in
      menu, background in
    ignore (Ui.frame ui (frame []) popup);
    let menu, background = Ui.frame ui (frame [key Input.Tab; key Input.Enter]) popup in
    check (menu = `Pick 1 && not background)
      "modal traversal reached a disabled row or escaped to the background";
    ignore (Ui.frame ui (frame [Event.WindowFocusLost]) (fun _ -> ()));
    let picker ui = Ui.modal ui "picker" (fun () ->
      Ui.picker ui "Search" ~query:"" (fun _ -> [|"One", ""; "Two", ""|])) in
    ignore (Ui.frame ui (frame []) picker);
    let picked = Ui.frame ui (frame [key Input.Tab; key Input.Enter]) picker in
    check (picked = Some ("", `Pick 0)) "picker stole focus from its keyboard-activated row";
    print_endline "PXUI keyboard: traversal, activation, text, cancellation and modal ownership passed")
