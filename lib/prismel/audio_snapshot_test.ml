let ok = function Ok value -> value | Error message -> failwith message
let u16 channel value=output_byte channel(value land 255);output_byte channel((value lsr 8)land 255)
let u32 channel value=u16 channel(value land 65535);u16 channel((value lsr 16)land 65535)
let wave path=
  let rate=8000 and count=80 in let channel=open_out_bin path in
  Fun.protect~finally:(fun()->close_out channel)(fun()->
    output_string channel"RIFF";u32 channel(36+count*2);output_string channel"WAVEfmt ";
    u32 channel 16;u16 channel 1;u16 channel 1;u32 channel rate;u32 channel(rate*2);
    u16 channel 2;u16 channel 16;output_string channel"data";u32 channel(count*2);
    for i=0 to count-1 do u16 channel((i*97)land 65535)done)
let bytes path=let c=open_in_bin path in Fun.protect~finally:(fun()->close_in c)(fun()->really_input_string c(in_channel_length c)|>Bytes.of_string)
let self_test()=
  let baseline=Audio_snapshot.live_bytes()in
  ok(Audio.init~frequency:8000~channels:4());
  let path=Filename.temp_file"prismel-audio-snapshot"".wav"in wave path;
  let encoded=bytes path in
  let sample=ok(Audio.Sample.load path)and music=ok(Audio.Music.load path)in
  let sample_snapshot=Option.get(Audio_snapshot.find(Obj.repr sample))
  and music_snapshot=Option.get(Audio_snapshot.find(Obj.repr music))in
  if sample_snapshot.encoded<>encoded||music_snapshot.encoded<>encoded then failwith"encoded bytes";
  begin match Audio.Sample.load(path^".missing")with Error _->()|Ok _->failwith"failed reload"end;
  if (Option.get(Audio_snapshot.find(Obj.repr sample))).generation<>sample_snapshot.generation then failwith"failed reload mutation";
  let channel=ok(Audio.Sample.play~volume:0. sample)in Audio.Sample.stop channel;
  let tone=ok(Audio.Sample.synth~sample_rate:8000~volume:0.~waveform:Sine~frequency:440.~duration:0.01())in
  let tone_snapshot=Option.get(Audio_snapshot.find(Obj.repr tone))in
  if Bytes.sub_string tone_snapshot.encoded 0 4<>"RIFF"||tone_snapshot.generation<>2L then failwith"synth snapshot";
  Audio.Sample.destroy tone;Audio.Sample.destroy sample;Audio.Music.destroy music;Sys.remove path;
  for _=1 to 100000 do let key=Obj.repr(ref 0)in Audio_snapshot.register key~kind:Sample(Bytes.of_string"x");Audio_snapshot.remove key done;
  if Audio_snapshot.live_bytes()<>baseline then failwith"audio snapshot plateau";
  Audio.shutdown()
let()=match Sys.getenv_opt"PRISMEL_TEST_AUDIO_SNAPSHOT"with Some"1"->self_test()|_->()
