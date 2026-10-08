open Rays
module Ui = Pxui.Ui

let frame count events = {(Test_ui.frame ~scale:1. ~time:(float count /. 60.) events) with
  width = 360; height = 240; size = (360, 240)}

let run () =
  let ui = Ui.create () in
  Fun.protect ~finally:(fun () -> Ui.destroy ui) (fun () ->
    let cells = ref 0 and first = ref max_int in
    let build ui = Ui.table ui ~at:(0., 0.) ~w:300. ~h:168. ~headers:[|"index"; "value"|]
        ~rows:1_000_000 ~cell:(fun row column -> incr cells; first := min !first row;
          string_of_int (row + column)) "table" in
    ignore (Ui.frame ui (frame 0 []) build);
    cells := 0;
    ignore (Ui.frame ui (frame 1 []) build);
    assert (!cells > 0 && !cells <= 20);
    let clicked, _ = Ui.frame ui (frame 2 [Event.MousePressed (Input.LeftButton, (30., 36.));
        Event.MouseReleased (Input.LeftButton, (30., 36.))]) build in
    assert (clicked = Some 0);
    cells := 0; first := max_int;
    ignore (Ui.frame ui (frame 3 [Event.MouseMoved (30., 100.); Event.MouseScrolled (0., -10000.)]) build);
    assert (!cells >= 12 && !cells <= 20 && !first = 10000);
    cells := 0;
    ignore (Ui.frame ui (frame 4 []) build);
    if not (!cells >= 12 && !cells <= 20 && !first = 10000) then
      failwith (Printf.sprintf "scrolled table cells=%d first=%d" !cells !first);
    let clicked, _ = Ui.frame ui (frame 5 [Event.MousePressed (Input.LeftButton, (30., 36.));
        Event.MouseReleased (Input.LeftButton, (30., 36.))]) build in
    assert (clicked = Some 10000);
    for count = 6 to 15 do
      cells := 0; first := max_int;
      ignore (Ui.frame ui (frame count [Event.MouseMoved (30., 100.); Event.MouseScrolled (0., -3.)]) build);
      assert (!cells >= 12 && !cells <= 20 && !first = 10000 + (count - 5) * 3)
    done;
    cells := 0; first := max_int;
    ignore (Ui.frame ui (frame 16 [Event.TrackpadScrolled {
      delta = (0., -72.); phase = Moved; time = 16. /. 60. };
      Event.MouseScrolled (0., -3.)]) build);
    assert (!cells >= 12 && !cells <= 20 && !first = 10033);
    ignore (Ui.frame ui (frame 17 [Event.TrackpadScrolled {
      delta = (0., -72.); phase = Moved; time = 17. /. 60. }]) build);
    ignore (Ui.frame ui (frame 18 [Event.TrackpadScrolled {
      delta = (0., 0.); phase = Lifted; time = 18. /. 60. }]) build);
    cells := 0; first := max_int;
    ignore (Ui.frame ui (frame 19 []) build);
    assert (!cells >= 12 && !cells <= 20 && !first > 10036);
    print_endline "table: million-row virtualization and row click passed")
