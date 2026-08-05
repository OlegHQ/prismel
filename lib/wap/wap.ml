type mouse_button = Left | Middle | Right | X1 | X2

type event =
  | Pointer_moved of int * int
  | Pointer_pressed of mouse_button * int * int
  | Pointer_released of mouse_button * int * int
  | Pointer_cancelled of mouse_button
  | Wheel of int * int
  | Key_pressed of string
  | Key_released of string
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Resized of int * int
  | Focus_lost
  | File_uploaded of { name : string; contents : bytes }

type pixel_buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type text_input_region = {
  x : int;
  y : int;
  width : int;
  height : int;
  focused : bool;
}

type audio_command =
  | Audio_master_volume of float
  | Audio_stop_all
  | Audio_sample_play of {
      asset : string; channel : int; loops : int; volume : float;
    }
  | Audio_sample_volume of { asset : string; volume : float }
  | Audio_sample_stop of int
  | Audio_sample_pause of int
  | Audio_sample_resume of int
  | Audio_music_play of { asset : string; loops : int; fade_ms : int }
  | Audio_music_volume of float
  | Audio_music_pause
  | Audio_music_resume
  | Audio_music_stop of int
  | Audio_asset_remove of string

type config = {
  interface : string;
  port : int;
  title : string;
  resizable : bool;
  max_events : int;
  max_clients : int;
  max_connections : int;
  max_message_bytes : int;
  max_queued_event_bytes : int;
  max_frame_pool_bytes : int;
  compress_frames : bool;
}

let default_config = {
  interface = "0.0.0.0";
  port = 8080;
  title = "Prismel web sketch";
  resizable = false;
  max_events = 4096;
  max_clients = 8;
  max_connections = 64;
  max_message_bytes = 16 * 1024 * 1024 + 4096;
  max_queued_event_bytes = 32 * 1024 * 1024;
  max_frame_pool_bytes = 256 * 1024 * 1024;
  compress_frames = true;
}

type frame_payload = Raw of pixel_buffer | Qoi of pixel_buffer

type frame_patch = {
  base_id : int;
  x : int;
  y : int;
  width : int;
  height : int;
  payload : frame_payload;
}

type published_frame = {
  id : int;
  drawable_width : int;
  drawable_height : int;
  logical_width : int;
  logical_height : int;
  pixels : pixel_buffer;
  full_payload : frame_payload;
  patch : frame_patch option;
  mutable references : int;
}

type stats = {
  frames_submitted : int;
  frames_published : int;
  frames_suppressed : int;
  source_bytes_submitted : int64;
  payload_bytes_published : int64;
  frames_sent : int;
  payload_bytes_sent : int64;
}

type mutable_stats = {
  mutable frames_submitted : int;
  mutable frames_published : int;
  mutable frames_suppressed : int;
  mutable source_bytes_submitted : int64;
  mutable payload_bytes_published : int64;
  mutable frames_sent : int;
  mutable payload_bytes_sent : int64;
}

type asset_source = Asset_file of string | Asset_bytes of bytes

type asset = {
  content_type : string;
  source : asset_source;
}

type outbound =
  | Outbound_command of int * string
  | Outbound_frame of published_frame * frame_payload * frame_patch option

type t = {
  config : config;
  listener : Unix.file_descr;
  actual_port : int;
  token : string;
  mutex : Mutex.t;
  publish_mutex : Mutex.t;
  frame_ready : Condition.t;
  connection_closed : Condition.t;
  mutable running : bool;
  mutable next_frame_id : int;
  mutable compression_backoff : int;
  mutable compression_source_length : int;
  mutable latest : published_frame option;
  frame_pool : pixel_buffer Queue.t;
  mutable frame_pool_bytes : int;
  events : event Queue.t;
  mutable queued_event_bytes : int;
  commands : string option array;
  mutable next_command_id : int;
  mutable text_input_regions : text_input_region list;
  assets : (string, asset) Hashtbl.t;
  mutable next_asset_id : int;
  stats : mutable_stats;
  mutable clients : client list;
  mutable connections : Unix.file_descr list;
  mutable accept_thread : Thread.t option;
}

and client = {
  server : t;
  descriptor : Unix.file_descr;
  write_mutex : Mutex.t;
  mutable active : bool;
  mutable next_command_id : int;
  mutable in_flight_frame_id : int option;
}

let interface server = server.config.interface
let port server = server.actual_port
let url server = Printf.sprintf "http://%s:%d/" (interface server) (port server)

let with_mutex mutex operation =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) operation

let random_token () =
  let bytes = Bytes.create 24 in
  let channel = open_in_bin "/dev/urandom" in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input channel bytes 0 (Bytes.length bytes));
  let output = Bytes.create (Bytes.length bytes * 2) in
  let digits = "0123456789abcdef" in
  Bytes.iteri (fun index value ->
    let value = Char.code value in
    Bytes.unsafe_set output (index * 2) digits.[value lsr 4];
    Bytes.unsafe_set output (index * 2 + 1) digits.[value land 0xf]) bytes;
  Bytes.unsafe_to_string output

let get_i32_le bytes offset =
  if offset < 0 || offset + 4 > Bytes.length bytes then
    invalid_arg "Wap event integer is truncated";
  let byte index = Int32.of_int (Char.code (Bytes.unsafe_get bytes index)) in
  Int32.logor (byte offset)
    (Int32.logor (Int32.shift_left (byte (offset + 1)) 8)
       (Int32.logor (Int32.shift_left (byte (offset + 2)) 16)
          (Int32.shift_left (byte (offset + 3)) 24)))
  |> Int32.to_int

let trailing_text bytes offset =
  if offset > Bytes.length bytes then invalid_arg "Wap event text is truncated";
  Bytes.sub_string bytes offset (Bytes.length bytes - offset)

let button_of_int = function
  | 1 -> Some Left
  | 2 -> Some Middle
  | 3 -> Some Right
  | 4 -> Some X1
  | 5 -> Some X2
  | _ -> None

let decode_event payload =
  try
    if Bytes.length payload < 2 || Char.code (Bytes.unsafe_get payload 0) <> 1
    then None
    else
      match Char.code (Bytes.unsafe_get payload 1) with
      | 1 when Bytes.length payload = 10 ->
          Some (Pointer_moved (get_i32_le payload 2, get_i32_le payload 6))
      | (2 | 3 as opcode) when Bytes.length payload = 14 ->
          Option.map
            (fun button ->
              let x = get_i32_le payload 6 and y = get_i32_le payload 10 in
              if opcode = 2 then Pointer_pressed (button, x, y)
              else Pointer_released (button, x, y))
            (button_of_int (get_i32_le payload 2))
      | 4 when Bytes.length payload = 10 ->
          Some (Wheel (get_i32_le payload 2, get_i32_le payload 6))
      | 5 -> Some (Key_pressed (trailing_text payload 2))
      | 6 -> Some (Key_released (trailing_text payload 2))
      | 7 -> Some (Text_input (trailing_text payload 2))
      | 8 when Bytes.length payload >= 10 ->
          Some (Text_editing {
            start = get_i32_le payload 2;
            length = get_i32_le payload 6;
            text = trailing_text payload 10;
          })
      | 9 when Bytes.length payload = 10 ->
          Some (Resized (get_i32_le payload 2, get_i32_le payload 6))
      | 10 when Bytes.length payload = 2 -> Some Focus_lost
      | 11 when Bytes.length payload >= 4 ->
          let name_length =
            Char.code (Bytes.unsafe_get payload 2)
            lor (Char.code (Bytes.unsafe_get payload 3) lsl 8) in
          if name_length = 0 || name_length > 1024
             || 4 + name_length > Bytes.length payload
          then None
          else
            Some (File_uploaded {
              name = Bytes.sub_string payload 4 name_length;
              contents =
                Bytes.sub payload (4 + name_length)
                  (Bytes.length payload - 4 - name_length);
            })
      | 12 when Bytes.length payload = 6 ->
          Option.map (fun button -> Pointer_cancelled button)
            (button_of_int (get_i32_le payload 2))
      | _ -> None
  with Invalid_argument _ -> None

let decode_events payload =
  if Bytes.length payload >= 10
     && Char.code (Bytes.unsafe_get payload 0) = 1
     && Char.code (Bytes.unsafe_get payload 1) = 1
     && (Bytes.length payload - 2) mod 8 = 0
  then
    List.init ((Bytes.length payload - 2) / 8) (fun index ->
      let offset = 2 + (index * 8) in
      Pointer_moved (get_i32_le payload offset, get_i32_le payload (offset + 4)))
  else Option.to_list (decode_event payload)

let release_frame_locked server frame =
  frame.references <- frame.references - 1;
  let length = Bigarray.Array1.dim frame.pixels in
  if frame.references = 0 && Queue.length server.frame_pool < 16
     && length <= server.config.max_frame_pool_bytes - server.frame_pool_bytes
  then begin
    Queue.add frame.pixels server.frame_pool;
    server.frame_pool_bytes <- server.frame_pool_bytes + length
  end

let recycle_frame_buffer_locked server pixels =
  let length = Bigarray.Array1.dim pixels in
  if Queue.length server.frame_pool < 16
     && length <= server.config.max_frame_pool_bytes - server.frame_pool_bytes
  then begin
    Queue.add pixels server.frame_pool;
    server.frame_pool_bytes <- server.frame_pool_bytes + length
  end

let acquire_frame server ~length =
  if length < 0 then invalid_arg "Wap.acquire_frame: negative length";
  with_mutex server.mutex (fun () ->
    let selected = ref None and retained = Queue.create () in
    while not (Queue.is_empty server.frame_pool) do
      let candidate = Queue.take server.frame_pool in
      let candidate_length = Bigarray.Array1.dim candidate in
      server.frame_pool_bytes <- server.frame_pool_bytes - candidate_length;
      if Option.is_none !selected && Bigarray.Array1.dim candidate = length then
        selected := Some candidate
      else begin
        Queue.add candidate retained;
        server.frame_pool_bytes <- server.frame_pool_bytes + candidate_length
      end
    done;
    Queue.transfer retained server.frame_pool;
    match !selected with
    | Some buffer -> buffer
    | None -> Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout length)

let discard_frame server pixels =
  with_mutex server.mutex (fun () -> recycle_frame_buffer_locked server pixels)

let payload_buffer = function Raw pixels | Qoi pixels -> pixels
let payload_length payload = Bigarray.Array1.dim (payload_buffer payload)
let payload_codec = function Raw _ -> 0 | Qoi _ -> 1

let compression_enabled server source_length =
  with_mutex server.mutex (fun () ->
    if not server.config.compress_frames then false
    else if server.compression_source_length <> source_length then begin
      server.compression_source_length <- source_length;
      server.compression_backoff <- 0;
      true
    end
    else if server.compression_backoff > 0 then begin
      server.compression_backoff <- server.compression_backoff - 1;
      false
    end else true)

let record_compression_result server source_length attempted encoded =
  if attempted then
    with_mutex server.mutex (fun () ->
      server.compression_backoff <-
        if source_length >= 4096 && Option.is_none encoded then 29 else 0)

let publish_frame server ~drawable_width ~drawable_height
    ~logical_width ~logical_height pixels =
  if drawable_width <= 0 || drawable_height <= 0
     || logical_width <= 0 || logical_height <= 0
  then invalid_arg "Wap.publish_frame: dimensions must be positive";
  if Bigarray.Array1.dim pixels <> drawable_width * drawable_height * 4 then
    invalid_arg "Wap.publish_frame: RGBA buffer length does not match dimensions";
  let source_length = Bigarray.Array1.dim pixels in
  with_mutex server.publish_mutex (fun () ->
    let previous =
      with_mutex server.mutex (fun () ->
        server.stats.frames_submitted <- server.stats.frames_submitted + 1;
        server.stats.source_bytes_submitted <-
          Int64.add server.stats.source_bytes_submitted
            (Int64.of_int source_length);
        match server.latest with
        | Some previous
          when previous.drawable_width = drawable_width
               && previous.drawable_height = drawable_height
               && previous.logical_width = logical_width
               && previous.logical_height = logical_height ->
            previous.references <- previous.references + 1;
            Some previous
        | _ -> None)
    in
    let difference =
      Option.map (fun previous ->
        Frame_codec.diff_rectangle previous.pixels pixels drawable_width)
        previous
    in
    match difference with
    | Some None ->
        with_mutex server.mutex (fun () ->
          server.stats.frames_suppressed <- server.stats.frames_suppressed + 1;
          recycle_frame_buffer_locked server pixels;
          Option.iter (release_frame_locked server) previous)
    | None | Some (Some _) ->
        let should_compress = compression_enabled server source_length in
        let encoded =
          if should_compress then Frame_codec.encode_qoi pixels else None
        in
        record_compression_result server source_length should_compress encoded;
        let full_payload =
          Option.fold ~none:(Raw pixels) ~some:(fun value -> Qoi value) encoded
        in
        let patch =
          match previous, difference with
          | Some previous, Some (Some (x, y, width, height, patch_pixels)) ->
              if width = drawable_width && height = drawable_height then None
              else
                let patch_payload =
                  match Frame_codec.encode_qoi patch_pixels with
                  | Some value -> Qoi value
                  | None -> Raw patch_pixels
                in
                if payload_length patch_payload + 16 < payload_length full_payload
                then Some {
                  base_id = previous.id; x; y; width; height;
                  payload = patch_payload;
                }
                else None
          | _ -> None
        in
        with_mutex server.mutex (fun () ->
          Option.iter (release_frame_locked server) previous;
          Option.iter (release_frame_locked server) server.latest;
          let id = server.next_frame_id in
          let frame = {
            id; drawable_width; drawable_height; logical_width; logical_height;
            pixels; full_payload; patch; references = 1;
          } in
          server.next_frame_id <- if id = max_int then 0 else id + 1;
          server.latest <- Some frame;
          server.stats.frames_published <- server.stats.frames_published + 1;
          let predicted_payload =
            Option.fold ~none:full_payload ~some:(fun patch -> patch.payload) patch
          in
          server.stats.payload_bytes_published <-
            Int64.add server.stats.payload_bytes_published
              (Int64.of_int (payload_length predicted_payload));
          Condition.broadcast server.frame_ready))

let client_count server =
  with_mutex server.mutex (fun () -> List.length server.clients)

let stats server : stats =
  with_mutex server.mutex (fun () ->
    ({
      frames_submitted = server.stats.frames_submitted;
      frames_published = server.stats.frames_published;
      frames_suppressed = server.stats.frames_suppressed;
      source_bytes_submitted = server.stats.source_bytes_submitted;
      payload_bytes_published = server.stats.payload_bytes_published;
      frames_sent = server.stats.frames_sent;
      payload_bytes_sent = server.stats.payload_bytes_sent;
    } : stats))

let enqueue_command_locked server message =
  let id = server.next_command_id in
  server.commands.(id mod Array.length server.commands) <- Some message;
  server.next_command_id <- if id = max_int then 0 else id + 1;
  Condition.broadcast server.frame_ready

let broadcast_text server message =
  if String.length message > 16_384 then
    invalid_arg "Wap.broadcast_text: command exceeds 16 KiB";
  with_mutex server.mutex (fun () -> enqueue_command_locked server message)

let text_input_regions_command regions =
  let buffer = Buffer.create (48 + (List.length regions * 32)) in
  Buffer.add_string buffer {|{"op":"text_input_regions","regions":[|};
  List.iteri (fun index (region : text_input_region) ->
    if index > 0 then Buffer.add_char buffer ',';
    Printf.bprintf buffer "[%d,%d,%d,%d,%d]"
      region.x region.y region.width region.height
      (if region.focused then 1 else 0)) regions;
  Buffer.add_string buffer "]}";
  Buffer.contents buffer

let set_text_input_regions server regions =
  if List.exists
       (fun (region : text_input_region) ->
         region.width <= 0 || region.height <= 0)
       regions
  then invalid_arg "Wap.set_text_input_regions: dimensions must be positive";
  let command = text_input_regions_command regions in
  if String.length command > 16_384 then
    invalid_arg "Wap.set_text_input_regions: regions exceed 16 KiB";
  with_mutex server.mutex (fun () ->
    if regions <> server.text_input_regions then begin
      server.text_input_regions <- regions;
      enqueue_command_locked server command
    end)

let json_string value =
  let output = Buffer.create (String.length value + 2) in
  Buffer.add_char output '"';
  String.iter (fun character ->
    match character with
    | '"' -> Buffer.add_string output "\\\""
    | '\\' -> Buffer.add_string output "\\\\"
    | '\b' -> Buffer.add_string output "\\b"
    | '\012' -> Buffer.add_string output "\\f"
    | '\n' -> Buffer.add_string output "\\n"
    | '\r' -> Buffer.add_string output "\\r"
    | '\t' -> Buffer.add_string output "\\t"
    | character when Char.code character < 0x20 ->
        Printf.bprintf output "\\u%04x" (Char.code character)
    | character -> Buffer.add_char output character) value;
  Buffer.add_char output '"';
  Buffer.contents output

let portable_download_filename filename =
  let basename =
    String.map (function '\\' -> '/' | character -> character) filename
    |> Filename.basename
  in
  let basename =
    String.map (function
      | ('a'..'z' | 'A'..'Z' | '0'..'9' | ' ' | '.' | '_' | '-') as character ->
          character
      | _ -> '_') basename
  in
  let basename =
    if basename = "" || basename = "." || basename = ".."
    then "prismel.png"
    else basename
  in
  let has_png_extension =
    String.lowercase_ascii (Filename.extension basename) = ".png"
  in
  let stem =
    if has_png_extension then Filename.remove_extension basename else basename
  in
  let stem =
    if String.length stem > 236 then String.sub stem 0 236 else stem
  in
  (if stem = "" then "prismel" else stem) ^ ".png"

let download_frame server ~filename =
  if client_count server = 0 then Error "No browser is connected"
  else
    let filename = portable_download_filename filename in
    let command =
      Printf.sprintf {|{"op":"download_frame","filename":%s}|}
        (json_string filename)
    in
    broadcast_text server command;
    Ok ()

let audio_command_text = function
  | Audio_master_volume volume ->
      Printf.sprintf {|{"op":"master_volume","volume":%.17g}|} volume
  | Audio_stop_all -> {|{"op":"stop_all"}|}
  | Audio_sample_play { asset; channel; loops; volume } ->
      Printf.sprintf
        {|{"op":"sample_play","id":%s,"channel":%d,"loops":%d,"volume":%.17g}|}
        (json_string asset) channel loops volume
  | Audio_sample_volume { asset; volume } ->
      Printf.sprintf {|{"op":"sample_volume","id":%s,"volume":%.17g}|}
        (json_string asset) volume
  | Audio_sample_stop channel ->
      Printf.sprintf {|{"op":"sample_stop","channel":%d}|} channel
  | Audio_sample_pause channel ->
      Printf.sprintf {|{"op":"sample_pause","channel":%d}|} channel
  | Audio_sample_resume channel ->
      Printf.sprintf {|{"op":"sample_resume","channel":%d}|} channel
  | Audio_music_play { asset; loops; fade_ms } ->
      Printf.sprintf {|{"op":"music_play","id":%s,"loops":%d,"fade":%d}|}
        (json_string asset) loops fade_ms
  | Audio_music_volume volume ->
      Printf.sprintf {|{"op":"music_volume","volume":%.17g}|} volume
  | Audio_music_pause -> {|{"op":"music_pause"}|}
  | Audio_music_resume -> {|{"op":"music_resume"}|}
  | Audio_music_stop fade_ms ->
      Printf.sprintf {|{"op":"music_stop","fade":%d}|} fade_ms
  | Audio_asset_remove asset ->
      Printf.sprintf {|{"op":"asset_remove","id":%s}|} (json_string asset)

let broadcast_audio server command =
  broadcast_text server (audio_command_text command)

let default_content_type path =
  match String.lowercase_ascii (Filename.extension path) with
  | ".wav" -> "audio/wav"
  | ".mp3" -> "audio/mpeg"
  | ".ogg" | ".oga" -> "audio/ogg"
  | ".flac" -> "audio/flac"
  | ".png" -> "image/png"
  | ".jpg" | ".jpeg" -> "image/jpeg"
  | _ -> "application/octet-stream"

let register_asset server content_type source =
  with_mutex server.mutex (fun () ->
    if not server.running then None
    else
      let id = Printf.sprintf "%x" server.next_asset_id in
      server.next_asset_id <-
        if server.next_asset_id = max_int then 0 else server.next_asset_id + 1;
      Hashtbl.replace server.assets id { content_type; source };
      Some id)

let register_file server ?content_type path =
  let readable_regular_file =
    try
      if (Unix.stat path).Unix.st_kind <> Unix.S_REG then false
      else begin
        Unix.access path [Unix.R_OK];
        true
      end
    with Unix.Unix_error _ -> false
  in
  if readable_regular_file then
    register_asset server
      (Option.value content_type ~default:(default_content_type path))
      (Asset_file path)
  else None

let register_bytes server ?(content_type = "application/octet-stream") bytes =
  register_asset server content_type (Asset_bytes (Bytes.copy bytes))

let remove_asset server id =
  with_mutex server.mutex (fun () -> Hashtbl.remove server.assets id)

let drain_events server =
  with_mutex server.mutex (fun () ->
    let rec drain values =
      if Queue.is_empty server.events then List.rev values
      else drain (Queue.take server.events :: values)
    in
    let events = drain [] in
    server.queued_event_bytes <- 0;
    events)

let event_bytes = function
  | Key_pressed key | Key_released key | Text_input key ->
      64 + String.length key
  | Text_editing { text; _ } -> 64 + String.length text
  | File_uploaded { name; contents } ->
      64 + String.length name + Bytes.length contents
  | _ -> 64

let enqueue_event server event =
  with_mutex server.mutex (fun () ->
    let bytes = event_bytes event in
    let rec make_room () =
      if not (Queue.is_empty server.events)
         && (Queue.length server.events >= server.config.max_events
             || server.queued_event_bytes + bytes
                > server.config.max_queued_event_bytes)
      then begin
        let removed = Queue.take server.events in
        server.queued_event_bytes <-
          server.queued_event_bytes - event_bytes removed;
        make_room ()
      end
    in
    make_room ();
    if bytes <= server.config.max_queued_event_bytes then begin
      Queue.add event server.events;
      server.queued_event_bytes <- server.queued_event_bytes + bytes
    end)

let set_u16_le bytes offset value =
  Bytes.unsafe_set bytes offset (Char.chr (value land 0xff));
  Bytes.unsafe_set bytes (offset + 1) (Char.chr ((value lsr 8) land 0xff))

let set_u32_le bytes offset value =
  let value = Int64.of_int value in
  for index = 0 to 3 do
    Bytes.unsafe_set bytes (offset + index)
      (Char.chr
         (Int64.to_int (Int64.shift_right_logical value (index * 8)) land 0xff))
  done

let frame_metadata frame payload patch =
  let output = Bytes.make (if Option.is_some patch then 44 else 28) '\000' in
  Bytes.blit_string "PRSM" 0 output 0 4;
  set_u16_le output 4 1;
  set_u16_le output 6
    (payload_codec payload + if Option.is_some patch then 2 else 0);
  set_u32_le output 8 frame.id;
  set_u32_le output 12 frame.drawable_width;
  set_u32_le output 16 frame.drawable_height;
  set_u32_le output 20 frame.logical_width;
  set_u32_le output 24 frame.logical_height;
  Option.iter (fun patch ->
    set_u32_le output 28 patch.x;
    set_u32_le output 32 patch.y;
    set_u32_le output 36 patch.width;
    set_u32_le output 40 patch.height) patch;
  output

let deactivate client =
  let should_close =
    with_mutex client.server.mutex (fun () ->
      if not client.active then false
      else begin
        client.active <- false;
        client.server.clients <-
          List.filter (fun candidate -> candidate != client) client.server.clients;
        Condition.broadcast client.server.frame_ready;
        true
      end)
  in
  if should_close then begin
    try Unix.shutdown client.descriptor Unix.SHUTDOWN_ALL
    with Unix.Unix_error _ -> ()
  end

let next_outbound client last_id =
  let server = client.server in
  Mutex.lock server.mutex;
  let rec wait () =
    if not server.running || not client.active then None
    else if client.next_command_id <> server.next_command_id then begin
      let capacity = Array.length server.commands in
      let oldest = max 0 (server.next_command_id - capacity) in
      if client.next_command_id < oldest then client.next_command_id <- oldest;
      let id = client.next_command_id in
      match server.commands.(id mod capacity) with
      | Some command -> Some (Outbound_command (id, command))
      | None ->
          client.next_command_id <- id + 1;
          wait ()
    end else
      match server.latest with
      | Some frame
        when frame.id <> last_id && Option.is_none client.in_flight_frame_id ->
          let patch = Option.bind frame.patch (fun patch ->
            if patch.base_id = last_id then Some patch else None) in
          let payload = Option.fold ~none:frame.full_payload
              ~some:(fun patch -> patch.payload) patch in
          frame.references <- frame.references + 1;
          client.in_flight_frame_id <- Some frame.id;
          Some (Outbound_frame (frame, payload, patch))
      | _ ->
          Condition.wait server.frame_ready server.mutex;
          wait ()
  in
  let result = wait () in
  Mutex.unlock server.mutex;
  result

let release_frame server frame =
  with_mutex server.mutex (fun () -> release_frame_locked server frame)

let write_frame client frame payload patch =
  with_mutex client.write_mutex (fun () ->
    Websocket.write_bytes client.descriptor ~fin:false ~opcode:Websocket.Binary
      (frame_metadata frame payload patch);
    Websocket.write_bigarray client.descriptor ~fin:true
      ~opcode:Websocket.Continuation (payload_buffer payload))

let writer_loop client =
  let last_id = ref (-1) in
  try
    let rec loop () =
      match next_outbound client !last_id with
      | None -> ()
      | Some (Outbound_command (id, command)) ->
          with_mutex client.write_mutex (fun () ->
            Websocket.write_bytes client.descriptor ~fin:true
              ~opcode:Websocket.Text (Bytes.of_string command));
          client.next_command_id <- id + 1;
          loop ()
      | Some (Outbound_frame (frame, payload, patch)) ->
          Fun.protect
            ~finally:(fun () -> release_frame client.server frame)
            (fun () -> write_frame client frame payload patch);
          with_mutex client.server.mutex (fun () ->
            client.server.stats.frames_sent <-
              client.server.stats.frames_sent + 1;
            client.server.stats.payload_bytes_sent <-
              Int64.add client.server.stats.payload_bytes_sent
                (Int64.of_int (payload_length payload)));
          last_id := frame.id;
          loop ()
    in
    loop ()
  with End_of_file | Unix.Unix_error _ -> deactivate client

let frame_ack payload =
  if Bytes.length payload = 6
     && Char.code (Bytes.unsafe_get payload 0) = 1
     && Char.code (Bytes.unsafe_get payload 1) = 13
  then Some (get_i32_le payload 2)
  else None

let handle_payload client payload =
  match frame_ack payload with
  | Some frame_id ->
      with_mutex client.server.mutex (fun () ->
        if client.in_flight_frame_id = Some frame_id then begin
          client.in_flight_frame_id <- None;
          Condition.broadcast client.server.frame_ready
        end)
  | None ->
      List.iter (enqueue_event client.server) (decode_events payload)

let reader_loop client =
  let fragment = Buffer.create 256 and fragmented_opcode = ref None in
  let rec loop () =
    let frame = Websocket.read_frame
        ~max_payload:client.server.config.max_message_bytes client.descriptor in
    match frame.opcode with
    | Websocket.Close ->
        with_mutex client.write_mutex (fun () ->
          Websocket.write_bytes client.descriptor ~fin:true ~opcode:Websocket.Close
            frame.payload)
    | Ping ->
        with_mutex client.write_mutex (fun () ->
          Websocket.write_bytes client.descriptor ~fin:true ~opcode:Websocket.Pong
            frame.payload);
        loop ()
    | Pong -> loop ()
    | Text ->
        if not frame.fin then invalid_arg "Fragmented text input is unsupported";
        loop ()
    | Binary ->
        if frame.fin then handle_payload client frame.payload
        else begin
          Buffer.clear fragment;
          Buffer.add_bytes fragment frame.payload;
          fragmented_opcode := Some Websocket.Binary
        end;
        loop ()
    | Continuation ->
        if Option.is_none !fragmented_opcode then
          invalid_arg "Unexpected WebSocket continuation frame";
        if Buffer.length fragment + Bytes.length frame.payload
           > client.server.config.max_message_bytes
        then
          invalid_arg "Fragmented WebSocket message is too large";
        Buffer.add_bytes fragment frame.payload;
        if frame.fin then begin
          handle_payload client
            (Buffer.to_bytes fragment);
          fragmented_opcode := None;
          Buffer.clear fragment
        end;
        loop ()
  in
  loop ()

let lowercase = String.lowercase_ascii

let read_http_request descriptor =
  let buffer = Buffer.create 1024 and chunk = Bytes.create 1024 in
  let contains_end value =
    let rec search index =
      if index + 4 > String.length value then false
      else if String.sub value index 4 = "\r\n\r\n" then true
      else search (index + 1)
    in
    search 0
  in
  let rec receive () =
    if Buffer.length buffer > 16_384 then invalid_arg "HTTP header is too large";
    let received = Unix.read descriptor chunk 0 (Bytes.length chunk) in
    if received = 0 then raise End_of_file;
    Buffer.add_subbytes buffer chunk 0 received;
    let contents = Buffer.contents buffer in
    if contains_end contents then contents
    else receive ()
  in
  let contents = receive () in
  let lines = String.split_on_char '\n' contents
    |> List.map (fun line -> String.trim line) in
  match lines with
  | request_line :: headers ->
      let request = String.split_on_char ' ' request_line in
      let method_, target = match request with
        | method_ :: target :: _ -> method_, target
        | _ -> invalid_arg "Malformed HTTP request line" in
      let headers =
        List.filter_map (fun line ->
          match String.index_opt line ':' with
          | None -> None
          | Some index ->
              Some
                (lowercase (String.trim (String.sub line 0 index)),
                 String.trim
                   (String.sub line (index + 1) (String.length line - index - 1))))
          headers
      in
      method_, target, headers
  | [] -> invalid_arg "Empty HTTP request"

let header name headers =
  List.find_map (fun (candidate, value) ->
    if candidate = lowercase name then Some value else None) headers

let write_response descriptor ~status ~content_type body =
  let response = Printf.sprintf
      "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; connect-src 'self' ws: wss:; script-src 'self'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n%s"
      status content_type (String.length body) body
  in
  let bytes = Bytes.unsafe_of_string response in
  Websocket.write_all descriptor bytes 0 (Bytes.length bytes)

let write_binary_header descriptor ~status ~content_type ~length
    ?content_range () =
  let content_range = Option.fold ~none:""
      ~some:(fun value -> "Content-Range: " ^ value ^ "\r\n") content_range in
  let response = Printf.sprintf
      "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccept-Ranges: bytes\r\n%sCache-Control: private, max-age=31536000, immutable\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
      status content_type length content_range
  in
  let bytes = Bytes.unsafe_of_string response in
  Websocket.write_all descriptor bytes 0 (Bytes.length bytes)

let parse_byte_range value length =
  let prefix = "bytes=" in
  if length <= 0 || not (String.starts_with ~prefix value)
     || String.contains value ','
  then None
  else
    let specification =
      String.sub value (String.length prefix)
        (String.length value - String.length prefix)
      |> String.trim
    in
    match String.split_on_char '-' specification with
    | [""; suffix] ->
        Option.bind (int_of_string_opt suffix) (fun suffix ->
          if suffix <= 0 then None
          else
            let count = min suffix length in
            Some (length - count, count))
    | [first; last] ->
        Option.bind (int_of_string_opt first) (fun first ->
          if first < 0 || first >= length then None
          else if last = "" then Some (first, length - first)
          else Option.bind (int_of_string_opt last) (fun last ->
            if last < first then None
            else
              let last = min last (length - 1) in
              Some (first, last - first + 1)))
    | _ -> None

let selected_range requested length =
  match requested with
  | None -> Ok (0, length, "200 OK", None)
  | Some value ->
      (match parse_byte_range value length with
       | None -> Error (Printf.sprintf "bytes */%d" length)
       | Some (offset, count) ->
           Ok (offset, count, "206 Partial Content",
             Some (Printf.sprintf "bytes %d-%d/%d"
               offset (offset + count - 1) length)))

let write_range_not_satisfiable descriptor content_type content_range =
  write_binary_header descriptor ~status:"416 Range Not Satisfiable"
    ~content_type ~length:0 ~content_range ()

let write_asset descriptor requested_range asset =
  match asset.source with
  | Asset_bytes contents ->
      (match selected_range requested_range (Bytes.length contents) with
       | Error content_range ->
           write_range_not_satisfiable descriptor asset.content_type content_range
       | Ok (offset, length, status, content_range) ->
           write_binary_header descriptor ~status
             ~content_type:asset.content_type ~length ?content_range ();
           Websocket.write_all descriptor contents offset length)
  | Asset_file path ->
      let channel = open_in_bin path in
      Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
        let full_length = in_channel_length channel in
        match selected_range requested_range full_length with
        | Error content_range ->
            write_range_not_satisfiable descriptor asset.content_type content_range
        | Ok (offset, length, status, content_range) ->
            seek_in channel offset;
            write_binary_header descriptor ~status
              ~content_type:asset.content_type ~length ?content_range ();
            let chunk = Bytes.create 65_536 in
            let rec copy remaining =
              if remaining > 0 then begin
                let count = input channel chunk 0
                    (min remaining (Bytes.length chunk)) in
                if count = 0 then raise End_of_file;
                Websocket.write_all descriptor chunk 0 count;
                copy (remaining - count)
              end
            in
            copy length)

let target_path target =
  match String.index_opt target '?' with
  | None -> target
  | Some index -> String.sub target 0 index

let target_token target =
  match String.index_opt target '?' with
  | None -> None
  | Some index ->
      String.sub target (index + 1) (String.length target - index - 1)
      |> String.split_on_char '&'
      |> List.find_map (fun part ->
        match String.split_on_char '=' part with
        | ["token"; value] -> Some value
        | _ -> None)

let asset_id target =
  let path = target_path target and prefix = "/asset/" in
  if String.starts_with ~prefix path && String.length path > String.length prefix
  then Some (String.sub path (String.length prefix)
      (String.length path - String.length prefix))
  else None

let websocket_handshake server descriptor target headers =
  if target_path target <> "/ws" || target_token target <> Some server.token then
    false
  else
    match header "upgrade" headers, header "sec-websocket-version" headers,
          header "sec-websocket-key" headers with
    | Some upgrade, Some "13", Some key when lowercase upgrade = "websocket" ->
        let response = Printf.sprintf
          "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n"
          (Websocket.accept_key key)
        in
        let bytes = Bytes.unsafe_of_string response in
        Websocket.write_all descriptor bytes 0 (Bytes.length bytes);
        true
    | _ -> false

let serve_websocket server descriptor =
  let client = {
    server; descriptor; write_mutex = Mutex.create (); active = true;
    next_command_id = 0; in_flight_frame_id = None;
  } in
  let accepted = with_mutex server.mutex (fun () ->
    if List.length server.clients >= server.config.max_clients then false
    else begin
      client.next_command_id <-
        max 0 (server.next_command_id - Array.length server.commands);
      server.clients <- client :: server.clients;
      true
    end) in
  if not accepted then begin
    try Unix.shutdown descriptor Unix.SHUTDOWN_ALL
    with Unix.Unix_error _ -> ()
  end else begin
    let writer = Thread.create writer_loop client in
    (try reader_loop client
     with End_of_file | Invalid_argument _ | Unix.Unix_error _ -> ());
    deactivate client;
    Thread.join writer
  end

let handle_connection server descriptor =
  Fun.protect
    ~finally:(fun () ->
      (try Unix.close descriptor with Unix.Unix_error _ -> ());
      with_mutex server.mutex (fun () ->
        server.connections <-
          List.filter (( <> ) descriptor) server.connections;
        Condition.broadcast server.connection_closed))
    (fun () ->
      Unix.setsockopt_float descriptor Unix.SO_SNDTIMEO 5.;
      Unix.setsockopt_float descriptor Unix.SO_RCVTIMEO 30.;
      Unix.setsockopt descriptor Unix.TCP_NODELAY true;
      try
        let method_, target, headers = read_http_request descriptor in
        if method_ <> "GET" then
          write_response descriptor ~status:"405 Method Not Allowed"
            ~content_type:"text/plain; charset=utf-8" "method not allowed\n"
        else if target_path target = "/ws" then begin
          if websocket_handshake server descriptor target headers then
            serve_websocket server descriptor
          else
            write_response descriptor ~status:"400 Bad Request"
              ~content_type:"text/plain; charset=utf-8"
              "invalid websocket request\n"
        end else if Option.is_some (asset_id target) then begin
          let asset =
            if target_token target <> Some server.token then None
            else with_mutex server.mutex (fun () ->
              Option.bind (asset_id target) (Hashtbl.find_opt server.assets))
          in
          (match asset with
           | Some asset -> write_asset descriptor (header "range" headers) asset
           | None ->
               write_response descriptor ~status:"404 Not Found"
                 ~content_type:"text/plain; charset=utf-8" "not found\n")
        end else begin
          let status, content_type, body =
            match target_path target with
            | "/" | "/index.html" ->
                "200 OK", "text/html; charset=utf-8",
                Client_html.page ~title:server.config.title ~token:server.token
                  ~resizable:server.config.resizable
            | "/client.js" ->
                "200 OK", "text/javascript; charset=utf-8", Client_html.script
            | _ -> "404 Not Found", "text/plain; charset=utf-8", "not found\n"
          in
          write_response descriptor ~status ~content_type body
        end
      with End_of_file | Invalid_argument _ | Unix.Unix_error _ -> ())

let accept_loop server =
  try
    while with_mutex server.mutex (fun () -> server.running) do
      let descriptor, _ = Unix.accept server.listener in
      let accepted = with_mutex server.mutex (fun () ->
        if not server.running
           || List.length server.connections >= server.config.max_connections
        then false
        else begin
          server.connections <- descriptor :: server.connections;
          true
        end) in
      if accepted then ignore (Thread.create (handle_connection server) descriptor)
      else Unix.close descriptor
    done
  with Unix.Unix_error _ -> ()

let start ?(config = default_config) () =
  if config.port < 0 || config.port > 65_535 then
    Error "Wap.start: port must be in 0..65535"
  else if config.max_events <= 0 || config.max_clients <= 0
          || config.max_connections <= 0
          || config.max_clients > config.max_connections
          || config.max_message_bytes <= 0 || config.max_queued_event_bytes <= 0
          || config.max_frame_pool_bytes <= 0
  then Error "Wap.start: queue and connection limits must be positive and consistent"
  else
    let listener = ref None in
    try
      let descriptor = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      listener := Some descriptor;
      Unix.setsockopt descriptor Unix.SO_REUSEADDR true;
      let address = Unix.inet_addr_of_string config.interface in
      Unix.bind descriptor (Unix.ADDR_INET (address, config.port));
      Unix.listen descriptor 16;
      let actual_port = match Unix.getsockname descriptor with
        | Unix.ADDR_INET (_, value) -> value
        | Unix.ADDR_UNIX _ -> assert false in
      let server = {
        config; listener = descriptor; actual_port; token = random_token ();
        mutex = Mutex.create (); publish_mutex = Mutex.create ();
        frame_ready = Condition.create ();
        connection_closed = Condition.create ();
        running = true; next_frame_id = 0; compression_backoff = 0;
        compression_source_length = 0;
        latest = None;
        frame_pool = Queue.create (); frame_pool_bytes = 0;
        events = Queue.create ();
        queued_event_bytes = 0; clients = [];
        commands = Array.make 256 None; next_command_id = 0;
        text_input_regions = [];
        assets = Hashtbl.create 32; next_asset_id = 0;
        stats = {
          frames_submitted = 0; frames_published = 0; frames_suppressed = 0;
          source_bytes_submitted = 0L; payload_bytes_published = 0L;
          frames_sent = 0; payload_bytes_sent = 0L;
        };
        connections = []; accept_thread = None;
      } in
      let thread = Thread.create accept_loop server in
      server.accept_thread <- Some thread;
      Ok server
    with
    | Unix.Unix_error (error, operation, _) ->
        Option.iter (fun descriptor ->
          try Unix.close descriptor with Unix.Unix_error _ -> ()) !listener;
        Error (Printf.sprintf "Wap.start: %s: %s" operation
          (Unix.error_message error))
    | (Failure message | Sys_error message) ->
        Option.iter (fun descriptor ->
          try Unix.close descriptor with Unix.Unix_error _ -> ()) !listener;
        Error ("Wap.start: " ^ message)
    | End_of_file ->
        Option.iter (fun descriptor ->
          try Unix.close descriptor with Unix.Unix_error _ -> ()) !listener;
        Error "Wap.start: system entropy source ended unexpectedly"

let stop server =
  let clients, connections, accept_thread, should_stop =
    with_mutex server.mutex (fun () ->
      if not server.running then [], [], None, false
      else begin
        server.running <- false;
        Condition.broadcast server.frame_ready;
        server.clients, server.connections, server.accept_thread, true
      end)
  in
  if should_stop then begin
    (try Unix.shutdown server.listener Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ());
    (try Unix.close server.listener with Unix.Unix_error _ -> ());
    List.iter deactivate clients;
    List.iter (fun descriptor ->
      try Unix.shutdown descriptor Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ())
      connections;
    Option.iter Thread.join accept_thread;
    Mutex.lock server.mutex;
    while server.connections <> [] do
      Condition.wait server.connection_closed server.mutex
    done;
    Mutex.unlock server.mutex;
    with_mutex server.mutex (fun () ->
      Option.iter (release_frame_locked server) server.latest;
      server.latest <- None;
      Queue.clear server.events;
      server.queued_event_bytes <- 0;
      Queue.clear server.frame_pool;
      server.frame_pool_bytes <- 0;
      Array.fill server.commands 0 (Array.length server.commands) None;
      server.text_input_regions <- [];
      Hashtbl.clear server.assets;
      server.accept_thread <- None)
  end

module Private = struct
  let websocket_accept = Websocket.accept_key
  let decode_event = decode_event
  let decode_events = decode_events
end
