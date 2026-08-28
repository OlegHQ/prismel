open Prismel_next_api

type target=Native|Headless|Web
type scenario=Basic|Pxui|Canvas|Scene3|All
let target=ref Headless and scenario=ref All and minutes=ref 30.
and frames=ref None and sample_every=ref 10. and report=ref None
let target_name=function Native->"native"|Headless->"headless"|Web->"web"
let scenario_name=function Basic->"basic"|Pxui->"pxui"|Canvas->"canvas"|Scene3->"scene3"|All->"all"
let rss_kib()=
  let argv=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|]in
  let input=Unix.open_process_args_in argv.(0)argv in
  Fun.protect~finally:(fun()->ignore(Unix.close_process_in input))
    (fun()->int_of_string(String.trim(input_line input)))
let fnv hash value=Int64.logxor(Int64.mul hash 0x100000001b3L)(Int64.of_int value)
let color frame=if frame land 1=0 then Color.rgb 32 96 192 else Color.rgb 192 96 32
let camera=Camera.perspective~at:(Vec3.create 0. 0. 4.)~target:Vec3.zero()
let pxui frame=List.init 64(fun index->Scene.rect~at:((index mod 8)*8,(index/8)*8)
  ~w:7~h:7~fill:(color(frame+index))())
let get=function Ok value->value|Error message->failwith message
let ppm path(r,g,b)=let ch=open_out_bin path in
  Fun.protect~finally:(fun()->close_out ch)(fun()->output_string ch"P6\n2 2\n255\n";
    for _=1 to 4 do output_char ch(Char.chr r);output_char ch(Char.chr g);output_char ch(Char.chr b)done)

type model={
  assets:Assets.t;image:Image.t;canvas:Canvas.t;
  mutable sample:Audio.Sample.t option;
  mutable frame:int;started:float;mutable next_sample:float;
  samples:Yojson.Safe.t option array;mutable observations:int;
  mutable rolling:int64;mutable checkpoints:(int*string)list;
  mutable created:int;mutable destroyed:int;mutable peak_live:int;
  mutable canvas_cycles:int;mutable reload_cycles:int;mutable failed_reload_cycles:int;
  mutable audio_cycles:int;mutable resize_cycles:int;mutable changing_mesh_frames:int;
  red:string;blue:string
}
let created model= model.created<-model.created+1;
  model.peak_live<-max model.peak_live(model.created-model.destroyed)
let destroyed model=model.destroyed<-model.destroyed+1
let lane model=match!scenario with
  |All->(match model.frame mod 4 with 0->Basic|1->Pxui|2->Canvas|_->Scene3)
  |value->value
let sample model elapsed=
  let gc=Gc.quick_stat()and live=model.created-model.destroyed in
  let runtime=Runtime_diagnostics.snapshot()in
  model.samples.(model.observations mod 256)<-Some(`Assoc[
    "frame",`Int model.frame;"elapsed_seconds",`Float elapsed;
    "rss_kib",`Int(rss_kib());"heap_words",`Int gc.heap_words;
    "resource_count",`Int live;"runtime_resource_count",`Int runtime.resource_count;
    "cache_entries",`Int runtime.cache_entries;
    "release_queue_pending",(match runtime.release_queue_pending with None->`Null|Some n->`Int n)]);
  model.observations<-model.observations+1;
  model.next_sample<-elapsed+. !sample_every
let update model _=
  model.frame<-model.frame+1;let frame=model.frame in
  if frame mod 120=0 then begin
    let side=if(frame/120)land 1=0 then 64 else 80 in
    Sketch.resize~width:side~height:side;model.resize_cycles<-model.resize_cycles+1
  end;
  if frame mod 90=0 then begin
    let identity=Image.Private.identity model.image
    and generation=Image.Private.generation model.image in
    get(Image.Private.reload model.image(if(frame/90)land 1=0 then model.red else model.blue));
    if Image.Private.identity model.image<>identity||
       Image.Private.generation model.image<>generation+1
    then failwith"watched reload identity/generation failure";
    model.reload_cycles<-model.reload_cycles+1
  end;
  if frame mod 450=0 then begin
    let generation=Image.Private.generation model.image in
    if Result.is_ok(Image.Private.reload model.image"/definitely/missing/prismel-r12")||
       Image.Private.generation model.image<>generation
    then failwith"failed reload changed retained image";
    model.failed_reload_cycles<-model.failed_reload_cycles+1
  end;
  if frame mod 30=0 then begin
    let transient=Canvas.create_exn~width:(8+frame mod 9)~height:(8+frame mod 7)in
    created model;Canvas.render transient[Scene.clear(color frame)];
    let copy=get(Canvas.to_image transient)in created model;
    Image.destroy copy;destroyed model;Canvas.destroy transient;destroyed model;
    model.canvas_cycles<-model.canvas_cycles+1
  end;
  if frame mod 180=0 then begin
    Option.iter(fun old->Audio.Sample.destroy old;destroyed model)model.sample;
    let value=get(Audio.Sample.synth~waveform:Audio.Sample.Sine~frequency:220.
      ~duration:0.01())in
    created model;let channel=get(Audio.Sample.play value)in Audio.Sample.stop channel;
    model.sample<-Some value;model.audio_cycles<-model.audio_cycles+1
  end;
  let selected=lane model in
  model.rolling<-fnv(fnv model.rolling frame)
    (match selected with Basic->1|Pxui->2|Canvas->3|Scene3->4|All->0);
  if List.mem frame[1;2;60;600]then
    model.checkpoints<-(frame,Printf.sprintf"%016Lx"model.rolling)::model.checkpoints;
  let elapsed=Unix.gettimeofday()-.model.started in
  if elapsed>=model.next_sample then sample model elapsed;
  let finished=match!frames with Some limit->frame>=limit|None->elapsed>= !minutes*.60. in
  if finished then Sketch.quit();model
let view model _=match lane model with
  |Basic->[Scene.clear(Color.rgb 8 16 24);
    Scene.circle~at:(32,32)~radius:18~fill:(color model.frame)()]
  |Pxui->Scene.clear(Color.rgb 8 16 24)::pxui model.frame
  |Canvas->[Scene.clear Color.black;Scene.image model.image~at:(24,24)()]
  |Scene3->
    model.changing_mesh_frames<-model.changing_mesh_frames+1;
    let width=1.25+.float(model.frame mod 31)/.100. in
    let mesh=Mesh.box~width~height:1.5~depth:1.5()in
    [Scene.clear(Color.rgb 8 16 24);
     Scene.view3d~camera(Scene3.create[Scene3.mesh mesh])]
  |All->assert false
let stop model=
  Option.iter(fun value->Audio.Sample.destroy value;destroyed model)model.sample;
  model.sample<-None;Audio.shutdown();destroyed model;
  Canvas.destroy model.canvas;destroyed model;
  Assets.destroy model.assets;destroyed model

let ()=
  Arg.parse[
    "--target",Arg.Symbol(["native";"headless";"web"],function
      |"native"->target:=Native|"headless"->target:=Headless|_->target:=Web),"target";
    "--scenario",Arg.Symbol(["basic";"pxui";"canvas";"scene3";"all"],function
      |"basic"->scenario:=Basic|"pxui"->scenario:=Pxui|"canvas"->scenario:=Canvas
      |"scene3"->scenario:=Scene3|_->scenario:=All),"scenario";
    "--minutes",Arg.Set_float minutes,"duration (default 30)";
    "--frames",Arg.Int(fun n->frames:=Some n),"short deterministic frame limit";
    "--sample-every",Arg.Set_float sample_every,"RSS sampling period in seconds";
    "--report",Arg.String(fun path->report:=Some path),"JSON report"]
    (fun value->raise(Arg.Bad value))"R12 final-facade stability";
  if !minutes<=0.|| !sample_every<=0.||
     Option.fold~none:false~some:(fun n->n<600)!frames
  then invalid_arg"positive duration, sample period, and at least 600 frames required";
  Unix.putenv"PRISMEL_RENDER_TARGET"(target_name!target);
  let release_before=match!target with
    |Native->Runtime_diagnostics.native_release_queue()
    |Headless|Web->None in
  let red=Filename.temp_file"prismel-r12-red-"".ppm"
  and blue=Filename.temp_file"prismel-r12-blue-"".ppm"in
  ppm red(255,0,0);ppm blue(0,0,255);
  let started=Unix.gettimeofday()in
  let final=Fun.protect~finally:(fun()->Sys.remove red;Sys.remove blue)(fun()->
    Sketch.run_state
      ~config:{Sketch.default_config with width=64;height=64;fps=Some 120;
        clock=Fixed(1./.120.);resizable=true}
      ~max_frames:(Option.value !frames ~default:max_int)
      ~init:(fun _->
        let assets=Assets.create~root:(Filename.dirname red)~watch:true()in
        let image=Assets.image_exn assets(Filename.basename red)in
        let canvas=Canvas.create_exn~width:16~height:16 in
        Canvas.render canvas[Scene.clear(Color.rgb 20 40 80)];
        get(Audio.init());
        {assets;image;canvas;sample=None;frame=0;started;next_sample=0.;
         samples=Array.make 256 None;observations=0;rolling=0xcbf29ce484222325L;
         checkpoints=[];created=3;destroyed=0;peak_live=3;canvas_cycles=0;
         reload_cycles=0;failed_reload_cycles=0;audio_cycles=0;resize_cycles=0;
         changing_mesh_frames=0;red;blue})
      ~update~view~on_stop:stop())in
  let retained=let n=min final.observations 256 in
    let start=if final.observations<=256 then 0 else final.observations mod 256 in
    List.init n(fun index->Option.get final.samples.((start+index)mod 256))in
  let runtime=Runtime_diagnostics.snapshot()in
  let release_after=match!target with
    |Native->Runtime_diagnostics.native_release_queue()
    |Headless|Web->None in
  let release_field select value=match value with None->`Null|Some stats->select stats in
  let output=`Assoc[
    "schema",`Int 1;"qualification",`String"R12-final-facade";
    "target",`String(target_name!target);"scenario",`String(scenario_name!scenario);
    "duration_seconds",`Float(Unix.gettimeofday()-.started);"frames",`Int final.frame;
    "checkpoints",`List(List.rev_map(fun(frame,hash)->`List[`Int frame;`String hash])final.checkpoints);
    "deterministic_hash",`String(Printf.sprintf"%016Lx"final.rolling);
    "sample_capacity",`Int 256;"sample_every_seconds",`Float!sample_every;
    "sample_observations",`Int final.observations;"samples",`List retained;
    "rss_limit_percent",`Float 5.;"created_resources",`Int final.created;
    "destroyed_resources",`Int final.destroyed;"peak_live_resources",`Int final.peak_live;
    "live_resources_after_teardown",`Int(final.created-final.destroyed);
    "window_live_after_teardown",`Bool runtime.active;
    "cache_entries_after_teardown",`Int runtime.cache_entries;
    "runtime_resources_after_teardown",`Int runtime.resource_count;
    "release_queue_pending_after_teardown",(match runtime.release_queue_pending with None->`Null|Some n->`Int n);
    "release_queue_counter_supported",`Bool(Option.is_some runtime.release_queue_pending);
    "metal_live_handles_before",release_field(fun x->`Int x.Runtime_diagnostics.live_handles)release_before;
    "metal_live_handles_after",release_field(fun x->`Int x.Runtime_diagnostics.live_handles)release_after;
    "metal_total_created_before",release_field(fun x->`Intlit(Int64.to_string x.Runtime_diagnostics.total_created))release_before;
    "metal_total_created_after",release_field(fun x->`Intlit(Int64.to_string x.Runtime_diagnostics.total_created))release_after;
    "metal_total_released_before",release_field(fun x->`Intlit(Int64.to_string x.Runtime_diagnostics.total_released))release_before;
    "metal_total_released_after",release_field(fun x->`Intlit(Int64.to_string x.Runtime_diagnostics.total_released))release_after;
    "canvas_cycles",`Int final.canvas_cycles;"watched_reload_cycles",`Int final.reload_cycles;
    "failed_reload_cycles",`Int final.failed_reload_cycles;"audio_cycles",`Int final.audio_cycles;
    "resize_cycles",`Int final.resize_cycles;"changing_mesh_frames",`Int final.changing_mesh_frames]in
  let text=Yojson.Safe.pretty_to_string output^"\n"in
  match!report with None->print_string text|Some path->
    let ch=open_out_bin path in
    Fun.protect~finally:(fun()->close_out ch)(fun()->output_string ch text)
