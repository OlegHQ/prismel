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

let () =
  let native = get (Input.create ~max_events:64 ~max_file_bytes:16
      ~logical_width:10 ~logical_height:10) in
  for iteration = 1 to 3 do
    List.iter (fun event -> get (Runtime_next_input_sdl3.push native event))
      (sdl_fixture iteration);
  done;
  let native_trace = Input.drain native in
  if List.length native_trace <> 33 then
    failwith "native frozen 33-event trace differs";
  let native_facts = Input.snapshot native in
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
  ignore (Input.drain native);
  let timestamp_ns=0L and window_id=1L and which=1L in
  let named=[40,"Enter";41,"Escape";42,"Backspace";43,"Tab";44,"Space";
    58,"F1";59,"F2";60,"F3";61,"F4";62,"F5";63,"F6";64,"F7";
    65,"F8";66,"F9";67,"F10";68,"F11";69,"F12";73,"Insert";
    74,"Home";75,"PageUp";76,"Delete";77,"End";78,"PageDown";
    79,"ArrowRight";80,"ArrowLeft";81,"ArrowDown";82,"ArrowUp";
    224,"Control";225,"Shift";226,"Alt";227,"Meta"]in
  List.iter(fun(scancode,key)->
    let event=Sdl3.Event.Key{timestamp_ns;window_id;which;scancode;
      keycode=1 lsl 30 lor scancode;modifiers=0;raw_scancode=scancode;
      down=true;repeat=false}in
    match Runtime_next_input_sdl3.translate event with
    |Some(Key_pressed fact)when fact.key=key->()
    |_->failwith("named SDL key drift: "^key))named;
  let modified=Sdl3.Event.Key{timestamp_ns;window_id;which;scancode=4;keycode=65;
    modifiers=0xBBC3;raw_scancode=4;down=true;repeat=true}in
  (match Runtime_next_input_sdl3.translate modified with
   |Some(Key_pressed{key="a";modifiers=[Shift;Control;Alt;Meta;Num_lock;Caps_lock;Scroll_lock];repeat=true})->()
   |_->failwith"SDL key modifier/repeat mapping drift");
  List.iter(fun(change,expected)->
    let event=Sdl3.Event.Window{timestamp_ns;window_id;change}in
    if Runtime_next_input_sdl3.translate event<>Some expected then
      failwith"window authority mapping drift")
    [Sdl3.Event.Shown,Visibility_changed true;Hidden,Visibility_changed false;
     Focus_gained,Runtime_next_input.Focus_gained];
  if Runtime_next_input_sdl3.translate(Sdl3.Event.Quit{timestamp_ns})<>Some Quit then
    failwith"quit mapping drift";
  let drop=Filename.temp_file"runtime-next-drop-"".bin"in
  let output=open_out_bin drop in output_string output"native-drop";close_out output;
  Fun.protect~finally:(fun()->Sys.remove drop)(fun()->
    get(Runtime_next_input_sdl3.push native(Sdl3.Event.Drop{timestamp_ns;
      window_id;change=File drop;x=0.;y=0.;source=None}));
    match Input.drain native with
    |[File_dropped{name;contents=Some bytes}]
      when name=Filename.basename drop&&Bytes.to_string bytes="native-drop"->()
    |_->failwith"native file drop ownership/order drift");
  (match Runtime_next_input_sdl3.push native(Sdl3.Event.Drop{timestamp_ns;
      window_id;change=File"/definitely/missing/drop.bin";x=0.;y=0.;source=None})with
   |Error _ when Input.queued_count native=0->()
   |_->failwith"malformed native drop was not failure-atomic");
  let key_events=Array.of_list(List.map(fun(scancode,_)->Sdl3.Event.Key{
    timestamp_ns;window_id;which;scancode;keycode=1 lsl 30 lor scancode;
    modifiers=0;raw_scancode=scancode;down=true;repeat=false})named)in
  let translate_all()=Array.map Runtime_next_input_sdl3.translate key_events in
  let sequential=translate_all()in
  let domains=Array.init 4(fun _->Domain.spawn translate_all)in
  Array.iter(fun domain->if Domain.join domain<>sequential then
    failwith"one/four-domain key translation drift")domains;
  let bounded = get (Input.create ~max_events:8 ~max_file_bytes:0
      ~logical_width:1 ~logical_height:1) in
  for index = 1 to 100_000 do
    get(Runtime_next_input_sdl3.push bounded(Sdl3.Event.Mouse_motion{
      timestamp_ns=Int64.of_int index;window_id=1L;which=1L;buttons=0L;
      x=float index;y=0.;dx=1.;dy=0.}))
  done;
  if Input.queued_count bounded <> 8
     || (Input.snapshot bounded).dropped_events <> 99_992 then
    failwith "input queue is not bounded";
  print_endline
    "runtime_next input: native trace33, Retina, reset, capture, bounded"
