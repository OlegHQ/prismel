open Sdl3
open Sdl3_image

let fail message = failwith ("SDL3_image test: " ^ message)
let get_image = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" Sdl3_image.pp_error error)

let get_sdl = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" Sdl3.pp_error error)

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    Bytes.of_string (really_input_string channel (in_channel_length channel)))

let () =
  if Array.length Sys.argv <> 2 then fail "expected a PNG fixture path";
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled <> { Version.major = 3; minor = 4; patch = 4 }
      || linked <> compiled || not Version.stable_headers
      || Version.function_count < 10 || Version.safe_function_count <> 4 then
    fail "generated or linked SDL3_image provenance changed";
  get_sdl (Init.init [Init.Events]);
  let file_surface = get_image (load_file Sys.argv.(1)) in
  if get_sdl (Surface.size file_surface) <> (640, 480) then
    fail "PNG dimensions changed";
  let file_rgba = get_sdl (Surface.copy_rgba file_surface) in
  if Bytes.length file_rgba.pixels <> 640 * 480 * 4 then
    fail "PNG was not normalized to tightly packed RGBA8";

  let encoded = read_file Sys.argv.(1) in
  let bytes_surface = get_image (load_bytes ~kind:"PNG" encoded) in
  Bytes.fill encoded 0 (Bytes.length encoded) '\x00';
  let bytes_rgba = get_sdl (Surface.copy_rgba bytes_surface) in
  if bytes_rgba.pixels <> file_rgba.pixels then
    fail "file and memory PNG decoders disagree";

  (match load_bytes (Bytes.of_string "not an image") with
   | Error { kind = Decoder_error; message; _ } when message <> "" -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "malformed image decoded"
   | Error _ -> fail "malformed image returned the wrong error");
  (match load_file "/definitely/missing/prismel-image.png" with
   | Error { kind = Decoder_error; message; _ } when message <> "" -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "missing image loaded"
   | Error _ -> fail "missing image returned the wrong error");
  (match load_file "bad\x00path" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "NUL path loaded"
   | Error _ -> fail "NUL path returned the wrong error");
  let wrong_domain = Domain.spawn (fun () -> load_bytes (Bytes.create 0))
    |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok surface -> ignore (Surface.destroy surface); fail "wrong-domain decode succeeded"
   | Error _ -> fail "wrong-domain decode returned the wrong error");

  get_sdl (Surface.destroy file_surface);
  get_sdl (Surface.destroy bytes_surface);
  get_sdl (Init.quit ());
  Printf.printf "SDL3_image %d.%d.%d CPU decode conformance passed\n%!"
    linked.major linked.minor linked.patch
