open Prismel_next_resources
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let u16 b o v=Bytes.set_uint8 b o(v land 255);Bytes.set_uint8 b(o+1)((v lsr 8)land 255)
let u32 b o v=u16 b o(v land 65535);u16 b(o+2)((v lsr 16)land 65535)
let wav()=let n=800 in let b=Bytes.make(44+n*2)'\000'in Bytes.blit_string"RIFF"0 b 0 4;u32 b 4(36+n*2);Bytes.blit_string"WAVEfmt "0 b 8 8;u32 b 16 16;u16 b 20 1;u16 b 22 1;u32 b 24 8000;u32 b 28 16000;u16 b 32 2;u16 b 34 16;Bytes.blit_string"data"0 b 36 4;u32 b 40(n*2);for i=0 to n-1 do u16 b(44+i*2)((if i land 8=0 then 8000 else -8000)land 65535)done;b
let nonzero b=let yes=ref false in Bytes.iter(fun c->if c<>'\000'then yes:=true)b;!yes
let ()=
  let owner=get(Audio.create_memory~sample_rate:48000~channels:2~max_channels:16)in
  let encoded=wav()in let sample=get(Audio.load_sample_bytes owner encoded)in Bytes.fill encoded 0(Bytes.length encoded)'\000';
  let generation=Audio.sample_generation sample in
  (match Audio.reload_sample_bytes sample(Bytes.of_string"bad")with Error _ when Audio.sample_generation sample=generation->()|_->failwith"reload retention");
  get(Audio.reload_sample_bytes sample(wav()));if Audio.sample_generation sample<>generation+1 then failwith"reload generation";
  let channel=get(Audio.play_sample owner~loops:1~fade_in_ms:2~volume:0.5 sample)in
  let generated=get(Audio.generate owner~frames:512)in if generated.mixed_bytes<=0||not(nonzero generated.pcm_f32)then failwith"dummy PCM";
  get(Audio.pause_channel owner channel);get(Audio.resume_channel owner channel);get(Audio.stop_channel owner channel~fade_out_ms:2());
  get(Audio.play_music owner~loops:1~fade_in_ms:2 sample);get(Audio.set_music_volume owner 0.4);get(Audio.pause_music owner);get(Audio.resume_music owner);get(Audio.stop_music owner~fade_out_ms:2());
  for i=1 to 100_000 do get(Audio.set_master_volume owner(float(i land 1)))done;
  if List.length(Audio.drain_web_intents owner)<>256||Audio.dropped_web_intents owner<99_000 then failwith"web intent bound";
  let assets=Assets.create()and order=ref[]in ignore(get(Assets.borrow assets~destroy:(fun()->order:=2::!order;Audio.destroy owner)owner));ignore(get(Assets.borrow assets~destroy:(fun()->order:=1::!order;Audio.destroy_sample sample)sample));get(Assets.destroy assets);if!order<>[2;1]then failwith"audio on_stop ordering";
  (match Audio.generate owner~frames:1 with Error{kind=Destroyed;_}->()|_->failwith"stale audio");
  print_endline"prismel_next_resources Audio: dummy PCM reload fades intents100k teardown passed"
