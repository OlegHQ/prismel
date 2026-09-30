(* Interaction contract of the immediate-mode kit: press/drag/release,
   capture, focus loss, text entry, numeric editing, scrolling, accordions,
   and identical behaviour at 1x and 2x backing scales. *)
open Prismel
module Ui = Pxui.Ui

let fail message = raise (Failure message)
let pointer (x, y) = float x, float y
let press point = Event.MousePressed (Input.LeftButton, pointer point)
let release point = Event.MouseReleased (Input.LeftButton, pointer point)
let move point = Event.MouseMoved (pointer point)

let frame ~scale ~time events : Frame.t =
  { width = 320; height = 240; size = 320, 240;
    drawable_width = int_of_float (320. *. scale);
    drawable_height = int_of_float (240. *. scale);
    drawable_size = int_of_float (320. *. scale), int_of_float (240. *. scale);
    pixel_scale = scale, scale; time; dt = 1. /. 60.; fps = 60.; count = 0;
    mouse = 0., 0.; mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events }

(* A panel at the origin, 240 wide: rows start at y = 3 and are 24 tall; the
   value column starts at x = 120 (half the 234-point inner width) and
   toggles occupy x in [197, 237). *)
let row y = 3 + (y * 24) + 12

let with_scale scale =
  let time = ref 0. in
  let step ui events build =
    time := !time +. 0.5;
    Ui.frame ui (frame ~scale ~time:!time events) (fun ui ->
      Ui.panel ui ~x:0. ~y:0. ~width:240. "panel" (fun () -> build ui)) in
  let fast_step ui events build =
    time := !time +. 0.1;
    Ui.frame ui (frame ~scale ~time:!time events) (fun ui ->
      Ui.panel ui ~x:0. ~y:0. ~width:240. "panel" (fun () -> build ui)) in
  let modified_step ui modifiers key build =
    time := !time +. 0.5;
    Ui.frame ui
      { (frame ~scale ~time:!time [Event.KeyPressed key])
        with keys = modifiers }
      (fun ui -> Ui.panel ui ~x:0. ~y:0. ~width:240. "panel"
        (fun () -> build ui)) in
  let command_step ui key build =
    modified_step ui [Input.Meta] (Input.KeyChar key) build in
  let settle ui build = ignore (step ui [] build) in
  let label = Printf.sprintf "%gx: %s" scale in

  let ui = Ui.create () in
  let roots events = Ui.frame ui (frame ~scale ~time:0.5 events) (fun ui ->
    let root = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 100.)
      ~h:(Ui.Px 100.) "root" in
    let child = Ui.within ui root (fun () ->
      Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 30.) ~h:(Ui.Px 30.)
        ~at:(10., 10.) "child") in
    Ui.signal ui root, Ui.signal ui child, Ui.key root) in
  let _, _, root_key = roots [] in
  if Ui.last_press_within ui (frame ~scale ~time:0.5 [press (15, 15)])
      [root_key] <> Some root_key then
    fail (label "hit-tree preview missed a child press");
  let root, child, _ = roots [press (15, 15)] in
  if root.pressed || root.subtree_press <> Some 0
      || not child.pressed || child.subtree_press <> Some 0 then
    fail (label "child press did not reach its hit ancestor");
  let root, child, _ = roots [release (15, 15); press (80, 80)] in
  if not root.pressed || root.subtree_press <> Some 1
      || child.pressed then
    fail (label "blank root press did not select the root");
  Ui.destroy ui;

  (* Toggle commits on release inside, never on press alone. *)
  let ui = Ui.create () in
  let value = ref false in
  let build ui = value := Ui.toggle ui "Enabled" !value in
  settle ui build;
  step ui [press (210, row 0)] build;
  if !value then fail (label "toggle fired before release");
  step ui [release (210, row 0)] build;
  if not !value then fail (label "toggle did not react to a click");
  step ui [press (210, row 0); release (300, row 0)] build;
  if not !value then fail (label "toggle fired after release outside");
  step ui [press (237, row 0); release (236, row 0)] build;
  if not !value then fail (label "half-open bounds accepted a press on the right edge");

  (* Slider capture: continuous, beyond bounds, clamped to the drag range. *)
  let amount = ref 5. in
  let build ui = amount := Ui.slider ui "Amount" ~range:(0., 10.) !amount in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (150, row 0)] build;
  let pressed = !amount in
  step ui [move (400, row 0)] build;
  if !amount <> 10. then fail (label "slider drag did not capture and clamp");
  step ui [move (100, row 0)] build;
  if !amount <> 0. then fail (label "slider did not follow the captured pointer");
  step ui [release (100, row 0)] build;
  if pressed = 5. then fail (label "slider press did not set the value");

  (* Compact inspector sliders use the visible track's position, including
     on a simple click, and Option-click opens the numeric editor. *)
  let compact = ref "0" in
  let build ui =
    let value, _ = Ui.value_field ui ~at:(20., 20.) ~w:101. ~h:21.
      ~fraction:(Option.value ~default:0. (float_of_string_opt !compact))
      ~slide:(fun fraction -> Printf.sprintf "%.17g" fraction)
      ~valid:(fun text -> float_of_string_opt text <> None) "compact" !compact in
    compact := value in
  let ui = Ui.create () in
  ignore (Ui.frame ui (frame ~scale ~time:0. [] ) build);
  ignore (Ui.frame ui (frame ~scale ~time:0.5
    [press (70, 30); release (70, 30)]) build);
  if abs_float (Option.get (float_of_string_opt !compact) -. 0.5) > 0.02
      || Ui.text_input_focused ui then
    fail (label "compact slider click did not jump to the pointer");
  ignore (Ui.frame ui { (frame ~scale ~time:1. [press (90, 30); release (90, 30)])
    with keys = [Input.Alt] } build);
  if not (Ui.text_input_focused ui) then
    fail (label "Option-click did not open compact numeric entry");
  let ui = Ui.create () in
  let build ui = amount := Ui.slider ui "Amount" ~range:(0., 10.) !amount in
  settle ui build;
  step ui [press (150, row 0)] build;
  let before = !amount in
  step ui [Event.WindowFocusLost; move (400, row 0)] build;
  if !amount <> before then fail (label "window focus loss did not cancel capture");
  step ui [press (150, row 0)] build;
  let before = !amount in
  step ui [Event.PointerCancelled Input.LeftButton; move (400, row 0)] build;
  if !amount <> before then fail (label "pointer cancellation did not stop capture");

  (* Buttons fire on release inside only. *)
  let clicks = ref 0 in
  let build ui = if Ui.button ui "Apply" then incr clicks in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (20, row 0); move (300, row 0); release (300, row 0)] build;
  if !clicks <> 0 then fail (label "button fired after release outside");
  step ui [press (20, row 0); release (20, row 0)] build;
  if !clicks <> 1 then fail (label "button did not fire on release inside");

  (* Accordions hide their rows and keep child values in the model. *)
  let nested = ref false and visible = ref false in
  let build ui =
    ignore (Ui.accordion ui "Advanced" (fun () ->
      nested := Ui.toggle ui "Nested" !nested));
    visible := Ui.toggle ui "Visible" !visible in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (210, row 1); release (210, row 1)] build;
  if not !visible || !nested then
    fail (label "collapsed accordion occupied a row");
  step ui [press (20, row 0); release (20, row 0)] build;
  settle ui build;
  step ui [press (210, row 1); release (210, row 1)] build;
  if not !nested then fail (label "expanded accordion child was not interactive");

  (* Integer sliders snap and clamp; typed values may exceed the soft range. *)
  let count = ref 2 in
  let build ui = count := Ui.int_slider ui "Count" ~range:(1, 5) !count in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (130, row 0); move (400, row 0); release (400, row 0)] build;
  if !count <> 5 then fail (label "integer slider did not snap and clamp");
  step ui [press (20, row 0); release (20, row 0)] build;
  fast_step ui [press (20, row 0); release (20, row 0)] build;
  if not (Ui.text_input_focused ui) then fail (label "label double-click did not edit");
  step ui [Event.TextInput "27"; Event.KeyPressed Input.Enter] build;
  if !count <> 27 || Ui.text_input_focused ui then
    fail (label "typed integer was not committed beyond the soft range");
  step ui [press (20, row 0); release (20, row 0)] build;
  fast_step ui [press (20, row 0); release (20, row 0)] build;
  step ui [Event.TextInput "3.5"; Event.KeyPressed Input.Enter] build;
  if !count <> 27 || not (Ui.text_input_focused ui) then
    fail (label "invalid integer text was committed or dismissed");
  step ui [Event.KeyPressed Input.Escape; Event.TextInput "4"] build;
  if !count <> 27 || Ui.text_input_focused ui then
    fail (label "Escape did not cancel numeric editing");
  step ui [press (20, row 0); release (20, row 0)] build;
  fast_step ui [press (20, row 0); release (20, row 0)] build;
  let previous_clipboard = Clipboard.get_text () in
  Fun.protect ~finally:(fun () ->
    match previous_clipboard with
    | Ok text -> ignore (Clipboard.set_text text)
    | Error _ -> ()) (fun () ->
      (match Clipboard.set_text "31" with Ok () -> ()
       | Error message -> fail message);
      command_step ui 'v' build;
      step ui [Event.KeyPressed Input.Enter] build;
      if !count <> 31 then fail (label "numeric editor did not paste valid text"));
  step ui [press (20, row 0); release (20, row 0)] build;
  fast_step ui [press (20, row 0); release (20, row 0)] build;
  step ui [Event.KeyPressed Input.ArrowRight;
    Event.KeyPressed Input.ArrowLeft; Event.TextInput "2";
    Event.KeyPressed Input.Enter] build;
  if !count <> 321 then fail (label "numeric editor ignored its insertion caret");

  let amount = ref 0.25 in
  let build ui = amount := Ui.slider ui "Amount" ~range:(0., 1.) !amount in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (20, row 0); release (20, row 0)] build;
  fast_step ui [press (20, row 0); release (20, row 0)] build;
  step ui [Event.TextInput "2.5"] build;
  step ui [press (300, 200)] build;
  if !amount <> 2.5 then fail (label "typed float was not committed by an outside press");

  (* A bounded panel scrolls by whole rows and routes hits to scrolled rows. *)
  let toggles = Array.make 4 false in
  let scrolled ui =
    Ui.panel ui ~x:0. ~y:0. ~width:240. ~max_height:80. "scroll" (fun () ->
      Array.iteri (fun index value ->
        toggles.(index) <- Ui.toggle ui (Printf.sprintf "Row %d" index) value)
        toggles) in
  let ui = Ui.create () in
  let scroll_step events =
    time := !time +. 0.5;
    Ui.frame ui (frame ~scale ~time:!time events) scrolled in
  scroll_step [];
  scroll_step [move (100, 40); Event.MouseScrolled (0., (-2.))];
  (* 102 points of rows in an 80-point panel scroll by at most 22. *)
  scroll_step [press (210, 40); release (210, 40)];
  if not toggles.(2) || toggles.(0) || toggles.(1) then
    fail (label "scrolled panel did not route the hit to the scrolled row");

  let fixed = Array.make 4 false in
  let ui = Ui.create () in
  let fixed_panel events =
    time := !time +. 0.5;
    Ui.frame ui (frame ~scale ~time:!time events) (fun ui ->
      Ui.panel ui ~x:0. ~y:0. ~width:240. ~height:80. "fixed" (fun () ->
        Array.iteri (fun index value ->
          fixed.(index) <- Ui.toggle ui (Printf.sprintf "Fixed %d" index) value)
          fixed)) in
  fixed_panel [];
  fixed_panel [move (100, 40); Event.MouseScrolled (0., -2.)];
  fixed_panel [press (210, 40); release (210, 40)];
  if not fixed.(2) || fixed.(0) || fixed.(1) then
    fail (label "fixed-height inspector panel did not scroll its rows");

  let ui = Ui.create () in
  let child_y = ref 0. in
  let rubber events =
    time := !time +. 0.5;
    let child = Ui.frame ui (frame ~scale ~time:!time events) (fun ui ->
      let parent = Ui.box ui ~flags:Ui.(scroll + clip) ~at:(0., 0.)
          ~w:(Ui.Px 100.) ~h:(Ui.Px 80.) ~scroll_step:24. "rubber" in
      Ui.within ui parent (fun () ->
        Ui.box ui ~w:(Ui.Px 100.) ~h:(Ui.Px 100.) "content")) in
    child_y := let _, y, _, _ = Ui.rect ui child in y in
  rubber [];
  rubber [move (50, 40); Event.MouseScrolled (0., 1.)];
  if !child_y <= 0. then fail (label "scroll did not stretch past the top edge");
  rubber [];
  if Float.abs !child_y > 0.25 then
    fail (label "rubber scroll did not spring back to the edge");

  let ui = Ui.create () in
  let scroll_dir events =
    time := !time +. 0.5;
    Ui.frame ui (frame ~scale ~time:!time events) (fun ui ->
      let parent = Ui.box ui ~flags:Ui.(scroll + clip)
          ~at:(0., 0.) ~w:(Ui.Px 100.) ~h:(Ui.Px 80.)
          ~scroll_step:24. "direction" in
      Ui.within ui parent (fun () ->
        ignore (Ui.box ui ~w:(Ui.Px 100.) ~h:(Ui.Px 240.) "long"));
      parent) in
  let parent = scroll_dir [] in
  Ui.set_scroll_offset ui parent 80.;
  let parent = scroll_dir [move (50, 40); Event.MouseScrolled (0., 1.)] in
  if Ui.scroll_offset ui parent <> 56. then
    fail (label "positive natural scroll did not move the view up");
  let parent = scroll_dir [Event.MouseScrolled (0., -1.)] in
  if Ui.scroll_offset ui parent <> 80. then
    fail (label "negative wheel scroll did not move the view down");

  (* Text fields: UTF-8 entry, Backspace/Delete, focus kept on cancel. *)
  let title = ref "" in
  let build ui = title := Ui.text_field ui "Title" !title in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (150, row 0); release (150, row 0);
    Event.TextEditing { text = "e"; start = 0; length = 1 };
    Event.TextInput "hé"; Event.KeyPressed Input.Backspace] build;
  if !title <> "h" then fail (label "text field did not accept UTF-8 input and backspace");
  let ime_cursor () = match Scene.Private.text_regions (Ui.scene ui) with
    | [(_, _, _, _, true, cursor)] -> cursor
    | _ -> fail (label "focused text field lost its IME region") in
  let cursor_after_h = ime_cursor () in
  if cursor_after_h <= 8 then fail (label "IME cursor stayed at the field origin");
  step ui [Event.PointerCancelled Input.LeftButton; Event.TextInput "!"] build;
  if !title <> "h!" then fail (label "pointer cancellation dismissed text focus");
  if ime_cursor () <= cursor_after_h then
    fail (label "IME cursor did not follow the inserted text");
  step ui [Event.TextInput " two words"; Event.KeyPressed Input.Delete;
    Event.TextInput "!"] build;
  if !title <> "h! two words!" || not (Ui.text_input_focused ui) then
    fail (label "focused text input lost spaces or changed at-end Delete");
  step ui [Event.KeyPressed Input.ArrowLeft; Event.KeyPressed Input.Backspace] build;
  if !title <> "h! two word!" then
    fail (label "Backspace ignored the moved caret");
  let cursor_before_end = ime_cursor () in
  step ui [Event.KeyPressed Input.End] build;
  if ime_cursor () <= cursor_before_end then
    fail (label "IME cursor ignored keyboard caret movement");
  let previous_clipboard = Clipboard.get_text () in
  Fun.protect ~finally:(fun () ->
    match previous_clipboard with
    | Ok text -> ignore (Clipboard.set_text text)
    | Error _ -> ()) (fun () ->
      (match Clipboard.set_text " pasted" with
       | Ok () -> () | Error message -> fail message);
      command_step ui 'v' build;
      if !title <> "h! two word! pasted" then
        fail (label "Command-V did not paste into the focused text field");
      command_step ui 'c' build;
      if Clipboard.get_text () <> Ok !title then
        fail (label "Command-C did not copy the focused text field");
      command_step ui 'x' build;
      if !title <> "" || Clipboard.get_text () <> Ok "h! two word! pasted" then
        fail (label "Command-X did not cut the focused text field");
      step ui [Event.TextInput "aé中z";
        Event.KeyPressed Input.ArrowLeft;
        Event.KeyPressed Input.ArrowLeft;
        Event.KeyPressed Input.Delete] build;
      if !title <> "aéz" then
        fail (label "Delete did not remove one UTF-8 character at the caret");
      modified_step ui [Input.Shift] Input.ArrowLeft build;
      command_step ui 'c' build;
      if Clipboard.get_text () <> Ok "é" then
        fail (label "Command-C ignored the selected UTF-8 character");
      command_step ui 'x' build;
      if !title <> "az" then fail (label "Command-X ignored selection bounds");
      command_step ui 'v' build;
      if !title <> "aéz" then fail (label "paste ignored the insertion caret"));
  step ui [press (125, row 0); release (125, row 0); Event.TextInput "!"] build;
  if !title <> "!aéz" then fail (label "mouse click did not place the text caret");
  step ui [press (300, 200)] build;
  if Ui.text_input_focused ui then fail (label "an outside press kept text focus");
  Ui.destroy ui;

  let short = ref "x" and long = ref "long text" in
  let build ui =
    short := Ui.text_field ui "Short" !short;
    long := Ui.text_field ui "Long" !long in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (150, row 1); release (150, row 1)] build;
  step ui [] build;
  if !short <> "x" || !long <> "long text" then
    fail (label "unfocused short field reused the longer field caret");
  Ui.destroy ui;

  let long_value = "abcdefghijklmnopqrstuvwxyz0123456789" in
  let field = ref long_value in
  let build ui =
    let value, _ = Ui.value_field ui ~at:(20., 20.) ~w:100. ~h:21.
      ~valid:(fun _ -> true) "long-field" !field in
    field := value in
  let ui = Ui.create () in
  let field_time = ref 0. in
  let field_step ?(keys = []) events =
    field_time := !field_time +. 0.5;
    ignore (Ui.frame ui { (frame ~scale ~time:!field_time events) with keys }
      build) in
  field_step [];
  field_step [press (40, 30); release (40, 30)];
  let cursor () = match Scene.Private.text_regions (Ui.scene ui) with
    | [(_, _, _, _, true, cursor)] -> cursor
    | regions -> fail (label (Printf.sprintf "long field lost its IME region (%d)"
        (List.length regions))) in
  field_step ~keys:[Input.Meta] [Event.KeyPressed Input.ArrowLeft];
  if cursor () > 12 then fail (label "Command-Left did not reveal the start");
  field_step ~keys:[Input.Meta] [Event.KeyPressed Input.ArrowRight];
  if cursor () < 80 || cursor () > 100 then
    fail (label "Command-Right did not reveal the end");
  field_step ~keys:[Input.Meta] [Event.KeyPressed Input.ArrowLeft];
  field_step [press (30, 30)];
  field_step [move (220, 30)];
  for _ = 1 to 30 do field_step [] done;
  field_step [release (220, 30)];
  let previous_clipboard = Clipboard.get_text () in
  Fun.protect ~finally:(fun () ->
    match previous_clipboard with
    | Ok text -> ignore (Clipboard.set_text text)
    | Error _ -> ()) (fun () ->
      field_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'c')];
      if Clipboard.get_text () <> Ok long_value then
        fail (label "edge drag did not select through the end"));
  Ui.destroy ui;

  (* Choice, range, and XY controls. *)
  let mode = ref 0 and band = ref (0.25, 0.75) and point = ref (0., 0.) in
  let build ui =
    mode := Ui.choice ui "Mode" ["dots"; "lines"] !mode;
    band := Ui.range_slider ui "Band" ~range:(0., 1.) !band;
    point := Ui.xy ui "Point" ~x_range:(-1., 1.) ~y_range:(-1., 1.) !point in
  let ui = Ui.create () in
  settle ui build;
  step ui [press (20, row 0); release (20, row 0)] build;
  if !mode <> 0 then fail (label "choice label area activated its control");
  step ui [press (200, row 0); release (200, row 0)] build;
  if !mode <> 1 then fail (label "choice right half did not advance");
  step ui [press (130, row 1); move (160, row 1); release (160, row 1)] build;
  if !band = (0.25, 0.75) || snd !band <> 0.75 then
    fail (label "range did not drag its nearer handle");
  step ui [press (150, row 2); move (200, row 2 + 6); release (200, row 2 + 6)] build;
  if !point = (0., 0.) then fail (label "xy pad did not update");
  Ui.destroy ui

let run () =
  (match Sdl3.Init.init [Sdl3.Init.Video] with
   | Ok () -> () | Error error -> fail (Format.asprintf "%a" Sdl3.pp_error error));
  let ui = Ui.create () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
    let build ?(key = "a") ?(skip = false) ui =
      let parent = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 100.) ~h:(Ui.Px 100.) "hover-parent" in
      let child = Ui.within ui parent (fun () ->
        Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 40.) ~h:(Ui.Px 40.) "hover-child") in
      let ready = not skip && Ui.hovered_within ui parent && Ui.hover_delay ui ~key in
      if ready then Ui.tooltip ui ~key ~text:"A shared tooltip.";
      ready, Ui.hovered_within ui parent, (Ui.signal ui child).hovered in
    let step ?key ?skip time events = Ui.frame ui (frame ~scale:1. ~time events)
      (build ?key ?skip) in
    ignore (step 0. []);
    let ready, parent, child = step 0.1 [move (10,10)] in
    if ready || not parent || not child then fail "hover ancestry did not use the shared hit tree";
    let ready,_,_ = step 0.479 [] in
    if ready then fail "tooltip appeared before 380 ms";
    let ready,_,_ = step 0.481 [] in
    if not ready then fail "tooltip did not appear after 380 ms";
    let ready,_,_ = step 0.5 [move (11,10)] in
    if ready then fail "pointer motion did not restart hover rest";
    let ready,_,_ = step 0.881 [] in
    if not ready then fail "tooltip did not restart after movement";
    ignore (step 0.9 [Event.WindowFocusLost]);
    let ready,_,_ = step 0.91 [move (11,10)] in
    if ready then fail "focus loss kept hover rest";
    let ready,_,_ = step ~key:"b" 1.3 [] in
    if ready then fail "a different target inherited hover time";
    let ready,_,_ = step ~key:"b" 1.681 [] in
    if not ready then fail "changed target did not settle";
    ignore (step ~skip:true 1.7 []);
    let ready,_,_ = step ~key:"b" 2.1 [] in
    if ready then fail "leaving a target retained its timer";
    let ready,_,_ = step ~key:"b" 2.6 [press (11,10)] in
    if ready then fail "pointer capture displayed a tooltip";
    ignore (step 2.7 [release (11,10)]);
    let ready,_,_ = step 1. [] in
    if ready then fail "a backwards clock retained hover time";
    let ready = Ui.frame ui (frame ~scale:1. ~time:1.5 []) (fun ui ->
      ignore (Ui.modal ui "hover-modal" (fun () -> Ui.label ui "Modal"));
      Ui.hover_delay ui ~key:"a") in
    if ready then fail "a newly opened popup kept a background tooltip");
  with_scale 1.;
  with_scale 2.;
  (* Hover: the topmost control under the pointer, from last frame's rects. *)
  let ui = Ui.create () in
  let hovered = ref false in
  let build ui = Ui.panel ui ~x:0. ~y:0. ~width:240. "panel" (fun () ->
    let row = Ui.box ui ~flags:Ui.clickable ~w:Ui.Grow ~h:(Ui.Px 24.) "probe" in
    hovered := (Ui.signal ui row).hovered) in
  Ui.frame ui (frame ~scale:2. ~time:0. []) build;
  Ui.frame ui (frame ~scale:2. ~time:0.1 [move (40, 12)]) build;
  if not !hovered || not (Ui.wants_pointer ui) then fail "hover did not follow the pointer";
  Ui.frame ui (frame ~scale:2. ~time:0.2 [move (300, 200)]) build;
  if !hovered || Ui.wants_pointer ui then fail "hover outlived the pointer";
  let divider ui =
    let parent = Ui.box ui ~w:(Ui.Px 100.) ~h:(Ui.Px 100.)
        ~axis:Ui.Row "divider parent" in
    Ui.within ui parent (fun () -> ignore (Ui.splitter ui "divider")) in
  Ui.frame ui (frame ~scale:1. ~time:0.3 []) divider;
  Ui.frame ui (frame ~scale:1. ~time:0.4 [move (3, 12)]) divider;
  if Ui.cursor ui <> Some `Horizontal_resize then
    fail "splitter did not request a resize cursor on hover";
  Ui.frame ui (frame ~scale:1. ~time:0.5 [move (300, 200)]) divider;
  if Ui.cursor ui <> None then fail "splitter cursor outlived hover";
  Ui.destroy ui;
  (* A canvas maps child coordinates by scale and offset, for layout,
     painting, and hit testing alike. *)
  let ui = Ui.create () in
  let clicked = ref false and child_rect = ref (0., 0., 0., 0.) in
  let build ui =
    let canvas = Ui.box ui ~w:(Ui.Px 200.) ~h:(Ui.Px 200.) ~at:(10., 20.)
        ~xform:(2., 5., 0.) "canvas" in
    Ui.within ui canvas (fun () ->
      let child = Ui.box ui ~flags:Ui.clickable ~w:(Ui.Px 10.) ~h:(Ui.Px 10.)
          ~at:(3., 4.) "child" in
      child_rect := Ui.rect ui child;
      Ui.draw ui child (fun paint _ ->
        Ui.Paint.input_region paint ~x:0. ~y:0. ~w:10. ~h:10.
          ~focused:true ~cursor:5. ());
      if (Ui.signal ui child).clicked then clicked := true) in
  Ui.frame ui (frame ~scale:1. ~time:0. []) build;
  (match Scene.Private.text_regions (Ui.scene ui) with
   | [(_, _, _, _, true, 10)] -> ()
   | _ -> fail "canvas transform did not scale the IME caret offset");
  Ui.frame ui (frame ~scale:1. ~time:0.1 []) build;
  (* origin (10, 20) + (3, 4) * 2 + (5, 0) = (21, 28), 20 points square *)
  if !child_rect <> (21., 28., 20., 20.) then fail "canvas transform misplaced a child";
  Ui.frame ui (frame ~scale:1. ~time:0.2 [press (40, 47); release (40, 47)]) build;
  if not !clicked then fail "canvas child did not receive a transformed hit";
  Ui.destroy ui;
  (* A cached subtree replays last frame's boxes while its stamp holds. *)
  let ui = Ui.create () in
  let built = ref 0 in
  let build stamp ui =
    Ui.panel ui ~x:0. ~y:0. ~width:240. "panel" (fun () ->
      Ui.cached ui ~key:"static" ~stamp (fun () ->
        incr built; Ui.label ui "One"; Ui.label ui "Two")) in
  let instances () =
    match Scene.Private.stage_native ~width:320 ~height:240 (Ui.scene ui) with
    | Ok staged -> List.fold_left (fun total -> function
        | Scene.Private.Ui_layer (batch, _) -> total + Scene_command.Ui_batch.count batch
        | _ -> total) 0 staged.layers
    | Error message -> fail message in
  Ui.frame ui (frame ~scale:1. ~time:0. []) (build 1);
  let painted = instances () in
  Ui.frame ui (frame ~scale:1. ~time:0.1 []) (build 1);
  Ui.frame ui (frame ~scale:1. ~time:0.2 []) (build 1);
  if !built <> 1 || painted = 0 || instances () <> painted then
    fail "cached subtree was rebuilt or lost";
  Ui.frame ui (frame ~scale:1. ~time:0.3 []) (build 2);
  if !built <> 2 then fail "a new stamp did not rebuild the cached subtree";
  Ui.destroy ui;
  (* One panel paints in a handful of batches, not one draw per label. *)
  let ui = Ui.create () in
  Ui.frame ui (frame ~scale:2. ~time:0. []) (fun ui ->
    Ui.panel ui "panel" (fun () ->
      Ui.label ui "PXUI";
      ignore (Ui.toggle ui "Animate" true);
      ignore (Ui.slider ui "Radius" ~range:(10., 120.) 48.);
      ignore (Ui.int_slider ui "Steps" ~range:(1, 64) 8);
      ignore (Ui.choice ui "Palette" ["ocean"; "sunset"] 0);
      ignore (Ui.text_field ui "Caption" "Functional UI");
      ignore (Ui.button ui "Quit")));
  (match Scene.Private.stage_native ~width:320 ~height:240 (Ui.scene ui) with
   | Ok staged ->
       let batches = List.fold_left (fun total -> function
         | Scene.Private.Ui_layer (batch, _) ->
             total + Array.length (Scene_command.Ui_batch.batches batch)
         | _ -> total) 0 staged.layers in
       if batches = 0 || batches > 4 then
         fail (Printf.sprintf "panel painted in %d batches" batches)
   | Error message -> fail message);
  Ui.destroy ui;
  (* Picker: typing filters, arrows move the cursor, Enter picks an index of
     the filtered rows, Delete arms then deletes, Backspace on an empty query
     goes back, Escape cancels. *)
  let key k = Event.KeyPressed k in
  let items = [| "alpha", "1"; "beta", "2"; "gamma", "3"; "delta", "4" |] in
  let rows query = Array.of_list (List.filter
      (fun (label, _) -> Ui.fuzzy_match ~query label) (Array.to_list items)) in
  let ui = Ui.create () and query = ref "" and last = ref `None in
  let pick ?(command=false) ?(shift=false) events =
    Ui.frame ui
      { (frame ~scale:1. ~time:0. events) with
        keys = (if command then [Input.Meta]
          else if shift then [Input.Shift] else []) } (fun ui ->
      Ui.panel ui ~x:0. ~y:0. ~width:240. "p" (fun () ->
        let edited, result = Ui.picker ui "Search" ~query:!query rows in
        query := edited; last := result)) in
  pick [];
  if not (Ui.text_input_focused ui) then fail "picker did not take keyboard focus";
  pick [key Input.ArrowDown; key Input.ArrowDown; key Input.Enter];
  if !last <> `Pick 2 then fail "picker arrows did not move the cursor";
  pick [Event.TextInput "dla"; key Input.Enter];
  if !query <> "dla" || !last <> `Pick 0 || fst (rows !query).(0) <> "delta" then
    fail "picker typing did not filter rows before Enter";
  let previous_clipboard = Clipboard.get_text () in
  Fun.protect ~finally:(fun () ->
    match previous_clipboard with
    | Ok text -> ignore (Clipboard.set_text text)
    | Error _ -> ()) (fun () ->
      query := "";
      (match Clipboard.set_text "del" with Ok () -> ()
       | Error message -> fail message);
      pick ~command:true [key (Input.KeyChar 'v')];
      if !query <> "del" then fail "picker did not paste the search query";
      pick ~command:true [key (Input.KeyChar 'c')];
      if Clipboard.get_text () <> Ok "del" then
        fail "picker did not copy the search query";
      pick ~command:true [key (Input.KeyChar 'x')];
      if !query <> "" then fail "picker did not cut the search query";
      query := "delta";
      pick [];
      pick [key Input.ArrowLeft];
      pick ~shift:true [key Input.ArrowLeft];
      pick ~command:true [key (Input.KeyChar 'c')];
      if Clipboard.get_text () <> Ok "t" then
        fail "picker did not copy the selected query character";
      pick ~command:true [key (Input.KeyChar 'x')];
      if !query <> "dela" then fail "picker did not cut the selection";
      pick ~command:true [key (Input.KeyChar 'v')];
      if !query <> "delta" then fail "picker pasted outside the caret");
  query := "dla";
  pick [key Input.Delete];
  if !last <> `None then fail "picker deleted on the first Delete";
  pick [key Input.Delete];
  if !last <> `Delete 0 then fail "picker did not delete on the second Delete";
  pick [Event.TextInput "zzz"; key Input.Enter];
  if !last <> `Submit then fail "picker Enter with no rows did not submit";
  query := "";
  pick [key Input.Backspace];
  if !last <> `Back then fail "picker Backspace on an empty query did not go back";
  pick [key Input.Escape];
  if !last <> `Cancel then fail "picker Escape did not cancel";
  (* The second row sits at y = 3 + 24 + 24 (search row, first row). *)
  query := "";
  pick [];
  pick [press (60, 3 + 48 + 12)];
  if !last <> `None then fail "picker row committed on press";
  pick [release (60, 3 + 48 + 12)];
  if !last <> `Pick 1 then fail "picker row did not commit on release inside";
  Ui.destroy ui;
  (* Context menu: rows commit on release inside, disabled rows are inert,
     a press outside dismisses; the host keeps it open on `Open. *)
  let ui = Ui.create () and result = ref `Open in
  let menu events =
    Ui.frame ui (frame ~scale:1. ~time:0. events) (fun ui ->
      result := Ui.context_menu ui ~at:(20., 20.) "ctx"
        ["One", true; "Two", false; "Three", true]) in
  let row index = 60, 20 + 3 + (index * 24) + 12 in
  menu [];
  menu [press (row 0)];
  if !result <> `Open then fail "context menu committed on press";
  menu [release (row 0)];
  if !result <> `Pick 0 then fail "context menu did not commit on release";
  menu [press (row 1); release (row 1)];
  if !result <> `Open then fail "disabled context menu row committed";
  menu [press (row 2); release (300, 200)];
  if !result <> `Open then fail "context menu committed after release outside";
  menu [press (300, 200)];
  if !result <> `Dismiss then fail "press outside did not dismiss the context menu";
  Ui.destroy ui;
  (* Text areas: the text_field edit and IME path over lines. *)
  let area = ref "" and readonly = ref false and errors = ref [] in
  let ui = Ui.create () and time = ref 0. in
  let area_step ?(keys = []) events =
    time := !time +. 0.5;
    ignore (Ui.frame ui { (frame ~scale:1. ~time:!time events) with keys } (fun ui ->
      area := Ui.text_area ui ~at:(0., 0.) ~w:300. ~h:96. ~readonly:!readonly
        ~errors:!errors "area" !area)) in
  let region () = match Scene.Private.text_regions (Ui.scene ui) with
    | [(_, y, _, _, true, cursor)] -> y, cursor
    | _ -> fail "text area lost its IME region" in
  let expect what want = if !area <> want then
    fail (Printf.sprintf "text area %s: %S" what !area) in
  area_step [];
  area_step [press (150, 12); release (150, 12); Event.TextInput "ab"; Event.KeyPressed Input.Enter;
    Event.TextInput "cd"];
  expect "insert and Enter" "ab\ncd";
  area_step [Event.KeyPressed Input.ArrowUp; Event.TextInput "X"];
  expect "Up keeps the column" "abX\ncd";
  area_step [Event.KeyPressed Input.Home; Event.TextInput "_"];
  expect "Home is line-scoped" "_abX\ncd";
  area_step [Event.KeyPressed Input.ArrowDown; Event.KeyPressed Input.End; Event.KeyPressed Input.Backspace];
  expect "Down then End then Backspace" "_abX\nc";
  area_step [Event.KeyPressed Input.Delete];
  expect "Delete at the end" "_abX\nc";
  let cursor = snd (region ()) in
  area_step [Event.TextEditing { text = "e"; start = 0; length = 1 }];
  if snd (region ()) <> cursor then fail "composition moved the caret";
  area_step [Event.TextInput "é"];
  expect "IME commit" "_abX\ncé";
  let previous_clipboard = Clipboard.get_text () in
  Fun.protect ~finally:(fun () -> match previous_clipboard with
    | Ok text -> ignore (Clipboard.set_text text) | Error _ -> ()) (fun () ->
    area_step ~keys:[Input.Shift] [Event.KeyPressed Input.ArrowLeft];
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'c')];
    if Clipboard.get_text () <> Ok "é" then fail "text area copy ignored the selection";
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'a')];
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'x')];
    expect "cut all" "";
    if Clipboard.get_text () <> Ok "_abX\ncé" then fail "text area cut lost the text";
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'v')];
    expect "paste keeps the newline" "_abX\ncé";
    readonly := true;
    area_step [Event.TextInput "no"; Event.KeyPressed Input.Backspace; Event.KeyPressed Input.Enter];
    expect "readonly" "_abX\ncé";
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'a')];
    area_step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'c')];
    if Clipboard.get_text () <> Ok "_abX\ncé" then fail "readonly text area cannot copy";
    readonly := false);
  (* scrolling: the caret line stays inside the 96-point area *)
  area := String.concat "\n" (List.init 40 string_of_int);
  errors := [ 3; 40 ];
  area_step [press (150, 12); release (150, 12)];
  area_step ~keys:[Input.Meta] [Event.KeyPressed Input.ArrowDown];
  for _ = 1 to 39 do area_step [Event.KeyPressed Input.ArrowDown] done;
  area_step [];
  let y, _ = region () in
  if y < 0 || y > 96 then fail (Printf.sprintf "caret line left the area (y %d)" y);
  area_step [Event.KeyPressed Input.Escape];
  if Ui.text_input_focused ui then fail "Escape did not leave the text area";
  Ui.destroy ui;
  (* Modal: centered, and Escape or a press outside dismisses it. *)
  let ui = Ui.create () and shown = ref None in
  let modal events = Ui.frame ui (frame ~scale:1. ~time:0. events) (fun ui ->
    shown := Ui.modal ui ~width:200. "modal" (fun () -> Ui.label ui "Hello")) in
  modal [];
  modal [];
  if !shown <> Some () then fail "modal did not build its content";
  modal [press (160, 120); release (160, 120)];
  if !shown <> Some () then fail "a press inside dismissed the modal";
  modal [key Input.Escape];
  if !shown <> None then fail "Escape did not dismiss the modal";
  modal [];
  modal [press (5, 5)];
  if !shown <> None then fail "a press outside did not dismiss the modal";
  Ui.destroy ui;
  let ui = Ui.create () and shown = ref None in
  let popup events = Ui.frame ui (frame ~scale:1. ~time:0. events) (fun ui ->
    shown := Ui.popup ui ~at:(20., 20.) ~width:200. ~height:10. "popup"
      (fun () -> Ui.label ui "One"; Ui.label ui "Two")) in
  popup [];
  popup [];
  popup [press (50, 58)];
  if !shown <> Some () then fail "popup dismissed a press inside its laid-out rect";
  popup [press (300, 200)];
  if !shown <> None then fail "popup kept a press outside its laid-out rect";
  Ui.destroy ui;
  (match Sdl3.Init.quit () with
   | Ok () -> () | Error error -> fail (Format.asprintf "%a" Sdl3.pp_error error));
  print_endline "PXUI Ui interaction contract passed at 1x and 2x"
