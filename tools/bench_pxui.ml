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

let measure name operation =
  ignore (operation ());
  let seconds = Array.make repeats 0.
  and allocated = Array.make repeats 0. in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.allocated_bytes () and started = Unix.gettimeofday () in
    let value = operation () in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    allocated.(repeat) <- Gc.allocated_bytes () -. before;
    sink := !sink lxor value
  done;
  Printf.printf "%s,%d,%d,%.6f,%.0f\n%!" name widget_count repeats
    (median seconds) (median allocated)

let canvas =
  let canvas = ref (Pxui.create ()) in
  for index = 0 to widget_count - 1 do
    canvas :=
      Pxui.slider ~name:("slider-" ^ string_of_int index)
        ~label:("Slider " ^ string_of_int index)
        ~min:0. ~max:1. ~value:0.5 !canvas
  done;
  !canvas

let () =
  Printf.printf "benchmark,widgets,repeats,median_seconds,median_allocated_bytes\n%!";
  measure "pxui_scene" (fun () ->
    ignore (Sys.opaque_identity (Pxui.scene canvas));
    widget_count);
  let target = widget_count - 1 in
  let y = 12 + 8 + (target * 32) + 16 in
  measure "pxui_drag" (fun () ->
    let _, changes =
      Pxui.update canvas
        [ Event.MousePressed (Input.LeftButton, (180, y));
          Event.MouseMoved (240, y);
          Event.MouseReleased (Input.LeftButton, (240, y)) ]
    in
    List.length changes);
  let runtime = Pxui.Runtime.create (Pxui.Spec.of_canvas canvas) in
  Pxui.Runtime.run_passes runtime;
  measure "pxui_reconcile_unchanged" (fun () ->
    Pxui.Runtime.reconcile runtime canvas);
  measure "pxui_retained_drag" (fun () ->
    let changes = Pxui.Runtime.update runtime
      [ Event.MousePressed (Input.LeftButton, (180, y));
        Event.MouseMoved (240, y);
        Event.MouseReleased (Input.LeftButton, (240, y)) ] in
    Pxui.Runtime.run_passes runtime;
    List.length changes);
  Pxui.Runtime.destroy runtime;
  if !sink = min_int then Printf.eprintf "unreachable\n"
