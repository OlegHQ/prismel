let fail format=Printf.ksprintf(fun message->prerr_endline("phase5-switch: "^message);exit 2)format
let command root program arguments=
  let path=Filename.temp_file"phase5-switch-"".out"in
  let quoted=String.concat" "(List.map Filename.quote arguments)in
  let status=Sys.command(Printf.sprintf"cd %s && %s %s > %s 2>&1"
    (Filename.quote root)(Filename.quote program)quoted(Filename.quote path))in
  let channel=open_in_bin path in let output=really_input_string channel(in_channel_length channel)in
  close_in_noerr channel;Sys.remove path;status,output
let strings json field=Yojson.Safe.Util.(json|>member field|>to_list|>List.map to_string)
let validate json=
  let open Yojson.Safe.Util in
  if json|>member"schema"|>to_int<>1 then fail"manifest schema drift";
  List.iter(fun field->let values=strings json field in
    if values=[]||List.sort_uniq String.compare values|>List.length<>List.length values then
      fail"%s must be non-empty and duplicate-free"field)
    ["delete";"replace";"required_public_modules";"forbidden_dependencies";
     "forbidden_link_names";"historical_text_allowlist"]
let exists root path=Sys.file_exists(Filename.concat root path)
let ()=
  let root=ref"."and manifest=ref"specification/evidence/gpu_migration/phase5_atomic_switch_manifest.json"
  and mode=ref"validate"in
  Arg.parse["--root",Arg.Set_string root,"repository root";
    "--manifest",Arg.Set_string manifest,"manifest path";
    "--mode",Arg.Set_string mode,"validate, pre-switch, or post-switch"]
    (fun value->raise(Arg.Bad value))"read-only Phase5 atomic switch preflight";
  let root=Unix.realpath!root in let manifest=if Filename.is_relative!manifest then Filename.concat root!manifest else!manifest in
  let json=Yojson.Safe.from_file manifest in validate json;
  if!mode="validate"then print_endline"Phase5 switch manifest structure passed"
  else begin
    let status,dirty=command root"/usr/bin/git"["status";"--porcelain"]in
    if status<>0 then fail"git status failed";
    if String.trim dirty<>""then fail"worktree is dirty; atomic preflight refused";
    let delete=strings json"delete"and replace=strings json"replace"in
    if!mode="pre-switch"then begin
      List.iter(fun path->if not(exists root path)then fail"pre-switch deletion input missing: %s"path)delete;
      List.iter(fun path->if not(exists root path)then fail"replacement input missing: %s"path)replace;
      Printf.printf"Phase5 pre-switch ready: %d deletion paths, %d replacement owners; no mutation performed\n"
        (List.length delete)(List.length replace)
    end else if!mode="post-switch"then begin
      List.iter(fun path->if exists root path then fail"legacy deletion path remains: %s"path)delete;
      List.iter(fun path->if not(exists root path)then fail"post-switch owner missing: %s"path)replace;
      let forbidden=strings json"forbidden_dependencies"in
      let status,tracked=command root"/usr/bin/git"["grep";"-n";"-i";
        String.concat"\\|"forbidden;"--";"*.ml";"*.mli";"dune";"dune-project";"*.opam"]in
      if status=0 then fail"forbidden post-switch text remains:\n%s"tracked
      else if status<>1 then fail"post-switch text scan failed";
      print_endline"Phase5 post-switch source/dependency preflight passed; run external clean link/install gates"
    end else fail"unknown mode %s"!mode
  end
