open Tsdl
module Mix = Tsdl_mixer.Mixer

let initialized = ref false

let require_main_domain () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Audio operations must run on the main domain"

let message prefix = function
  | Ok value -> Ok value
  | Error (`Msg detail) -> Error (prefix ^ ": " ^ detail)

let init ?(frequency = Mix.default_frequency) ?(channels = 32)
    ?(chunk_size = 1024) () =
  require_main_domain ();
  if !initialized then Ok ()
  else
    match Sdl.init_sub_system Sdl.Init.audio with
    | Error (`Msg detail) -> Error ("SDL audio initialization failed: " ^ detail)
    | Ok () ->
        (match Mix.open_audio frequency Mix.default_format
            Mix.default_channels chunk_size with
         | Error (`Msg detail) ->
             Sdl.quit_sub_system Sdl.Init.audio;
             Error ("Audio device open failed: " ^ detail)
         | Ok () ->
             ignore (Mix.allocate_channels (max 1 channels));
             let requested = Mix.Init.(ogg + mp3 + flac) in
             ignore (Mix.init requested);
             initialized := true;
             Ok ())

let is_initialized () = !initialized

let ensure () =
  match init () with
  | Ok () -> Ok ()
  | Error _ as error -> error

let volume value =
  int_of_float (max 0. (min 1. value) *. float Mix.max_volume +. 0.5)

let normalized_volume value = max 0. (min 1. value)

let set_master_volume value =
  require_main_domain ();
  ignore (Mix.volume (-1) (volume value));
  ignore (Mix.volume_music (volume value));
  Backend.send_web_audio
    (Runtime.Audio_master_volume (normalized_volume value))

let stop_all () =
  require_main_domain ();
  if !initialized then begin
    ignore (Mix.halt_channel (-1));
    ignore (Mix.halt_music ());
    Backend.send_web_audio Runtime.Audio_stop_all
  end

let shutdown () =
  require_main_domain ();
  if !initialized then begin
    stop_all ();
    Mix.close_audio ();
    Mix.quit ();
    Sdl.quit_sub_system Sdl.Init.audio;
    initialized := false
  end

module Sample = struct
  type waveform = Sine | Square | Saw | Triangle

  type t = {
    chunk : Mix.chunk;
    mutable destroyed : bool;
    mutable web_asset : string option;
    mutable web_volume : float;
  }

  let ensure_sample sample =
    require_main_domain ();
    if sample.destroyed then invalid_arg "Audio sample has been destroyed"

  let load path =
    require_main_domain ();
    match ensure () with
    | Error _ as error -> error
    | Ok () ->
        (match message (Printf.sprintf "sample %S" path) (Mix.load_wav path) with
         | Error _ as error -> error
         | Ok chunk -> Ok {
             chunk;
             destroyed = false;
             web_asset = Backend.register_web_file path;
             web_volume = 1.;
           })

  let load_exn path =
    match load path with Ok sample -> sample | Error detail -> failwith detail

  let output_u16 channel value =
    output_byte channel (value land 0xff);
    output_byte channel ((value lsr 8) land 0xff)

  let output_u32 channel value =
    output_u16 channel (value land 0xffff);
    output_u16 channel ((value lsr 16) land 0xffff)

  let wave waveform phase =
    match waveform with
    | Sine -> Float.sin (phase *. Math.two_pi)
    | Square -> if phase < 0.5 then 1. else -1.
    | Saw -> (2. *. phase) -. 1.
    | Triangle -> 1. -. (4. *. abs_float (phase -. 0.5))

  let synth ?(sample_rate = 44_100) ?(volume = 0.8) ~waveform
      ~frequency ~duration () =
    require_main_domain ();
    if sample_rate <= 0 then Error "Audio.Sample.synth: invalid sample rate"
    else if frequency <= 0. then Error "Audio.Sample.synth: frequency must be positive"
    else if duration <= 0. then Error "Audio.Sample.synth: duration must be positive"
    else
      let count = max 1 (int_of_float (duration *. float sample_rate)) in
      let filename = Filename.temp_file "prismel-synth-" ".wav" in
      let write () =
        let channel = open_out_bin filename in
        Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
          output_string channel "RIFF";
          output_u32 channel (36 + (count * 2));
          output_string channel "WAVEfmt ";
          output_u32 channel 16;
          output_u16 channel 1;
          output_u16 channel 1;
          output_u32 channel sample_rate;
          output_u32 channel (sample_rate * 2);
          output_u16 channel 2;
          output_u16 channel 16;
          output_string channel "data";
          output_u32 channel (count * 2);
          let amplitude = max 0. (min 1. volume) *. 32_767. in
          for index = 0 to count - 1 do
            let phase =
              mod_float (float index *. frequency /. float sample_rate) 1.
            in
            let signed = int_of_float (wave waveform phase *. amplitude) in
            output_u16 channel (signed land 0xffff)
          done)
      in
      Fun.protect
        ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
        (fun () ->
          try
            write ();
            let channel = open_in_bin filename in
            let bytes =
              Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
                really_input_string channel (in_channel_length channel)
                |> Bytes.of_string) in
            let result = load filename in
            (match result with
             | Error _ -> ()
             | Ok sample ->
                 Option.iter Backend.remove_web_asset sample.web_asset;
                 sample.web_asset <-
                   Backend.register_web_bytes ~content_type:"audio/wav" bytes);
            result
          with Sys_error detail -> Error ("Audio synthesis failed: " ^ detail))

  let set_volume sample value =
    ensure_sample sample;
    let value = normalized_volume value in
    sample.web_volume <- value;
    ignore (Mix.volume_chunk sample.chunk (volume value));
    Option.iter (fun id ->
      Backend.send_web_audio
        (Runtime.Audio_sample_volume { asset = id; volume = value }))
      sample.web_asset

  let play ?(loops = 0) ?volume:sample_volume sample =
    ensure_sample sample;
    Option.iter (set_volume sample) sample_volume;
    match Mix.play_channel (-1) sample.chunk loops with
    | Ok channel ->
        Option.iter (fun id ->
          Backend.send_web_audio
            (Runtime.Audio_sample_play {
              asset = id;
              channel;
              loops;
              volume = sample.web_volume;
            })) sample.web_asset;
        Ok channel
    | Error (`Msg detail) -> Error ("Sample playback failed: " ^ detail)

  let stop channel =
    require_main_domain ();
    ignore (Mix.halt_channel channel);
    Backend.send_web_audio (Runtime.Audio_sample_stop channel)

  let pause channel =
    require_main_domain ();
    Mix.pause channel;
    Backend.send_web_audio (Runtime.Audio_sample_pause channel)
  let resume channel =
    require_main_domain ();
    Mix.resume channel;
    Backend.send_web_audio (Runtime.Audio_sample_resume channel)
  let is_playing channel = require_main_domain (); Mix.playing (Some channel)

  let destroy sample =
    require_main_domain ();
    if not sample.destroyed then begin
      Option.iter (fun id ->
        Backend.send_web_audio (Runtime.Audio_asset_remove id);
        Backend.remove_web_asset id) sample.web_asset;
      sample.web_asset <- None;
      Mix.free_chunk sample.chunk;
      sample.destroyed <- true
    end
end

module Music = struct
  type t = {
    music : Mix.music;
    mutable destroyed : bool;
    mutable web_asset : string option;
  }

  let ensure_music music =
    require_main_domain ();
    if music.destroyed then invalid_arg "Audio music has been destroyed"

  let load path =
    require_main_domain ();
    match ensure () with
    | Error _ as error -> error
    | Ok () ->
        (match message (Printf.sprintf "music %S" path) (Mix.load_mus path) with
         | Error _ as error -> error
         | Ok music -> Ok {
             music;
             destroyed = false;
             web_asset = Backend.register_web_file path;
           })

  let load_exn path =
    match load path with Ok music -> music | Error detail -> failwith detail

  let play ?(loops = 0) ?(fade_ms = 0) music =
    ensure_music music;
    let result =
      if fade_ms > 0 then Mix.fade_in_music music.music loops fade_ms
      else Mix.play_music music.music loops
    in
    match result with
    | Ok _ ->
        Option.iter (fun id ->
          Backend.send_web_audio
            (Runtime.Audio_music_play { asset = id; loops; fade_ms }))
          music.web_asset;
        Ok ()
    | Error (`Msg detail) -> Error ("Music playback failed: " ^ detail)

  let set_volume value =
    require_main_domain ();
    let value = normalized_volume value in
    ignore (Mix.volume_music (volume value));
    Backend.send_web_audio (Runtime.Audio_music_volume value)

  let pause () =
    require_main_domain ();
    Mix.pause_music ();
    Backend.send_web_audio Runtime.Audio_music_pause
  let resume () =
    require_main_domain ();
    Mix.resume_music ();
    Backend.send_web_audio Runtime.Audio_music_resume

  let stop ?(fade_ms = 0) () =
    require_main_domain ();
    if fade_ms > 0 then ignore (Mix.fade_out_music fade_ms)
    else ignore (Mix.halt_music ());
    Backend.send_web_audio (Runtime.Audio_music_stop fade_ms)

  let is_playing () = require_main_domain (); Mix.playing_music ()

  let destroy music =
    require_main_domain ();
    if not music.destroyed then begin
      Option.iter (fun id ->
        Backend.send_web_audio (Runtime.Audio_asset_remove id);
        Backend.remove_web_asset id) music.web_asset;
      music.web_asset <- None;
      Mix.free_music music.music;
      music.destroyed <- true
    end
end
