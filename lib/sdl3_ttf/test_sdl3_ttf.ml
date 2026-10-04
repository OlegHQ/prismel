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

let run () =
  if Array.length Sys.argv <> 2 then fail "unexpected command-line arguments";
  let font_path = get_ttf (Font.system_path ()) in
  if not (Sys.file_exists font_path) then
    fail "installed system font discovery returned a missing path";
  let triple (v : Sdl3.version) = v.major, v.minor, v.patch in
  (match Sdl3_lock.check_installed ~lock:(Sdl3_lock.read "../../packaging/sdl3.lock")
      ~key:"sdl3_ttf" ~compiled:(triple compiled_version)
      ~linked:(triple (linked_version ())) with
   | Ok () -> () | Error message -> fail message);
  (match check_version ~release:true () with
   | Ok () -> () | Error error -> fail (Format.asprintf "%a" pp_error error));
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
       ignore (linked_version ());
       if captured.message <> original then
         fail "TTF error text changed after a subsequent native call"
   | Ok font -> ignore (Font.destroy font); fail "missing font opened"
   | Error _ -> fail "missing font returned the wrong error");

  let font = get_ttf (Font.open_file ~path:font_path ~size:18.) in
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
  (match Font.size_text font "bad\xc0\xaf" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "malformed UTF-8 text metrics were accepted");
  (match Font.render_blended font ~color:(256, 0, 0, 255) "bad" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "out-of-range text color was accepted");
  (match Font.render_blended font ~color:(0, 0, 0, 255) "bad\x00text" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "NUL raster text was accepted");
  (match get_ttf (Font.render_blended font ~color:(12, 34, 56, 200) "") with
   | None -> ()
   | Some _ -> fail "empty text allocated a raster");
  let rgba = match get_ttf
      (Font.render_blended font ~color:(12, 34, 56, 200) "Prismel ž") with
    | Some rgba -> rgba
    | None -> fail "non-empty text did not rasterize"
  in
  if rgba.width <> width || rgba.height <> height
      || Bytes.length rgba.pixels <> width * height * 4
      || not (has_visible_alpha rgba.pixels) then
    fail "CPU glyph rasterization disagrees with text metrics or alpha";
  (* every render owns its buffer *)
  let again = match get_ttf
      (Font.render_blended font ~color:(12, 34, 56, 200) "Prismel ž") with
    | Some rgba -> rgba | None -> fail "second raster of the same text failed" in
  if again.pixels == rgba.pixels || again.pixels <> rgba.pixels then
    fail "two renders of one text share a buffer or differ";

  (* setters: accepted values and the rejected one *)
  get_ttf (Font.set_style font [Font.Bold; Font.Italic; Font.Underline]);
  get_ttf (Font.set_style font [Font.Normal]);
  get_ttf (Font.set_outline font 2);
  (match Font.set_outline font (-1) with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "negative font outline was accepted");
  get_ttf (Font.set_outline font 0);
  get_ttf (Font.set_hinting font Font.Mono_hinting);
  get_ttf (Font.set_hinting font Font.Normal_hinting);
  get_ttf (Font.set_kerning font false);
  get_ttf (Font.set_kerning font true);
  let glyph = get_ttf (Font.glyph_metrics font (Char.code 'A')) in
  if glyph.advance <= 0 || glyph.max_x < glyph.min_x || glyph.max_y < glyph.min_y then
    fail "ASCII glyph metrics are invalid";
  List.iter (fun codepoint ->
    match Font.glyph_metrics font codepoint with
    | Error { kind = Invalid_argument; _ } -> ()
    | Ok _ | Error _ -> fail "invalid Unicode scalar was accepted")
    [-1; 0xd800; 0x110000];
  let wrapped_width, wrapped_height =
    get_ttf (Font.size_text_wrapped font ~wrap_width:80
      "a deterministic wrapped line with several words")
  in
  if wrapped_width > 80 || wrapped_height <= metrics.line_skip then
    fail "wrapped text metrics did not produce multiple bounded lines";
  get_ttf (Font.set_wrap_alignment font Font.Center);
  let wrapped = match get_ttf (Font.render_blended_wrapped font
      ~color:(200, 180, 160, 255) ~wrap_width:80
      "a deterministic wrapped line with several words") with
    | Some rgba -> rgba
    | None -> fail "wrapped non-empty text did not rasterize"
  in
  if wrapped.width <> wrapped_width || wrapped.height <> wrapped_height
      || not (has_visible_alpha wrapped.pixels) then
    fail "wrapped raster disagrees with wrapped metrics";
  (match Font.render_blended_wrapped font ~color:(0, 0, 0, 255)
      ~wrap_width:80 "bad\xed\xa0\x80" with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "malformed wrapped UTF-8 was accepted");

  (* density: the same text at 144 DPI is about twice the size of 72 DPI *)
  get_ttf (Font.set_size_dpi font ~size:18. ~horizontal:72 ~vertical:72);
  let one_x_width, one_x_height = get_ttf (Font.size_text font "Density") in
  get_ttf (Font.set_size_dpi font ~size:18. ~horizontal:144 ~vertical:144);
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

  let wrong_domain = Domain.spawn (fun () -> Font.size_text font "domain")
    |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain font access was not rejected");
  (match Init.quit () with
   | Error { kind = Fonts_still_open; _ } -> ()
   | Ok () | Error _ -> fail "TTF quit ignored a live font");

  get_ttf (Font.destroy font);
  get_ttf (Font.destroy font);
  (match Font.metrics font with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale font access was not rejected");
  for _ = 1 to 10_000 do
    let transient = get_ttf (Font.open_file ~path:font_path ~size:8.) in
    get_ttf (Font.destroy transient)
  done;
  get_ttf (Init.quit ());
  get_ttf (Init.quit ());
  Printf.printf "SDL3_ttf %d.%d.%d CPU font conformance passed\n%!"
    (linked_version ()).major (linked_version ()).minor (linked_version ()).patch
