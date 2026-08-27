type clock=Realtime|Fixed of float type render_target=Native|Headless|Web
type config={width:int;height:int;title:string;fps:int option;domains:int option;clock:clock;resizable:bool;fullscreen:bool}
let default_config={width=800;height=600;title="Prismel sketch";fps=Some 60;domains=None;clock=Realtime;resizable=true;fullscreen=false}
let stopped=ref false let quit()=stopped:=true
let render_target()=match Runtime_next_compat.selected_target()with Ok Runtime_next_compat.Native->Native|Ok Headless->Headless|Ok Web->Web|Error message->invalid_arg message
let is_headless()=render_target()=Headless let is_web()=render_target()=Web
let frame config count time dt events={Frame.width=config.width;height=config.height;size=(config.width,config.height);drawable_width=config.width;drawable_height=config.height;drawable_size=(config.width,config.height);pixel_scale=(1.,1.);time;dt;fps=(if dt > 0. then 1. /. dt else 0.);count;mouse=Input.mouse_pos();mouse_delta=Input.mouse_delta();keys=Input.keys_down();mouse_buttons=Input.mouse_buttons_down();events}
let run_state_internal ?(config=default_config)?max_frames ?(after_present=fun _ _->())~init~update~view ?(on_stop=fun _->())()=
  if config.width<=0||config.height<=0 then invalid_arg"Sketch: dimensions must be positive";
  Option.iter(fun fps->if fps<=0 then invalid_arg"Sketch: fps must be positive")config.fps;
  Option.iter(fun domains->if domains<=0 then invalid_arg"Sketch: domains must be positive")config.domains;
  stopped:=false;Time.init();let first=frame config 0 0. 0.[]in let model=ref(init first)in
  let target=match render_target()with Native->Prismel_next_execution.Native|Headless->Headless|Web->Web in
  let timing=match config.clock with Realtime->Prismel_next_execution.Variable|Fixed dt when Float.is_finite dt&&dt>0.->Fixed dt|Fixed _->invalid_arg"fixed dt must be finite and positive"in
  let configuration={Prismel_next_execution.default_configuration with target;logical_width=config.width;logical_height=config.height;drawable_width=config.width;drawable_height=config.height;title=config.title;timing}in
  let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)in
  let coordinator=get(Prismel_next_execution.create configuration)in
  let capture ()=Prismel_next_execution.capture coordinator
    |>Result.map(fun bytes->config.width,config.height,bytes)
    |>Result.map_error(fun error->Format.asprintf"%a"Prismel_next_execution.pp_error error)in
  let save filename=match target with
    |Prismel_next_execution.Web->Prismel_next_execution.download_frame coordinator~filename
        |>Result.map_error(fun error->Format.asprintf"%a"Prismel_next_execution.pp_error error)
    |Native|Headless->Result.bind(capture())(fun(width,height,bytes)->
        match Prismel_next_resources.Canvas.create~width~height with
        |Error error->Error(Format.asprintf"%a"Prismel_next_resources.pp_error error)
        |Ok canvas->Fun.protect~finally:(fun()->ignore(Prismel_next_resources.Canvas.destroy canvas))(fun()->
            for y=0 to height-1 do for x=0 to width-1 do let o=(y*width+x)*4 in
              let packed=Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes o)))24)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+1))))16)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+2))))8)(Int32.of_int(Char.code(Bytes.get bytes(o+3))))))in
              Prismel_next_resources.Canvas.set_pixel canvas~x~y packed|>Result.get_ok done done;
            Prismel_next_resources.Canvas.save_png canvas filename
            |>Result.map_error(fun error->Format.asprintf"%a"Prismel_next_resources.pp_error error)))in
  Canvas_runtime.install~capture~save;
  let latest=ref None and last_scene=ref None in Scene.Private.install_renderer(fun scene->last_scene:=Some scene;let ir,resources=Result.get_ok(Scene.Private.stage~width:config.width~height:config.height scene)in latest:=Some(get(Prismel_next_execution.lower_scene2 coordinator~density:1~resource:(fun id->List.assoc_opt id resources)ir)));
  let cleanup()=Fun.protect~finally:(fun()->Canvas_runtime.clear();Option.iter Scene.Private.release !last_scene;ignore(Prismel_next_execution.destroy coordinator))(fun()->on_stop!model)in
  Fun.protect~finally:cleanup(fun()->
    let limit=match max_frames with Some value->Some value|None when is_headless()||is_web()->Some 1|None->None in let count=ref 0 in while not !stopped&&Option.fold~none:true~some:(fun limit-> !count<limit)limit do
      Time.update();let events=Event.poll_events()in incr count;let dt=match config.clock with Realtime->Time.get_delta_time()|Fixed value->value in
      let facts=frame config !count(match config.clock with Realtime->Time.now()|Fixed _->float !count*.dt)dt events in model:=update !model facts;Scene.render(view !model facts);ignore(get(Prismel_next_execution.step coordinator(Option.value!latest~default:[])));after_present !model facts;Time.limit_frame_rate()done;!model)
let run_state ?config~init~update~view ?on_stop()=
  Parallel.run ?domains:(Option.bind config(fun value->value.domains))(fun()->run_state_internal?config~init~update~view?on_stop())
let run ?config view=ignore(run_state?config~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
let run_assets ?config ?(root=".") ?(watch=false)~init~update~view()=let assets=Assets.create~root~watch()in Fun.protect~finally:(fun()->Assets.destroy assets)(fun()->run_state?config~init:(init assets)~update:(update assets)~view:(view assets)())
let export_state ?(config=default_config)?(fps=60)?(prefix="frame")~directory~frames~init~update~view ?(on_stop=fun _->())()=
  if frames<=0 then invalid_arg"Sketch.export_state: frames must be positive";
  if fps<=0 then invalid_arg"Sketch.export_state: fps must be positive";
  if prefix=""||prefix="."||prefix=".."||Filename.basename prefix<>prefix then invalid_arg"Sketch.export_state: invalid prefix";
  let rec ensure path=if path=""||path="."||Sys.file_exists path then()else(let parent=Filename.dirname path in if parent<>path then ensure parent;try Unix.mkdir path 0o755 with Unix.Unix_error(Unix.EEXIST,_,_)->())in
  ensure directory;let index=ref 0 in
  let after_present _ _=let filename=Filename.concat directory(Printf.sprintf"%s-%06d.png"prefix !index)in match Canvas.save_screen_png filename with Ok()->incr index|Error message->failwith("Frame export failed: "^message)in
  let config={config with clock=Fixed(1./.float fps);fps=None}in
  Parallel.run ?domains:config.domains(fun()->run_state_internal~config~max_frames:frames~after_present~init~update~view~on_stop())
let export ?config ?fps ?prefix ~directory ~frames view=ignore(export_state?config?fps?prefix~directory~frames~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
