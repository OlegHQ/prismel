open Sdl3_mixer

let fail message = failwith ("SDL3_mixer test: " ^ message)

let get = function
  | Ok value -> value
  | Error error -> fail (Format.asprintf "%a" pp_error error)

let set_u16 bytes offset value =
  Bytes.set_uint8 bytes offset (value land 0xff);
  Bytes.set_uint8 bytes (offset + 1) ((value lsr 8) land 0xff)

let set_u32 bytes offset value =
  set_u16 bytes offset (value land 0xffff);
  set_u16 bytes (offset + 2) ((value lsr 16) land 0xffff)

let tiny_wav () =
  let samples = 80 in
  let data_bytes = samples * 2 in
  let bytes = Bytes.make (44 + data_bytes) '\x00' in
  Bytes.blit_string "RIFF" 0 bytes 0 4;
  set_u32 bytes 4 (36 + data_bytes);
  Bytes.blit_string "WAVEfmt " 0 bytes 8 8;
  set_u32 bytes 16 16;
  set_u16 bytes 20 1;
  set_u16 bytes 22 1;
  set_u32 bytes 24 8_000;
  set_u32 bytes 28 16_000;
  set_u16 bytes 32 2;
  set_u16 bytes 34 16;
  Bytes.blit_string "data" 0 bytes 36 4;
  set_u32 bytes 40 data_bytes;
  for sample = 0 to samples - 1 do
    let value = if sample mod 16 < 8 then 8_000 else -8_000 in
    set_u16 bytes (44 + (sample * 2)) (value land 0xffff)
  done;
  bytes

let any_nonzero bytes =
  let rec loop index =
    index < Bytes.length bytes
    && (Bytes.get_uint8 bytes index <> 0 || loop (index + 1))
  in
  loop 0

let () =
  let compiled = Version.compiled and linked = Version.linked () in
  if compiled <> { Version.major = 3; minor = 2; patch = 4 }
      || linked <> compiled || not Version.stable_headers
      || Version.function_count < 90 || Version.safe_function_count <> 30 then
    fail "generated or linked SDL3_mixer provenance changed";
  (match Mixer.create_memory ~sample_rate:48_000 ~channels:2 with
   | Error { kind = Not_initialized; _ } -> ()
   | Ok mixer -> ignore (Mixer.destroy mixer); fail "mixer created before init"
   | Error _ -> fail "pre-init mixer returned the wrong error");
  get (Init.init ());
  if not (get (Init.initialized ())) then fail "mixer init was not retained";
  (match Domain.spawn Init.initialized |> Domain.join with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain mixer init query was not rejected");

  let mixer = get (Mixer.create_memory ~sample_rate:48_000 ~channels:2) in
  if Mixer.mode mixer <> Mixer.Memory
      || get (Mixer.format mixer) <> { Mixer.sample_rate = 48_000; channels = 2 }
  then fail "memory mixer format changed";
  get (Mixer.set_gain mixer 0.75);
  if get (Mixer.gain mixer) <> 0.75 then fail "mixer gain changed";
  (match Mixer.set_gain mixer nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "NaN mixer gain was accepted");

  let encoded = tiny_wav () in
  let memory_audio = get (Audio.load_bytes mixer encoded) in
  Bytes.fill encoded 0 (Bytes.length encoded) '\x00';
  if get (Audio.duration_frames memory_audio) <= 0L then
    fail "memory WAV has no duration";
  let temp = Filename.temp_file "prismel-sdl3-mixer-" ".wav" in
  at_exit (fun () -> try Sys.remove temp with Sys_error _ -> ());
  let wav = tiny_wav () in
  let channel = open_out_bin temp in
  output_bytes channel wav;
  close_out channel;
  let file_audio = get (Audio.load_file mixer ~path:temp ~predecode:false ()) in
  if get (Audio.duration_frames file_audio) <= 0L then
    fail "file WAV has no duration";
  (match Audio.load_bytes mixer (Bytes.of_string "bad audio") with
   | Error { kind = Mixer_error; message; _ } when message <> "" -> ()
   | Ok audio -> ignore (Audio.destroy audio); fail "malformed audio loaded"
   | Error _ -> fail "malformed audio returned the wrong error");

  let sine = get (Audio.create_sine mixer ~frequency:440 ~amplitude:0.25
      ~duration_ms:100) in
  if get (Audio.duration_frames sine) <= 0L then fail "sine has no duration";
  let track = get (Track.create mixer) in
  get (Track.set_audio track sine);
  get (Track.set_gain track 0.5);
  if get (Track.gain track) <> 0.5 then fail "track gain changed";
  get (Track.play track ~loops:1 ~fade_in_ms:5 ());
  if not (get (Track.playing track)) then fail "memory track did not start";
  let generated = get (Mixer.generate mixer ~frames:256) in
  if Bytes.length generated.pcm_f32 <> 256 * 2 * 4
      || generated.mixed_bytes <= 0 || not (any_nonzero generated.pcm_f32) then
    fail "memory mixer did not generate finite non-silent float32 PCM";
  get (Track.pause track);
  if not (get (Track.paused track)) then fail "track did not pause";
  get (Track.resume track);
  if get (Track.paused track) then fail "track did not resume";
  get (Track.set_loops track 0);
  if get (Track.loops track) <> 0 then fail "live loop update changed";
  get (Track.stop track ~fade_out_ms:2 ());

  (match Mixer.destroy mixer with
   | Error { kind = Parent_has_dependents; _ } -> ()
   | Ok () | Error _ -> fail "mixer teardown ignored child handles");
  let wrong_domain = Domain.spawn (fun () -> Mixer.gain mixer) |> Domain.join in
  (match wrong_domain with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain mixer access was not rejected");
  get (Track.destroy track);
  get (Track.destroy track);
  get (Audio.destroy sine);
  get (Audio.destroy memory_audio);
  get (Audio.destroy file_audio);
  (match Track.playing track with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale track access was not rejected");
  get (Mixer.destroy mixer);
  get (Mixer.destroy mixer);

  let device = get (Mixer.create_device ()) in
  if Mixer.mode device <> Mixer.Device then fail "device mixer mode changed";
  let device_audio = get (Audio.create_sine device ~frequency:220 ~amplitude:0.1
      ~duration_ms:25) in
  let device_track = get (Track.create device) in
  get (Track.set_audio device_track device_audio);
  get (Track.play device_track ());
  get (Track.pause device_track);
  get (Track.resume device_track);
  get (Mixer.stop_all device ());
  get (Track.destroy device_track);
  get (Audio.destroy device_audio);
  get (Mixer.destroy device);

  get (Init.quit ());
  get (Init.quit ());
  Printf.printf "SDL3_mixer %d.%d.%d track/device/memory conformance passed\n%!"
    linked.major linked.minor linked.patch
