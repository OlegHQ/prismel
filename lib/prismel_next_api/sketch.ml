type clock=Realtime|Fixed of float type render_target=Native|Headless|Web
type config={width:int;height:int;title:string;fps:int option;domains:int option;clock:clock;resizable:bool;fullscreen:bool}
let default_config={width=800;height=600;title="Prismel";fps=None;domains=None;clock=Realtime;resizable=true;fullscreen=false}
let stopped=ref false let quit()=stopped:=true
let render_target()=match Runtime_next_compat.selected_target()with Ok Runtime_next_compat.Native->Native|Ok Headless->Headless|Ok Web->Web|Error message->invalid_arg message
let is_headless()=render_target()=Headless let is_web()=render_target()=Web
let frame config count time dt events={Frame.width=config.width;height=config.height;size=(config.width,config.height);drawable_width=config.width;drawable_height=config.height;drawable_size=(config.width,config.height);pixel_scale=(1.,1.);time;dt;fps=(if dt > 0. then 1. /. dt else 0.);count;mouse=Input.mouse_pos();mouse_delta=Input.mouse_delta();keys=Input.keys_down();mouse_buttons=Input.mouse_buttons_down();events}
let run_state ?(config=default_config)~init~update~view ?(on_stop=fun _->())()=
  stopped:=false;Time.init();let first=frame config 0 0. 0.[]in let model=ref(init first)in
  let target=match render_target()with Native->Prismel_next_execution.Native|Headless->Headless|Web->Web in
  let timing=match config.clock with Realtime->Prismel_next_execution.Variable|Fixed dt when Float.is_finite dt&&dt>0.->Fixed dt|Fixed _->invalid_arg"fixed dt must be finite and positive"in
  let configuration={Prismel_next_execution.default_configuration with target;logical_width=config.width;logical_height=config.height;drawable_width=config.width;drawable_height=config.height;title=config.title;timing}in
  let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)in
  let coordinator=get(Prismel_next_execution.create configuration)in
  let latest=ref None and last_scene=ref None in Scene.Private.install_renderer(fun scene->last_scene:=Some scene;let ir,resources=Result.get_ok(Scene.Private.stage~width:config.width~height:config.height scene)in latest:=Some(get(Prismel_next_execution.lower_scene2 coordinator~density:1~resource:(fun id->List.assoc_opt id resources)ir)));
  Fun.protect~finally:(fun()->on_stop!model;Option.iter Scene.Private.release !last_scene;ignore(Prismel_next_execution.destroy coordinator))(fun()->
    let finite=is_headless()||is_web()in let count=ref 0 in while not !stopped&&(not finite|| !count<1)do
      Time.update();let events=Event.poll_events()in incr count;let dt=match config.clock with Realtime->Time.get_delta_time()|Fixed value->value in
      let facts=frame config !count(match config.clock with Realtime->Time.now()|Fixed _->float !count*.dt)dt events in model:=update !model facts;Scene.render(view !model facts);ignore(get(Prismel_next_execution.step coordinator(Option.value!latest~default:[])));Time.limit_frame_rate()done;!model)
let run ?config view=ignore(run_state?config~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
let run_assets ?config ?(root=".") ?(watch=false)~init~update~view()=let assets=Assets.create~root~watch()in Fun.protect~finally:(fun()->Assets.destroy assets)(fun()->run_state?config~init:(init assets)~update:(update assets)~view:(view assets)())
let export_state ?(config=default_config)?(fps=60)?(prefix="frame")~directory~frames~init~update~view ?(on_stop=fun _->())()=
  if frames<0||fps<=0 then invalid_arg"invalid export cardinality";ignore(prefix,directory);let model=ref(init(frame config 0 0. (1. /. float fps) []))in
  for count=1 to frames do let facts=frame config count(float count /. float fps)(1. /. float fps)[]in model:=update !model facts;Scene.render(view !model facts)done;on_stop !model; !model
let export ?config ?fps ?prefix ~directory ~frames view=ignore(export_state?config?fps?prefix~directory~frames~init:(fun _->())~update:(fun()_->())~view:(fun()frame->view frame)())
