open Rays
module Ui = Pxui.Ui

let check condition message = if not condition then failwith message

let frame ?(buttons = []) ?(keys = []) events : Frame.t = {
  width = 320; height = 240; size = 320, 240;
  drawable_width = 320; drawable_height = 240; drawable_size = 320, 240;
  pixel_scale = 1., 1.; time = 0.; dt = 0.; fps = 60.; count = 0;
  mouse = 10., 10.; mouse_delta = 0., 0.; keys; mouse_buttons = buttons; events }

let run () =
  let ui = Ui.create ~font_size:11 () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
  let body ui =
    let view = Ui.box ui ~flags:Ui.clickable ~at:(0., 0.)
      ~w:(Ui.Px 160.) ~h:(Ui.Px 240.) "view" in
    let control = Ui.within ui view (fun () -> Ui.box ui
      ~flags:Ui.(clickable + focusable) ~at:(30., 30.)
      ~w:(Ui.Px 50.) ~h:(Ui.Px 50.) "control") in
    let graph = Ui.box ui ~flags:Ui.(clickable + scroll) ~at:(160., 0.)
      ~w:(Ui.Px 160.) ~h:(Ui.Px 240.) "graph" in
    Ui.key view, Ui.signal ui control, Ui.signal ui graph in
  let step ?(popup = false) frame =
    let owner, control, graph = Ui.frame ui frame (fun ui ->
      if popup then ignore (Ui.modal ui "modal" (fun () -> Ui.label ui "Popup"));
      body ui) in
    Ui.input ~owner ui, control, graph in
  ignore (step (frame []));
  let drag = [Event.MousePressed (Input.RightButton, (10., 10.));
    Event.MouseMoved (220., 20.); Event.MouseReleased (Input.RightButton, (220., 20.))] in
  let input, _, graph = step (frame drag) in
  check (input.events = drag && not graph.pressed) "viewport capture did not survive a pane crossing/release";
  let drag = [Event.MousePressed (Input.MiddleButton, (200., 10.));
    Event.MouseMoved (10., 10.); Event.MouseReleased (Input.MiddleButton, (10., 10.))] in
  let input, _, graph = step (frame drag) in
  check (input.events = [Event.PointerCancelled Input.MiddleButton] && graph.pressed)
    "graph-owned drag reached the viewport";
  let click = [Event.MousePressed (Input.LeftButton, (40., 40.));
    Event.MouseReleased (Input.LeftButton, (40., 40.)); Event.KeyPressed Input.Enter] in
  let input, control, _ = step (frame ~keys:[Input.Shift] click) in
  check (control.clicked && input.events = [Event.PointerCancelled Input.LeftButton]
    && input.keys = []) "child widget input escaped to its viewport root";
  let events = click @ [Event.MouseScrolled (0., 1.)] in
  let input, control, _ = step ~popup:true (frame events) in
  check (not control.clicked && input.mouse_buttons = [] && input.mouse_delta = (0., 0.)
    && input.events = [Event.PointerCancelled Input.LeftButton])
    "new popup did not shield this frame's underlying controls";
  let input, control, _ = step ~popup:true (frame (Event.KeyPressed Input.Escape :: click)) in
  check (not control.clicked && input.events = [Event.PointerCancelled Input.LeftButton])
    "popup dismissal leaked its remaining press/release events";
  ignore (step (frame []));
  ignore (step (frame ~buttons:[Input.RightButton]
    [Event.MousePressed (Input.RightButton, (10., 10.))]));
  let input, _, _ = step ~popup:true (frame ~buttons:[Input.RightButton] []) in
  check (List.mem (Event.PointerCancelled Input.RightButton) input.events)
    "popup opening did not cancel the viewport's captured gesture";
  ignore (step (frame [Event.WindowFocusLost]));
  let input, _, _ = step (frame [Event.WindowFocusLost; Event.PointerCancelled Input.RightButton]) in
  check (input.events = [Event.WindowFocusLost; Event.PointerCancelled Input.RightButton])
    "cancellation events were consumed";
  let modal_y key =
    let row = Ui.frame ui (frame []) (fun ui -> Ui.modal ui key (fun () ->
      Ui.box ui ~h:(Ui.Px 24.) "row")) |> Option.get in
    let _, y, _, _ = Ui.rect ui row in y in
  ignore (modal_y "height-original");
  let centred = modal_y "height-original" in
  ignore (Ui.frame ui (frame []) (fun _ -> ()));
  ignore (Ui.frame ui (frame []) (fun _ -> ()));
  check (modal_y "height-original" = centred) "closed modal lost its remembered height";
  for index = 0 to 63 do
    let key = "height-" ^ string_of_int index in
    ignore (modal_y key); ignore (modal_y key)
  done;
  check (modal_y "height-original" <> centred) "dynamic modal keys did not evict old cached heights";
  let probe ui =
    let box = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 100.) ~h:(Ui.Px 100.) "press-keys" in
    Ui.press_keys ui box in
  ignore (Ui.frame ui (frame []) probe);
  let pressed = Ui.frame ui (frame ~keys:[Input.Shift] ~buttons:[Input.LeftButton]
    [Event.KeyPressed Input.Shift; Event.MousePressed (Input.LeftButton, (10., 10.))]) probe in
  let held = Ui.frame ui (frame ~buttons:[Input.LeftButton]
    [Event.KeyReleased Input.Shift; Event.MouseMoved (20., 10.)]) probe in
  let released = Ui.frame ui (frame [Event.MouseReleased (Input.LeftButton, (20., 10.))]) probe in
  check (pressed = [Input.Shift] && held = pressed && released = pressed)
    "captured press keys changed during motion or release";
  print_endline "PXUI ordered input: viewport/child ownership, crossings, popup transitions and cancellation passed")
