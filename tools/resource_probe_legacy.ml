open Prismel

let digest colors =
  let bytes = Bytes.create (Array.length colors * 4) in
  Array.iteri (fun index color ->
    let offset = index * 4 in
    Bytes.set_uint8 bytes offset color.Color.r;
    Bytes.set_uint8 bytes (offset+1) color.Color.g;
    Bytes.set_uint8 bytes (offset+2) color.Color.b;
    Bytes.set_uint8 bytes (offset+3) color.Color.a) colors;
  Digest.to_hex (Digest.bytes bytes)
let result = function Ok value -> value | Error message -> failwith message
let msg = function Ok value -> value | Error (`Msg message) -> failwith message

let () =
  if Array.length Sys.argv <> 2 then failwith "fixture directory required";
  Unix.putenv "PRISMEL_RENDER_TARGET" "headless"; Unix.putenv "SDL_VIDEODRIVER" "dummy";
  match (try Low.App.init_sdl (); Ok () with exn -> Error (Printexc.to_string exn)) with
  | Error blocker ->
      Yojson.Safe.pretty_to_channel stdout (`Assoc ["schema", `Int 1;
        "stack", `String "legacy"; "available", `Bool false;
        "blocker", `String blocker]); output_char stdout '\n'
  | Ok () -> Fun.protect ~finally:Low.App.cleanup_sdl (fun () ->
    let created = Image.create ~width:1 ~height:1 ~color:Color.red () in
    let canvas = result (Canvas.create ~width:3 ~height:2) in
    Canvas.set_pixel canvas ~x:1 ~y:0 Color.red;
    let capture_hash = digest (Canvas.pixels canvas) in
    let font = msg (Font.system ~size:14 ()) in
    Font.set_style font [Font.Bold]; Font.set_hinting font Font.Light_hinting; Font.set_kerning font true;
    let _,_,_,_,advance = msg (Font.glyph_metrics font 65) in
    let empty = match Font.render_text font "" (Font.Blended Color.white) with Ok _ -> true | Error _ -> false in
    let wrapped = msg (Font.render_wrapped font "alpha beta" (Font.Blended Color.white) 30) in
    let audio_ready = match Audio.init ~frequency:8000 ~channels:1 () with Ok () -> true | Error _ -> false in
    let json = `Assoc ["schema", `Int 1; "stack", `String "legacy";
      "image", `Assoc ["create_size", `List [`Int (Image.get_width created); `Int (Image.get_height created)];
        "watched_reload", `String "legacy_internal_only"];
      "canvas", `Assoc ["capture_hash", `String capture_hash; "size", `List [`Int 3; `Int 2]];
      "font", `Assoc ["glyph_advance", `Int advance; "empty_noop", `Bool empty;
        "wrapped_lines", `Int (List.length wrapped)];
      "audio", `Assoc ["dummy_initialized", `Bool audio_ready;
        "encoded_pcm_facts", `String "legacy_internal_only"]] in
    Yojson.Safe.pretty_to_channel stdout json; output_char stdout '\n';
    List.iter Image.destroy wrapped; Font.destroy font; Canvas.destroy canvas; Image.destroy created;
    if audio_ready then Audio.shutdown ())
