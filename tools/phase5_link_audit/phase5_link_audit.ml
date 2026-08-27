let forbidden=["tsdl";"tsdl_gfx";"sdl2";"libSDL2";"OpenGL.framework";"libGL"]
let lower=String.lowercase_ascii
let contains source needle=let source=lower source and needle=lower needle in
  let n=String.length needle in let rec loop i=i+n<=String.length source&&
    (String.sub source i n=needle||loop(i+1))in loop 0
let read_lines path=let channel=open_in path in Fun.protect~finally:(fun()->close_in_noerr channel)(fun()->
  let rec loop acc=match input_line channel with line->loop(line::acc)|exception End_of_file->List.rev acc in loop[])
let command_lines program arguments=
  let channel=Unix.open_process_args_in program(Array.of_list(program::arguments))in
  let rec loop acc=match input_line channel with line->loop(line::acc)|exception End_of_file->List.rev acc in
  let lines=loop[]in match Unix.close_process_in channel with Unix.WEXITED 0->lines|_->failwith(program^" failed")
let rec artifacts root relative=
  let path=Filename.concat root relative in
  if not(Sys.file_exists path)then[]else Array.to_list(Sys.readdir path)|>List.concat_map(fun name->
    let child=Filename.concat relative name and absolute=Filename.concat path name in
    if Sys.is_directory absolute then artifacts root child else if
      List.exists(Filename.check_suffix name)[".exe";".cmxs";".dylib";".so"]then[child]else[])
let violations kind lines=lines|>List.filter(fun line->List.exists(contains line)forbidden)
  |>List.sort_uniq String.compare|>List.map(fun line->`Assoc["kind",`String kind;"line",`String line])
let ()=
  let root=ref"."and deps_file=ref""and otool_file=ref""and report_only=ref false in
  Arg.parse["--root",Arg.Set_string root,"repository root";"--deps-file",Arg.Set_string deps_file,"captured Dune dependencies";
    "--otool-file",Arg.Set_string otool_file,"captured artifact<TAB>dependency lines";
    "--report-only",Arg.Set report_only,"emit violations with exit zero"]
    (fun value->raise(Arg.Bad value))"Phase5 D2/D3 dependency/link audit";
  let root=Unix.realpath!root in
  let deps=if!deps_file<>""then read_lines!deps_file else
    command_lines"opam"["exec";"--";"dune";"describe";"external-lib-deps";"--format=sexp"]in
  let links=if!otool_file<>""then read_lines!otool_file else
    artifacts root"_build/default"|>List.concat_map(fun relative->
      let absolute=Filename.concat root relative in
      try command_lines"/usr/bin/otool"["-L";absolute]|>List.map(fun line->relative^"\t"^String.trim line)
      with _->[relative^"\t<otool failed>"])in
  let failures=violations"dune_dependency"deps@violations"native_link"links|>List.sort compare in
  let json=`Assoc["schema",`Int 1;"dependency_lines",`Int(List.length deps);
    "artifact_link_lines",`Int(List.length links);"forbidden",`List(List.map(fun x->`String x)forbidden);
    "violations",`List failures;"passed",`Bool(failures=[])]in
  Yojson.Safe.pretty_to_channel stdout json;output_char stdout '\n';
  if failures<>[]&&not!report_only then exit 2
