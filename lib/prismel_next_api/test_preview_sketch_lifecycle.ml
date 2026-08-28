open Prismel_next_api

let require condition message = if not condition then failwith message
let normalize text = text |> String.to_seq |> Seq.filter (fun c -> not (List.mem c [' ';'\n';'\r';'\t'])) |> String.of_seq
let read path = let input=open_in_bin path in Fun.protect ~finally:(fun()->close_in_noerr input)(fun()->really_input_string input(in_channel_length input))
let strip_comments text =
  let output=Buffer.create(String.length text)and depth=ref 0 and index=ref 0 in
  while !index<String.length text do
    if !index+1<String.length text&&text.[!index]='('&&text.[!index+1]='*'then(depth:=!depth+1;index:=!index+2)
    else if !index+1<String.length text&&text.[!index]='*'&&text.[!index+1]=')'&& !depth>0 then(depth:=!depth-1;index:=!index+2)
    else(if !depth=0 then Buffer.add_char output text.[!index];incr index)
  done;Buffer.contents output
let interface path=normalize(strip_comments(read path))

let () = match Array.to_list Sys.argv with
|[_;legacy_preview;next_preview;legacy_sketch;next_sketch]->
  require(interface legacy_preview=interface next_preview)"Preview frozen interface drift";
  require(interface legacy_sketch=interface next_sketch)"Sketch frozen interface drift";
  require(not(Preview.is_open()))"preview initially closed";
  for cycle=1 to 100 do Preview.start~width:8~height:8();Preview.start~width:16~height:16();require(Preview.is_open())"idempotent preview start";require(Preview.step Scene.empty=[])"ordered empty headless events";Preview.stop();Preview.stop();require(not(Preview.is_open()))(Printf.sprintf"preview teardown cycle %d"cycle)done;
  let stopped=ref 0 in
  let model=Sketch.run_state~config:{Sketch.default_config with width=8;height=8;clock=Fixed(1./.60.)}
    ~init:(fun frame->require(frame.count=0)"initial frame";0)
    ~update:(fun model frame->require(frame.count=1)(Printf.sprintf"finite headless frame: %d"frame.count);model+1)
    ~view:(fun _ _->Scene.empty)~on_stop:(fun _->incr stopped)()in
  require(model=1)"finite headless lifecycle";require(!stopped=1)"exactly-once on_stop";
  let bounded=Sketch.run_state~config:{Sketch.default_config with width=8;height=8;clock=Fixed(1./.60.)}
    ~max_frames:3 ~init:(fun _->0) ~update:(fun model frame->
      require(frame.count=model+1)"bounded frame ordering";model+1)
    ~view:(fun _ _->Scene.empty)()in
  require(bounded=3)"explicit headless max_frames lifecycle";
  let directory=Filename.concat(Filename.get_temp_dir_name())(Printf.sprintf"prismel-next-export-%d"(Unix.getpid()))in
  let export_stopped=ref 0 in
  let exported=Sketch.export_state~config:{Sketch.default_config with width=8;height=8}
    ~fps:30~prefix:"exact"~directory~frames:2 ~init:(fun _->0)
    ~update:(fun model _->model+1)~view:(fun _ _->Scene.empty)
    ~on_stop:(fun _->incr export_stopped)()in
  require(exported=2&& !export_stopped=1)"finite export lifecycle";
  for index=0 to 1 do let path=Filename.concat directory(Printf.sprintf"exact-%06d.png"index)in
    let bytes=read path in require(String.length bytes>=8&&String.sub bytes 0 8="\x89PNG\r\n\x1a\n")"export PNG";Sys.remove path done;Unix.rmdir directory;
  print_endline"Preview/Sketch exact interface and headless lifecycle passed"
|_->failwith"expected legacy/next Preview/Sketch MLI paths"
