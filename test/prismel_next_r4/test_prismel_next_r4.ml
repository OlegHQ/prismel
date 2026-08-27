open Prismel_next_resources
let resource=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let execution=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)
let check value message=if not value then failwith message
let hash bytes=let value=ref 0xcbf29ce484222325L in Bytes.iter(fun byte->value:=Int64.mul(Int64.logxor!value(Int64.of_int(Char.code byte)))0x100000001b3L)bytes;!value
let u16 b o v=Bytes.set_uint8 b o(v land 255);Bytes.set_uint8 b(o+1)((v lsr 8)land 255)
let u32 b o v=u16 b o(v land 65535);u16 b(o+2)((v lsr 16)land 65535)
let wav()=let n=80 in let b=Bytes.make(44+n*2)'\000'in Bytes.blit_string"RIFF"0 b 0 4;u32 b 4(36+n*2);Bytes.blit_string"WAVEfmt "0 b 8 8;u32 b 16 16;u16 b 20 1;u16 b 22 1;u32 b 24 8000;u32 b 28 16000;u16 b 32 2;u16 b 34 16;Bytes.blit_string"data"0 b 36 4;u32 b 40(n*2);for i=0 to n-1 do u16 b(44+i*2)((if i land 8=0 then 8000 else -8000)land 65535)done;b
let temporary_png color =
  let canvas=resource(Canvas.create~width:2~height:2)in resource(Canvas.clear canvas color);
  let path=Filename.temp_file"prismel-r4-"".png"in resource(Canvas.save_png canvas path);resource(Canvas.destroy canvas);path
let image_command id=Result.get_ok(Raster2.Render_ir.create[|Raster2.Render_ir.Image{resource_id=id;source={x=0.;y=0.;width=2.;height=2.};destination={x=0.;y=0.;width=8.;height=8.}}|])
let run_target (selected:Prismel_next_execution.target) image expected =
  let config=Prismel_next_execution.{default_configuration with target=selected;logical_width=8;logical_height=8;drawable_width=8;drawable_height=8;max_events=64}in
  match Prismel_next_execution.create config with
  |Error _ when selected=Prismel_next_execution.Native->()
  |Error e->failwith(Format.asprintf"target: %a"Prismel_next_execution.pp_error e)
  |Ok runtime->
      let ir=image_command(Image.identity image)in
      let draws=execution(Prismel_next_execution.lower_scene2 runtime~density:1~resource:(fun _->Some(Prismel_next_execution.Image image))ir)in
      List.iter(fun frame->if List.mem frame[1;2;60;600]then(ignore(execution(Prismel_next_execution.step runtime draws));let pixels=execution(Prismel_next_execution.capture runtime)in check(hash pixels=expected)(Printf.sprintf"target hash frame %d: %Lx"frame(hash pixels))))[1;2;60;600];
      check(Prismel_next_execution.snapshot_cache_entries runtime=1)"execution snapshot cache";
      execution(Prismel_next_execution.destroy runtime)
let ()=
  let red_path=temporary_png 0xff0000ffl in
  let watched=resource(Image.load_file red_path)in let identity=Image.identity watched and generation=Image.generation watched in
  let bad=Filename.temp_file"prismel-r4-bad-"".png"in let output=open_out_bin bad in output_string output"bad";close_out output;
  check(Result.is_error(Image.reload_file watched bad))"watched malformed reload";
  check(Image.identity watched=identity&&Image.generation watched=generation)"watched failure retention";
  let green_path=temporary_png 0x00ff00ffl in resource(Image.reload_file watched green_path);
  check(Image.identity watched=identity&&Image.generation watched=generation+1)"watched stable replacement";
  let image_hash=hash(resource(Image.pixels watched))in
  let canvas=resource(Canvas.create~width:4~height:4)in resource(Canvas.clear canvas 0x010203ffl);resource(Canvas.draw_image canvas watched~x:1~y:1);
  let capture=resource(Canvas.capture canvas)in let canvas_hash=hash(resource(Image.pixels capture))in
  let font=resource(Font.open_system~size:14.)in
  let text1=Option.get(resource(Font.render_cached font~renderer:9~density:1~color:(255,255,255,255)"R4"))
  and text2=Option.get(resource(Font.render_cached font~renderer:9~density:2~color:(255,255,255,255)"R4"))in
  let font_hash=Int64.logxor(hash(resource(Text.pixels text1)))(hash(resource(Text.pixels text2)))in
  for index=0 to 299 do ignore(resource(Font.render_cached font~renderer:9~density:1~color:(255,255,255,255)(string_of_int index)))done;
  check(Font.cache_entries font~renderer:9=256)"font cache bound";resource(Font.set_outline font 1);check(Font.cache_entries font~renderer:9=0)"font mutation invalidation";
  let audio=resource(Audio.create_memory~sample_rate:48000~channels:2~max_channels:8)in let sample=resource(Audio.load_sample_bytes audio(wav()))in
  ignore(resource(Audio.play_sample audio~loops:1 sample));let mixed=resource(Audio.generate audio~frames:128)in check(mixed.mixed_bytes>0&&Bytes.exists((<>)'\000')mixed.pcm_f32)"audio PCM";
  for index=1 to 100_000 do resource(Audio.set_master_volume audio(float(index land 1)))done;
  check(List.length(Audio.drain_web_intents audio)=256&&Audio.dropped_web_intents audio>99_000)"audio intent bound";
  check(image_hash=0xae5c0427abc31345L)"watched image hash";
  check(canvas_hash=0x218d14f7afd656cdL)"canvas ordering hash";
  check(font_hash=0xa710632c411b1aa9L)"font density hash";
  let expected_frame=0xc07782b19c579525L in
  run_target Prismel_next_execution.Headless watched expected_frame;
  run_target Prismel_next_execution.Web watched expected_frame;
  run_target Prismel_next_execution.Native watched expected_frame;
  let assets=Assets.create()and order=ref[]in
  ignore(resource(Assets.borrow assets~destroy:(fun()->order:="image"::!order;Image.destroy watched)watched));
  ignore(resource(Assets.borrow assets~destroy:(fun()->order:="canvas"::!order;Canvas.destroy canvas)canvas));
  ignore(resource(Assets.borrow assets~destroy:(fun()->order:="audio"::!order;Audio.destroy audio)audio));
  ignore(resource(Assets.borrow assets~destroy:(fun()->order:="sample"::!order;Audio.destroy_sample sample)sample));
  resource(Assets.destroy assets);check(!order=["image";"canvas";"audio";"sample"])"borrowed teardown order";
  resource(Image.destroy capture);resource(Text.destroy text1);resource(Text.destroy text2);resource(Font.destroy font);
  List.iter Sys.remove[red_path;green_path;bad]
