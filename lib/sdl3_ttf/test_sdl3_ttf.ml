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

type cached =
  { key : int * string * (int * int * int * int)
  ; surface : Surface.t
  }

type cache =
  { capacity : int
  ; mutable entries : cached list
  }

let create_cache capacity =
  if capacity <= 0 then invalid_arg "create_cache";
  { capacity; entries = [] }

let clear_cache cache =
  List.iter (fun entry -> get_sdl (Surface.destroy entry.surface)) cache.entries;
  cache.entries <- []

let cached_text cache font ~color text =
  let key = Font.generation font, text, color in
  let rec extract reversed = function
    | [] -> None, List.rev reversed
    | entry :: rest when entry.key = key ->
        Some entry, List.rev_append reversed rest
    | entry :: rest -> extract (entry :: reversed) rest
  in
  match extract [] cache.entries with
  | Some entry, remaining ->
      cache.entries <- entry :: remaining;
      Some entry.surface
  | None, _ ->
      match get_ttf (Font.render_blended font ~color text) with
      | None -> None
      | Some surface ->
          let inserted = { key; surface } in
          let rec trim count kept = function
            | [] -> List.rev kept
            | entry :: rest when count < cache.capacity ->
                trim (count + 1) (entry :: kept) rest
            | entry :: rest ->
                get_sdl (Surface.destroy entry.surface);
                trim count kept rest
          in
          cache.entries <- trim 0 [] (inserted :: cache.entries);
          Some surface

let () =
  if Array.length Sys.argv <> 1 then fail "unexpected command-line arguments";
  let font_path = get_ttf (Font.system_path ()) in
  if not (Sys.file_exists font_path) then
    fail "installed system font discovery returned a missing path";
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled <> { Version.major = 3; minor = 2; patch = 2 }
      || linked <> compiled || not Version.stable_headers
      || Version.function_count < 100 || Version.safe_function_count <> 17 then
    fail "generated or linked SDL3_ttf provenance changed";
  (match Font.open_file ~path:font_path ~size:18. with
   | Error { kind = Not_initialized; _ } -> ()
   | Ok font -> ignore (Font.destroy font); fail "font opened before TTF init"
   | Error _ -> fail "pre-init font open returned the wrong error");
  get_ttf (Init.init ());
  if not (get_ttf (Init.initialized ())) then
    fail "TTF initialization was not retained";
  (match Domain.spawn Init.initialized |> Domain.join with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain TTF init query was not rejected");
  (match Font.open_file ~path:font_path ~size:nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok font -> ignore (Font.destroy font); fail "NaN font size was accepted"
   | Error _ -> fail "NaN font size returned the wrong error");
  (match Font.open_file ~path:"" ~size:18. with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok font -> ignore (Font.destroy font); fail "empty font path opened"
   | Error _ -> fail "empty font path returned the wrong error");
  (match Font.open_file ~path:"/definitely/missing/font.ttf" ~size:18. with
   | Error ({ kind = Ttf_error; message; _ } as captured) when message <> "" ->
       let original = captured.message in
       ignore (Version.linked ());
       if captured.message <> original then
         fail "TTF error text changed after a subsequent native call"
   | Ok font -> ignore (Font.destroy font); fail "missing font opened"
   | Error _ -> fail "missing font returned the wrong error");

  let font = get_ttf (Font.open_file ~path:font_path ~size:18.) in
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
  (match Font.size_text font "bad\x00text" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "NUL text metrics were accepted");
  (match Font.render_blended font ~color:(256, 0, 0, 255) "bad" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "out-of-range text color was accepted");
  (match Font.render_blended font ~color:(0, 0, 0, 255) "bad\x00text" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "NUL raster text was accepted");
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

  let cache = create_cache 256 in
  let cached_first = match cached_text cache font ~color:(255, 255, 255, 255)
      "cached text" with
    | Some surface -> surface
    | None -> fail "non-empty cache entry did not rasterize"
  in
  let cached_again = match cached_text cache font ~color:(255, 255, 255, 255)
      "cached text" with
    | Some surface -> surface
    | None -> fail "cached text disappeared"
  in
  if cached_first != cached_again || List.length cache.entries <> 1 then
    fail "font cache duplicated a borrowed CPU raster";

  clear_cache cache;
  get_ttf (Font.set_size font 36.);
  if not (Surface.destroyed cached_first) || cache.entries <> [] then
    fail "font mutation did not invalidate cached raster ownership";
  if Font.generation font = generation then
    fail "font mutation did not invalidate its generation";
  let larger_width, larger_height = get_ttf (Font.size_text font "Prismel ž") in
  if larger_width <= width || larger_height <= height then
    fail "font size mutation did not change metrics";

  let density_generation = Font.generation font in
  get_ttf (Font.set_size_dpi font ~size:18. ~horizontal:72 ~vertical:72);
  if get_ttf (Font.dpi font) <> (72, 72) then fail "72-DPI state changed";
  let one_x_width, one_x_height = get_ttf (Font.size_text font "Density") in
  get_ttf (Font.set_size_dpi font ~size:18. ~horizontal:144 ~vertical:144);
  if get_ttf (Font.dpi font) <> (144, 144)
      || Font.generation font = density_generation then
    fail "density mutation did not update DPI and generation";
  let two_x_width, two_x_height = get_ttf (Font.size_text font "Density") in
  let width_scale = float_of_int two_x_width /. float_of_int one_x_width
  and height_scale = float_of_int two_x_height /. float_of_int one_x_height in
  if width_scale < 1.8 || width_scale > 2.2
      || height_scale < 1.8 || height_scale > 2.2 then
    fail (Printf.sprintf
      "144-DPI raster metrics are not approximately twice 72-DPI metrics: \
       %dx%d -> %dx%d"
      one_x_width one_x_height two_x_width two_x_height);
  (match Font.set_size_dpi font ~size:18. ~horizontal:0 ~vertical:144 with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "non-positive font DPI was accepted");

  let oldest = ref None and newest = ref None in
  for index = 0 to 269 do
    match cached_text cache font ~color:(255, 255, 255, 255)
        (string_of_int index) with
    | None -> fail "dynamic cache label did not rasterize"
    | Some surface ->
        if index = 0 then oldest := Some surface;
        if index = 269 then newest := Some surface
  done;
  if List.length cache.entries <> 256 then
    fail "dynamic labels escaped the 256-entry font cache bound";
  (match !oldest with
   | Some surface when Surface.destroyed surface -> ()
   | Some _ | None -> fail "font LRU did not destroy its oldest raster");
  (match !newest with
   | None -> fail "font LRU did not retain its newest raster"
   | Some expected ->
       match cached_text cache font ~color:(255, 255, 255, 255) "269" with
       | Some actual when actual == expected -> ()
       | Some _ | None -> fail "font LRU hit changed borrowed identity");
  clear_cache cache;
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
