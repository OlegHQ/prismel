module System_thread = Thread

open Sdl3

let fail message = failwith ("SDL3 test: " ^ message)
let get = function Ok value -> value | Error error -> fail (Format.asprintf "%a" pp_error error)

let () =
  let frequency=Time.performance_frequency()and before=Time.performance_counter()in
  System_thread.delay 0.001;
  let after=Time.performance_counter()in
  if frequency<=0L||before<0L||after<before||not(Float.is_finite(Time.monotonic_seconds()))then
    fail"SDL3 monotonic performance counter invalid";
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled.major <> 3 || compiled.minor <> 4 || compiled.patch <> 14 then
    fail "generated header version changed without fixture review";
  if linked.major < compiled.major
      || (linked.major = compiled.major && linked.minor < compiled.minor) then
    fail "linked SDL is older than the generated headers";
  if not Version.stable_headers || Version.function_count < 1_200
      || Version.safe_function_count < 20 then
    fail "generated inventory is incomplete or prerelease";
  (match Version.validate ~release:true ~linked:{ major = 3; minor = 4; patch = 12 } with
   | Error { kind = Incompatible_version; _ } -> ()
   | Ok () | Error _ -> fail "older linked version was not rejected");
  get (Init.init [Init.Video; Init.Events]);
  if not (get (Init.initialized [Init.Video; Init.Events])) then
    fail "initialized subsystem mask was not retained";
  (match Window.create ~title:"bad\x00title" ~width:8 ~height:8 () with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok window -> ignore (Window.destroy window); fail "NUL window title succeeded"
   | Error _ -> fail "NUL window title returned the wrong error");
  let window = get (Window.create ~title:"SDL3 ownership test" ~width:96 ~height:64
      ~flags:[Window.Hidden; Window.Resizable] ()) in
  (match Metal_view.create window with
   | Error { kind = Sdl_error; message; _ } when message <> "" -> ()
   | Ok view ->
       get (Metal_view.destroy view);
       fail "dummy-video window unexpectedly created a Metal view"
   | Error error -> fail (Format.asprintf
       "dummy Metal-view constructor returned the wrong error: %a" pp_error error));
  if Window.destroyed window then fail "new window starts destroyed";
  if get (Window.title window) <> "SDL3 ownership test" then
    fail "window title snapshot changed";
  get (Window.set_title window "SDL3 renamed ž");
  if get (Window.title window) <> "SDL3 renamed ž" then
    fail "window title did not round-trip";
  (match Window.set_title window "bad\x00title" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "NUL title mutation was accepted");
  let window_id = get (Window.id window) in
  if window_id = 0L then fail "window ID is zero";
  if get (Window.size window) <> (96, 64) then fail "logical window size changed";
  let pixel_width, pixel_height = get (Window.size_in_pixels window) in
  if pixel_width < 96 || pixel_height < 64 then fail "drawable size is too small";
  let pixel_density = get (Window.pixel_density window) in
  let display_scale = get (Window.display_scale window) in
  if pixel_density < 1. || display_scale <= 0. then
    fail "window DPI facts are invalid";
  if abs_float (pixel_density -. 1.) > 0.000_001
      || pixel_width <> 96 || pixel_height <> 64 then
    fail "dummy-video window is not a 1x logical/drawable fixture";
  let displays = get (Display.all ()) in
  if displays = [] then fail "dummy video reported no displays";
  let primary = get (Display.primary ()) in
  let display = get (Window.display window) in
  if not (List.exists (fun candidate -> Display.id candidate = Display.id display)
      displays) then fail "window display is absent from display inventory";
  ignore (get (Display.name primary));
  let bounds = get (Display.bounds primary) in
  let usable = get (Display.usable_bounds primary) in
  if bounds.width <= 0 || bounds.height <= 0
      || usable.width <= 0 || usable.height <= 0
      || get (Display.content_scale primary) <= 0. then
    fail "display bounds or scale are invalid";
  get (Window.set_position window ~x:11 ~y:13);
  ignore (get (Window.position window));
  get (Window.center window);
  get (Window.set_size window ~width:112 ~height:72);
  get (Window.sync window);
  if get (Window.size window) <> (112, 72)
      || get (Window.size_in_pixels window) <> (112, 72) then
    fail "synchronized 1x window resize changed logical/drawable size";
  let facts = get (Window.presentation_facts window ~vsync:true) in
  if facts.logical_width <> 112 || facts.logical_height <> 72
      || facts.drawable_width <> 112 || facts.drawable_height <> 72
      || facts.pixel_density <> 1. || not facts.vsync then
    fail "dummy presentation facts changed";
  (match Window.set_size window ~width:0 ~height:72 with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "invalid window resize was not rejected");
  let has_flag flag bits = Int64.logand bits flag <> 0L in
  get (Window.set_bordered window false);
  get (Window.set_bordered window true);
  get (Window.set_resizable window false);
  get (Window.sync window);
  get (Window.set_resizable window true);
  get (Window.sync window);
  get (Window.set_always_on_top window true);
  get (Window.sync window);
  get (Window.set_always_on_top window false);
  (match Window.set_relative_mouse window true with
   | Ok () ->
       if not (get (Window.relative_mouse window)) then
         fail "relative mouse mode did not round-trip";
       get (Window.set_relative_mouse window false)
   | Error { kind = Sdl_error; message; _ } when message <> "" -> ()
   | Error _ -> fail "relative mouse capability returned an untyped error");
  get (Window.show window);
  get (Window.sync window);
  if has_flag 0x8L (get (Window.flags window)) then
    fail "shown window retained the hidden flag";
  get (Window.set_fullscreen window true);
  get (Window.sync window);
  if not (has_flag 0x1L (get (Window.flags window))) then
    fail "fullscreen transition did not update flags";
  get (Window.set_fullscreen window false);
  get (Window.sync window);
  if has_flag 0x1L (get (Window.flags window)) then
    fail "window did not leave fullscreen";
  (match Window.minimize window with
   | Error { kind = Sdl_error; message; _ } when message <> "" -> ()
   | Ok () | Error _ -> fail "dummy driver did not report unsupported minimize");
  get (Window.hide window);
  get (Window.sync window);
  if not (has_flag 0x8L (get (Window.flags window))) then
    fail "hidden transition did not update flags";
  get (Text_input.set_area window
    (Some { x = 3; y = 4; width = 40; height = 16 }) ~cursor:7);
  (match get (Text_input.area window) with
   | { x = 3; y = 4; width = 40; height = 16 }, 7 -> ()
   | _ -> fail "text-input logical area changed");
  get (Text_input.start window);
  if not (get (Text_input.active window)) then fail "text input did not start";
  get (Text_input.stop window);
  if get (Text_input.active window) then fail "text input did not stop";
  get (Clipboard.set_text "Prismel ž clipboard");
  if not (get (Clipboard.has_text ()))
      || get (Clipboard.get_text ()) <> "Prismel ž clipboard" then
    fail "clipboard UTF-8 text did not round-trip";
  (match Cursor.create Cursor.Crosshair with
   | Error { kind = Unsupported; message; _ } when message <> "" -> ()
   | Error _ -> fail "cursor capability returned an untyped error"
   | Ok cursor ->
       get (Cursor.set cursor);
       get (Cursor.hide ());
       if get (Cursor.visible ()) then fail "cursor remained visible after hide";
       get (Cursor.show ());
       if not (get (Cursor.visible ())) then fail "cursor remained hidden after show";
       get (Cursor.destroy cursor);
       get (Cursor.destroy cursor);
       (match Cursor.set cursor with
        | Error { kind = Destroyed; _ } -> ()
        | Ok () | Error _ -> fail "destroyed cursor was accepted"));
  (match Mouse.capture true with
   | Ok () -> get (Mouse.capture false)
   | Error { kind = Unsupported; message; _ } when message <> "" -> ()
   | Error _ -> fail "mouse capture capability returned an untyped error");
  ignore (get (Event.poll_all ()));
  (match get (Event.wait ~timeout_ms:0) with
   | None -> ()
   | Some _ -> fail "zero-timeout wait returned an unexpected event");
  (match Event.wait ~timeout_ms:(-2) with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "invalid event timeout was not rejected");
  let worker_may_run = Atomic.make false in
  let begin_wait = Atomic.make false in
  let worker = System_thread.create (fun () ->
    while not (Atomic.get begin_wait) do System_thread.yield () done;
    System_thread.delay 0.01;
    Atomic.set worker_may_run true) () in
  Atomic.set begin_wait true;
  ignore (get (Event.wait ~timeout_ms:50));
  if not (Atomic.get worker_may_run) then
    fail "blocking event wait retained the OCaml runtime lock";
  System_thread.join worker;
  let expect_wrong_domain label = function
    | Error { kind = Wrong_domain; _ } -> ()
    | Ok _ | Error _ -> fail (label ^ " was not rejected on a worker domain")
  in
  expect_wrong_domain "init"
    (Domain.spawn (fun () -> Init.init [Init.Events]) |> Domain.join);
  expect_wrong_domain "init query"
    (Domain.spawn (fun () -> Init.initialized [Init.Events]) |> Domain.join);
  expect_wrong_domain "display query"
    (Domain.spawn Display.all |> Domain.join);
  expect_wrong_domain "clipboard query"
    (Domain.spawn Clipboard.has_text |> Domain.join);
  expect_wrong_domain "text-input query"
    (Domain.spawn (fun () -> Text_input.active window) |> Domain.join);
  expect_wrong_domain "window synchronization"
    (Domain.spawn (fun () -> Window.sync window) |> Domain.join);
  expect_wrong_domain "cursor visibility"
    (Domain.spawn Cursor.visible |> Domain.join);
  let wrong_domain = Domain.spawn (fun () ->
    Window.create ~title:"wrong domain" ~width:8 ~height:8 ()) |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok window -> ignore (Window.destroy window); fail "wrong-domain create succeeded"
   | Error _ -> fail "wrong-domain create returned the wrong error");
  expect_wrong_domain "event poll" (Domain.spawn Event.poll |> Domain.join);
  let padded = Bytes.make 24 '\x7f' in
  for index = 0 to 7 do
    Bytes.set padded index (Char.chr index);
    Bytes.set padded (12 + index) (Char.chr (8 + index))
  done;
  let surface = get (Surface.of_rgba ~width:2 ~height:2 ~stride:12 padded) in
  if Surface.destroyed surface || get (Surface.size surface) <> (2, 2)
      || get (Surface.pitch surface) < 8 then
    fail "owned CPU surface metadata changed";
  Bytes.fill padded 0 (Bytes.length padded) '\x00';
  let snapshot = get (Surface.copy_rgba surface) in
  let expected = Bytes.init 16 Char.chr in
  if snapshot.width <> 2 || snapshot.height <> 2 || snapshot.stride <> 8
      || snapshot.pixels <> expected then
    fail "RGBA rows were not copied without source padding";
  (match Surface.of_rgba ~width:2 ~height:2 ~stride:7 (Bytes.make 16 '\x00') with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "short stride was accepted"
   | Error _ -> fail "short stride returned the wrong error");
  (match Surface.create_rgba ~width:max_int ~height:max_int with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "overflow surface succeeded"
   | Error _ -> fail "overflow surface returned the wrong error");
  let wrong_domain_surface = Domain.spawn (fun () ->
    Surface.create_rgba ~width:2 ~height:2) |> Domain.join in
  (match wrong_domain_surface with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "wrong-domain surface succeeded"
   | Error _ -> fail "wrong-domain surface returned the wrong error");
  get (Surface.destroy surface);
  get (Surface.destroy surface);
  (match Surface.copy_rgba surface with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale surface access was not rejected");
  get (Window.destroy window);
  get (Window.destroy window);
  if not (Window.destroyed window) then fail "destroy did not mark the handle stale";
  (match Window.size window with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale window access was not rejected");
  get (Init.quit ());
  get (drain_release_queue ());
  Printf.printf "SDL3 %d.%d.%d (%d inventoried functions) ownership test passed\n%!"
    linked.major linked.minor linked.patch Version.function_count
