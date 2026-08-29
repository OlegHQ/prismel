let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let metal = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
let rss_kib () = let argv=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|]in let input=Unix.open_process_args_in argv.(0)argv in Fun.protect~finally:(fun()->ignore(Unix.close_process_in input))(fun()->int_of_string(String.trim(input_line input)))
let command_output program arguments=
  let input=Unix.open_process_args_in program(Array.of_list(program::arguments))and output=Buffer.create 128 in
  (try while true do Buffer.add_string output(input_line input);Buffer.add_char output '\n'done with End_of_file->());
  match Unix.close_process_in input with Unix.WEXITED 0->Some(String.trim(Buffer.contents output))|_->None
let canonical_commit value=String.length value=40&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)value
let source_snapshot()=match command_output"git"["rev-parse";"HEAD"],command_output"git"["status";"--porcelain=v1";"--untracked-files=all"]with
  |Some commit,Some status when canonical_commit commit->Some(commit,status="")|_->None
let source_json=function None->`Null|Some(commit,clean)->`Assoc["commit",`String commit;"clean",`Bool clean]
let write_atomic path text postflight=
  let temporary,channel=Filename.open_temp_file~temp_dir:(Filename.dirname path)(Filename.basename path^".tmp-")".json"in
  Fun.protect~finally:(fun()->close_out_noerr channel;if Sys.file_exists temporary then Sys.remove temporary)(fun()->output_string channel text;flush channel;close_out channel;postflight();Sys.rename temporary path)
let mesh frame =
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  let shift=float(frame mod 17)/.128. and color=Int32.logor 0x000000FFl(Int32.shift_left(Int32.of_int(frame land 255))24)in
  List.iteri(fun index(x,y)->let offset=index*16 in Bytes.set_int32_le vertices offset(Int32.bits_of_float(x+.shift));Bytes.set_int32_le vertices(offset+4)(Int32.bits_of_float y);Bytes.set_int32_le vertices(offset+8)color)[-1.,1.;1.,1.;-1.,-1.];
  {Scene_execution.key=Printf.sprintf"churn-%02d"(frame mod 80);vertices;vertex_count=3;indices;index_count=3}
let draw frame width height=let inset=frame mod 3 in
  {Scene_execution.mesh=mesh frame;state={viewport=(0,0,width,height);
    scissor=(inset,inset,width-inset,height-inset);cull=Ogpu.Render_pass.Cull_none;
    depth_compare=Ogpu.Render_pass.Always;depth_write=false;
    depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;
    stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}}
let () =
  let minutes=ref 30. and report=ref None and changing_payload=ref true and resizing=ref true and capturing=ref true in
  Arg.parse["--minutes",Arg.Set_float minutes,"duration";"--report",Arg.String(fun value->report:=Some value),"JSON report";"--stable-payload",Arg.Clear changing_payload,"reuse one mesh payload";"--no-resize",Arg.Clear resizing,"disable resize churn";"--no-capture",Arg.Clear capturing,"disable readback churn"](fun value->raise(Arg.Bad value))"runtime_next_native_stability";
  if not(Float.is_finite !minutes)|| !minutes<=0. then invalid_arg"minutes";
  let qualification= !minutes>=30. in
  if qualification&&not(!changing_payload&& !resizing&& !capturing)then
    failwith"O6 qualification requires payload, resize, and capture churn";
  let source_before=source_snapshot()in
  if qualification && (match source_before with Some(_,true)->false|_->true)then failwith"O6 qualification requires a canonical clean source tree";
  let before=metal(Metal.Release_queue.stats())and started=Unix.gettimeofday()in
  let width=ref 64 and height=ref 48 and frame=ref 0 and rolling=ref 0L and resize_events=ref 0 and capture_events=ref 0 and captured_bytes=ref 0L in
  let runtime=get(Runtime_next.create~width:!width~height:!height())in
  let expected_pipeline_cache=(Runtime_next.stats runtime).pipeline_cache_entries in
  let samples=Array.make 256 None and observations=ref 0 and last_sample=ref(started-.1.)and last_allocated=ref(Gc.allocated_bytes())and last_created=ref before.total_created and last_released=ref before.total_released in
  while Unix.gettimeofday()-.started < !minutes*.60. do
    incr frame;
    if !resizing&& !frame mod 300=0 then begin width:=if !width=64 then 80 else 64;height:=if !height=48 then 60 else 48;incr resize_events;get(Runtime_next.resize runtime~width:!width~height:!height)end;
    ignore(get(Runtime_next.render~clear:(0.,0.,0.,1.)runtime[draw(if !changing_payload then !frame else 0)!width !height]));
    if !frame mod 600=0 then begin
      if !capturing then begin let facts=Runtime_next.frame_facts runtime in let pixels=get(Runtime_next.read_pixels runtime~bytes_per_row:(facts.drawable_width*4))in incr capture_events;captured_bytes:=Int64.add !captured_bytes(Int64.of_int(Bytes.length pixels));rolling:=Int64.logxor(Int64.mul !rolling 1099511628211L)(Int64.of_int(Hashtbl.hash pixels))end;
      let now=Unix.gettimeofday()in
      if now-. !last_sample>=1. then begin
        last_sample:=now;
        Gc.full_major();
        ignore(metal(Metal.Release_queue.drain()));
        let stats=Runtime_next.stats runtime and handles=metal(Metal.Release_queue.stats())and gc=Gc.quick_stat()and allocated=Gc.allocated_bytes()in
        let allocated_since_sample=allocated-. !last_allocated and created_since_sample=Int64.sub handles.total_created !last_created and released_since_sample=Int64.sub handles.total_released !last_released in
        last_allocated:=allocated;last_created:=handles.total_created;last_released:=handles.total_released;
        samples.(!observations mod 256)<-Some(`Assoc["observation",`Int(!observations+1);"elapsed",`Float(now-.started);"frame",`Int !frame;"rss_kib",`Int(rss_kib());"heap_words",`Int gc.heap_words;"live_words",`Int gc.live_words;"gc_allocated_bytes_since_sample",`Float allocated_since_sample;"mesh_cache",`Int stats.mesh_cache_entries;"pipeline_cache",`Int stats.pipeline_cache_entries;"runtime_uploaded_bytes",`Intlit(Int64.to_string stats.uploaded_bytes);"retained_plan_entries",`Int stats.retained_plan_entries;"retained_plan_capacity",`Int stats.retained_plan_capacity;"retained_plan_builds",`Intlit(Int64.to_string stats.retained_plan_builds);"retained_plan_hits",`Intlit(Int64.to_string stats.retained_plan_hits);"retained_plan_misses",`Intlit(Int64.to_string stats.retained_plan_misses);"retained_plan_evictions",`Intlit(Int64.to_string stats.retained_plan_evictions);"metal_live",`Int handles.live_handles;"metal_pending",`Int handles.pending;"metal_created",`Intlit(Int64.to_string handles.total_created);"metal_released",`Intlit(Int64.to_string handles.total_released);"metal_created_since_sample",`Intlit(Int64.to_string created_since_sample);"metal_released_since_sample",`Intlit(Int64.to_string released_since_sample);"resident_bytes",`Intlit(Int64.to_string handles.resident_bytes)]);incr observations
      end
    end
  done;
  (* [Runtime_next.stats.mesh_cache_entries] includes the Scene2 uniform cache.
     This workload cycles 80 mesh identities and one shared identity transform;
     the production cache is bounded at 256 mesh entries, so the exact settled
     cardinality is 80 + 1 rather than the historical 64-entry eviction value. *)
  let expected_mesh_cache=if !changing_payload then 81 else 2 in
  let live=Runtime_next.stats runtime in if live.mesh_cache_entries<>expected_mesh_cache||live.pipeline_cache_entries<>expected_pipeline_cache then failwith(Printf.sprintf"native cache bound: mesh=%d expected=%d pipeline=%d expected=%d"live.mesh_cache_entries expected_mesh_cache live.pipeline_cache_entries expected_pipeline_cache);
  let expected_plans=if !changing_payload then 80 else 1 in
  if live.retained_plan_capacity<>256||live.retained_plan_entries<>expected_plans||
     live.retained_plan_builds<>Int64.of_int expected_plans||
     live.retained_plan_misses<>Int64.of_int expected_plans||
     live.retained_plan_evictions<>0L then
    failwith(Printf.sprintf"native retained-plan bound: entries=%d/%d builds=%Ld misses=%Ld evictions=%Ld capacity=%d"live.retained_plan_entries expected_plans live.retained_plan_builds live.retained_plan_misses live.retained_plan_evictions live.retained_plan_capacity);
  get(Runtime_next.destroy runtime);ignore(metal(Metal.Release_queue.drain()));
  let dead=Runtime_next.stats runtime and after=metal(Metal.Release_queue.stats())in
  if dead.mesh_cache_entries<>0||dead.pipeline_cache_entries<>0||after.live_handles<>before.live_handles then failwith(Printf.sprintf"native teardown delta mesh=%d pipeline=%d handles=%d->%d"dead.mesh_cache_entries dead.pipeline_cache_entries before.live_handles after.live_handles);
  let length=min !observations 256 and start=if !observations<=256 then 0 else !observations mod 256 in
  let retained=List.init length(fun offset->match samples.((start+offset)mod 256)with Some value->value|None->assert false)in
  let rss sample=match sample with `Assoc fields->(match List.assoc_opt"rss_kib"fields with Some(`Int value)->value|_->assert false)|_->assert false in
  let resident sample=match sample with `Assoc fields->(match List.assoc_opt"resident_bytes"fields with Some(`Intlit value)->Int64.of_string value|Some(`Int value)->Int64.of_int value|_->assert false)|_->assert false in
  let first_half,second_half=let half=length/2 in List.filteri(fun i _->i<half)retained,List.filteri(fun i _->i>=half)retained in
  let maximum values=List.fold_left(fun high sample->max high(rss sample))0 values in
  let first_high=maximum first_half and second_high=maximum second_half in
  let plateau_slack_kib=8192 in
  if length=256&&second_high>first_high+plateau_slack_kib then failwith(Printf.sprintf"native settled RSS high-water grew: %d -> %d KiB"first_high second_high);
  let tail=List.filteri(fun index _->index>=length*3/4)retained in
  let tail_rss=List.map rss tail in
  let tail_low,tail_high=match tail_rss with []->let current=rss_kib()in current,current|first::rest->List.fold_left min first rest,List.fold_left max first rest in
  let tail_resident=List.map resident tail in
  let resident_low,resident_high=match tail_resident with []->after.resident_bytes,after.resident_bytes|first::rest->List.fold_left Int64.min first rest,List.fold_left Int64.max first rest in
  let rss_limit_percent=5. in
  let rss_range_percent=if tail_low<=0 then infinity else 100.*.float(tail_high-tail_low)/.float tail_low in
  let resident_range_percent=if resident_low<=0L then infinity else 100.*.Int64.to_float(Int64.sub resident_high resident_low)/.Int64.to_float resident_low in
  if qualification && (length<>256 || !observations<256)then failwith"O6 qualification requires the exact final 256-sample ring";
  if qualification && (rss_range_percent>rss_limit_percent || resident_range_percent>rss_limit_percent)then failwith(Printf.sprintf"O6 final-window RSS range %.3f%%/%.3f%% exceeds %.1f%%"rss_range_percent resident_range_percent rss_limit_percent);
  let source_after=source_snapshot()in
  let source_stable_clean=match source_before,source_after with Some(a,true),Some(b,true)->a=b|_->false in
  if qualification && not source_stable_clean then failwith"O6 qualification source changed during measurement";
  let created_delta=Int64.sub after.total_created before.total_created and released_delta=Int64.sub after.total_released before.total_released in
  let resident_teardown_limit=Int64.add resident_high(Int64.div resident_high 20L)in
  if qualification && (after.pending<>0 || created_delta<>released_delta || after.resident_bytes>resident_teardown_limit)then failwith"O6 qualification teardown counters did not settle";
  let json=`Assoc["schema",`Int 5;"qualification",`String(if qualification then"O6-native-30m"else"smoke");"source_before",source_json source_before;"source_after",source_json source_after;"source_stable_clean",`Bool source_stable_clean;"minutes",`Float !minutes;"changing_payload",`Bool !changing_payload;"resizing",`Bool !resizing;"resize_events",`Int !resize_events;"capturing",`Bool !capturing;"capture_events",`Int !capture_events;"captured_bytes",`Intlit(Int64.to_string !captured_bytes);"frames",`Int !frame;"hash",`String(Printf.sprintf"%016Lx" !rolling);"sample_capacity",`Int 256;"observations",`Int !observations;"retained",`Int length;"samples",`List retained;"rss_limit_percent",`Float rss_limit_percent;"final_window_rss_low_kib",`Int tail_low;"final_window_rss_high_kib",`Int tail_high;"final_window_rss_range_percent",`Float rss_range_percent;"settled_rss_first_half_high_kib",`Int first_high;"settled_rss_second_half_high_kib",`Int second_high;"settled_rss_plateau_slack_kib",`Int plateau_slack_kib;"live_mesh_cache_peak_bound",`Int expected_mesh_cache;"pipeline_cache_live_expected",`Int expected_pipeline_cache;"retained_plan_capacity_expected",`Int 256;"retained_plan_entries_live_expected",`Int expected_plans;"retained_plan_entries_final",`Int dead.retained_plan_entries;"retained_plan_builds",`Intlit(Int64.to_string live.retained_plan_builds);"retained_plan_hits",`Intlit(Int64.to_string live.retained_plan_hits);"retained_plan_misses",`Intlit(Int64.to_string live.retained_plan_misses);"retained_plan_evictions",`Intlit(Int64.to_string live.retained_plan_evictions);"live_mesh_cache_final",`Int dead.mesh_cache_entries;"pipeline_cache_final",`Int dead.pipeline_cache_entries;"metal_pending_final",`Int after.pending;"metal_live_before",`Int before.live_handles;"metal_live_after",`Int after.live_handles;"metal_created_delta",`Intlit(Int64.to_string created_delta);"metal_released_delta",`Intlit(Int64.to_string released_delta);"metal_resident_bytes_before",`Intlit(Int64.to_string before.resident_bytes);"metal_resident_bytes_after",`Intlit(Int64.to_string after.resident_bytes)]in
  let text=Yojson.Safe.pretty_to_string json^"\n"in match !report with None->print_string text|Some path->write_atomic path text(fun()->if qualification then match source_snapshot()with Some(commit,true)when source_before=Some(commit,true)->()|_->failwith"O6 source changed before atomic publication")
