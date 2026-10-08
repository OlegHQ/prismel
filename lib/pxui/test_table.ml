open Rays
module Ui = Pxui.Ui

let frame count events = {(Test_ui.frame ~scale:1. ~time:(float count /. 60.) events) with
  width = 360; height = 240; size = (360, 240)}

let run () =
  let ui = Ui.create () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
    let cells = ref 0 in
    let build ui = Ui.table ui ~at:(0., 0.) ~w:300. ~h:168. ~headers:[|"index"; "value"|]
        ~rows:1_000_000 ~cell:(fun row column -> incr cells; string_of_int (row + column)) "table" in
    ignore (Ui.frame ui (frame 0 []) build);
    cells := 0;
    ignore (Ui.frame ui (frame 1 []) build);
    assert (!cells > 0 && !cells <= 20);
    let clicked, _ = Ui.frame ui (frame 2 [Event.MousePressed (Input.LeftButton, (30., 36.));
        Event.MouseReleased (Input.LeftButton, (30., 36.))]) build in
    assert (clicked = Some 0);
    cells := 0;
    ignore (Ui.frame ui (frame 3 [Event.MouseMoved (30., 100.); Event.MouseScrolled (0., -10000.)]) build);
    ignore (Ui.frame ui (frame 4 []) build);
    assert (!cells <= 40);
    print_endline "table: million-row virtualization and row click passed")
