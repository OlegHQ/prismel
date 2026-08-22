open Sdl3

let fail message = failwith ("SDL3 stress test: " ^ message)

let get = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" pp_error error)

let iterations = 100_000

let () =
  get (Init.init [ Init.Events ]);
  let source = Bytes.of_string "\x11\x22\x33\xff" in
  for _ = 1 to iterations do
    let surface = get (Surface.of_rgba ~width:1 ~height:1 source) in
    let rgba = get (Surface.copy_rgba surface) in
    if rgba.width <> 1 || rgba.height <> 1 || rgba.pixels <> source then
      fail "surface contents changed during lifecycle stress";
    get (Surface.destroy surface)
  done;
  Gc.full_major ();
  get (drain_release_queue ());
  if dropped_release_tokens () <> 0 then
    fail "bounded release queue dropped an explicitly released handle";
  get (Init.quit ());
  Printf.printf "SDL3 surface lifecycle stress passed (%d cycles)\n%!" iterations
