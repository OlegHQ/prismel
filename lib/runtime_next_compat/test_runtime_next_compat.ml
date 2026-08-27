open Runtime_next_compat
let get=function Ok x->x|Error e->failwith e
let ()=
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
  if not(List.mem"present(renderer)"omitted_raw_api)then failwith"raw allowlist";
  for _=1 to 10_000 do ignore(get(target_of_string"headless"))done;
  print_endline"runtime_next_compat: headless trace stale raw-allowlist 10k passed"
