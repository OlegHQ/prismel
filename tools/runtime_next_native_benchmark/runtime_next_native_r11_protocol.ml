let ()=
  let benchmark=ref None and artifact=ref None and output_dir=ref None and visibility=ref"hidden"and seconds=ref 30. and runs=ref 5 in
  Arg.parse["--benchmark",Arg.String(fun x->benchmark:=Some x),"benchmark executable";"--artifact",Arg.String(fun x->artifact:=Some x),"acceptance artifact";"--output-dir",Arg.String(fun x->output_dir:=Some x),"report directory";"--visibility",Arg.Symbol(["visible";"hidden"],fun x->visibility:=x),"mode";"--seconds",Arg.Set_float seconds,"sample duration";"--runs",Arg.Set_int runs,"sample count"]ignore"runtime_next_native_r11_protocol";
  if !seconds <= 0. || !runs <= 0 then invalid_arg"positive protocol counts required";
  let benchmark=Option.get!benchmark and artifact=Option.get!artifact and output_dir=Option.get!output_dir in
  for run=1 to!runs do
    let report=Filename.concat output_dir(Printf.sprintf"shattered-%s-%02d.json"!visibility run)in
    let arguments=[|benchmark;"shattered";"--acceptance-artifact";artifact;"--visibility";!visibility;"--warmup";"5";"--sample-seconds";string_of_float!seconds;"--report";report|]in
    let pid=Unix.create_process benchmark arguments Unix.stdin Unix.stdout Unix.stderr in
    match snd(Unix.waitpid[]pid)with Unix.WEXITED 0->()|WEXITED code->failwith(Printf.sprintf"R11 child %d exited %d"run code)|WSIGNALED signal|WSTOPPED signal->failwith(Printf.sprintf"R11 child %d signaled %d"run signal)
  done
