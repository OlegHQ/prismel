open Prismel

let require condition message = if not condition then failwith message

let panel count =
  let value = ref (Pxui.create ()) in
  for index = 0 to count - 1 do
    value := Pxui.slider ~name:("slider-" ^ string_of_int index)
      ~label:("Slider " ^ string_of_int index)
      ~min:0. ~max:1. ~value:0.5 !value
  done;
  !value

let drag_last value count =
  let target = count - 1 in
  let y = 12 + 8 + (target * 32) + 16 in
  Pxui.update value
    [ Event.MousePressed (Input.LeftButton, (180, y));
      Event.MouseMoved (240, y);
      Event.MouseReleased (Input.LeftButton, (240, y)) ]

let allocated_drag count =
  let value = panel count in
  ignore (Pxui.scene value);
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let updated, changes = drag_last value count in
  let allocated = Gc.allocated_bytes () -. before in
  require (List.exists (function Pxui.Slid _ -> true | _ -> false) changes)
    "slider drag emitted no value change";
  require (Pxui.slider_value updated ("slider-" ^ string_of_int (count - 1))
      <> Some 0.5) "slider drag did not update the target";
  allocated

let () =
  let small = allocated_drag 100 in
  let large = allocated_drag 1_000 in
  require (large < 2_000_000.)
    (Printf.sprintf "1,000-widget drag allocated %.0f bytes" large);
  require (large < small *. 15.)
    (Printf.sprintf "slider drag allocation is superlinear: %.0f -> %.0f"
       small large);
  let stable = panel 1_000 in
  let first = Pxui.scene stable and second = Pxui.scene stable in
  require (first == second) "unchanged panel did not reuse its scene";
  let unchanged = Pxui.set_slider_value stable "slider-999" 0.5 in
  require (unchanged == stable) "unchanged slider setter rebuilt the panel";
  Printf.printf "PXUI layout snapshot: drag100=%.0f B drag1000=%.0f B\n"
    small large
