type state={audio:Runtime_resources.Audio.t}
let engine:state option ref=ref None
let message operation error=Format.asprintf"%s: %a"operation Runtime_resources.pp_error error
let current operation=match!engine with Some value->Ok value|None->Error(operation^": not initialized")
let init ()=match!engine with Some _->Ok()|None->
  begin match Runtime_resources.Audio.create_device ~max_channels:32 with
  |Ok audio->engine:=Some{audio};Ok()|Error error->Error(message"Audio.init"error)end
let is_initialized()=Option.is_some!engine
let shutdown()=match!engine with None->()|Some value->ignore(Runtime_resources.Audio.destroy value.audio);engine:=None
let read path=let input=open_in_bin path in Fun.protect~finally:(fun()->close_in_noerr input)(fun()->really_input_string input(in_channel_length input)|>Bytes.of_string)
module Sample=struct
  type waveform=Sine|Square|Saw|Triangle
  type t={resource:Runtime_resources.Audio.sample;mutable destroyed:bool;volume:float}
  let load path=match current"Audio.Sample.load"with Error _ as error->error|Ok audio->
    begin try match Runtime_resources.Audio.load_sample_bytes audio.audio(read path)with
    |Ok resource->Ok{resource;destroyed=false;volume=1.}|Error error->Error(message"Audio.Sample.load"error)
    with Sys_error value->Error value end
  let synth ?(volume=1.)~waveform ~frequency ~duration ()=let sample_rate=48000 in match current"Audio.Sample.synth"with Error _ as e->e|Ok state->
    if frequency<=0.||duration<=0. then Error"Audio.Sample.synth: invalid frequency or duration"else
    let frames=max 1(int_of_float(duration*.float sample_rate))in let bytes=Bytes.make(44+frames*2)'\000'in
    let p16 o v=Bytes.set bytes o(Char.chr(v land 255));Bytes.set bytes(o+1)(Char.chr((v lsr 8)land 255))in let p32 o v=p16 o v;p16(o+2)(v lsr 16)in
    Bytes.blit_string"RIFF"0 bytes 0 4;p32 4(36+frames*2);Bytes.blit_string"WAVEfmt "0 bytes 8 8;p32 16 16;p16 20 1;p16 22 1;p32 24 sample_rate;p32 28(sample_rate*2);p16 32 2;p16 34 16;Bytes.blit_string"data"0 bytes 36 4;p32 40(frames*2);
    let pi=4. *. atan 1. in for i=0 to frames-1 do let phase=frequency *. float i /. float sample_rate in let x=match waveform with Sine->sin(2. *. pi *. phase)|Square->if sin(2. *. pi *. phase)>=0. then 1. else -1.|Saw->2. *. (phase -. floor(phase +. 0.5))|Triangle->2. *. Float.abs(2. *. (phase -. floor(phase +. 0.5))) -. 1. in let scaled=Float.max (-1.) (Float.min 1. (volume *. x)) in p16(44+i*2)(int_of_float(scaled *. 32767.)land 0xffff)done;
    match Runtime_resources.Audio.load_sample_bytes state.audio bytes with Ok resource->Ok{resource;destroyed=false;volume=1.}|Error e->Error(message"Audio.Sample.synth"e)
  let play ?loops ?volume sample=match current"Audio.Sample.play"with Error _ as error->error|Ok state->
    begin match Runtime_resources.Audio.play_sample state.audio ?loops ~volume:(Option.value volume~default:sample.volume) sample.resource with Ok channel->Ok channel|Error error->Error(message"Audio.Sample.play"error)end
  let destroy sample=if not sample.destroyed then(ignore(Runtime_resources.Audio.destroy_sample sample.resource);sample.destroyed<-true)
end
