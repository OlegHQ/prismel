open Rays
module Ui = Pxui.Ui

let check condition message = if not condition then failwith message
let key value = Event.KeyPressed value
let frame ?(keys = []) events : Frame.t = {
  width = 500; height = 360; size = 500, 360;
  drawable_width = 500; drawable_height = 360; drawable_size = 500, 360;
  pixel_scale = 1., 1.; time = 1.; dt = 0.; fps = 60.; count = 0;
  mouse = -10., -10.; mouse_delta = 0., 0.; keys; mouse_buttons = []; events }

type model = { clicks : int; enabled : bool; choice : int; amount : float;
  count : int; range : float * float; point : float * float; text : string }

let run () =
  let ui = Ui.create () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
    let model = ref { clicks = 0; enabled = false; choice = 0; amount = 0.5;
      count = 2; range = 0.2, 0.8; point = 0.5, 0.5; text = "old" } in
    let build ui = Ui.panel ui ~width:400. "controls" (fun () ->
      let clicks = !model.clicks + if Ui.button ui "Run" then 1 else 0 in
      let enabled = Ui.toggle ui "Enabled" !model.enabled in
      let choice = Ui.choice ui "Choice" ["A"; "B"; "C"] !model.choice in
      let amount = Ui.slider ui "Amount" ~range:(0., 1.) !model.amount in
      let count = Ui.int_slider ui "Count" ~range:(0, 5) !model.count in
      let range = Ui.range_slider ui "Range" ~range:(0., 1.) !model.range in
      let point = Ui.xy ui "Point" ~x_range:(0., 1.) ~y_range:(0., 1.) !model.point in
      ignore (Ui.accordion ui "Details" (fun () -> Ui.label ui "Detail"));
      let text = Ui.text_field ui "Text" !model.text in
      { clicks; enabled; choice; amount; count; range; point; text }) in
    let step ?keys events = model := Ui.frame ui (frame ?keys events) build in
    step [];
    step [key Input.Shift; key Input.Tab; Event.KeyReleased Input.Shift; Event.TextInput "!"];
    check (!model.text = "old!") "same-frame Shift release changed backwards Tab traversal";
    step [key Input.Tab; key Input.Enter];
    check (!model.clicks = 1 && (Ui.input ui).events = [])
      "Tab/Enter did not activate the first control or leaked into the host";
    step [key Input.Tab; key Input.Space];
    check !model.enabled "Space did not toggle the focused control";
    step [key Input.Tab; key Input.ArrowLeft];
    check (!model.choice = 2) "keyboard choice did not wrap backwards";
    step [key Input.Enter];
    check (!model.choice = 0) "Enter did not advance a choice";
    step [key Input.Tab; key Input.End; key Input.ArrowRight];
    check (!model.amount = 1.) "slider keyboard adjustment did not clamp";
    step [key Input.Home; key Input.Shift; key Input.ArrowRight;
      Event.KeyReleased Input.Shift; key Input.ArrowRight];
    check (abs_float (!model.amount -. 0.11) < 1e-12)
      "slider steps used final Shift state instead of each key's modifiers";
    step [key Input.Meta; key Input.Enter; Event.KeyReleased Input.Meta];
    step [Event.TextInput "9"; key Input.Escape];
    check (abs_float (!model.amount -. 0.11) < 1e-12)
      "Command-Enter incorrectly opened numeric entry";
    (* Escape relinquishes the slider's keyboard stop; restore it. *)
    step (List.init 4 (fun _ -> key Input.Tab));
    step [key Input.Enter; Event.TextInput "3.25"; key Input.Enter];
    check (!model.amount = 3.25) "keyboard numeric entry did not preserve the soft range";
    (* Committing numeric input relinquishes focus, so traversal restarts. *)
    step (List.init 5 (fun _ -> key Input.Tab) @ [key Input.ArrowRight]);
    check (!model.count = 3) "integer keyboard adjustment did not move one unit";
    step [key Input.Tab; key Input.ArrowRight];
    check (abs_float (fst !model.range -. 0.21) < 1e-12)
      "range keyboard adjustment did not move the lower handle";
    step [key Input.Space; key Input.ArrowLeft];
    check (abs_float (snd !model.range -. 0.79) < 1e-12)
      "range keyboard activation did not select the upper handle";
    step [key Input.Tab; key Input.ArrowRight; key Input.ArrowUp];
    check (!model.point = (0.51, 0.49)) "XY control ignored keyboard movement";
    step [key Input.Tab; key Input.Enter];
    let opened = Ui.frame ui (frame []) (fun ui ->
      Ui.panel ui ~width:400. "controls" (fun () -> Ui.expanded ui "Details")) in
    check (opened = Some true) "accordion ignored keyboard activation";
    (* Rebuilding fewer controls prunes focus and keeps hidden controls inert. *)
    check (not (Ui.text_input_focused ui)) "disappearing focused controls kept focus";
    step [];
    step ~keys:[Input.Shift] [key Input.Tab; Event.TextInput "!"];
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
    let original = Float.next_after 0.1 1., 999.999_999_999_999_9 in
    let unchanged = ref original in
    for _ = 1 to 20 do
      unchanged := Ui.frame ui (frame []) (fun ui -> Ui.panel ui "idle-range" (fun () ->
        Ui.range_slider ui "Range" ~range:(0.1, 1000.) !unchanged))
    done;
    check (!unchanged = original) "idle range controls changed values without an edit";
    let custom ui =
      let control = Ui.box ui ~flags:Ui.tab_stop ~w:(Ui.Px 100.) ~h:(Ui.Px 24.) "custom" in
      Ui.focus ui control;
      Ui.key_events ui control in
    ignore (Ui.frame ui (frame []) custom);
    let modifiers = Ui.frame ui (frame [key Input.Meta; key (Input.KeyChar 'a');
        Event.KeyReleased Input.Meta; key (Input.KeyChar 'a')]) custom
      |> List.filter_map (function
        | Event.KeyPressed (Input.KeyChar 'a'), held -> Some (List.mem Input.Meta held)
        | _ -> None) in
    check (modifiers = [true; false]) "custom controls lost per-event modifier context";
    print_endline "PXUI keyboard: traversal, activation, adjustments, text, cancellation and modal ownership passed")
