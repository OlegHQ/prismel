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
  if get (Window.size window) <> (96, 64) then fail "logical window size changed";
  let pixel_width, pixel_height = get (Window.size_in_pixels window) in
  if pixel_width < 96 || pixel_height < 64 then fail "drawable size is too small";
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
