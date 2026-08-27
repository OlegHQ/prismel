open Prismel
open Sdl3_mixer

module Loop=Prismel_runtime_next_sketch
let get=function Ok value->value|Error error->failwith(Format.asprintf"%a"pp_error error)
let set_u16 bytes offset value=Bytes.set_uint8 bytes offset(value land 255);
  Bytes.set_uint8 bytes(offset+1)((value lsr 8)land 255)
let set_u32 bytes offset value=set_u16 bytes offset(value land 65535);
  set_u16 bytes(offset+2)((value lsr 16)land 65535)
let wav()=let samples=80 and bytes=Bytes.make(44+160)'\000'in
  Bytes.blit_string"RIFF"0 bytes 0 4;set_u32 bytes 4 196;
  Bytes.blit_string"WAVEfmt "0 bytes 8 8;set_u32 bytes 16 16;set_u16 bytes 20 1;
  set_u16 bytes 22 1;set_u32 bytes 24 8000;set_u32 bytes 28 16000;
  set_u16 bytes 32 2;set_u16 bytes 34 16;Bytes.blit_string"data"0 bytes 36 4;
  set_u32 bytes 40 160;for i=0 to samples-1 do
    set_u16 bytes(44+i*2)((if i mod 16<8 then 8000 else -8000)land 65535)done;bytes
let nonzero bytes=let found=ref false in Bytes.iter(fun value->if value<>'\000'then found:=true)bytes;!found

let test()=
  match Init.init()with
  |Error error->Format.printf"runtime-next audio unavailable: %a@."pp_error error
  |Ok()->
    let memory=get(Mixer.create_memory~sample_rate:48000~channels:2)in
    let sample=get(Audio.load_bytes memory(wav()))
    and music=get(Audio.create_sine memory~frequency:220~amplitude:0.2~duration_ms:200)in
    let sample_track=get(Track.create memory)and music_track=get(Track.create memory)in
    get(Track.set_audio sample_track sample);get(Track.set_audio music_track music);
    let device=get(Mixer.create_device())in
    let device_audio=get(Audio.create_sine device~frequency:440~amplitude:0.1~duration_ms:100)in
    let device_track=get(Track.create device)in get(Track.set_audio device_track device_audio);
    let checkpoints=Hashtbl.create 4 and mixed_nonzero=ref false
    and stopped_while_live=ref false in
    let vertices=Bytes.make 48 '\000'in let set i x y=
      Bytes.set_int64_le vertices(i*16)(Int64.bits_of_float x);
      Bytes.set_int64_le vertices(i*16+8)(Int64.bits_of_float y)in
    set 0 0. 0.;set 1 4. 0.;set 2 0. 4.;let indices=Bytes.make 12 '\000'in
    Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
    let draw:Scene_execution.draw={mesh={key="audio";vertices;vertex_count=3;
      indices;index_count=3};state={viewport=(0,0,4,4);scissor=(0,0,4,4)}}in
    let configuration:Loop.configuration={target=Runtime_next_orchestrator.Headless;
      logical_width=4;logical_height=4;drawable_width=4;drawable_height=4;
      frames=600;dt=1./.60.;wap_config=None}in
    let result=Loop.run_state~configuration~init:(fun _->())~update:(fun() _->())
      ~view:(fun()_->[Scene.clear Color.black])~prepare:(fun frame _->
        begin match frame.Frame.count with
        |1->get(Mixer.set_gain memory 0.75);get(Track.set_gain sample_track 0.5);
          get(Track.play sample_track~loops:1());get(Track.play device_track())
        |2->get(Track.pause sample_track);if not(get(Track.paused sample_track))then
          failwith"audio pause";get(Track.resume sample_track)
        |60->get(Track.set_loops sample_track 0);get(Track.play music_track~loops:2());
          get(Track.set_gain music_track 0.25)
        |600->get(Track.stop sample_track());get(Track.stop music_track());
          get(Mixer.stop_all device())
        |_->()end;
        let generated=get(Mixer.generate memory~frames:64)in
        if nonzero generated.pcm_f32 then mixed_nonzero:=true;
        if List.mem frame.count[1;2;60;600]then Hashtbl.add checkpoints frame.count
          (generated.mixed_bytes,Track.loops sample_track|>get,
           Track.gain sample_track|>get);
        Ok[draw])
      ~on_stop:(fun()->
        stopped_while_live:=get(Init.initialized());
        get(Track.destroy device_track);get(Audio.destroy device_audio);get(Mixer.destroy device);
        get(Track.destroy sample_track);get(Track.destroy music_track);
        get(Audio.destroy sample);get(Audio.destroy music);get(Mixer.destroy memory);
        get(Init.quit()))()in
    begin match result with Error error->failwith(Ogpu.Error.to_string error)|Ok _->()end;
    if not !mixed_nonzero||not !stopped_while_live||Hashtbl.length checkpoints<>4 then
      failwith"runtime-next audio finite execution";
    if get(Init.initialized())then failwith"audio subsystem retained after zero handles";
    begin match Track.playing sample_track with Error{kind=Destroyed;_}->()|_->
      failwith"destroyed audio track remained live"end;
    print_endline"runtime-next audio: dummy+memory frames1/2/60/600 zero handles passed"

let()=match Sys.getenv_opt"PRISMEL_TEST_RUNTIME_NEXT_AUDIO"with
  |Some"1"->test()|_->()
