open Prismel

type model = {
  sample : Audio.Sample.t;
  music : Audio.Music.t;
  wave_path : string;
  trace_path : string;
  sample_started : bool;
  sample_stopped : bool;
  music_started : bool;
  music_stopped : bool;
}

let result_exn = function
  | Ok value -> value
  | Error message -> failwith message

let output_u16 channel value =
  output_byte channel (value land 0xff);
  output_byte channel ((value lsr 8) land 0xff)

let output_u32 channel value =
  output_u16 channel (value land 0xffff);
  output_u16 channel ((value lsr 16) land 0xffff)

let write_wave path =
  let sample_rate = 44_100 and count = 4_410 in
  let channel = open_out_bin path in
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
    for index = 0 to count - 1 do
      let phase = float index *. 440. /. float sample_rate in
      let value = int_of_float (Float.sin (phase *. Math.two_pi) *. 4_096.) in
      output_u16 channel (value land 0xffff)
    done)

let init _frame =
  if Array.length Sys.argv <> 2 then
    invalid_arg "gpu_baseline_audio: expected trace output path";
  if not (Sketch.is_headless ()) then
    failwith "gpu_baseline_audio must run on the headless dummy audio target";
  let wave_path = Filename.temp_file "prismel-gpu-audio-" ".wav" in
  write_wave wave_path;
  let sample = result_exn (Audio.Sample.load wave_path)
  and music = result_exn (Audio.Music.load wave_path) in
  Audio.set_master_volume 0.25;
  Audio.Sample.set_volume sample 0.;
  let channel = result_exn (Audio.Sample.play ~loops:1 sample) in
  let sample_started = Audio.Sample.is_playing channel in
  Audio.Sample.pause channel;
  Audio.Sample.resume channel;
  Audio.Sample.stop channel;
  let sample_stopped = not (Audio.Sample.is_playing channel) in
  Audio.Music.set_volume 0.;
  result_exn (Audio.Music.play ~loops:1 ~fade_ms:0 music);
  let music_started = Audio.Music.is_playing () in
  Audio.Music.pause ();
  Audio.Music.resume ();
  Audio.Music.stop ~fade_ms:0 ();
  let music_stopped = not (Audio.Music.is_playing ()) in
  {
    sample;
    music;
    wave_path;
    trace_path = Sys.argv.(1);
    sample_started;
    sample_stopped;
    music_started;
    music_stopped;
  }

let update model (frame : Frame.t) =
  if frame.count = 2 then Sketch.quit ();
  model

let stop model =
  Audio.stop_all ();
  Audio.Sample.destroy model.sample;
  Audio.Sample.destroy model.sample;
  Audio.Music.destroy model.music;
  Audio.Music.destroy model.music;
  if Sys.file_exists model.wave_path then Sys.remove model.wave_path;
  let channel = open_out_bin model.trace_path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    Printf.fprintf channel
      "{\n  \"schema\": 1,\n  \"target\": \"headless\",\n  \"driver\": \"SDL dummy audio through SDL_mixer\",\n  \"sample_started\": %b,\n  \"sample_stopped\": %b,\n  \"music_started\": %b,\n  \"music_stopped\": %b,\n  \"operations\": [\n    \"sample.load\",\n    \"sample.set_volume\",\n    \"sample.play_loop\",\n    \"sample.pause\",\n    \"sample.resume\",\n    \"sample.stop\",\n    \"music.load\",\n    \"music.set_volume\",\n    \"music.play_loop\",\n    \"music.pause\",\n    \"music.resume\",\n    \"music.stop\",\n    \"audio.stop_all\",\n    \"sample.destroy\",\n    \"sample.destroy_idempotent\",\n    \"music.destroy\",\n    \"music.destroy_idempotent\",\n    \"temporary_wave.remove\"\n  ]\n}\n"
      model.sample_started model.sample_stopped model.music_started
      model.music_stopped)

let () =
  ignore
    (Sketch.run_state
      ~config:{
        Sketch.default_config with
        width = 32;
        height = 32;
        title = "Prismel GPU audio baseline";
        fps = Some 120;
        domains = Some 1;
        clock = Sketch.Fixed (1. /. 60.);
      }
      ~init ~update ~view:(fun _ _ -> Scene.[clear Color.black])
      ~on_stop:stop ())
