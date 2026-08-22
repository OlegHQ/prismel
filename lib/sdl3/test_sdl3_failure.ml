open Sdl3

let fail message = failwith ("SDL3 failure-injection test: " ^ message)

let () =
  (match Init.init [Init.Events] with
   | Error error -> fail (Format.asprintf "event init failed: %a" pp_error error)
   | Ok () -> ());
  let window_error = match
      Window.create ~title:"no video subsystem" ~width:16 ~height:16 () with
    | Error ({ kind = Sdl_error; message; _ } as error) when message <> "" ->
        error
    | Ok window ->
        ignore (Window.destroy window);
        fail "window creation succeeded without a video subsystem"
    | Error _ -> fail "window constructor returned the wrong failure kind"
  in
  let captured = window_error.message in
  ignore (Version.linked ());
  if window_error.message <> captured || captured = "" then
    fail "SDL error text was not captured before a subsequent SDL call";
  (match Init.quit () with
   | Ok () -> ()
   | Error error -> fail (Format.asprintf "event quit failed: %a" pp_error error));
  (match Init.init [Init.Video] with
   | Error { kind = Sdl_error; message; _ } when message <> "" -> ()
   | Ok () ->
       ignore (Init.quit ());
       fail "invalid SDL video driver unexpectedly initialized"
   | Error _ -> fail "video init returned the wrong injected failure");
  print_endline "SDL3 init/window failure injection passed"
