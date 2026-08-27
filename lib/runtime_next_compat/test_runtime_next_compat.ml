open Runtime_next_compat
let get=function Ok x->x|Error e->failwith e
let trim=String.trim
let starts prefix value=String.length value>=String.length prefix&&String.sub value 0(String.length prefix)=prefix
let symbol prefix line=
  let line=trim line in
  if not(starts prefix line)then None else
    let rest=String.sub line(String.length prefix)(String.length line-String.length prefix)in
    let stop=match String.index_opt rest ' ' ,String.index_opt rest ':' with
      | None,None->String.length rest|Some x,None|None,Some x->x|Some x,Some y->min x y in
    Some(String.sub rest 0 stop)
let lines path=let channel=open_in path in Fun.protect~finally:(fun()->close_in_noerr channel)(fun()->
  let rec loop acc=match input_line channel with line->loop(line::acc)|exception End_of_file->List.rev acc in loop[])
let unique label values=let sorted=List.sort_uniq String.compare values in
  if List.length sorted<>List.length values then failwith(label^" contains duplicates");sorted
let check_manifest ()=
  if Array.length Sys.argv<>2 then failwith"Runtime signature path missing";
  let source=lines Sys.argv.(1)in
  let values=List.filter_map(symbol"val ")source in
  let private_values=List.filter_map(fun line->match symbol"val "line with
    | Some name when String.length line>0&&line.[0]=' '->Some("Private."^name)|_->None)source in
  let public_values=List.filter_map(fun line->if String.length line>0&&line.[0]<>' 'then symbol"val "line else None)source in
  let expected=unique"runtime values"(public_values@private_values)in
  let actual=unique"coverage manifest"(List.map fst api_coverage)in
  if expected<>actual then failwith"Runtime value coverage manifest drift";
  let types=List.filter_map(fun line->if String.length line>0&&line.[0]<>' 'then symbol"type "line else None)source in
  if unique"runtime types"types<>unique"type manifest"(List.map fst api_type_coverage)then
    failwith"Runtime type coverage manifest drift";
  if List.sort String.compare omitted_raw_api<>
      List.sort String.compare(List.filter_map(function name,Raw_omission _->Some name|_->None)api_coverage)
  then failwith"raw omission allowlist drift";
  ignore values
let ()=
  check_manifest();
  Unix.putenv "PRISMEL_RENDER_TARGET" "headless";
  if get(selected_target())<>Headless||not(is_headless())||is_web()||not(is_displayless())then failwith"selection";
  let value=get(start~width:4~height:3~title:"compat"~resizable:true)in
  if target value<>Headless then failwith"target";
  let initial_facts=get(facts value)in if initial_facts.logical_width<>4||initial_facts.logical_height<>3 then failwith"facts";
  ignore(get(render value[]));let pace=get(pacing value)in if pace.frames<>1L then failwith"pacing";
  if Bytes.length(get(capture value~bytes_per_row:16))<>48 then failwith"capture";
  get(resize value~logical_width:2~logical_height:2~drawable_width:2~drawable_height:2);
  if web_url value<>None||web_client_count value<>0||drain_web_events value<>[] then failwith"web fallback";
  stop value;stop value;
  (match facts value with Error _->()|Ok _->failwith"stale");
  Unix.putenv "PRISMEL_RENDER_TARGET" "web";
  let web=get(start~width:2~height:2~title:"compat-web"~resizable:false)in
  if target web<>Web||web_url web=None||web_client_count web<>0 then failwith"web trace";
  let asset=Option.get(register_web_bytes web~content_type:"application/octet-stream"(Bytes.of_string"x"))in
  remove_web_asset web asset;send_web_audio web Audio_stop_all;
  set_web_text_input_regions web[{x=0;y=0;width=1;height=1;focused=true}];
  ignore(get(render web[]));stop web;
  if not(List.mem"present"omitted_raw_api)then failwith"raw allowlist";
  for _=1 to 10_000 do ignore(get(target_of_string"headless"))done;
  print_endline"runtime_next_compat: headless trace stale raw-allowlist 10k passed"
