type clock=Realtime|Fixed of float
type config={width:int;height:int;title:string;fps:int option;domains:int option;clock:clock;resizable:bool;fullscreen:bool}
let default_config={width=800;height=600;title="Prismel sketch";fps=Some 60;domains=None;clock=Realtime;resizable=true;fullscreen=false}
let stopped=ref false let quit()=stopped:=true
let relative_current : (bool -> (unit, string) result) option ref = ref None
let cursor_current : ([`Default|`Horizontal_resize|`Vertical_resize] ->
  (unit,string) result) option ref = ref None
let set_relative_mouse enabled = match !relative_current with
  |None->Error"Sketch.set_relative_mouse: no sketch is running"
  |Some set->set enabled
let set_cursor shape = match !cursor_current with
  |None->Error"Sketch.set_cursor: no sketch is running"
  |Some set->set shape
let frame config count time dt events={Frame.width=config.width;height=config.height;size=(config.width,config.height);drawable_width=config.width;drawable_height=config.height;drawable_size=(config.width,config.height);pixel_scale=(1.,1.);time;dt;fps=(if dt > 0. then 1. /. dt else 0.);count;mouse=Input_state.mouse();mouse_delta=Input_state.mouse_delta();keys=Input_state.keys();mouse_buttons=Input_state.buttons();events}

(* ---- crash reports: every fatal error in a sketch leaves a folder under
   /tmp/prismel-crash (or PRISMEL_CRASH_DIR) with the exception, backtrace,
   recent input, GC and environment facts, and whatever the sketch dumps. *)
let crash_root()=Option.value(Sys.getenv_opt"PRISMEL_CRASH_DIR")~default:"/tmp/prismel-crash"
let key_name=function
  |Input.KeyChar c->Printf.sprintf"%C"c|ArrowUp->"Up"|ArrowDown->"Down"|ArrowLeft->"Left"
  |ArrowRight->"Right"|Space->"Space"|Enter->"Enter"|Escape->"Escape"|Backspace->"Backspace"
  |Tab->"Tab"|Shift->"Shift"|Ctrl->"Ctrl"|Alt->"Alt"|Meta->"Meta"|Home->"Home"|End->"End"
  |PageUp->"PageUp"|PageDown->"PageDown"|Insert->"Insert"|Delete->"Delete"
  |Unknown code->Printf.sprintf"key%d"code|key->Printf.sprintf"F%d"(match key with
    |F1->1|F2->2|F3->3|F4->4|F5->5|F6->6|F7->7|F8->8|F9->9|F10->10|F11->11|_->12)
let button_name=function Input.LeftButton->"left"|RightButton->"right"|MiddleButton->"middle"
  |MouseX1->"x1"|MouseX2->"x2"
let event_text=function
  |Event.KeyPressed k->"press "^key_name k|KeyReleased k->"release "^key_name k
  |MouseMoved(x,y)->Printf.sprintf"move %.0f,%.0f"x y
  |MousePressed(b,(x,y))->Printf.sprintf"down %s %.0f,%.0f"(button_name b)x y
  |MouseReleased(b,(x,y))->Printf.sprintf"up %s %.0f,%.0f"(button_name b)x y
  |PointerCancelled b->"cancel "^button_name b
  |MouseScrolled(x,y)->Printf.sprintf"scroll %.2f,%.2f"x y
  |TextInput t->Printf.sprintf"text %S"t|TextEditing{text;_}->Printf.sprintf"ime %S"text
  |FileDropped f->"drop "^f|WindowResized(w,h)->Printf.sprintf"resize %dx%d"w h
  |WindowFocusLost->"focus-lost"|WindowClosed->"close"
let write_crash ~title ~dump ~recent exn backtrace=
  let tm=Unix.localtime(Unix.gettimeofday())in
  let name=Printf.sprintf"%s-%04d%02d%02d-%02d%02d%02d-%d"
    (String.map (function 'a'..'z' | 'A'..'Z' | '0'..'9' as c -> c | _ -> '_') title)
    (tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec(Unix.getpid())in
  let directory=Filename.concat(crash_root())name in
  let rec mkdir path=if not(Sys.file_exists path)then(mkdir(Filename.dirname path);
    try Sys.mkdir path 0o755 with Sys_error _->())in
  (try
    mkdir directory;
    let buffer=Buffer.create 4096 in
    let line fmt=Printf.bprintf buffer(fmt^^"\n")in
    line"Prismel crash report";line"sketch: %s"title;
    line"time: %04d-%02d-%02d %02d:%02d:%02d"(tm.tm_year+1900)(tm.tm_mon+1)tm.tm_mday
      tm.tm_hour tm.tm_min tm.tm_sec;
    line"command: %s"(String.concat" "(Array.to_list Sys.argv));
    line"ocaml: %s  pid: %d"Sys.ocaml_version(Unix.getpid());
    line"";line"exception: %s"(Printexc.to_string exn);line"";line"backtrace:";
    Buffer.add_string buffer(Printexc.raw_backtrace_to_string backtrace);line"";
    line"recent frames (oldest first; frames without input are counted, not listed):";
    let quiet=ref 0 in
    List.iter(fun(f:Frame.t)->
      if f.events=[]&&f.keys=[]&&f.mouse_buttons=[]then incr quiet
      else begin
        if !quiet>0 then(line"  … %d idle frames"!quiet;quiet:=0);
        line"  #%d t=%.3f %dx%d mouse=%.0f,%.0f keys=[%s] buttons=[%s] events=[%s]"f.count f.time
          f.width f.height(fst f.mouse)(snd f.mouse)
          (String.concat" "(List.map key_name f.keys))
          (String.concat" "(List.map button_name f.mouse_buttons))
          (String.concat"; "(List.map event_text f.events))end)recent;
    if !quiet>0 then line"  … %d idle frames"!quiet;
    let gc=Gc.quick_stat()in
    line"";line"gc: heap %d words, top %d words, minor %d, major %d, compactions %d"
      gc.heap_words gc.top_heap_words gc.minor_collections gc.major_collections gc.compactions;
    line"";line"environment:";
    Array.iter(fun entry->if String.starts_with~prefix:"PRISMEL_"entry
      ||String.starts_with~prefix:"SDL_"entry||String.starts_with~prefix:"OCAMLRUNPARAM"entry
      then line"  %s"entry)(Unix.environment());
    line"";line"native crashes (segfaults, GPU faults) are not caught here: macOS writes";
    line"~/Library/Logs/DiagnosticReports/%s-*.ips"(Filename.basename Sys.executable_name);
    Out_channel.with_open_text(Filename.concat directory"crash.txt")(fun channel->
      Out_channel.output_string channel(Buffer.contents buffer));
    (try dump directory with extra->
      Out_channel.with_open_text(Filename.concat directory"dump-failed.txt")(fun channel->
        Out_channel.output_string channel(Printexc.to_string extra)));
    Printf.eprintf"Prismel crash report: %s\n%!"directory
  with error->Printf.eprintf"Prismel crash report could not be written: %s\n%!"
    (Printexc.to_string error))
let run_state_internal ?(config=default_config)?max_frames ?(after_present=fun model _->model)?(crash_dump=fun _ _->())~init~update~view ?(on_stop=fun _->())()=
  if config.width<=0||config.height<=0 then invalid_arg"Sketch: dimensions must be positive";
  let max_frames=match max_frames,Sys.getenv_opt"PRISMEL_MAX_FRAMES"with
    |Some _,_|None,(None|Some"")->max_frames
    |None,Some text->(match int_of_string_opt text with Some _ as n->n|None->invalid_arg"Sketch: PRISMEL_MAX_FRAMES must be an integer")in
  Option.iter(fun frames->if frames<=0 then invalid_arg"Sketch: max_frames must be positive")max_frames;
  Option.iter(fun fps->if fps<=0 then invalid_arg"Sketch: fps must be positive")config.fps;
  Option.iter(fun domains->if domains<=0 then invalid_arg"Sketch: domains must be positive")config.domains;
  stopped:=false;Time.init();
  Time.set_frame_rate(Option.value config.fps~default:0);
  let vsync=match config.clock with Fixed _->false|Realtime->true in
  Time.set_vsync vsync;
  let first=frame config 0 0. 0.[]in
  (match config.clock with Fixed dt when not(Float.is_finite dt&&dt>0.)->
    invalid_arg"fixed dt must be finite and positive"|_->());
  let configuration={Prismel_execution.logical_width=config.width;logical_height=config.height;drawable_width=config.width;drawable_height=config.height;title=config.title;vsync}in
  let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_execution.pp_error e)in
  let coordinator=get(Prismel_execution.create configuration)in
  get(Prismel_execution.show coordinator);
  (match Prismel_execution.presentation_facts coordinator with
   |Ok facts->Input_state.configure~logical_width:facts.logical_width
       ~logical_height:facts.logical_height
   |Error _->());
  let logical_width=ref config.width and logical_height=ref config.height in
  let capture ()=
    let facts=get(Prismel_execution.presentation_facts coordinator)in
    Prismel_execution.capture coordinator
    |>Result.map(fun bytes->facts.drawable_width,facts.drawable_height,bytes)
    |>Result.map_error(fun error->Format.asprintf"%a"Prismel_execution.pp_error error)in
  let save filename=Result.bind(capture())(fun(width,height,bytes)->
        match Runtime_resources.Canvas.create~width~height with
        |Error error->Error(Format.asprintf"%a"Runtime_resources.pp_error error)
        |Ok canvas->Fun.protect~finally:(fun()->ignore(Runtime_resources.Canvas.destroy canvas))(fun()->
            for y=0 to height-1 do for x=0 to width-1 do let o=(y*width+x)*4 in
              let packed=Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes o)))24)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+1))))16)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+2))))8)(Int32.of_int(Char.code(Bytes.get bytes(o+3))))))in
              Runtime_resources.Canvas.set_pixel canvas~x~y packed|>Result.get_ok done done;
            Runtime_resources.Canvas.save_png canvas filename
            |>Result.map_error(fun error->Format.asprintf"%a"Runtime_resources.pp_error error)))in
  Canvas_runtime.install~capture~save;
  relative_current:=Some(fun enabled->
    match Prismel_execution.set_relative_mouse coordinator enabled with
    |Ok()->Input_state.set_relative enabled;Ok()
    |Error error->Error(Format.asprintf"%a"Prismel_execution.pp_error error));
  cursor_current:=Some(fun shape->
    match Prismel_execution.set_cursor coordinator shape with
    |Ok()->Ok()
    |Error error->Error(Format.asprintf"%a"Prismel_execution.pp_error error));
  Scene.Private.install_renderer(fun scene->
    (* ponytail: scan scene metadata each frame; move the focused region into
       staged scene facts if large retained scenes make this measurable. *)
    let area=Scene.Private.text_regions scene
      |>List.find_opt(fun(_,_,_,_,focused,_)->focused)
      |>Option.map(fun(x,y,w,h,_,cursor)->(x,y,w,h),cursor)in
    get(Prismel_execution.set_text_input_area coordinator area);
    let facts=get(Prismel_execution.presentation_facts coordinator)in
    let density=
      let from_drawable=float facts.drawable_width/.float(max 1 facts.logical_width)in
      max 1(int_of_float(Float.round(max facts.pixel_density from_drawable)))in
    match Native_scene_lowering.render~execution:coordinator~density
      ~width:facts.logical_width~height:facts.logical_height scene with
    |Ok _->()
    |Error error->
        failwith(Format.asprintf"Sketch.render: %a"Native_scene_lowering.pp_error error));
  Printexc.record_backtrace true;
  let recent=Array.make 120 first and cursor=ref 0 in
  let crashed exn=
    let backtrace=Printexc.get_raw_backtrace()in
    let frames=List.init(Array.length recent)(fun index->
      recent.((!cursor+index)mod Array.length recent))
      |>List.filter(fun(f:Frame.t)->f.count>0)in
    exn,backtrace,frames in
  let model=ref(try init first with exn->
    let exn,backtrace,frames=crashed exn in
    write_crash~title:config.title~dump:(fun _->())~recent:frames exn backtrace;
    Printexc.raise_with_backtrace exn backtrace)in
  let cleanup()=Fun.protect~finally:(fun()->
      (* Never leave the pointer captured after the sketch stops. *)
      Option.iter(fun set->ignore(set false))!relative_current;
      relative_current:=None;cursor_current:=None;
      Canvas_runtime.clear();ignore(Prismel_execution.destroy coordinator))(fun()->on_stop!model)in
  Fun.protect~finally:cleanup(fun()->
    let limit=max_frames in let count=ref 0 in while not !stopped&&Option.fold~none:true~some:(fun limit-> !count<limit)limit do
      Time.update();let events=Input_state.poll()in
      if List.exists(function Event.WindowClosed->true|_->false)events then quit();
      incr count;let dt=match config.clock with Realtime->Time.delta()|Fixed value->value in
      let base=frame config !count(match config.clock with Realtime->Time.now()|Fixed _->float !count*.dt)dt events in
      let presentation=get(Prismel_execution.presentation_facts coordinator)in
      if presentation.logical_width<> !logical_width
          ||presentation.logical_height<> !logical_height then
        Input_state.configure~logical_width:presentation.logical_width
          ~logical_height:presentation.logical_height;
      logical_width:=presentation.logical_width;logical_height:=presentation.logical_height;
      let scale_x=float presentation.drawable_width/.float presentation.logical_width
      and scale_y=float presentation.drawable_height/.float presentation.logical_height in
      let facts={base with width=presentation.logical_width;height=presentation.logical_height;
        size=(presentation.logical_width,presentation.logical_height);
        drawable_width=presentation.drawable_width;drawable_height=presentation.drawable_height;
        drawable_size=(presentation.drawable_width,presentation.drawable_height);
        pixel_scale=(scale_x,scale_y)}in
      recent.(!cursor)<-facts;cursor:=(!cursor+1)mod Array.length recent;
      (try
        model:=update !model facts;Scene.render(view !model facts);
        model:=after_present !model facts
      with exn->
        let exn,backtrace,frames=crashed exn in
        write_crash~title:config.title~dump:(crash_dump !model)~recent:frames exn backtrace;
        Printexc.raise_with_backtrace exn backtrace);
      Time.limit_frame_rate()done;!model)
let run_state ?config ?max_frames ~init~update~view ?after_present ?crash_dump ?on_stop()=
  Parallel.run ?domains:(Option.bind config(fun value->value.domains))(fun()->run_state_internal?config?max_frames?after_present?crash_dump~init~update~view?on_stop())
let run ?config view=ignore(run_state?config~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
let export_state ?(config=default_config)?(fps=60)?(prefix="frame")~directory~frames~init~update~view ?(on_stop=fun _->())()=
  if frames<=0 then invalid_arg"Sketch.export_state: frames must be positive";
  if fps<=0 then invalid_arg"Sketch.export_state: fps must be positive";
  if prefix=""||prefix="."||prefix=".."||Filename.basename prefix<>prefix then invalid_arg"Sketch.export_state: invalid prefix";
  Canvas_runtime.ensure_directory directory;let index=ref 0 in
  let after_present model _=let filename=Filename.concat directory(Printf.sprintf"%s-%06d.png"prefix !index)in match Canvas.save_screen_png filename with Ok()->incr index;model|Error message->failwith("Frame export failed: "^message)in
  let config={config with clock=Fixed(1./.float fps);fps=None}in
  Parallel.run ?domains:config.domains(fun()->run_state_internal~config~max_frames:frames~after_present~init~update~view~on_stop())
let export ?config ?fps ?prefix ~directory ~frames view=ignore(export_state?config?fps?prefix~directory~frames~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
