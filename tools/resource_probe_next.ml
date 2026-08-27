open Prismel_next_resources

let get = function Ok value -> value | Error error ->
  failwith (Format.asprintf "%a" pp_error error)
let digest bytes = Digest.to_hex (Digest.bytes bytes)
let read path = let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
    Bytes.of_string (really_input_string channel (in_channel_length channel)))

let wav () =
  let bytes = Bytes.make 48 '\000' in
  Bytes.blit_string "RIFF" 0 bytes 0 4; Bytes.set_int32_le bytes 4 40l;
  Bytes.blit_string "WAVEfmt " 0 bytes 8 8; Bytes.set_int32_le bytes 16 16l;
  Bytes.set_int16_le bytes 20 1; Bytes.set_int16_le bytes 22 1;
  Bytes.set_int32_le bytes 24 8000l; Bytes.set_int32_le bytes 28 16000l;
  Bytes.set_int16_le bytes 32 2; Bytes.set_int16_le bytes 34 16;
  Bytes.blit_string "data" 0 bytes 36 4; Bytes.set_int32_le bytes 40 4l;
  Bytes.set_int16_le bytes 44 1000; Bytes.set_int16_le bytes 46 (-1000); bytes

let () =
  if Array.length Sys.argv <> 2 then failwith "fixture directory required";
  let png = Filename.concat Sys.argv.(1) "sample.png" in
  let encoded = read png in
  let file = get (Image.load_file png) and memory = get (Image.load_bytes ~kind:"PNG" encoded) in
  let created = get (Image.create ~width:2 ~height:1
      ~rgba:(Bytes.of_string "\x01\x02\x03\xff\x04\x05\x06\x80")) in
  let created_id = Image.identity created and generation = Image.generation created in
  let failed_reload = match Image.reload_file created "/definitely/missing.png" with
    | Error _ -> Image.identity created = created_id && Image.generation created = generation
    | Ok () -> false in
  get (Image.replace created ~width:1 ~height:1 ~rgba:(Bytes.of_string "\xff\x00\x00\xff"));
  let canvas = get (Canvas.create ~width:3 ~height:2) in
  get (Canvas.clear canvas 0x010203ffl); get (Canvas.draw_image canvas created ~x:1 ~y:0);
  let capture = get (Canvas.capture canvas) in
  let capture_hash = digest (get (Image.pixels capture)) in
  get (Canvas.resize canvas ~width:4 ~height:3);
  let font = get (Font.open_system ~size:14.) in
  get (Font.set_style font [Font.Bold]); get (Font.set_hinting font Font.Light_hinting);
  get (Font.set_kerning font true); let glyph = get (Font.glyph_metrics font 65) in
  let empty = get (Font.render font ~density:1 ~color:(255,255,255,255) "") = None in
  let wrapped = Option.get (get (Font.render font ~wrap_width:30 ~density:1
      ~color:(255,255,255,255) "alpha beta")) in
  let wrapped_size = get (Text.size wrapped) in
  let audio = get (Audio.create_memory ~sample_rate:8000 ~channels:1 ~max_channels:4) in
  let sample = get (Audio.load_sample_bytes audio (wav ())) in
  let channel = get (Audio.play_sample audio ~loops:1 ~fade_in_ms:1 ~volume:0.5 sample) in
  get (Audio.stop_channel audio channel ~fade_out_ms:1 ());
  get (Audio.play_music audio ~loops:1 ~fade_in_ms:1 sample); get (Audio.stop_music audio ~fade_out_ms:1 ());
  let mixed = get (Audio.generate audio ~frames:8) in
  let json = `Assoc [
    "schema", `Int 1; "stack", `String "next";
    "image", `Assoc ["file_bytes_equal", `Bool (get (Image.pixels file) = get (Image.pixels memory));
      "created_hash", `String (digest (get (Image.pixels created)));
      "generation", `Int (Image.generation created); "failed_reload_retained", `Bool failed_reload];
    "canvas", `Assoc ["capture_hash", `String capture_hash; "resized", `List [`Int 4; `Int 3]];
    "font", `Assoc ["glyph_advance", `Int glyph.advance; "empty_noop", `Bool empty;
      "wrapped", `List [`Int (fst wrapped_size); `Int (snd wrapped_size)]];
    "audio", `Assoc ["encoded_hash", `String (digest (get (Audio.sample_encoded sample)));
      "mixed_bytes", `Int mixed.mixed_bytes; "lifecycle", `Bool true]
  ] in
  Yojson.Safe.pretty_to_channel stdout json; output_char stdout '\n';
  get (Text.destroy wrapped); get (Font.destroy font); get (Image.destroy capture);
  get (Canvas.destroy canvas); List.iter (fun image -> get (Image.destroy image)) [file;memory;created];
  get (Audio.destroy_sample sample); get (Audio.destroy audio)
