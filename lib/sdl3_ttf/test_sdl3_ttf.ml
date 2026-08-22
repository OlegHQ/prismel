open Sdl3
open Sdl3_ttf

let fail message = failwith ("SDL3_ttf test: " ^ message)

let get_ttf = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" Sdl3_ttf.pp_error error)

let get_sdl = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" Sdl3.pp_error error)

let has_visible_alpha pixels =
  let rec loop index =
    index < Bytes.length pixels
    && (Char.code (Bytes.get pixels index) <> 0 || loop (index + 4))
  in
  Bytes.length pixels >= 4 && loop 3

let () =
  if Array.length Sys.argv <> 2 || not (Sys.file_exists Sys.argv.(1)) then
    fail "expected an installed font path";
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled <> { Version.major = 3; minor = 2; patch = 2 }
      || linked <> compiled || not Version.stable_headers
      || Version.function_count < 100 || Version.safe_function_count <> 15 then
    fail "generated or linked SDL3_ttf provenance changed";
  (match Font.open_file ~path:Sys.argv.(1) ~size:18. with
   | Error { kind = Not_initialized; _ } -> ()
   | Ok font -> ignore (Font.destroy font); fail "font opened before TTF init"
   | Error _ -> fail "pre-init font open returned the wrong error");
  get_ttf (Init.init ());
  if not (Init.initialized ()) then fail "TTF initialization was not retained";
  (match Font.open_file ~path:Sys.argv.(1) ~size:nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok font -> ignore (Font.destroy font); fail "NaN font size was accepted"
   | Error _ -> fail "NaN font size returned the wrong error");
  (match Font.open_file ~path:"/definitely/missing/font.ttf" ~size:18. with
   | Error { kind = Ttf_error; message; _ } when message <> "" -> ()
   | Ok font -> ignore (Font.destroy font); fail "missing font opened"
   | Error _ -> fail "missing font returned the wrong error");

  let font = get_ttf (Font.open_file ~path:Sys.argv.(1) ~size:18.) in
  let generation = Font.generation font in
  let metrics = get_ttf (Font.metrics font) in
  if metrics.height <= 0 || metrics.ascent <= 0 || metrics.line_skip <= 0 then
    fail "font metrics are not positive";
  (match get_ttf (Font.family_name font), get_ttf (Font.style_name font) with
   | Some family, Some style when family <> "" && style <> "" -> ()
   | _ -> fail "borrowed font names were not copied");
  let width, height = get_ttf (Font.size_text font "Prismel ž") in
  if width <= 0 || height <= 0 then fail "UTF-8 text metrics are empty";
  if get_ttf (Font.size_text font "") <> (0, 0) then
    fail "empty text metrics are not a safe no-op";
  (match get_ttf (Font.render_blended font ~color:(12, 34, 56, 200) "") with
   | None -> ()
   | Some surface -> ignore (Surface.destroy surface);
       fail "empty text allocated a surface");
  let rendered = match get_ttf
      (Font.render_blended font ~color:(12, 34, 56, 200) "Prismel ž") with
    | Some surface -> surface
    | None -> fail "non-empty text did not rasterize"
  in
  let rgba = get_sdl (Surface.copy_rgba rendered) in
  if rgba.width <> width || rgba.height <> height
      || not (has_visible_alpha rgba.pixels) then
    fail "CPU glyph rasterization disagrees with text metrics or alpha";

  get_ttf (Font.set_size font 36.);
  if Font.generation font = generation then
    fail "font mutation did not invalidate its generation";
  let larger_width, larger_height = get_ttf (Font.size_text font "Prismel ž") in
  if larger_width <= width || larger_height <= height then
    fail "font size mutation did not change metrics";
  let wrong_domain = Domain.spawn (fun () -> Font.size_text font "domain")
    |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain font access was not rejected");
  (match Init.quit () with
   | Error { kind = Fonts_still_open; _ } -> ()
   | Ok () | Error _ -> fail "TTF quit ignored a live font");

  get_sdl (Surface.destroy rendered);
  get_ttf (Font.destroy font);
  get_ttf (Font.destroy font);
  (match Font.metrics font with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale font access was not rejected");
  get_ttf (Init.quit ());
  get_ttf (Init.quit ());
  Printf.printf "SDL3_ttf %d.%d.%d CPU font conformance passed\n%!"
    linked.major linked.minor linked.patch
