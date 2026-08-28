let command_output program arguments=
  let input=Unix.open_process_args_in program arguments and contents=Buffer.create 128 in
  let rec read()=match input_line input with line->Buffer.add_string contents line;Buffer.add_char contents '\n';read()|exception End_of_file->()in
  read();match Unix.close_process_in input with Unix.WEXITED 0->Some(String.trim(Buffer.contents contents))|_->None
let clean_commit()=match command_output"git"[|"git";"rev-parse";"HEAD"|],
  command_output"git"[|"git";"status";"--porcelain=v1";"--untracked-files=all"|]with
  |Some commit,Some""->commit|Some _,Some _->failwith"R11 protocol requires a clean source tree"
  |_->failwith"R11 protocol could not capture source state"
let validate_precursor_report ~run ~sketch ~benchmark ~artifact report=
  let open Yojson.Safe.Util in
  let json=Yojson.Safe.from_file report in
  let provenance=member"r11_sketch_invocation"json in
  let require label expected actual = if actual<>expected then
    failwith(Printf.sprintf"R11 child %d %s provenance mismatch: expected %S, got %S"run label expected actual)in
  require"status""graph-validated-renderer-delegated"(provenance|>member"status"|>to_string);
  require"evidence class""precursor"(provenance|>member"evidence_class"|>to_string);
  require"invoked executable"sketch(provenance|>member"invoked_executable"|>to_string);
  require"measured executable"benchmark(provenance|>member"measured_executable"|>to_string);
  require"artifact"artifact(provenance|>member"artifact"|>to_string);
  if provenance|>member"frozen_r11_closure"|>to_bool then
    failwith(Printf.sprintf"R11 child %d incorrectly claimed frozen R11 closure"run)
let ()=
  let sketch=ref None and benchmark=ref None and artifact=ref None and output_dir=ref None and visibility=ref"hidden"and seconds=ref 30. and runs=ref 5 in
  Arg.parse["--sketch",Arg.String(fun x->sketch:=Some x),"sketches/shattered_cube/main.exe";"--benchmark",Arg.String(fun x->benchmark:=Some x),"renderer benchmark executable";"--artifact",Arg.String(fun x->artifact:=Some x),"acceptance artifact";"--output-dir",Arg.String(fun x->output_dir:=Some x),"report directory";"--visibility",Arg.Symbol(["visible";"hidden"],fun x->visibility:=x),"mode";"--seconds",Arg.Set_float seconds,"sample duration";"--runs",Arg.Set_int runs,"sample count"]ignore"runtime_next_native_r11_protocol";
  if !seconds <= 0. || !runs <= 0 then invalid_arg"positive protocol counts required";
  let sketch=Option.get!sketch and benchmark=Option.get!benchmark and artifact=Option.get!artifact and output_dir=Option.get!output_dir in
  let commit=clean_commit()in
  for run=1 to!runs do
    let report=Filename.concat output_dir(Printf.sprintf"shattered-%s-%02d.json"!visibility run)in
    let arguments=[|sketch;"--r11-renderer";benchmark;"--r11-artifact";artifact;"--r11-visibility";!visibility;"--r11-seconds";string_of_float!seconds;"--r11-report";report|]in
    let pid=Unix.create_process sketch arguments Unix.stdin Unix.stdout Unix.stderr in
    (match snd(Unix.waitpid[]pid)with Unix.WEXITED 0->()|WEXITED code->failwith(Printf.sprintf"R11 child %d exited %d"run code)|WSIGNALED signal|WSTOPPED signal->failwith(Printf.sprintf"R11 child %d signaled %d"run signal));
    validate_precursor_report~run~sketch~benchmark~artifact report;
    if clean_commit()<>commit then failwith(Printf.sprintf"R11 source changed after child %d"run)
  done
