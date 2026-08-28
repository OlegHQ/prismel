let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let metal = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
let rss_kib () = let argv=[|"/bin/ps";"-o";"rss=";"-p";string_of_int(Unix.getpid())|]in let input=Unix.open_process_args_in argv.(0)argv in Fun.protect~finally:(fun()->ignore(Unix.close_process_in input))(fun()->int_of_string(String.trim(input_line input)))
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
  let before=metal(Metal.Release_queue.stats())and started=Unix.gettimeofday()in
  let width=ref 64 and height=ref 48 and frame=ref 0 and rolling=ref 0L in
  let runtime=get(Runtime_next.create~width:!width~height:!height)in
  let expected_pipeline_cache=(Runtime_next.stats runtime).pipeline_cache_entries in
  let samples=Array.make 256 None and observations=ref 0 and last_sample=ref(started-.1.)in
  while Unix.gettimeofday()-.started < !minutes*.60. do
    incr frame;
    if !resizing&& !frame mod 300=0 then begin width:=if !width=64 then 80 else 64;height:=if !height=48 then 60 else 48;get(Runtime_next.resize runtime~width:!width~height:!height)end;
    ignore(get(Runtime_next.render~clear:(0.,0.,0.,1.)runtime[draw(if !changing_payload then !frame else 0)!width !height]));
    if !frame mod 600=0 then begin
      if !capturing then begin let facts=Runtime_next.frame_facts runtime in let pixels=get(Runtime_next.read_pixels runtime~bytes_per_row:(facts.drawable_width*4))in rolling:=Int64.logxor(Int64.mul !rolling 1099511628211L)(Int64.of_int(Hashtbl.hash pixels))end;
      let now=Unix.gettimeofday()in
      if now-. !last_sample>=1. then begin
        last_sample:=now;
        Gc.full_major();
        ignore(metal(Metal.Release_queue.drain()));
        let stats=Runtime_next.stats runtime and handles=metal(Metal.Release_queue.stats())and gc=Gc.quick_stat()in
        samples.(!observations mod 256)<-Some(`Assoc["elapsed",`Float(now-.started);"frame",`Int !frame;"rss_kib",`Int(rss_kib());"heap_words",`Int gc.heap_words;"live_words",`Int gc.live_words;"mesh_cache",`Int stats.mesh_cache_entries;"pipeline_cache",`Int stats.pipeline_cache_entries;"metal_live",`Int handles.live_handles;"metal_pending",`Int handles.pending;"metal_created",`Intlit(Int64.to_string handles.total_created);"metal_released",`Intlit(Int64.to_string handles.total_released);"resident_bytes",`Intlit(Int64.to_string handles.resident_bytes)]);incr observations
      end
    end
  done;
  let expected_mesh_cache=if !changing_payload then 64 else 1 in
  let live=Runtime_next.stats runtime in if live.mesh_cache_entries<>expected_mesh_cache||live.pipeline_cache_entries<>expected_pipeline_cache then failwith(Printf.sprintf"native cache bound: mesh=%d expected=%d pipeline=%d expected=%d"live.mesh_cache_entries expected_mesh_cache live.pipeline_cache_entries expected_pipeline_cache);
  get(Runtime_next.destroy runtime);ignore(metal(Metal.Release_queue.drain()));
  let dead=Runtime_next.stats runtime and after=metal(Metal.Release_queue.stats())in
  if dead.mesh_cache_entries<>0||dead.pipeline_cache_entries<>0||after.live_handles<>before.live_handles then failwith(Printf.sprintf"native teardown delta mesh=%d pipeline=%d handles=%d->%d"dead.mesh_cache_entries dead.pipeline_cache_entries before.live_handles after.live_handles);
  let length=min !observations 256 and start=if !observations<=256 then 0 else !observations mod 256 in
  let retained=List.init length(fun offset->match samples.((start+offset)mod 256)with Some value->value|None->assert false)in
  let rss sample=match sample with `Assoc fields->(match List.assoc_opt"rss_kib"fields with Some(`Int value)->value|_->assert false)|_->assert false in
  let first_half,second_half=let half=length/2 in List.filteri(fun i _->i<half)retained,List.filteri(fun i _->i>=half)retained in
  let maximum values=List.fold_left(fun high sample->max high(rss sample))0 values in
  let first_high=maximum first_half and second_high=maximum second_half in
  let plateau_slack_kib=8192 in
  if length=256&&second_high>first_high+plateau_slack_kib then failwith(Printf.sprintf"native settled RSS high-water grew: %d -> %d KiB"first_high second_high);
  let json=`Assoc["schema",`Int 3;"minutes",`Float !minutes;"changing_payload",`Bool !changing_payload;"resizing",`Bool !resizing;"capturing",`Bool !capturing;"frames",`Int !frame;"hash",`String(Printf.sprintf"%016Lx" !rolling);"observations",`Int !observations;"retained",`Int length;"samples",`List retained;"settled_rss_first_half_high_kib",`Int first_high;"settled_rss_second_half_high_kib",`Int second_high;"settled_rss_plateau_slack_kib",`Int plateau_slack_kib;"live_mesh_cache_peak_bound",`Int expected_mesh_cache;"pipeline_cache_live_expected",`Int expected_pipeline_cache;"live_mesh_cache_final",`Int dead.mesh_cache_entries;"pipeline_cache_final",`Int dead.pipeline_cache_entries;"metal_live_before",`Int before.live_handles;"metal_live_after",`Int after.live_handles]in
  let text=Yojson.Safe.pretty_to_string json^"\n"in match !report with None->print_string text|Some path->let channel=open_out_bin path in output_string channel text;close_out channel
