(* Allocation and time per SDL event through the typed runtime input queue:
   SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune exec --profile release tools/bench_input.exe *)
let events =
  let timestamp_ns = 0L and window_id = 1L and which = 2L in
  [| Sdl3.Event.Mouse_motion { timestamp_ns; window_id; which; buttons = 0L;
       x = 7.; y = 11.; dx = 1.; dy = 2. };
     Mouse_motion { timestamp_ns; window_id; which; buttons = 1L;
       x = 9.; y = 14.; dx = 2.; dy = 3. };
     Mouse_button { timestamp_ns; window_id; which; button = 1; down = true;
       clicks = 1; x = 7.; y = 11. };
     Mouse_button { timestamp_ns; window_id; which; button = 1; down = false;
       clicks = 1; x = 9.; y = 14. };
     Mouse_wheel { timestamp_ns; window_id; which; x = 1.; y = -2.;
       direction = Normal; mouse_x = 9.; mouse_y = 14.; integer_x = 1;
       integer_y = -2 };
     Key { timestamp_ns; window_id; which; scancode = 4; keycode = 65;
       modifiers = 0; raw_scancode = 4; down = true; repeat = false };
     Key { timestamp_ns; window_id; which; scancode = 4; keycode = 65;
       modifiers = 0; raw_scancode = 4; down = false; repeat = false } |]

let repeats = match Sys.getenv_opt "PRISMEL_INPUT_BENCH_REPEATS" with
  | None -> 200_000 | Some value -> max 1 (int_of_string value)

let () =
  let input = match Runtime_next_input.create ~max_events:64
      ~logical_width:640 ~logical_height:480 with
    | Ok value -> value | Error message -> failwith message in
  let push event = match Runtime_next_input_sdl3.push input event with
    | Ok () -> () | Error message -> failwith message in
  let frame () = Array.iter push events;
    ignore (Runtime_next_input.drain input); Runtime_next_input.begin_frame input in
  for _ = 1 to 100 do frame () done;
  Gc.full_major ();
  let words = (Gc.quick_stat ()).minor_words and started = Unix.gettimeofday () in
  for _ = 1 to repeats do frame () done;
  let seconds = Unix.gettimeofday () -. started
  and words = (Gc.quick_stat ()).minor_words -. words in
  let count = float (repeats * Array.length events) in
  Printf.printf "events,%d,bytes_per_event,%.1f,ns_per_event,%.1f\n"
    (int_of_float count) (words *. float (Sys.word_size / 8) /. count)
    (seconds *. 1e9 /. count)
