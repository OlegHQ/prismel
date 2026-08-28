let sample index=`Assoc["frame",`Int(index*100+1);"elapsed_seconds",`Float(float(index*10));"rss_kib",`Int 1000;"heap_words",`Int 1;"resource_count",`Int 2]
let report ?(scenario="all")?(checkpoints=[1;2;60;600])?(created=2)?(destroyed=2)
    ?(ordered=true)?(period=10.)?(rss_limit=5.)?(stale=false)?(metal_balanced=true) target=
  let samples=List.init 181 sample in
  let samples=if stale then List.map(function `Assoc fields->`Assoc(List.map(function
    |"elapsed_seconds",`Float value->"elapsed_seconds",`Float(value-.100.)|field->field)fields)|x->x)samples else samples in
  let samples=if ordered then samples else List.rev samples in
  let native=target="native"in
  `Assoc["schema",`Int 1;"qualification",`String"R12-final-facade";"target",`String target;"scenario",`String scenario;
    "duration_seconds",`Float 1800.;"frames",`Int 10000;"checkpoints",`List(List.map(fun frame->`List[`Int frame;`String"0123456789abcdef"])checkpoints);
    "deterministic_hash",`String"fedcba9876543210";"sample_capacity",`Int 256;"sample_every_seconds",`Float period;
    "sample_observations",`Int 181;"samples",`List samples;"rss_limit_percent",`Float rss_limit;"created_resources",`Int created;
    "destroyed_resources",`Int destroyed;"live_resources_after_teardown",`Int 0;"window_live_after_teardown",`Bool false;
    "cache_entries_after_teardown",`Int 0;"runtime_resources_after_teardown",`Int 0;
    "release_queue_pending_after_teardown",(if native then`Int 0 else`Null);
    "release_queue_counter_supported",`Bool native;
    "metal_live_handles_before",(if native then`Int 4 else`Null);
    "metal_live_handles_after",(if native then`Int(if metal_balanced then 4 else 5)else`Null);
    "metal_total_created_before",(if native then`Intlit"10"else`Null);
    "metal_total_created_after",(if native then`Intlit"14"else`Null);
    "metal_total_released_before",(if native then`Intlit"6"else`Null);
    "metal_total_released_after",(if native then`Intlit"10"else`Null);
    "canvas_cycles",`Int 1;"watched_reload_cycles",`Int 1;
    "failed_reload_cycles",`Int 1;"audio_cycles",`Int 1;"resize_cycles",`Int 1;"changing_mesh_frames",`Int 1]
let run validator args expected=
  let command=String.concat" "(Filename.quote validator::List.map Filename.quote args)^" >/dev/null 2>&1"in
  if (Sys.command command=0)<>expected then failwith("unexpected validator result: "^command)
let write directory name json=let path=Filename.concat directory name in Yojson.Safe.to_file path json;path
let ()=let validator=Sys.argv.(1)and directory=Filename.get_temp_dir_name()in
  let native=write directory"r12-validator-native.json"(report"native")and headless=write directory"r12-validator-headless.json"(report"headless")and web=write directory"r12-validator-web.json"(report"web")in
  run validator["--complete-set";native;headless;web]true;
  run validator[write directory"r12-bad-scenario.json"(report~scenario:"basic""native")]false;
  run validator[write directory"r12-bad-checkpoints.json"(report~checkpoints:[2;1;60;600]"native")]false;
  run validator[write directory"r12-bad-order.json"(report~ordered:false"native")]false;
  run validator[write directory"r12-bad-owner.json"(report~created:2~destroyed:1"native")]false;
  run validator[write directory"r12-stale-ring.json"(report~stale:true"native")]false;
  run validator[write directory"r12-period-drift.json"(report~period:9."native")]false;
  run validator[write directory"r12-policy-drift.json"(report~rss_limit:6."native")]false;
  run validator[write directory"r12-metal-leak.json"(report~metal_balanced:false"native")]false;
  run validator["--complete-set";native;headless;headless]false;
  List.iter(fun path->try Sys.remove path with Sys_error _->())[native;headless;web];
  print_endline"R12 validator positive/negative fixtures passed"
