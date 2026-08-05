open Wap

let fail message = failwith ("Wap test: " ^ message)

let contains value needle =
  let value_length = String.length value
  and needle_length = String.length needle in
  let rec loop offset =
    offset + needle_length <= value_length
    && (String.sub value offset needle_length = needle || loop (offset + 1))
  in
  needle_length = 0 || loop 0

let write_all descriptor bytes =
  let rec loop offset =
    if offset < Bytes.length bytes then
      let written = Unix.single_write descriptor bytes offset
          (Bytes.length bytes - offset) in
      if written = 0 then raise End_of_file else loop (offset + written)
  in
  loop 0

let read_exact descriptor length =
  let output = Bytes.create length in
  let rec loop offset =
    if offset < length then
      let received = Unix.read descriptor output offset (length - offset) in
      if received = 0 then raise End_of_file else loop (offset + received)
  in
  loop 0;
  output

let read_until descriptor marker =
  let output = Buffer.create 256 and byte = Bytes.create 1 in
  let rec loop () =
    if Unix.read descriptor byte 0 1 = 0 then raise End_of_file;
    Buffer.add_char output (Bytes.unsafe_get byte 0);
    let value = Buffer.contents output in
    if String.length value >= String.length marker
       && String.sub value (String.length value - String.length marker)
            (String.length marker) = marker
    then value
    else loop ()
  in
  loop ()

let connect port =
  let descriptor = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect descriptor
    (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  descriptor

let http_get port path headers =
  let descriptor = connect port in
  let request =
    Printf.sprintf "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n%s\r\n"
      path port headers
  in
  write_all descriptor (Bytes.of_string request);
  descriptor

let websocket_payload descriptor =
  let first = read_exact descriptor 2 in
  let opcode = Char.code (Bytes.unsafe_get first 0) land 0xf
  and short = Char.code (Bytes.unsafe_get first 1) land 0x7f in
  let length =
    if short < 126 then short
    else if short = 126 then
      let bytes = read_exact descriptor 2 in
      (Char.code (Bytes.unsafe_get bytes 0) lsl 8)
      lor Char.code (Bytes.unsafe_get bytes 1)
    else
      let bytes = read_exact descriptor 8 in
      let value = ref 0 in
      for index = 0 to 7 do
        value := (!value lsl 8) lor Char.code (Bytes.unsafe_get bytes index)
      done;
      !value
  in
  opcode, Char.code (Bytes.unsafe_get first 0) land 0x80 <> 0,
  read_exact descriptor length

let masked_binary payload =
  let length = Bytes.length payload in
  if length > 125 then invalid_arg "test payload too large";
  let mask = Bytes.of_string "\x12\x34\x56\x78" in
  let output = Bytes.create (6 + length) in
  Bytes.unsafe_set output 0 (Char.chr 0x82);
  Bytes.unsafe_set output 1 (Char.chr (0x80 lor length));
  Bytes.blit mask 0 output 2 4;
  for index = 0 to length - 1 do
    Bytes.unsafe_set output (6 + index)
      (Char.chr
         (Char.code (Bytes.unsafe_get payload index)
          lxor Char.code (Bytes.unsafe_get mask (index land 3))))
  done;
  output

let set_i32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.unsafe_set bytes (offset + index)
      (Char.chr ((value lsr (index * 8)) land 0xff))
  done

let get_u16_le bytes offset =
  Char.code (Bytes.unsafe_get bytes offset)
  lor (Char.code (Bytes.unsafe_get bytes (offset + 1)) lsl 8)

let get_u32_le bytes offset =
  List.init 4 Fun.id
  |> List.fold_left (fun value index ->
       value lor
       (Char.code (Bytes.unsafe_get bytes (offset + index)) lsl (index * 8))) 0

let decode_qoi ~pixel_bytes encoded =
  let output = Bytes.create pixel_bytes in
  let index = Array.make 64 (0, 0, 0, 0) in
  let source = ref 0 and target = ref 0 in
  let r = ref 0 and g = ref 0 and b = ref 0 and a = ref 255 in
  let byte () =
    if !source >= Bytes.length encoded then
      fail
        (Printf.sprintf "truncated QOI payload at source %d/%d target %d/%d"
           !source (Bytes.length encoded) !target pixel_bytes);
    let value = Char.code (Bytes.unsafe_get encoded !source) in
    incr source;
    value
  in
  let write () =
    if !target + 4 > pixel_bytes then fail "oversized QOI payload";
    Bytes.unsafe_set output !target (Char.chr !r);
    Bytes.unsafe_set output (!target + 1) (Char.chr !g);
    Bytes.unsafe_set output (!target + 2) (Char.chr !b);
    Bytes.unsafe_set output (!target + 3) (Char.chr !a);
    target := !target + 4
  in
  let wrap value = value land 255 in
  while !target < pixel_bytes do
    let opcode = byte () in
    if opcode = 0xfe then begin
      r := byte (); g := byte (); b := byte ()
    end else if opcode = 0xff then begin
      r := byte (); g := byte (); b := byte (); a := byte ()
    end else begin
      match opcode land 0xc0 with
      | 0x00 ->
          let red, green, blue, alpha = index.(opcode land 63) in
          r := red; g := green; b := blue; a := alpha
      | 0x40 ->
          r := wrap (!r + ((opcode lsr 4 land 3) - 2));
          g := wrap (!g + ((opcode lsr 2 land 3) - 2));
          b := wrap (!b + ((opcode land 3) - 2))
      | 0x80 ->
          let next = byte () and green = (opcode land 63) - 32 in
          r := wrap (!r + green + ((next lsr 4) - 8));
          g := wrap (!g + green);
          b := wrap (!b + green + ((next land 15) - 8))
      | _ ->
          for _ = 1 to (opcode land 63) + 1 do write () done
    end;
    if opcode land 0xc0 <> 0xc0 || opcode = 0xfe || opcode = 0xff then begin
      let slot = (!r * 3 + !g * 5 + !b * 7 + !a * 11) land 63 in
      index.(slot) <- !r, !g, !b, !a;
      write ()
    end
  done;
  if !source <> Bytes.length encoded then fail "trailing QOI payload bytes";
  output

let wait_until predicate =
  let deadline = Unix.gettimeofday () +. 2. in
  let rec loop () =
    if predicate () then true
    else if Unix.gettimeofday () >= deadline then false
    else begin Thread.delay 0.005; loop () end
  in
  loop ()

let () =
  List.iter (fun (name, expected) ->
    if Runtime.target_of_string name <> Ok expected then
      fail ("runtime target parser rejected " ^ name))
    ["native", Runtime.Native; "sdl", Native;
     "headless", Headless; "software", Headless;
     "web", Web; "webgl", Web];
  if Result.is_ok (Runtime.target_of_string "unknown") then
    fail "runtime target parser accepted an unknown target";
  let prismal_only = function
    | "PRISMAL_RENDER_TARGET" -> Some "web"
    | _ -> None in
  if Runtime.Private.select_target prismal_only <> Ok Runtime.Web then
    fail "PRISMAL_-prefixed render target alias was not selected";
  let prefixed_headless = function
    | "PRISMEL_HEADLESS" -> Some "yes"
    | _ -> None in
  if Runtime.Private.select_target prefixed_headless <> Ok Runtime.Headless then
    fail "prefixed headless shorthand was not selected";
  let scheduled = Runtime.Private.next_web_deadline
      ~previous:10. ~now:10.016 ~frame_interval:0.033 ~traffic_interval:0.002 in
  if Float.abs (scheduled -. 10.033) > 0.000_001 then
    fail "web cadence drifted from its previous deadline";
  let traffic_limited = Runtime.Private.next_web_deadline
      ~previous:10. ~now:10.016 ~frame_interval:0.033 ~traffic_interval:0.1 in
  if Float.abs (traffic_limited -. 10.116) > 0.000_001 then
    fail "web traffic budget did not anchor to the current publish time";
  if Runtime.Private.fitted_web_drawable_size ~max_pixels:250_000
       ~logical_width:1_000 ~logical_height:1_000 <> (500, 500)
  then fail "web backing-pixel fit did not preserve viewport aspect ratio";
  let base_interval = 1. /. 60. in
  if Runtime.Private.idle_frame_interval base_interval 0 <> base_interval
     || Runtime.Private.idle_frame_interval base_interval 2
        <> base_interval *. 2.
     || Runtime.Private.idle_frame_interval base_interval 4
        <> base_interval *. 4.
  then fail "duplicate-frame readback backoff changed";
  if Private.websocket_accept "dGhlIHNhbXBsZSBub25jZQ=="
     <> "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
  then fail "RFC 6455 handshake digest changed";
  let pointer = Bytes.make 10 '\000' in
  Bytes.unsafe_set pointer 0 '\001';
  Bytes.unsafe_set pointer 1 '\001';
  set_i32_le pointer 2 17;
  set_i32_le pointer 6 29;
  if Private.decode_event pointer <> Some (Pointer_moved (17, 29)) then
    fail "binary pointer event decoding changed";
  let batched_pointer = Bytes.make 26 '\000' in
  Bytes.unsafe_set batched_pointer 0 '\001';
  Bytes.unsafe_set batched_pointer 1 '\001';
  List.iteri (fun index (x, y) ->
    set_i32_le batched_pointer (2 + (index * 8)) x;
    set_i32_le batched_pointer (6 + (index * 8)) y)
    [3, 5; 8, 13; 21, 34];
  if Private.decode_events batched_pointer <>
       [Pointer_moved (3, 5); Pointer_moved (8, 13); Pointer_moved (21, 34)]
  then fail "coalesced pointer batch decoding changed";
  let upload = Bytes.of_string "\001\011\005\000a.txthello" in
  (match Private.decode_event upload with
   | Some (File_uploaded { name = "a.txt"; contents })
     when Bytes.to_string contents = "hello" -> ()
   | _ -> fail "browser file upload decoding changed");
  let cancelled = Bytes.make 6 '\000' in
  Bytes.unsafe_set cancelled 0 '\001';
  Bytes.unsafe_set cancelled 1 '\012';
  set_i32_le cancelled 2 1;
  if Private.decode_event cancelled <> Some (Pointer_cancelled Left) then
    fail "browser pointer cancellation decoding changed";
  let server =
    match start ~config:{ default_config with port = 0; title = "Wap test" } () with
    | Ok server -> server
    | Error message -> fail message
  in
  Fun.protect ~finally:(fun () -> stop server) (fun () ->
    let page = http_get (port server) "/" "" in
    let response = read_until page "</html>" in
    Unix.close page;
    if not (String.starts_with ~prefix:"HTTP/1.1 200 OK" response)
       || not (String.contains response '<')
       || not (String.contains response 'W')
    then fail "HTTP browser shell was not served";
    let script_request = http_get (port server) "/client.js" "" in
    let script_response = read_until script_request "initializeWebGL();" in
    Unix.close script_request;
    if not (String.starts_with ~prefix:"HTTP/1.1 200 OK" script_response)
       || not (contains script_response "antialias: true")
       || not (contains script_response "gl.TEXTURE_MIN_FILTER, gl.LINEAR")
       || not (contains script_response "document.documentElement.clientWidth")
       || not (contains script_response "function decodeQoi")
       || not (contains script_response "send(13,[frameId])")
       || not (contains script_response "pendingTextFocus")
       || not (contains script_response "canvas.toBlob")
       || not (contains script_response "download_frame")
       || not (contains script_response "getCoalescedEvents")
       || not (contains script_response "scheduleFramePresentation")
       || not (contains script_response "synchronizeImeValue")
       || contains script_response "Math.min(logicalWidth - 1"
    then
      fail "mobile-aware browser client was not served";
    let token_marker = "data-token=\"" in
    let marker_start =
      match String.index_from_opt response 0 'd' with
      | None -> fail "browser token missing"
      | Some _ ->
          let rec find offset =
            if offset + String.length token_marker > String.length response then
              fail "browser token missing"
            else if String.sub response offset (String.length token_marker)
                    = token_marker
            then offset + String.length token_marker
            else find (offset + 1)
          in find 0
    in
    let token_end = String.index_from response marker_start '"' in
    let token = String.sub response marker_start (token_end - marker_start) in
    (match download_frame server ~filename:"stale.png" with
     | Error _ -> ()
     | Ok () -> fail "download was queued without a connected browser");
    let websocket = http_get (port server) ("/ws?token=" ^ token)
      "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" in
    let handshake = read_until websocket "\r\n\r\n" in
    if not (String.starts_with ~prefix:"HTTP/1.1 101" handshake)
       || not (String.contains handshake '+')
    then fail "WebSocket upgrade failed";
    if not (wait_until (fun () -> client_count server = 1)) then
      fail "WebSocket client was not registered";
    let asset =
      match register_bytes server ~content_type:"text/plain"
          (Bytes.of_string "browser audio") with
      | Some id -> id
      | None -> fail "browser asset registration failed" in
    let asset_request =
      http_get (port server) ("/asset/" ^ asset ^ "?token=" ^ token) "" in
    let asset_response = read_until asset_request "browser audio" in
    Unix.close asset_request;
    if not (String.starts_with ~prefix:"HTTP/1.1 200 OK" asset_response) then
      fail "token-protected browser asset was not served";
    let partial_request =
      http_get (port server) ("/asset/" ^ asset ^ "?token=" ^ token)
        "Range: bytes=3-7\r\n" in
    let partial_response = read_until partial_request "wser " in
    Unix.close partial_request;
    if not (String.starts_with ~prefix:"HTTP/1.1 206 Partial Content"
              partial_response)
       || not (String.contains partial_response '/')
    then fail "browser asset byte range was not served";
    let invalid_range =
      http_get (port server) ("/asset/" ^ asset ^ "?token=" ^ token)
        "Range: bytes=999-1000\r\n" in
    let invalid_response = read_until invalid_range "\r\n\r\n" in
    Unix.close invalid_range;
    if not (String.starts_with
              ~prefix:"HTTP/1.1 416 Range Not Satisfiable" invalid_response)
    then fail "invalid browser asset byte range was accepted";
    if Option.is_some (register_file server ".") then
      fail "asset registration accepted a directory";
    broadcast_audio server
      (Audio_sample_volume { asset = "quoted\"asset"; volume = 0.5 });
    let opcode, fin, audio_command = websocket_payload websocket in
    if opcode <> 1 || not fin
       || Bytes.to_string audio_command <>
            {|{"op":"sample_volume","id":"quoted\"asset","volume":0.5}|}
    then fail "typed browser audio command encoding changed";
    let text_region = { x = 4; y = 5; width = 60; height = 24; focused = false } in
    set_text_input_regions server [text_region];
    let opcode, fin, region_command = websocket_payload websocket in
    if opcode <> 1 || not fin
       || Bytes.to_string region_command <>
            {|{"op":"text_input_regions","regions":[[4,5,60,24,0]]}|}
    then fail "typed browser text-input regions were not streamed";
    set_text_input_regions server [text_region];
    (match download_frame server ~filename:"../my drawing" with
     | Error message -> fail ("browser download command failed: " ^ message)
     | Ok () -> ());
    let opcode, fin, download_command = websocket_payload websocket in
    if opcode <> 1 || not fin
       || Bytes.to_string download_command <>
            {|{"op":"download_frame","filename":"my drawing.png"}|}
    then fail "typed browser download command encoding changed";
    broadcast_text server {|{"op":"test"}|};
    let opcode, fin, command = websocket_payload websocket in
    if opcode <> 1 || not fin || Bytes.to_string command <> {|{"op":"test"}|}
    then fail "ordered browser control command was not streamed";
    let pixels = acquire_frame server ~length:8 in
    let values = [|255;0;0;255; 0;255;0;255|] in
    Array.iteri (Bigarray.Array1.set pixels) values;
    publish_frame server ~drawable_width:2 ~drawable_height:1
      ~logical_width:2 ~logical_height:1 pixels;
    let opcode, fin, metadata = websocket_payload websocket in
    if opcode <> 2 || fin || Bytes.sub_string metadata 0 4 <> "PRSM"
    then fail "frame metadata did not begin a fragmented binary message";
    let opcode, fin, rgba = websocket_payload websocket in
    if opcode <> 0 || not fin || Bytes.length rgba <> 8
       || Char.code (Bytes.unsafe_get rgba 0) <> 255
       || Char.code (Bytes.unsafe_get rgba 5) <> 255
    then fail "RGBA frame payload was not streamed intact";
    let acknowledge frame_id =
      let payload = Bytes.make 6 '\000' in
      Bytes.unsafe_set payload 0 '\001';
      Bytes.unsafe_set payload 1 '\013';
      set_i32_le payload 2 frame_id;
      write_all websocket (masked_binary payload)
    in
    acknowledge 0;
    let width = 64 and height = 64 in
    let compressible = acquire_frame server ~length:(width * height * 4) in
    for index = 0 to width * height - 1 do
      Bigarray.Array1.set compressible (index * 4) 12;
      Bigarray.Array1.set compressible (index * 4 + 1) 34;
      Bigarray.Array1.set compressible (index * 4 + 2) 56;
      Bigarray.Array1.set compressible (index * 4 + 3) 255
    done;
    publish_frame server ~drawable_width:width ~drawable_height:height
      ~logical_width:width ~logical_height:height compressible;
    let opcode, fin, compressed_metadata = websocket_payload websocket in
    if opcode <> 2 || fin || get_u16_le compressed_metadata 6 <> 1
       || get_u32_le compressed_metadata 8 <> 1
    then fail "compressible frame did not select the QOI wire codec";
    let opcode, fin, compressed = websocket_payload websocket in
    let encoded_pixels = ref 1 in
    for index = 4 to Bytes.length compressed - 1 do
      let value = Char.code (Bytes.unsafe_get compressed index) in
      if value land 0xc0 = 0xc0 then
        encoded_pixels := !encoded_pixels + (value land 63) + 1
    done;
    if !encoded_pixels <> width * height then
      fail (Printf.sprintf "QOI encoder covered %d/%d pixels"
        !encoded_pixels (width * height));
    let decoded = decode_qoi ~pixel_bytes:(width * height * 4) compressed in
    if opcode <> 0 || not fin || Bytes.length compressed >= Bytes.length decoded
       || Char.code (Bytes.unsafe_get decoded 0) <> 12
       || Char.code (Bytes.unsafe_get decoded 1) <> 34
       || Char.code (Bytes.unsafe_get decoded 2) <> 56
       || Char.code (Bytes.unsafe_get decoded (Bytes.length decoded - 1)) <> 255
    then fail "QOI frame did not decode to its source RGBA pixels";
    acknowledge 1;
    let patch_x = 17 and patch_y = 23 in
    let patch_offset = ((patch_y * width) + patch_x) * 4 in
    let patched_bytes = Bytes.copy decoded in
    Bytes.set_uint8 patched_bytes patch_offset 201;
    Bytes.set_uint8 patched_bytes (patch_offset + 1) 77;
    Bytes.set_uint8 patched_bytes (patch_offset + 2) 19;
    Bytes.set_uint8 patched_bytes (patch_offset + 3) 255;
    let patched = acquire_frame server ~length:(width * height * 4) in
    for index = 0 to Bigarray.Array1.dim patched - 1 do
      Bigarray.Array1.set patched index (Bytes.get_uint8 patched_bytes index)
    done;
    publish_frame server ~drawable_width:width ~drawable_height:height
      ~logical_width:width ~logical_height:height patched;
    let opcode, fin, patch_metadata = websocket_payload websocket in
    if opcode <> 2 || fin || Bytes.length patch_metadata <> 44
       || get_u16_le patch_metadata 6 <> 2
       || get_u32_le patch_metadata 8 <> 2
       || get_u32_le patch_metadata 28 <> patch_x
       || get_u32_le patch_metadata 32 <> patch_y
       || get_u32_le patch_metadata 36 <> 1
       || get_u32_le patch_metadata 40 <> 1
    then fail "single-pixel change did not select the raw patch wire codec";
    let opcode, fin, patch_pixels = websocket_payload websocket in
    if opcode <> 0 || not fin || Bytes.length patch_pixels <> 4
       || Bytes.get_uint8 patch_pixels 0 <> 201
       || Bytes.get_uint8 patch_pixels 1 <> 77
       || Bytes.get_uint8 patch_pixels 2 <> 19
       || Bytes.get_uint8 patch_pixels 3 <> 255
    then fail "dirty-rectangle payload did not preserve changed pixels";
    acknowledge 2;
    let duplicate = acquire_frame server ~length:(width * height * 4) in
    for index = 0 to Bigarray.Array1.dim duplicate - 1 do
      Bigarray.Array1.set duplicate index (Bytes.get_uint8 patched_bytes index)
    done;
    publish_frame server ~drawable_width:width ~drawable_height:height
      ~logical_width:width ~logical_height:height duplicate;
    let transport = stats server in
    if transport.frames_submitted <> 4 || transport.frames_published <> 3
       || transport.frames_suppressed <> 1
       || transport.payload_bytes_published >= transport.source_bytes_submitted
    then fail "frame compression or exact duplicate suppression counters changed";
    write_all websocket (masked_binary pointer);
    if not (wait_until (fun () ->
      match drain_events server with
      | [Pointer_moved (17, 29)] -> true
      | _ -> false))
    then fail "browser input did not reach the bounded event queue";
    Unix.close websocket);
  let capped_server =
    match start ~config:{ default_config with
      port = 0;
      max_frame_pool_bytes = 7;
    } () with
    | Ok server -> server
    | Error message -> fail message
  in
  Fun.protect ~finally:(fun () -> stop capped_server) (fun () ->
    let oversized = acquire_frame capped_server ~length:8 in
    discard_frame capped_server oversized;
    let replacement = acquire_frame capped_server ~length:8 in
    if replacement == oversized then
      fail "frame pool retained a buffer beyond its byte ceiling";
    discard_frame capped_server replacement)
