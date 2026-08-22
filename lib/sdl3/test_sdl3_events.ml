open Sdl3

external push_event_trace : unit -> bool = "caml_sdl3_test_push_event_trace"
external mutate_event_sources : unit -> unit
  = "caml_sdl3_test_mutate_event_sources"

let fail message = failwith ("SDL3 event test: " ^ message)
let get = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" pp_error error)

let () =
  get (Init.init [Init.Events]);
  ignore (get (Event.poll_all ()));
  if not (push_event_trace ()) then fail "SDL rejected a trace event";
  let event_list = get (Event.poll_all ()) in
  let events = Array.of_list event_list in
  if Array.length events <> 33 then
    fail (Printf.sprintf "expected 33 ordered events, received %d"
      (Array.length events));

  (match events.(0), events.(1) with
   | Event.Key { timestamp_ns = 1L; window_id = 7L; which = 8L;
       down = true; repeat = false; raw_scancode = 42; _ },
     Event.Key { timestamp_ns = 2L; down = false; _ } -> ()
   | _ -> fail "ordered key press/release payload changed");

  let input_copy = match events.(2) with
    | Event.Text_input { timestamp_ns = 3L; window_id = 7L; text }
      when text = "žirafa" -> text
    | _ -> fail "UTF-8 text input was not copied"
  in
  let editing_copy = match events.(3) with
    | Event.Text_editing {
        timestamp_ns = 4L; window_id = 7L; text; start = 1; length = 2;
      } when text = "č" -> text
    | _ -> fail "IME composition payload changed"
  in
  let candidates_copy = match events.(4) with
    | Event.Text_editing_candidates {
        timestamp_ns = 5L; candidates;
        selected = Some 1; horizontal = true; _
      } when candidates = ["čaj"; "chai"] -> candidates
    | _ -> fail "IME candidates payload changed"
  in

  if Event.mouse_delta event_list <> (7., 3.) then
    fail "mouse delta did not sum all ordered motion";
  (match events.(5), events.(6), events.(7), events.(8) with
   | Event.Mouse_motion { dx = 3.; dy = -2.; buttons; _ },
     Event.Mouse_motion { dx = 4.; dy = 5.; _ },
     Event.Mouse_button { button = 1; down = true; clicks = 2; _ },
     Event.Mouse_wheel {
       x = 1.; y = -2.; direction = Event.Flipped;
       integer_x = 1; integer_y = -2; _
     } when buttons <> 0L -> ()
   | _ -> fail "mouse motion/button/wheel trace changed");

  (match events.(9), events.(10), events.(11), events.(12) with
   | Event.Window { change = Event.Resized (640, 480); _ },
     Event.Window { change = Event.Exposed; _ },
     Event.Window { change = Event.Focus_lost; _ },
     Event.Display { display_id = 12L; change = Event.Moved; _ } -> ()
   | _ -> fail "window/display lifecycle trace changed");

  (match events.(13), events.(14), events.(15) with
   | Event.Touch { phase = Event.Cancelled; touch_id = 13L; finger_id = 14L; _ },
     Event.Pen_motion { which = 15L; x = 100.; y = 200.; _ },
     Event.Pen_axis { which = 15L; value = 0.75; _ } -> ()
   | _ -> fail "touch/pen trace changed");

  (match events.(16), events.(17) with
   | Event.Gamepad_axis { which = 16L; value = 1234; _ },
     Event.Gamepad_device { which = 16L; change = Event.Gamepad_added; _ } -> ()
   | _ -> fail "gamepad trace changed");

  let source_copy, path_copy = match events.(18) with
    | Event.Drop {
        source = Some source; change = Event.File path; x = 30.; y = 40.; _
      } when source = "event-test" && path = "/tmp/žaba.png" -> source, path
    | _ -> fail "file-drop payload changed"
  in
  let mime_copy = match events.(19) with
    | Event.Clipboard {
        owner = true; mime_types; _
      } when mime_types = ["text/plain"; "image/png"] -> mime_types
    | _ -> fail "clipboard MIME payload changed"
  in
  (match events.(20), events.(21) with
   | Event.Audio_device {
       which = 17L; recording = false; change = Event.Audio_added; _
     },
     Event.Sensor {
       which = 18L; sensor_timestamp_ns = 220L;
       data = (1., 2., 3., 4., 5., 6.); _
     } -> ()
   | _ -> fail "audio/sensor trace changed");

  (match events.(22), events.(23), events.(24), events.(25) with
   | Event.Quit { timestamp_ns = 23L },
     Event.Keyboard_device { which = 19L; change = Event.Added; _ },
     Event.Mouse_device { which = 20L; change = Event.Removed; _ },
     Event.Gamepad_button { which = 21L; down = true; _ } -> ()
   | _ -> fail "application/device event trace changed");

  (match events.(26), events.(27), events.(28) with
   | Event.Gamepad_touchpad {
       which = 21L; touchpad = 2; finger = 3; phase = Event.Down;
       x = 0.25; y = 0.5; pressure = 0.75; _
     },
     Event.Gamepad_sensor {
       which = 21L; sensor_timestamp_ns = 280L; data = (7., 8., 9.); _
     },
     Event.Pinch { phase = Event.Updated; scale = 1.25; _ } -> ()
   | _ -> fail "gamepad sensor/touchpad/pinch trace changed");

  (match events.(29), events.(30), events.(31), events.(32) with
   | Event.Pen_proximity { which = 22L; change = Event.Entered; _ },
     Event.Pen_touch { which = 22L; down = true; eraser = false; _ },
     Event.Pen_button { which = 22L; button = 2; down = true; _ },
     Event.Unknown { event_type = 0x8000; timestamp_ns = 33L } -> ()
   | _ -> fail "pen/unknown event trace changed");

  mutate_event_sources ();
  if input_copy <> "žirafa" || editing_copy <> "č"
      || candidates_copy <> ["čaj"; "chai"]
      || source_copy <> "event-test" || path_copy <> "/tmp/žaba.png"
      || mime_copy <> ["text/plain"; "image/png"] then
    fail "an SDL-borrowed pointer escaped without an OCaml copy";

  get (Init.quit ());
  Printf.printf "SDL3 copied typed event trace passed (%d events)\n%!"
    (Array.length events)
