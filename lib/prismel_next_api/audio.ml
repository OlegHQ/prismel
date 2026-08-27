type state={audio:Prismel_next_resources.Audio.t;playing:(int,unit)Hashtbl.t;mutable music_playing:bool}
let engine:state option ref=ref None
let message operation error=Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error
let current operation=match!engine with Some value->Ok value|None->Error(operation^": not initialized")
let init ?(frequency=48000)?(channels=2)?chunk_size:_ ()=match!engine with Some _->Ok()|None->
  begin match Prismel_next_resources.Audio.create_memory ~sample_rate:frequency ~channels ~max_channels:32 with
  |Ok audio->engine:=Some{audio;playing=Hashtbl.create 32;music_playing=false};Ok()|Error error->Error(message"Audio.init"error)end
let is_initialized()=Option.is_some!engine
let shutdown()=match!engine with None->()|Some value->ignore(Prismel_next_resources.Audio.destroy value.audio);engine:=None
let set_master_volume volume=match current"Audio.set_master_volume"with Ok value->ignore(Prismel_next_resources.Audio.set_master_volume value.audio volume)|Error _->()
let stop_all()=match!engine with None->()|Some value->List.init 32 Fun.id|>List.iter(fun channel->ignore(Prismel_next_resources.Audio.stop_channel value.audio channel()));Hashtbl.clear value.playing;value.music_playing<-false
let read path=let input=open_in_bin path in Fun.protect~finally:(fun()->close_in_noerr input)(fun()->really_input_string input(in_channel_length input)|>Bytes.of_string)
module Sample=struct
  type waveform=Sine|Square|Saw|Triangle
  type t={resource:Prismel_next_resources.Audio.sample;mutable destroyed:bool;mutable volume:float}
  let load path=match current"Audio.Sample.load"with Error _ as error->error|Ok audio->
    begin try match Prismel_next_resources.Audio.load_sample_bytes audio.audio(read path)with
    |Ok resource->Ok{resource;destroyed=false;volume=1.}|Error error->Error(message"Audio.Sample.load"error)
    with Sys_error value->Error value end
  let load_exn path=match load path with Ok value->value|Error value->failwith value
  let synth ?(sample_rate=48000)?(volume=1.)~waveform ~frequency ~duration ()=match current"Audio.Sample.synth"with Error _ as e->e|Ok state->
    if frequency<=0.||duration<=0. then Error"Audio.Sample.synth: invalid frequency or duration"else
    let frames=max 1(int_of_float(duration*.float sample_rate))in let bytes=Bytes.make(44+frames*2)'\000'in
    let p16 o v=Bytes.set bytes o(Char.chr(v land 255));Bytes.set bytes(o+1)(Char.chr((v lsr 8)land 255))in let p32 o v=p16 o v;p16(o+2)(v lsr 16)in
    Bytes.blit_string"RIFF"0 bytes 0 4;p32 4(36+frames*2);Bytes.blit_string"WAVEfmt "0 bytes 8 8;p32 16 16;p16 20 1;p16 22 1;p32 24 sample_rate;p32 28(sample_rate*2);p16 32 2;p16 34 16;Bytes.blit_string"data"0 bytes 36 4;p32 40(frames*2);
    let pi=4. *. atan 1. in for i=0 to frames-1 do let phase=frequency *. float i /. float sample_rate in let x=match waveform with Sine->sin(2. *. pi *. phase)|Square->if sin(2. *. pi *. phase)>=0. then 1. else -1.|Saw->2. *. (phase -. floor(phase +. 0.5))|Triangle->2. *. Float.abs(2. *. (phase -. floor(phase +. 0.5))) -. 1. in let scaled=Float.max (-1.) (Float.min 1. (volume *. x)) in p16(44+i*2)(int_of_float(scaled *. 32767.)land 0xffff)done;
    match Prismel_next_resources.Audio.load_sample_bytes state.audio bytes with Ok resource->Ok{resource;destroyed=false;volume=1.}|Error e->Error(message"Audio.Sample.synth"e)
  let play ?loops ?volume sample=match current"Audio.Sample.play"with Error _ as error->error|Ok state->
    begin match Prismel_next_resources.Audio.play_sample state.audio ?loops ~volume:(Option.value volume~default:sample.volume) sample.resource with Ok channel->Hashtbl.replace state.playing channel();Ok channel|Error error->Error(message"Audio.Sample.play"error)end
  let set_volume sample value=sample.volume<-max 0. (min 1. value)
  let stop channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.stop_channel value.audio channel());Hashtbl.remove value.playing channel|None->()
  let pause channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.pause_channel value.audio channel)|None->()
  let resume channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.resume_channel value.audio channel)|None->()
  let is_playing channel=match!engine with Some value->Hashtbl.mem value.playing channel|None->false
  let destroy sample=if not sample.destroyed then(ignore(Prismel_next_resources.Audio.destroy_sample sample.resource);sample.destroyed<-true)
end
module Music=struct
  type t=Sample.t
  let load=Sample.load
  let load_exn=Sample.load_exn
  let play ?loops ?(fade_ms=0) value=match current"Audio.Music.play"with Error _ as error->error|Ok audio->
    begin match Prismel_next_resources.Audio.play_music audio.audio ?loops ~fade_in_ms:fade_ms value.Sample.resource with Ok()->audio.music_playing<-true;Ok()|Error error->Error(message"Audio.Music.play"error)end
  let set_volume value=match!engine with Some audio->ignore(Prismel_next_resources.Audio.set_music_volume audio.audio value)|None->()
  let pause()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.pause_music audio.audio)|None->()
  let resume()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.resume_music audio.audio)|None->()
  let stop ?(fade_ms=0)()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.stop_music audio.audio ~fade_out_ms:fade_ms());audio.music_playing<-false|None->()
  let is_playing()=match!engine with Some audio->audio.music_playing|None->false
  let destroy=Sample.destroy
end
