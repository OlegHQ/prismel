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

let run () =
  let triple (v : Sdl3.version) = v.major, v.minor, v.patch in
  (match Sdl3_lock.check_installed ~lock:(Sdl3_lock.read "../../packaging/sdl3.lock")
      ~key:"sdl3_mixer" ~compiled:(triple compiled_version)
      ~linked:(triple (linked_version ())) with
   | Ok () -> () | Error message -> fail message);
  (match check_version ~release:true () with
   | Ok () -> () | Error error -> fail (Format.asprintf "%a" pp_error error));
  (match Mixer.create_memory ~sample_rate:48_000 ~channels:2 with
   | Error { kind = Not_initialized; _ } -> ()
   | Ok mixer -> ignore (Mixer.destroy mixer); fail "mixer created before init"
   | Error _ -> fail "pre-init mixer returned the wrong error");
  (match Domain.spawn Init.init |> Domain.join with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain mixer init was not rejected");
  get (Init.init ());
  (match Mixer.create_memory ~sample_rate:7_999 ~channels:2 with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok mixer -> ignore (Mixer.destroy mixer); fail "invalid sample rate succeeded"
   | Error _ -> fail "invalid sample rate returned the wrong error");
  (match Mixer.create_memory ~sample_rate:48_000 ~channels:0 with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok mixer -> ignore (Mixer.destroy mixer); fail "invalid channels succeeded"
   | Error _ -> fail "invalid channels returned the wrong error");

  let mixer = get (Mixer.create_memory ~sample_rate:48_000 ~channels:2) in
  get (Mixer.set_gain mixer 0.75);
  (match Mixer.set_gain mixer nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "NaN mixer gain was accepted");

  let encoded = tiny_wav () in
  let audio = get (Audio.load_bytes mixer encoded) in
  (* the audio owns a copy: scribbling on the source changes nothing *)
  Bytes.fill encoded 0 (Bytes.length encoded) '\x00';
  (match Audio.load_bytes mixer Bytes.empty with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok audio -> ignore (Audio.destroy audio); fail "empty audio bytes loaded"
   | Error _ -> fail "empty audio bytes returned the wrong error");
  (match Audio.load_bytes mixer (Bytes.of_string "bad audio") with
   | Error ({ kind = Mixer_error; message; _ } as captured) when message <> "" ->
       let original = captured.message in
       ignore (linked_version ());
       if captured.message <> original then
         fail "mixer error text changed after a subsequent native call"
   | Ok audio -> ignore (Audio.destroy audio); fail "malformed audio loaded"
   | Error _ -> fail "malformed audio returned the wrong error");
  (* a failed reload leaves the original usable; a good one is a new value *)
  (match Audio.reload_bytes audio (Bytes.of_string "bad reload") with
   | Error { kind = Mixer_error; _ } -> ()
   | Ok replacement -> ignore (Audio.destroy replacement); fail "malformed reload succeeded"
   | Error _ -> fail "malformed reload returned the wrong error");
  let reloaded = get (Audio.reload_bytes audio (tiny_wav ())) in
  if reloaded == audio then fail "encoded reload did not create an owned replacement";

  let track = get (Music.create mixer) in
  get (Music.set_audio track audio);
  get (Music.set_volume track 0.5);
  (match Music.set_volume track nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "NaN track volume was accepted");
  get (Music.play track ~loops:1 ~fade_in_ms:5 ());
  let generated = get (Mixer.generate mixer ~frames:256) in
  if Bytes.length generated.pcm_f32 <> 256 * 2 * 4
      || generated.mixed_bytes <= 0 || not (any_nonzero generated.pcm_f32) then
    fail "memory mixer did not generate finite non-silent float32 PCM";
  get (Music.pause track);
  get (Music.resume track);
  get (Music.stop track ~fade_out_ms:2 ());

  let channels = get (Channels.create mixer ~count:32) in
  if Channels.count channels <> 32 then fail "bounded channel count changed";
  let selected = get (Channels.play channels ~loops:1 ~fade_in_ms:1 audio) in
  get (Channels.set_volume channels selected 0.4);
  if not (get (Channels.playing channels selected)) then
    fail "channel playback state changed";
  get (Channels.pause channels selected);
  get (Channels.resume channels selected);
  get (Channels.stop channels selected ~fade_out_ms:1 ());
  (match Channels.playing channels 32 with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok _ | Error _ -> fail "out-of-range channel was accepted");
  (match Channels.set_volume channels 0 nan with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "NaN channel volume was accepted");
  (match Domain.spawn (fun () -> Channels.playing channels 0) |> Domain.join with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "concurrent channel misuse was not rejected");
  for index = 0 to 31 do
    ignore (get (Channels.play channels ~channel:index ~loops:(index land 1) audio))
  done;
  (match Channels.play channels audio with
   | Error { kind = Mixer_error; _ } -> ()
   | Ok _ | Error _ -> fail "full channel bank did not reject an unnamed channel");
  for index = 0 to 31 do get (Channels.stop channels index ()) done;
  get (Channels.destroy channels);
  get (Channels.destroy channels);

  for _cycle = 1 to 10_000 do
    let transient = get (Music.create mixer) in
    get (Music.destroy transient)
  done;

  let other = get (Mixer.create_memory ~sample_rate:48_000 ~channels:2) in
  let foreign = get (Music.create other) in
  (match Music.set_audio foreign audio with
   | Error { kind = Invalid_argument; _ } -> ()
   | Ok () | Error _ -> fail "cross-mixer audio attachment was accepted");
  get (Music.destroy foreign); get (Mixer.destroy other);

  (match Mixer.destroy mixer with
   | Error { kind = Parent_has_dependents; _ } -> ()
   | Ok () | Error _ -> fail "mixer teardown ignored child handles");
  (match Domain.spawn (fun () -> Mixer.set_gain mixer 1.) |> Domain.join with
   | Error { kind = Wrong_domain; _ } -> ()
   | Ok _ | Error _ -> fail "wrong-domain mixer access was not rejected");
  get (Music.destroy track);
  get (Music.destroy track);
  get (Audio.destroy audio);
  get (Audio.destroy reloaded);
  (match Music.pause track with
   | Error { kind = Destroyed; _ } -> ()
   | Ok _ | Error _ -> fail "stale track access was not rejected");
  get (Mixer.destroy mixer);
  get (Mixer.destroy mixer);
  (match Music.create mixer with
   | Error { kind = Destroyed; _ } -> ()
   | Ok track -> ignore (Music.destroy track); fail "track used destroyed mixer"
   | Error _ -> fail "destroyed-mixer track returned the wrong error");

  let device = get (Mixer.create_device ()) in
  let device_audio = get (Audio.load_bytes device (tiny_wav ())) in
  let device_track = get (Music.create device) in
  get (Music.set_audio device_track device_audio);
  get (Music.play device_track ());
  get (Music.pause device_track);
  get (Music.resume device_track);
  get (Music.stop device_track ());
  get (Music.destroy device_track);
  get (Audio.destroy device_audio);
  get (Mixer.destroy device);

  get (Init.quit ());
  get (Init.quit ());
  Printf.printf "SDL3_mixer %d.%d.%d track/device/memory conformance passed\n%!"
    (linked_version ()).major (linked_version ()).minor (linked_version ()).patch
