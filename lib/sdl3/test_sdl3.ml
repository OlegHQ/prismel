open Sdl3

let fail message = failwith ("SDL3 test: " ^ message)
let get = function Ok value -> value | Error error -> fail (Format.asprintf "%a" pp_error error)

let () =
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
  if not (Init.initialized [Init.Video; Init.Events]) then
    fail "initialized subsystem mask was not retained";
  let window = get (Window.create ~title:"SDL3 ownership test" ~width:96 ~height:64
      ~flags:[Window.Hidden] ()) in
  if Window.destroyed window then fail "new window starts destroyed";
  let window_id = get (Window.id window) in
  if window_id = 0L then fail "window ID is zero";
  if get (Window.size window) <> (96, 64) then fail "logical window size changed";
  let pixel_width, pixel_height = get (Window.size_in_pixels window) in
  if pixel_width < 96 || pixel_height < 64 then fail "drawable size is too small";
  let pixel_density = get (Window.pixel_density window) in
  let display_scale = get (Window.display_scale window) in
  if pixel_density < 1. || display_scale <= 0. then
    fail "window DPI facts are invalid";
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
  ignore (get (Event.poll_all ()));
  (match get (Event.wait ~timeout_ms:0) with
   | None -> ()
   | Some _ -> fail "zero-timeout wait returned an unexpected event");
  (match Event.wait ~timeout_ms:(-2) with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "invalid event timeout was not rejected");
  let wrong_domain = Domain.spawn (fun () ->
    Window.create ~title:"wrong domain" ~width:8 ~height:8 ()) |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok window -> ignore (Window.destroy window); fail "wrong-domain create succeeded"
   | Error _ -> fail "wrong-domain create returned the wrong error");
  let wrong_domain_event = Domain.spawn Event.poll |> Domain.join in
  (match wrong_domain_event with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain event poll was not rejected");
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
