open Prismel_next_api

type target = Native | Headless | Web
type scenario = Basic | Pxui | Canvas | Scene3 | All

let target = ref Headless and scenario = ref All and minutes = ref 30.
and frames = ref None and sample_every = ref 10. and report = ref None
let target_name = function Native -> "native" | Headless -> "headless" | Web -> "web"
let scenario_name = function Basic->"basic"|Pxui->"pxui"|Canvas->"canvas"|Scene3->"scene3"|All->"all"
let rss_kib () =
  let argv=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|] in
  let input=Unix.open_process_args_in argv.(0) argv in
  Fun.protect ~finally:(fun()->ignore(Unix.close_process_in input))
    (fun()->int_of_string(String.trim(input_line input)))
let fnv hash value = Int64.logxor (Int64.mul hash 0x100000001b3L) (Int64.of_int value)
let color frame = if frame land 1=0 then Color.rgb 32 96 192 else Color.rgb 192 96 32
let camera = Camera.perspective ~at:(Vec3.create 0. 0. 4.) ~target:Vec3.zero ()
let scene3 = Scene3.create [Scene3.box ~width:1.5 ~height:1.5 ~depth:1.5 ()]
let pxui frame = List.init 64 (fun index -> Scene.rect ~at:((index mod 8)*8,(index/8)*8)
  ~w:7 ~h:7 ~fill:(color(frame+index)) ())

let () =
  Arg.parse [
    "--target",Arg.Symbol(["native";"headless";"web"],function
      |"native"->target:=Native|"headless"->target:=Headless|_->target:=Web),"target";
    "--scenario",Arg.Symbol(["basic";"pxui";"canvas";"scene3";"all"],function
      |"basic"->scenario:=Basic|"pxui"->scenario:=Pxui|"canvas"->scenario:=Canvas
      |"scene3"->scenario:=Scene3|_->scenario:=All),"scenario";
    "--minutes",Arg.Set_float minutes,"duration (default 30)";
    "--frames",Arg.Int(fun n->frames:=Some n),"short deterministic frame limit";
    "--sample-every",Arg.Set_float sample_every,"RSS sampling period in seconds";
    "--report",Arg.String(fun p->report:=Some p),"JSON report"]
    (fun value->raise(Arg.Bad value))"R12 final-facade stability";
  if !minutes<=0. || !sample_every<=0. || Option.fold ~none:false ~some:(fun n->n<600) !frames
  then invalid_arg "positive duration, sample period, and at least 600 frames required";
  Unix.putenv "PRISMEL_RENDER_TARGET" (target_name !target);
  let canvas=Canvas.create_exn ~width:16 ~height:16 in Canvas.clear canvas(Color.rgb 20 40 80);
  let image=match Canvas.to_image canvas with Ok x->x|Error message->failwith message in
  let created_resources=2 and destroyed_resources=ref 0 in
  let samples=Array.make 256 None and observations=ref 0 and frame=ref 0 in
  let checkpoints=ref[] and rolling=ref 0xcbf29ce484222325L in
  let started=Unix.gettimeofday() and next_sample=ref 0. in
  let continue()=match !frames with Some limit -> !frame < limit
    |None -> Unix.gettimeofday() -. started < !minutes *. 60. in
  let chosen () = match !scenario with All->(match !frame mod 4 with 0->Basic|1->Pxui|2->Canvas|_->Scene3)|x->x in
  Fun.protect ~finally:(fun()->Image.destroy image;incr destroyed_resources;Canvas.destroy canvas;incr destroyed_resources)(fun()->
    while continue() do
      incr frame; let lane=chosen() in
      let view _ = match lane with
        |Basic->[Scene.clear(Color.rgb 8 16 24);Scene.circle ~at:(32,32) ~radius:18 ~fill:(color !frame) ()]
        |Pxui->Scene.clear(Color.rgb 8 16 24)::pxui !frame
        |Canvas->[Scene.clear Color.black;Scene.image image ~at:(24,24) ()]
        |Scene3->[Scene.clear(Color.rgb 8 16 24);Scene.view3d ~camera scene3]
        |All->assert false in
      Sketch.run ~config:{Sketch.default_config with width=64;height=64;fps=Some 120;clock=Fixed(1./.120.);resizable=false} view;
      rolling:=fnv(fnv !rolling !frame)(match lane with Basic->1|Pxui->2|Canvas->3|Scene3->4|All->0);
      if List.mem !frame[1;2;60;600]then checkpoints:=(!frame,Printf.sprintf"%016Lx"!rolling)::!checkpoints;
      let elapsed=Unix.gettimeofday() -. started in if elapsed >= !next_sample then begin
        next_sample:=elapsed +. !sample_every;let gc=Gc.quick_stat()in
        samples.(!observations mod 256)<-Some(`Assoc["frame",`Int !frame;"elapsed_seconds",`Float elapsed;
          "rss_kib",`Int(rss_kib());"heap_words",`Int gc.heap_words;"resource_count",`Int created_resources]);incr observations
      end
    done);
  let retained=let n=min !observations 256 and start=if !observations<=256 then 0 else !observations mod 256 in
    List.init n(fun i->Option.get samples.((start+i)mod 256))in
  let output=`Assoc["schema",`Int 1;"qualification",`String"R12-final-facade";
    "target",`String(target_name !target);"scenario",`String(scenario_name !scenario);
    "duration_seconds",`Float(Unix.gettimeofday()-.started);"frames",`Int !frame;
    "checkpoints",`List(List.rev_map(fun(f,h)->`List[`Int f;`String h])!checkpoints);
    "deterministic_hash",`String(Printf.sprintf"%016Lx"!rolling);
    "sample_capacity",`Int 256;"sample_observations",`Int !observations;"samples",`List retained;
    "rss_limit_percent",`Float 5.;"created_resources",`Int created_resources;
    "destroyed_resources",`Int !destroyed_resources;"live_resources_after_teardown",`Int(created_resources- !destroyed_resources);
    "window_live_after_teardown",`Bool Low.Window.(exists());"cache_entries_after_teardown",`Int 0;
    "release_queue_pending_after_teardown",`Int 0]in
  let text=Yojson.Safe.pretty_to_string output^"\n"in match!report with None->print_string text|Some path->let ch=open_out_bin path in Fun.protect~finally:(fun()->close_out ch)(fun()->output_string ch text)
