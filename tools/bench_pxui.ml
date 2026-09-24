open Prismel

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let widget_count = integer_env "PRISMEL_PXUI_BENCH_WIDGETS" 1_000
let repeats = integer_env "PRISMEL_PXUI_BENCH_REPEATS" 7
let sink = ref 0

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

(* Each row: median wall time, median allocated bytes, and an operation
   specific count (changed values, draw batches, ...). *)
let measure name operation =
  ignore (operation ());
  let seconds = Array.make repeats 0.
  and allocated = Array.make repeats 0. and count = ref 0 in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.allocated_bytes () and started = Unix.gettimeofday () in
    let value = operation () in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    allocated.(repeat) <- Gc.allocated_bytes () -. before;
    count := value;
    sink := !sink lxor value
  done;
  Printf.printf "%s,%d,%d,%.6f,%.0f,%d\n%!" name widget_count repeats
    (median seconds) (median allocated) !count

let frame ?(time = 0.) events : Frame.t =
  { width = 1200; height = 800; size = 1200, 800; drawable_width = 2400;
    drawable_height = 1600; drawable_size = 2400, 1600; pixel_scale = 2., 2.;
    time; dt = 1. /. 60.; fps = 60.; count = 0; mouse = 0., 0.;
    mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events }

(* One full UI frame over [widget_count] sliders in a bounded panel: route,
   build, layout, paint, and publish. Returns how many values changed. *)
let values = Array.init widget_count (fun _ -> 0.5)
let ui = Pxui.Ui.create ()
let step events =
  Pxui.Ui.frame ui (frame events) (fun ui ->
    Pxui.Ui.panel ui ~x:12. ~y:12. ~width:280. ~max_height:760. "bench" (fun () ->
      let changed = ref 0 in
      Array.iteri (fun index value ->
        let next = Pxui.Ui.slider ui ("Slider " ^ string_of_int index)
            ~range:(0., 1.) value in
        if next <> value then (incr changed; values.(index) <- next)) values;
      !changed))

(* Default panel: y = 12, padding 3, 24-point rows; the slider control starts
   after the 120-point label column. *)
let row_y index = 12 + 3 + (index * 24) + 12
let target = 10
let point x = float x, float (row_y target)
let press x = Event.MousePressed (Input.LeftButton, point x)
let moved x = Event.MouseMoved (point x)
let released x = Event.MouseReleased (Input.LeftButton, point x)

let batches scene =
  match Scene.Private.stage_native_render ~width:1200 ~height:800 scene with
  | Ok staged -> List.fold_left (fun total -> function
      | Scene.Private.Ui_layer (batch, _) ->
          total + Array.length (Scene_command.Ui_batch.batches batch)
      | _ -> total) 0 staged.layers
  | Error message -> failwith message

let () =
  Printf.printf
    "benchmark,widgets,repeats,median_seconds,median_allocated_bytes,count\n%!";
  ignore (step []);
  (* Steady frames rebuild everything: there is no cache to hit or miss. *)
  measure "pxui_frame" (fun () -> step []);
  let flip = ref false in
  measure "pxui_frame_value_changed" (fun () ->
    flip := not !flip;
    values.(0) <- (if !flip then 0.25 else 0.75);
    step []);
  let target_x = ref 240 in
  measure "pxui_drag" (fun () ->
    target_x := (if !target_x = 240 then 260 else 240);
    let changed = step [press 180; moved !target_x; released !target_x] in
    if changed = 0 then failwith "pxui_drag missed its slider";
    changed);
  ignore (step [press 180]);
  let x = ref 180 in
  measure "pxui_drag_frame" (fun () ->
    x := 180 + ((!x - 179) mod 200);
    step [moved !x]);
  ignore (step [released !x]);
  let panel = Pxui.Ui.create () in
  Pxui.Ui.frame panel (frame []) (fun ui ->
    Pxui.Ui.panel ui "panel" (fun () ->
      Pxui.Ui.label ui "PXUI";
      ignore (Pxui.Ui.toggle ui "Animate" true);
      ignore (Pxui.Ui.slider ui "Radius" ~range:(10., 120.) 48.);
      ignore (Pxui.Ui.int_slider ui "Steps" ~range:(1, 64) 8);
      ignore (Pxui.Ui.choice ui "Palette" ["ocean"; "sunset"; "mono"] 0);
      ignore (Pxui.Ui.text_field ui "Caption" "Functional UI");
      ignore (Pxui.Ui.button ui "Quit")));
  measure "pxui_panel_draw_batches" (fun () -> batches (Pxui.Ui.scene panel));
  Pxui.Ui.destroy panel;
  Pxui.Ui.destroy ui;
  if !sink = min_int then Printf.eprintf "unreachable\n"
