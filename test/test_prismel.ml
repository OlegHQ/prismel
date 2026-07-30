let fail message = raise (Failure message)

let () =
  let press point =
    Prismel.Event.MousePressed (Prismel.Input.LeftButton, point)
  in
  let release point =
    Prismel.Event.MouseReleased (Prismel.Input.LeftButton, point)
  in
  let move point = Prismel.Event.MouseMoved point in
  let canvas = Pxui.create ~x:0 ~y:0 ~width:240 () in
  Pxui.add_toggle canvas ~name:"enabled" ~label:"Enabled" ~value:false;
  Pxui.add_slider canvas ~name:"amount" ~label:"Amount"
    ~min:0. ~max:10. ~value:5.;
  if Pxui.handle_event canvas (press (210, 16)) <> [] then
    fail "toggle fired before pointer release";
  let changes = Pxui.handle_event canvas (release (210, 16)) in
  (match changes, Pxui.toggle_value canvas "enabled" with
   | [Pxui.Toggled ("enabled", true)], Some true -> ()
   | _ -> fail "toggle did not react to a click");
  ignore (Pxui.handle_event canvas (press (120, 48)));
  let drag_changes = Pxui.handle_event canvas (move (400, 48)) in
  ignore (Pxui.handle_event canvas (release (400, 48)));
  if Pxui.slider_value canvas "amount" <> Some 10.
     || not (List.exists
       (function Pxui.Slid ("amount", 10.) -> true | _ -> false)
       drag_changes)
  then fail "slider drag did not capture, update, and clamp";
  let focus_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.slider ~name:"focus" ~label:"Focus"
         ~min:0. ~max:10. ~value:5.
  in
  let focus_ui, _ = Pxui.update focus_ui [press (120, 16)] in
  let before_focus_loss = Pxui.slider_value focus_ui "focus" in
  let focus_ui, focus_changes =
    Pxui.update focus_ui
      [Prismel.Event.WindowFocusLost; move (400, 16)]
  in
  if focus_changes <> []
     || Pxui.slider_value focus_ui "focus" <> before_focus_loss
  then fail "window focus loss did not cancel pointer capture";
  let edge_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.toggle ~name:"edge" ~label:"Edge" ~value:false
  in
  let edge_ui, edge_changes =
    Pxui.update edge_ui [press (232, 16); release (231, 16)]
  in
  if edge_changes <> [] || Pxui.toggle_value edge_ui "edge" <> Some false then
    fail "half-open PXUI bounds accepted a press on the right edge";
  let button_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.button ~name:"apply" ~label:"Apply"
  in
  let _, cancelled =
    Pxui.update button_ui
      [press (20, 16); move (300, 16); release (300, 16)]
  in
  if cancelled <> [] then fail "button fired after release outside its bounds";
  let _, clicked =
    Pxui.update button_ui [press (20, 16); release (20, 16)]
  in
  if clicked <> [Pxui.Clicked "apply"] then
    fail "button did not fire on release inside";
  let functional_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.toggle ~name:"pure" ~label:"Pure" ~value:false
    |> Pxui.text_field ~name:"title" ~label:"Title" ~value:""
    |> Pxui.choice ~name:"mode" ~label:"Mode"
         ~options:["dots"; "lines"] ~selected:0
    |> Pxui.range ~name:"band" ~label:"Band"
         ~min:0. ~max:1. ~low:0.25 ~high:0.75
    |> Pxui.xy ~name:"point" ~label:"Point"
         ~x_range:(-1., 1.) ~y_range:(-1., 1.) ~value:(0., 0.)
  in
  let updated_ui, changes =
    Pxui.update functional_ui
      [press (210, 16); release (210, 16)]
  in
  (match
     Pxui.toggle_value functional_ui "pure",
     Pxui.toggle_value updated_ui "pure",
     changes
   with
   | Some false, Some true, [Pxui.Toggled ("pure", true)] -> ()
   | _ -> fail "functional UI update mutated its input or lost its change");
  if Pxui.scene updated_ui = [] then fail "functional UI scene was empty";
  let typed_ui, text_changes =
    Pxui.update updated_ui
      [ press (100, 48);
        release (100, 48);
        Prismel.Event.TextEditing { text = "e"; start = 0; length = 1 };
        Prismel.Event.TextInput "hé";
        Prismel.Event.KeyPressed Prismel.Input.Backspace;
      ]
  in
  if Pxui.text_value typed_ui "title" <> Some "h" then
    fail "text field did not accept UTF-8 input and backspace";
  (match text_changes with
   | [Pxui.Text_changed ("title", "hé"); Pxui.Text_changed ("title", "h")] -> ()
   | _ -> fail "text field changes were not ordered");
  let controls_ui, control_changes =
    Pxui.update typed_ui
      [ press (200, 80);
        release (200, 80);
        press (120, 112);
        move (160, 112);
        release (160, 112);
        press (150, 144);
        move (200, 150);
        release (200, 150);
      ]
  in
  if Pxui.choice_value controls_ui "mode" <> Some "lines"
     || Pxui.range_value controls_ui "band" = Some (0.25, 0.75)
     || Pxui.xy_value controls_ui "point" = Some (0., 0.)
  then fail "advanced functional controls did not update";
  let kinds =
    List.map
      (function
        | Pxui.Selected _ -> `Selected
        | Pxui.Ranged _ -> `Ranged
        | Pxui.Moved2 _ -> `Moved
        | _ -> `Other)
      control_changes
  in
  (match kinds with
   | `Selected :: rest
     when List.mem `Ranged rest && List.mem `Moved rest -> ()
   | _ -> fail "advanced drag control changes were missing or misordered");
  let label_click_ui, label_changes =
    Pxui.update typed_ui [press (20, 80); release (20, 80)]
  in
  if label_changes <> []
     || Pxui.choice_value label_click_ui "mode" <> Some "dots"
  then fail "choice label area incorrectly activated its control";
  let restored_ui =
    match Pxui.decode functional_ui (Pxui.encode controls_ui) with
    | Ok ui -> ui
    | Error message -> fail message
  in
  if Pxui.toggle_value restored_ui "pure" <> Some true
     || Pxui.text_value restored_ui "title" <> Some "h"
     || Pxui.choice_value restored_ui "mode" <> Some "lines"
  then fail "PXUI settings did not round-trip typed values";
  let settings_file = Filename.temp_file "prismel-pxui-" ".settings" in
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists settings_file then Sys.remove settings_file)
    (fun () ->
      (match Pxui.save controls_ui settings_file with
       | Ok () -> ()
       | Error message -> fail message);
      match Pxui.load functional_ui settings_file with
      | Ok loaded when Pxui.text_value loaded "title" = Some "h" -> ()
      | Ok _ -> fail "PXUI settings file lost a typed value"
      | Error message -> fail message);
  Prismel.Input.reset ~mouse:(10, 10);
  Prismel.Input.begin_frame ();
  Prismel.Input.update_mouse_pos 13 14;
  Prismel.Input.update_mouse_pos 20 25;
  if Prismel.Input.mouse_pos () <> (20, 25)
     || Prismel.Input.mouse_delta () <> (10, 15)
  then fail "mouse delta did not accumulate every event in the frame";
  Prismel.Input.begin_frame ();
  if Prismel.Input.mouse_delta () <> (0, 0) then
    fail "mouse delta remained stale on an idle frame";
  let squares = Prismel.Parallel.map ~grain:1 (fun x -> x * x) [1; 2; 3; 4] in
  if squares <> [1; 4; 9; 16] then
    fail "parallel map did not preserve order";
  let left, right =
    Prismel.Parallel.run ~domains:2 (fun () ->
      Prismel.Parallel.both (fun () -> 20 + 1) (fun () -> 6 * 7))
  in
  if left <> 21 || right <> 42 then
    fail "parallel computations returned incorrect values";
  if not (Prismel.Color.equal
      (Prismel.Color.hsv 0. 1. 1.) Prismel.Color.red) then
    fail "HSV red conversion is incorrect";
  if not (Prismel.Color.equal
      (Prismel.Color.hsl 180. 1. 0.5) Prismel.Color.cyan) then
    fail "HSL cyan conversion is incorrect";
  (match Prismel.Color.hex "#369c" with
   | Ok { r = 0x33; g = 0x66; b = 0x99; a = 0xcc } -> ()
   | _ -> fail "short RGBA hex parsing is incorrect");
  let samples generator =
    let a, generator = Prismel.Rand.int ~bound:10_000 generator in
    let b, generator = Prismel.Rand.float generator in
    let c, _ = Prismel.Rand.bool generator in
    a, b, c
  in
  if samples (Prismel.Rand.seed 42) <> samples (Prismel.Rand.seed 42) then
    fail "equal random seeds were not reproducible";
  let noise_a = Prismel.Noise.create 17 in
  let noise_b = Prismel.Noise.create 17 in
  let sample_a = Prismel.Noise.fbm2 noise_a ~x:1.25 ~y:(-3.5) in
  let sample_b = Prismel.Noise.fbm2 noise_b ~x:1.25 ~y:(-3.5) in
  if sample_a <> sample_b then fail "equal noise seeds were not reproducible";
  if sample_a < 0. || sample_a > 1. then fail "noise sample escaped 0..1";
  let nearby = Prismel.Noise.sample2 noise_a ~x:1.251 ~y:(-3.5) in
  let base = Prismel.Noise.sample2 noise_a ~x:1.25 ~y:(-3.5) in
  if abs_float (nearby -. base) > 0.05 then
    fail "coherent noise was discontinuous for nearby inputs";
  let path =
    Prismel.Path.empty
    |> Prismel.Path.move_to 0. 0.
    |> Prismel.Path.line_to 10. 0.
    |> Prismel.Path.quadratic_to ~control:(15., 5.) ~to_:(10., 10.)
    |> Prismel.Path.cubic_to
         ~control1:(5., 15.) ~control2:(0., 15.) ~to_:(0., 10.)
    |> Prismel.Path.close
  in
  let points = Prismel.Path.points ~steps:4 path in
  if List.hd points <> (0, 0)
     || List.hd (List.rev points) <> (0, 0)
     || List.length points <> 11 then
    fail "path flattening did not preserve endpoints and samples";
  let multi =
    path
    |> Prismel.Path.move_to 3. 3.
    |> Prismel.Path.line_to 4. 3.
    |> Prismel.Path.line_to 4. 4.
    |> Prismel.Path.close
  in
  match Prismel.Path.contours ~steps:4 multi with
  | [outer; inner]
    when List.length outer = 11 && List.length inner = 4 -> ()
  | _ -> fail "path flattening joined separate contours"
