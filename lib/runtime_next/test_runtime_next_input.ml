module Input = Runtime_next_input

let get = function Ok value -> value | Error message -> failwith message

let sdl_fixture iteration =
  let timestamp_ns = Int64.of_int iteration in
  let window_id = 1L and which = 2L in
  [
    Sdl3.Event.Mouse_motion { timestamp_ns; window_id; which; buttons = 0L;
      x = 7.; y = 11.; dx = 7.; dy = 11. };
    Mouse_button { timestamp_ns; window_id; which; button = 1; down = true;
      clicks = 1; x = 7.; y = 11. };
    Mouse_motion { timestamp_ns; window_id; which; buttons = 1L;
      x = 9.; y = 14.; dx = 2.; dy = 3. };
    Mouse_button { timestamp_ns; window_id; which; button = 1; down = false;
      clicks = 1; x = 9.; y = 14. };
    Mouse_wheel { timestamp_ns; window_id; which; x = 1.; y = -2.;
      direction = Normal; mouse_x = 9.; mouse_y = 14.; integer_x = 1;
      integer_y = -2 };
    Key { timestamp_ns; window_id; which; scancode = 4; keycode = 65;
      modifiers = 0; raw_scancode = 4; down = true; repeat = false };
    Key { timestamp_ns; window_id; which; scancode = 4; keycode = 65;
      modifiers = 0; raw_scancode = 4; down = false; repeat = false };
    Text_input { timestamp_ns; window_id; text = "a" };
    Text_editing { timestamp_ns; window_id; text = "ab"; start = 1;
      length = 1 };
    Window { timestamp_ns; window_id; change = Resized (20, 10) };
    Window { timestamp_ns; window_id; change = Focus_lost };
  ]

let wap_fixture =
  [ Wap.Pointer_moved (7, 11); Pointer_pressed (Left, 7, 11);
    Pointer_moved (9, 14); Pointer_released (Left, 9, 14);
    Wheel (1, -2); Key_pressed "65"; Key_released "65"; Text_input "a";
    Text_editing { text = "ab"; start = 1; length = 1 };
    Resized (20, 10); Focus_lost ]

let () =
  let native = get (Input.create ~max_events:64 ~max_file_bytes:16
      ~logical_width:10 ~logical_height:10)
  and web = get (Input.create ~max_events:64 ~max_file_bytes:16
      ~logical_width:10 ~logical_height:10) in
  for iteration = 1 to 3 do
    List.iter (fun event -> get (Runtime_next_input_sdl3.push native event))
      (sdl_fixture iteration);
    List.iter (fun event -> get (Runtime_next_input_wap.push web event))
      wap_fixture
  done;
  let native_trace = Input.drain native and web_trace = Input.drain web in
  if List.length native_trace <> 33 || native_trace <> web_trace then
    failwith "native/web frozen 33-event trace differs";
  let native_facts = Input.snapshot native and web_facts = Input.snapshot web in
  if native_facts <> web_facts then failwith "native/web input facts differ";
  if native_facts.pointer <> (9., 14.) then
    failwith "SDL logical coordinates were incorrectly Retina-scaled";
  if native_facts.mouse_delta <> (9., 14.)
     || native_facts.wheel_delta <> (3., -6.) then
    failwith "frame delta accumulation drift";
  Input.begin_frame native;
  let reset = Input.snapshot native in
  if reset.mouse_delta <> (0., 0.) || reset.wheel_delta <> (0., 0.) then
    failwith "frame deltas did not reset";
  get (Input.push native (Pointer_pressed (Left, 1., 1.)));
  get (Input.push native Focus_lost);
  if not (Input.snapshot native).pointer_captured then
    failwith "focus loss incorrectly acted as pointer cancellation";
  get (Input.push native (Pointer_cancelled Left));
  if (Input.snapshot native).pointer_captured then
    failwith "pointer cancellation retained capture";
  let uploaded = Bytes.of_string "payload" in
  get (Runtime_next_input_wap.push native
      (Wap.File_uploaded { name = "drop.bin"; contents = uploaded }));
  Bytes.fill uploaded 0 (Bytes.length uploaded) 'x';
  begin
    match List.rev (Input.drain native) with
    | Input.File_dropped { contents = Some copy; _ } :: _
      when Bytes.to_string copy = "payload" -> ()
    | _ -> failwith "file-drop bytes were not copied into bounded ownership"
  end;
  begin
    match Runtime_next_input_wap.push native
        (Wap.File_uploaded { name = "large"; contents = Bytes.make 17 'x' }) with
    | Error _ -> ()
    | Ok () -> failwith "oversized file drop was accepted"
  end;
  let bounded = get (Input.create ~max_events:8 ~max_file_bytes:0
      ~logical_width:1 ~logical_height:1) in
  for index = 1 to 100_000 do
    get (Input.push bounded (Pointer_moved (float index, 0.)))
  done;
  if Input.queued_count bounded <> 8
     || (Input.snapshot bounded).dropped_events <> 99_992 then
    failwith "input queue is not bounded";
  print_endline
    "runtime_next input: native/web trace33, Retina, reset, capture, bounded"
