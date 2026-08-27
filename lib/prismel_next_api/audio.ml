let engine:Prismel_next_resources.Audio.t option ref=ref None
let message operation error=Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error
let current operation=match!engine with Some value->Ok value|None->Error(operation^": not initialized")
let init ?(frequency=48000)?(channels=2)?chunk_size:_ ()=match!engine with Some _->Ok()|None->
  begin match Prismel_next_resources.Audio.create_memory ~sample_rate:frequency ~channels ~max_channels:32 with
  |Ok value->engine:=Some value;Ok()|Error error->Error(message"Audio.init"error)end
let is_initialized()=Option.is_some!engine
let shutdown()=match!engine with None->()|Some value->ignore(Prismel_next_resources.Audio.destroy value);engine:=None
let set_master_volume volume=match current"Audio.set_master_volume"with Ok value->ignore(Prismel_next_resources.Audio.set_master_volume value volume)|Error _->()
let stop_all()=match!engine with None->()|Some value->List.init 32 Fun.id|>List.iter(fun channel->ignore(Prismel_next_resources.Audio.stop_channel value channel()))
let read path=let input=open_in_bin path in Fun.protect~finally:(fun()->close_in_noerr input)(fun()->really_input_string input(in_channel_length input)|>Bytes.of_string)
module Sample=struct
  type t={resource:Prismel_next_resources.Audio.sample;mutable destroyed:bool}
  let load path=match current"Audio.Sample.load"with Error _ as error->error|Ok audio->
    begin try match Prismel_next_resources.Audio.load_sample_bytes audio(read path)with
    |Ok resource->Ok{resource;destroyed=false}|Error error->Error(message"Audio.Sample.load"error)
    with Sys_error value->Error value end
  let load_exn path=match load path with Ok value->value|Error value->failwith value
  let play ?loops ?volume sample=match current"Audio.Sample.play"with Error _ as error->error|Ok audio->
    begin match Prismel_next_resources.Audio.play_sample audio ?loops ?volume sample.resource with Ok channel->Ok channel|Error error->Error(message"Audio.Sample.play"error)end
  let set_volume _sample _value=()
  let stop channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.stop_channel value channel())|None->()
  let pause channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.pause_channel value channel)|None->()
  let resume channel=match!engine with Some value->ignore(Prismel_next_resources.Audio.resume_channel value channel)|None->()
  let destroy sample=if not sample.destroyed then(ignore(Prismel_next_resources.Audio.destroy_sample sample.resource);sample.destroyed<-true)
end
module Music=struct
  type t=Sample.t
  let load=Sample.load
  let load_exn=Sample.load_exn
  let play ?loops ?(fade_ms=0) value=match current"Audio.Music.play"with Error _ as error->error|Ok audio->
    begin match Prismel_next_resources.Audio.play_music audio ?loops ~fade_in_ms:fade_ms value.Sample.resource with Ok()->Ok()|Error error->Error(message"Audio.Music.play"error)end
  let set_volume value=match!engine with Some audio->ignore(Prismel_next_resources.Audio.set_music_volume audio value)|None->()
  let pause()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.pause_music audio)|None->()
  let resume()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.resume_music audio)|None->()
  let stop ?(fade_ms=0)()=match!engine with Some audio->ignore(Prismel_next_resources.Audio.stop_music audio ~fade_out_ms:fade_ms())|None->()
  let destroy=Sample.destroy
end
