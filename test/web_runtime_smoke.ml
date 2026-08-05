open Prismel

let fail message = failwith ("Web runtime smoke: " ^ message)

let write_all descriptor bytes =
  let rec loop offset =
    if offset < Bytes.length bytes then
      let written = Unix.single_write descriptor bytes offset
          (Bytes.length bytes - offset) in
      if written = 0 then raise End_of_file else loop (offset + written)
  in loop 0

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
  let output = Buffer.create 512 and byte = Bytes.create 1 in
  let rec loop () =
    if Unix.read descriptor byte 0 1 = 0 then raise End_of_file;
    Buffer.add_char output (Bytes.unsafe_get byte 0);
    let value = Buffer.contents output in
    if String.length value >= String.length marker
       && String.sub value (String.length value - String.length marker)
            (String.length marker) = marker
    then value
    else loop ()
  in loop ()

let find_between value prefix suffix =
  let rec find offset =
    if offset + String.length prefix > String.length value then
      fail (prefix ^ " not found")
    else if String.sub value offset (String.length prefix) = prefix then
      let start = offset + String.length prefix in
      let finish = String.index_from value start suffix in
      String.sub value start (finish - start)
    else find (offset + 1)
  in find 0

let connect port =
  let descriptor = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float descriptor Unix.SO_RCVTIMEO 3.;
  Unix.connect descriptor (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  descriptor

let request descriptor port target headers =
  Printf.sprintf "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n%s\r\n"
    target port headers
  |> Bytes.of_string |> write_all descriptor

let websocket_payload descriptor =
  let header = read_exact descriptor 2 in
  let first = Char.code (Bytes.unsafe_get header 0)
  and short = Char.code (Bytes.unsafe_get header 1) land 0x7f in
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
  first land 0xf, first land 0x80 <> 0, read_exact descriptor length

let set_i32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.unsafe_set bytes (offset + index)
      (Char.chr ((value lsr (index * 8)) land 0xff))
  done

let decode_qoi ~pixel_bytes encoded =
  let output = Bytes.create pixel_bytes in
  let index = Array.make 64 (0, 0, 0, 0) in
  let source = ref 0 and target = ref 0 in
  let r = ref 0 and g = ref 0 and b = ref 0 and a = ref 255 in
  let byte () =
    if !source >= Bytes.length encoded then fail "truncated QOI frame";
    let value = Char.code (Bytes.unsafe_get encoded !source) in
    incr source;
    value
  in
  let write () =
    if !target + 4 > pixel_bytes then fail "oversized QOI frame";
    Bytes.unsafe_set output !target (Char.chr !r);
    Bytes.unsafe_set output (!target + 1) (Char.chr !g);
    Bytes.unsafe_set output (!target + 2) (Char.chr !b);
    Bytes.unsafe_set output (!target + 3) (Char.chr !a);
    target := !target + 4
  and wrap value = value land 255 in
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
      | _ -> for _ = 1 to (opcode land 63) + 1 do write () done
    end;
    if opcode land 0xc0 <> 0xc0 || opcode = 0xfe || opcode = 0xff then begin
      let slot = (!r * 3 + !g * 5 + !b * 7 + !a * 11) land 63 in
      index.(slot) <- !r, !g, !b, !a;
      write ()
    end
  done;
  if !source <> Bytes.length encoded then fail "trailing QOI frame data";
  output

let event opcode integers =
  let payload = Bytes.make (2 + (Array.length integers * 4)) '\000' in
  Bytes.unsafe_set payload 0 '\001';
  Bytes.unsafe_set payload 1 (Char.chr opcode);
  Array.iteri (fun index value -> set_i32_le payload (2 + index * 4) value)
    integers;
  payload

let text_event opcode text =
  let payload = Bytes.create (2 + String.length text) in
  Bytes.unsafe_set payload 0 '\001';
  Bytes.unsafe_set payload 1 (Char.chr opcode);
  Bytes.blit_string text 0 payload 2 (String.length text);
  payload

let upload_event name contents =
  let payload = Bytes.create (4 + String.length name + String.length contents) in
  Bytes.unsafe_set payload 0 '\001';
  Bytes.unsafe_set payload 1 '\011';
  Bytes.unsafe_set payload 2 (Char.chr (String.length name land 0xff));
  Bytes.unsafe_set payload 3 (Char.chr (String.length name lsr 8));
  Bytes.blit_string name 0 payload 4 (String.length name);
  Bytes.blit_string contents 0 payload (4 + String.length name)
    (String.length contents);
  payload

let masked_binary salt payload =
  let length = Bytes.length payload in
  let output = Bytes.create (6 + length) in
  Bytes.unsafe_set output 0 (Char.chr 0x82);
  Bytes.unsafe_set output 1 (Char.chr (0x80 lor length));
  for index = 0 to 3 do
    Bytes.unsafe_set output (2 + index) (Char.chr ((salt + index * 37) land 0xff))
  done;
  for index = 0 to length - 1 do
    Bytes.unsafe_set output (6 + index)
      (Char.chr
         (Char.code (Bytes.unsafe_get payload index)
          lxor Char.code (Bytes.unsafe_get output (2 + (index land 3)))))
  done;
  output

let port_of_url value =
  match String.rindex_opt value ':' with
  | None -> fail "runtime URL omitted its port"
  | Some colon ->
      let slash = String.index_from value colon '/' in
      int_of_string (String.sub value (colon + 1) (slash - colon - 1))

let browser_client port =
  let http = connect port in
  request http port "/" "";
  let page = read_until http "</html>" in
  Unix.close http;
  if find_between page "data-resizable=\"" '"' <> "1" then
    fail "runtime did not make the browser viewport authoritative";
  let token = find_between page "data-token=\"" '"' in
  let socket = connect port in
  Fun.protect ~finally:(fun () -> try Unix.close socket with Unix.Unix_error _ -> ())
    (fun () ->
      request socket port ("/ws?token=" ^ token)
        "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n";
      let handshake = read_until socket "\r\n\r\n" in
      if not (String.starts_with ~prefix:"HTTP/1.1 101" handshake) then
        fail "runtime rejected browser WebSocket upgrade";
      let opcode, fin, audio_command = websocket_payload socket in
      if opcode <> 1 || not fin then
        fail "runtime did not mirror audio control into the browser";
      let audio_command = Bytes.to_string audio_command in
      let asset = find_between audio_command "\"id\":\"" '"' in
      let audio = connect port in
      request audio port ("/asset/" ^ asset ^ "?token=" ^ token) "";
      let audio_response = read_until audio "RIFF" in
      Unix.close audio;
      if not (String.starts_with ~prefix:"HTTP/1.1 200 OK" audio_response) then
        fail "runtime did not expose synthesized browser audio";
      let opcode, fin, regions = websocket_payload socket in
      if opcode <> 1 || not fin
         || Bytes.to_string regions <>
              {|{"op":"text_input_regions","regions":[[5,6,10,11,0]]}|}
      then fail "runtime did not publish browser text-input hit regions";
      let opcode, fin, metadata = websocket_payload socket in
      if opcode <> 2 || fin || Bytes.sub_string metadata 0 4 <> "PRSM" then
        fail "runtime did not publish frame metadata";
      let codec =
        Char.code (Bytes.unsafe_get metadata 6)
        lor (Char.code (Bytes.unsafe_get metadata 7) lsl 8)
      in
      let opcode, fin, pixels = websocket_payload socket in
      let pixels = match codec with
        | 0 -> pixels
        | 1 -> decode_qoi ~pixel_bytes:(64 * 48 * 4) pixels
        | _ -> fail "runtime selected an unknown browser frame codec"
      in
      if opcode <> 0 || not fin || Bytes.length pixels <> 64 * 48 * 4 then
        fail "runtime did not publish the complete native framebuffer";
      if Char.code (Bytes.unsafe_get pixels 0) <> 7
         || Char.code (Bytes.unsafe_get pixels 1) <> 11
         || Char.code (Bytes.unsafe_get pixels 2) <> 19
      then fail "browser framebuffer pixels differ from the rendered scene";
      [ event 1 [|13; 17|];
        event 13 [|0|];
        event 2 [|1; 13; 17|];
        event 4 [|0; 1|];
        text_event 5 "a";
        text_event 7 "A";
        text_event 6 "a";
        event 3 [|1; 13; 17|];
        event 9 [|80; 60|];
        upload_event "browser.txt" "prismel web upload";
        event 10 [||];
      ]
      |> List.iteri (fun index payload ->
        write_all socket (masked_binary (19 + index) payload)))

type model = {
  mutable client : Thread.t option;
  result : (unit, string) result option Atomic.t;
  mutable received : bool;
  mutable observed : Event.t list;
  mutable correct_delta : bool;
  mutable dropped_path : string option;
  sample : Audio.Sample.t;
}

let () =
  let sdl_environment =
    List.map (fun name -> name, Sys.getenv_opt name)
      ["SDL_VIDEODRIVER"; "SDL_RENDER_DRIVER"; "SDL_AUDIODRIVER"] in
  if Sketch.render_target () <> Sketch.Web || not (Sketch.is_web ())
     || Sketch.is_headless ()
  then fail "web target selection was not visible through Sketch";
  let final =
    Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 64; height = 48; fps = Some 120; title = "web smoke";
        (* Web deployments adopt the viewport independently of native-window
           resize opt-in. *)
        resizable = false;
      }
      ~init:(fun _ ->
        let port = match Low.Backend.web_url () with
          | Some url -> port_of_url url
          | None -> fail "runtime did not expose its web URL" in
        let model = {
          client = None; result = Atomic.make None; received = false;
          observed = []; correct_delta = false;
          dropped_path = None;
          sample =
            Audio.Sample.synth ~waveform:Audio.Sample.Sine ~frequency:440.
              ~duration:0.05 () |> Result.get_ok;
        } in
        ignore (Audio.Sample.play model.sample);
        let thread = Thread.create (fun () ->
          try browser_client port; Atomic.set model.result (Some (Ok ()))
          with error ->
            Atomic.set model.result
              (Some (Error (Printexc.to_string error)))) () in
        model.client <- Some thread;
        model)
      ~update:(fun model frame ->
        model.observed <- model.observed @ frame.events;
        if List.exists (function Event.MouseMoved _ -> true | _ -> false)
            frame.events
        then model.correct_delta <- frame.mouse_delta = (13, 17);
        if List.exists (( = ) Event.WindowFocusLost) frame.events then
        (match model.observed with
         | [ Event.MouseMoved (13, 17);
             MousePressed (Input.LeftButton, (13, 17));
             MouseScrolled (0, 1);
             KeyPressed (Input.KeyChar 'a');
             TextInput "A";
             KeyReleased (Input.KeyChar 'a');
             MouseReleased (Input.LeftButton, (13, 17));
             WindowResized (80, 60);
             FileDropped path;
             WindowFocusLost ] ->
             if frame.size <> (80, 60) || frame.mouse <> (13, 17)
                || not model.correct_delta
                || frame.keys <> [] || frame.mouse_buttons <> []
             then fail "browser input state or resize snapshot was inconsistent";
             let channel = open_in_bin path in
             let contents = really_input_string channel (in_channel_length channel) in
             close_in channel;
             if contents <> "prismel web upload" then
               fail "browser file upload contents changed";
             model.dropped_path <- Some path;
             model.received <- true;
             Sketch.quit ()
         | events ->
             fail ("browser event order changed: "
               ^ String.concat ", " (List.map Event.event_to_string events)));
        if frame.count > 360 then fail "timed out waiting for browser input";
        model)
      ~view:(fun _ _ -> Scene.[
        clear (Color.rgb 7 11 19);
        rect ~at:(20, 12) ~w:24 ~h:20 ~fill:Color.cyan ();
        text_input_region ~at:(5, 6) ~w:10 ~h:11 ();
      ])
      ~on_stop:(fun model ->
        Option.iter Thread.join model.client;
        Audio.Sample.destroy model.sample)
      ()
  in
  if not final.received then fail "browser input never reached Frame.events";
  Option.iter (fun path ->
    if Sys.file_exists path then fail "uploaded temporary file leaked after stop")
    final.dropped_path;
  List.iter (fun (name, expected) ->
    if Sys.getenv_opt name <> expected then
      fail (name ^ " leaked across Runtime.stop")) sdl_environment;
  match Atomic.get final.result with
  | Some (Ok ()) -> ()
  | Some (Error message) -> fail message
  | None -> fail "browser client did not finish"
