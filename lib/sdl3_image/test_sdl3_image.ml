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

let write_file path bytes =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () ->
    output_bytes channel bytes)

let fixture root name = Filename.concat root name

type fixture =
  { file : string
  ; kind : string
  ; width : int
  ; height : int
  }

let fixtures =
  [ { file = "sample.avif"; kind = "AVIF"; width = 23; height = 42 }
  ; { file = "sample.bmp"; kind = "BMP"; width = 23; height = 42 }
  ; { file = "sample.cur"; kind = "CUR"; width = 23; height = 42 }
  ; { file = "palette.gif"; kind = "GIF"; width = 23; height = 42 }
  ; { file = "sample.ico"; kind = "ICO"; width = 23; height = 42 }
  ; { file = "sample.jpg"; kind = "JPG"; width = 23; height = 42 }
  ; { file = "sample.jxl"; kind = "JXL"; width = 23; height = 42 }
  ; { file = "sample.lbm"; kind = "LBM"; width = 16; height = 1 }
  ; { file = "sample.pcx"; kind = "PCX"; width = 23; height = 42 }
  ; { file = "sample.png"; kind = "PNG"; width = 23; height = 42 }
  ; { file = "sample.pnm"; kind = "PNM"; width = 23; height = 42 }
  ; { file = "sample.qoi"; kind = "QOI"; width = 23; height = 42 }
  ; { file = "svg.svg"; kind = "SVG"; width = 32; height = 32 }
  ; { file = "sample.tga"; kind = "TGA"; width = 23; height = 42 }
  ; { file = "sample.tif"; kind = "TIF"; width = 23; height = 42 }
  ; { file = "sample.webp"; kind = "WEBP"; width = 23; height = 42 }
  ; { file = "sample.xcf"; kind = "XCF"; width = 23; height = 42 }
  ; { file = "sample.xpm"; kind = "XPM"; width = 23; height = 42 }
  ; { file = "sample.xv"; kind = "XV"; width = 2; height = 1 }
  ]

let checked_rgba surface ~width ~height =
  if get_sdl (Surface.size surface) <> (width, height) then
    fail (Printf.sprintf "decoded dimensions changed: expected %dx%d" width height);
  let rgba = get_sdl (Surface.copy_rgba surface) in
  if rgba.width <> width || rgba.height <> height || rgba.stride <> width * 4
      || Bytes.length rgba.pixels <> width * height * 4 then
    fail "decoder did not return tightly packed RGBA8";
  rgba

let check_fixture root value =
  let path = fixture root value.file in
  let by_path = match load_file path with
    | Ok surface -> surface
    | Error error -> fail (Format.asprintf "%s path decode: %a"
        value.file Sdl3_image.pp_error error)
  in
  let path_rgba = checked_rgba by_path ~width:value.width ~height:value.height in
  let encoded = read_file path in
  let by_bytes = match load_bytes ~kind:value.kind encoded with
    | Ok surface -> surface
    | Error error -> fail (Format.asprintf "%s byte decode: %a"
        value.file Sdl3_image.pp_error error)
  in
  let byte_rgba = checked_rgba by_bytes ~width:value.width ~height:value.height in
  if path_rgba.pixels <> byte_rgba.pixels then
    fail (value.file ^ " path and copied-byte decoders disagree");
  Bytes.fill encoded 0 (Bytes.length encoded) '\x00';
  get_sdl (Surface.destroy by_path);
  get_sdl (Surface.destroy by_bytes)

let pixel pixels width x y =
  let offset = ((y * width) + x) * 4 in
  Bytes.sub pixels offset 4

type watched =
  { mutable surface : Surface.t
  ; mutable generation : int
  }

let refresh watched path =
  match load_file path with
  | Error _ as failure -> failure
  | Ok replacement ->
      let previous = watched.surface in
      watched.surface <- replacement;
      watched.generation <- watched.generation + 1;
      get_sdl (Surface.destroy previous);
      Ok ()

let check_watched_reload root =
  let path = Filename.temp_file "prismel-sdl3-image-watch-" ".png" in
  Fun.protect ~finally:(fun () ->
    if Sys.file_exists path then Sys.remove path) (fun () ->
      write_file path (read_file (fixture root "sample.png"));
      let watched = { surface = get_image (load_file path); generation = 0 } in
      let borrowed = watched in
      let valid_surface = watched.surface in
      let valid_pixels = (get_sdl (Surface.copy_rgba valid_surface)).pixels in
      write_file path (Bytes.of_string "malformed replacement");
      (match refresh watched path with
       | Error { kind = Decoder_error; message; _ } when message <> "" -> ()
       | Ok () | Error _ -> fail "malformed watched reload returned wrong result");
      if borrowed != watched || watched.surface != valid_surface
          || watched.generation <> 0
          || (get_sdl (Surface.copy_rgba watched.surface)).pixels <> valid_pixels
      then fail "failed watched reload did not retain identity and old pixels";
      write_file path (read_file (fixture root "rgbrgb.png"));
      get_image (refresh watched path);
      if borrowed != watched || watched.surface == valid_surface
          || watched.generation <> 1
          || get_sdl (Surface.size watched.surface) <> (256, 256)
          || not (Surface.destroyed valid_surface)
      then fail "successful watched reload did not atomically replace content";
      get_sdl (Surface.destroy watched.surface))

let () =
  if Array.length Sys.argv <> 2 || not (Sys.file_exists Sys.argv.(1)) then
    fail "expected the SDL3_image fixture directory";
  let root = Sys.argv.(1) in
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled <> { Version.major = 3; minor = 4; patch = 4 }
      || linked <> compiled || not Version.stable_headers
      || Version.function_count < 10 || Version.safe_function_count <> 3 then
    fail "generated or linked SDL3_image provenance changed";
  get_sdl (Init.init [Init.Events]);
  List.iter (check_fixture root) fixtures;

  let alpha_surface = get_image (load_file (fixture root "alpha.svg")) in
  let alpha = checked_rgba alpha_surface ~width:2 ~height:1 in
  let saw_transparent = ref false and saw_opaque = ref false in
  for index = 3 to Bytes.length alpha.pixels - 1 do
    if index mod 4 = 3 then begin
      let value = Bytes.get_uint8 alpha.pixels index in
      if value < 255 then saw_transparent := true;
      if value = 255 then saw_opaque := true
    end
  done;
  if not (!saw_transparent && !saw_opaque) then
    fail "alpha fixture lost transparent or opaque pixels";
  get_sdl (Surface.destroy alpha_surface);

  let base = get_image (load_file (fixture root "sample.jpg")) in
  let oriented = get_image (load_file (fixture root "orientation-6.jpg")) in
  let source = checked_rgba base ~width:23 ~height:42 in
  let rotated = checked_rgba oriented ~width:42 ~height:23 in
  for y = 0 to 22 do
    for x = 0 to 41 do
      if pixel rotated.pixels 42 x y
          <> pixel source.pixels 23 y (41 - x) then
        fail "EXIF orientation-6 pixel mapping changed"
    done
  done;
  get_sdl (Surface.destroy base);
  get_sdl (Surface.destroy oriented);

  List.iter (fun value ->
    match load_bytes ~kind:value.kind (Bytes.of_string "not an image") with
    | Error { kind = Decoder_error; message; _ } when message <> "" -> ()
    | Ok surface ->
        get_sdl (Surface.destroy surface);
        fail (value.kind ^ " malformed bytes decoded")
    | Error _ -> fail (value.kind ^ " malformed bytes returned wrong error"))
    fixtures;
  (match load_file "/definitely/missing/prismel-image.png" with
   | Error { kind = Decoder_error; message; _ } when message <> "" -> ()
   | Ok surface -> get_sdl (Surface.destroy surface); fail "missing image loaded"
   | Error _ -> fail "missing image returned the wrong error");
  (match load_file "bad\x00path" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok surface -> get_sdl (Surface.destroy surface); fail "NUL path loaded"
   | Error _ -> fail "NUL path returned the wrong error");
  (match load_bytes ~kind:"PNG\x00bad" (Bytes.create 0) with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok surface -> get_sdl (Surface.destroy surface); fail "NUL kind decoded"
   | Error _ -> fail "NUL kind returned the wrong error");
  let wrong_domain = Domain.spawn (fun () -> load_bytes (Bytes.create 0))
    |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok surface -> get_sdl (Surface.destroy surface);
       fail "wrong-domain decode succeeded"
   | Error _ -> fail "wrong-domain decode returned the wrong error");
  check_watched_reload root;
  get_sdl (Init.quit ());
  Printf.printf
    "SDL3_image %d.%d.%d CPU decode conformance passed (%d formats)\n%!"
    linked.major linked.minor linked.patch (List.length fixtures)
