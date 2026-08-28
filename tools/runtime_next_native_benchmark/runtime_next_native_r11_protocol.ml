let command_output program arguments=
  let input=Unix.open_process_args_in program arguments and contents=Buffer.create 128 in
  let rec read()=match input_line input with line->Buffer.add_string contents line;Buffer.add_char contents '\n';read()|exception End_of_file->()in
  read();match Unix.close_process_in input with Unix.WEXITED 0->Some(String.trim(Buffer.contents contents))|_->None
let clean_commit()=match command_output"git"[|"git";"rev-parse";"HEAD"|],
  command_output"git"[|"git";"status";"--porcelain=v1";"--untracked-files=all"|]with
  |Some commit,Some""->commit|Some _,Some _->failwith"R11 protocol requires a clean source tree"
  |_->failwith"R11 protocol could not capture source state"
let validate_actual_report ~run ~sketch ~artifact report=
  let open Yojson.Safe.Util in
  let json=Yojson.Safe.from_file report in
  if json|>member"schema"|>to_int<>2 then
    failwith(Printf.sprintf"R11 child %d report schema is not actual-sketch v2"run);
  let provenance=member"r11_sketch_invocation"json in
  let require label expected actual = if actual<>expected then
    failwith(Printf.sprintf"R11 child %d %s provenance mismatch: expected %S, got %S"run label expected actual)in
  require"status""actual-sketch-cooked-and-rendered"(provenance|>member"status"|>to_string);
  require"evidence class""candidate"(provenance|>member"evidence_class"|>to_string);
  require"invoked executable"sketch(provenance|>member"invoked_executable"|>to_string);
  require"measured executable"sketch(provenance|>member"measured_executable"|>to_string);
  require"artifact"artifact(provenance|>member"artifact"|>to_string);
  if provenance|>member"frozen_r11_closure"|>to_bool then
    failwith(Printf.sprintf"R11 child %d incorrectly claimed frozen R11 closure"run);
  let require_int label expected value=if value<>expected then
    failwith(Printf.sprintf"R11 child %d %s mismatch: expected %d, got %d"run label expected value)in
  require"backend""actual-sketch-runtime-next-metal"(json|>member"backend"|>to_string);
  let visibility=json|>member"visibility"|>to_string in
  if (json|>member"observed_visible"|>to_bool)<>(visibility="visible")then
    failwith(Printf.sprintf"R11 child %d observed visibility mismatch"run);
  require_int"width"1200(json|>member"width"|>to_int);
  require_int"height"760(json|>member"height"|>to_int);
  require_int"pieces"18_278(json|>member"pieces"|>to_int);
  require_int"triangles"278_368(json|>member"triangles"|>to_int);
  require_int"render vertices"835_104(json|>member"render_vertices"|>to_int);
  require"prepared upload bytes""60127488"(json|>member"prepared_upload_bytes"|>to_string);
  if json|>member"measurement_upload_bytes"|>to_string<>"0"then
    failwith(Printf.sprintf"R11 child %d performed replacement upload"run);
  let frames=json|>member"sample_frames"|>to_int in
  if frames<=0 then failwith(Printf.sprintf"R11 child %d measured no frames"run);
  List.iter(fun label->require_int label frames(json|>member label|>to_int))
    ["draws";"passes";"backend_calls"];
  if json|>member"cache_entries"|>to_int<>1 then
    failwith(Printf.sprintf"R11 child %d did not retain exactly one mesh cache entry"run);
  let cook=json|>member"acceptance_cook"in
  List.iter(fun(label,expected)->require label expected(cook|>member label|>to_string))[
    "topology_hash","f7df96ba5de50db4f964caa418ac4a90";
    "attribute_hash","a34503939b89dcd5f6d8503f58b3fd8d";
    "order_hash","2a4f0c8756d6abc4c0f8cec85c10dc10";
    "render_hash","681eacdabdce457de462c3f4fc01a761"];
  let gpu=json|>member"native_gpu_counters"in
  match gpu|>member"status"|>to_string with
  |"measured"->if not(gpu|>member"supported"|>to_bool)then
      failwith(Printf.sprintf"R11 child %d has inconsistent measured GPU status"run)
  |"unsupported"->
      if gpu|>member"supported"|>to_bool||gpu|>member"gpu_duration"<>`Null||
         gpu|>member"gpu_utilization"<>`Null then
        failwith(Printf.sprintf"R11 child %d fabricated unsupported GPU counters"run)
  |status->failwith(Printf.sprintf"R11 child %d unknown GPU counter status %S"run status)
let ()=
  let sketch=ref None and benchmark=ref None and artifact=ref None and output_dir=ref None
  and validate_only=ref None and visibility=ref"hidden"and seconds=ref 30. and runs=ref 5 in
  Arg.parse["--sketch",Arg.String(fun x->sketch:=Some x),"sketches/shattered_cube/main.exe";"--benchmark",Arg.String(fun x->benchmark:=Some x),"deprecated compatibility argument; actual sketch is measured";"--artifact",Arg.String(fun x->artifact:=Some x),"acceptance artifact";"--output-dir",Arg.String(fun x->output_dir:=Some x),"report directory";"--validate-only",Arg.String(fun x->validate_only:=Some x),"validate one existing report without running";"--visibility",Arg.Symbol(["visible";"hidden"],fun x->visibility:=x),"mode";"--seconds",Arg.Set_float seconds,"sample duration";"--runs",Arg.Set_int runs,"sample count"]ignore"runtime_next_native_r11_protocol";
  if !seconds <= 0. || !runs <= 0 then invalid_arg"positive protocol counts required";
  let sketch=Option.get!sketch and artifact=Option.get!artifact in
  (match!validate_only with Some report->validate_actual_report~run:1~sketch~artifact report;exit 0|None->());
  let benchmark=Option.value!benchmark~default:sketch in
  let output_dir=Option.get!output_dir in
  let commit=clean_commit()in
  for run=1 to!runs do
    let report=Filename.concat output_dir(Printf.sprintf"shattered-%s-%02d.json"!visibility run)in
    let arguments=[|sketch;"--r11-renderer";benchmark;"--r11-artifact";artifact;"--r11-visibility";!visibility;"--r11-seconds";string_of_float!seconds;"--r11-report";report|]in
    let pid=Unix.create_process sketch arguments Unix.stdin Unix.stdout Unix.stderr in
    (match snd(Unix.waitpid[]pid)with Unix.WEXITED 0->()|WEXITED code->failwith(Printf.sprintf"R11 child %d exited %d"run code)|WSIGNALED signal|WSTOPPED signal->failwith(Printf.sprintf"R11 child %d signaled %d"run signal));
    validate_actual_report~run~sketch~artifact report;
    if clean_commit()<>commit then failwith(Printf.sprintf"R11 source changed after child %d"run)
  done
