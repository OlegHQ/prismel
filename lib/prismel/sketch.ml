type clock=Realtime|Fixed of float type render_target=Native
type config={width:int;height:int;title:string;fps:int option;domains:int option;clock:clock;resizable:bool;fullscreen:bool}
let default_config={width=800;height=600;title="Prismel sketch";fps=Some 60;domains=None;clock=Realtime;resizable=true;fullscreen=false}
let stopped=ref false let quit()=stopped:=true
let resize_current : (width:int -> height:int -> unit) option ref = ref None
let resize ~width ~height =
  if width<=0||height<=0 then invalid_arg"Sketch.resize: dimensions must be positive";
  match !resize_current with
  |None->invalid_arg"Sketch.resize: no sketch is running"
  |Some resize->resize~width~height
let render_target () = Native
let frame config count time dt events={Frame.width=config.width;height=config.height;size=(config.width,config.height);drawable_width=config.width;drawable_height=config.height;drawable_size=(config.width,config.height);pixel_scale=(1.,1.);time;dt;fps=(if dt > 0. then 1. /. dt else 0.);count;mouse=Input.mouse_pos();mouse_delta=Input.mouse_delta();keys=Input.keys_down();mouse_buttons=Input.mouse_buttons_down();events}
let run_state_internal ?(config=default_config)?max_frames ?(after_present=fun _ _->())~init~update~view ?(on_stop=fun _->())()=
  if config.width<=0||config.height<=0 then invalid_arg"Sketch: dimensions must be positive";
  Option.iter(fun frames->if frames<=0 then invalid_arg"Sketch: max_frames must be positive")max_frames;
  Option.iter(fun fps->if fps<=0 then invalid_arg"Sketch: fps must be positive")config.fps;
  Option.iter(fun domains->if domains<=0 then invalid_arg"Sketch: domains must be positive")config.domains;
  stopped:=false;Time.init();let first=frame config 0 0. 0.[]in let model=ref(init first)in
  let target=Prismel_next_execution.Native in
  let timing=match config.clock with Realtime->Prismel_next_execution.Variable|Fixed dt when Float.is_finite dt&&dt>0.->Fixed dt|Fixed _->invalid_arg"fixed dt must be finite and positive"in
  let configuration={Prismel_next_execution.default_configuration with target;logical_width=config.width;logical_height=config.height;drawable_width=config.width;drawable_height=config.height;title=config.title;timing}in
  let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_execution.pp_error e)in
  let coordinator=get(Prismel_next_execution.create configuration)in
  Runtime_diagnostics.Private.install coordinator;
  let logical_width=ref config.width and logical_height=ref config.height in
  let capture ()=Prismel_next_execution.capture coordinator
    |>Result.map(fun bytes-> !logical_width,!logical_height,bytes)
    |>Result.map_error(fun error->Format.asprintf"%a"Prismel_next_execution.pp_error error)in
  let save filename=Result.bind(capture())(fun(width,height,bytes)->
        match Prismel_next_resources.Canvas.create~width~height with
        |Error error->Error(Format.asprintf"%a"Prismel_next_resources.pp_error error)
        |Ok canvas->Fun.protect~finally:(fun()->ignore(Prismel_next_resources.Canvas.destroy canvas))(fun()->
            for y=0 to height-1 do for x=0 to width-1 do let o=(y*width+x)*4 in
              let packed=Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes o)))24)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+1))))16)(Int32.logor(Int32.shift_left(Int32.of_int(Char.code(Bytes.get bytes(o+2))))8)(Int32.of_int(Char.code(Bytes.get bytes(o+3))))))in
              Prismel_next_resources.Canvas.set_pixel canvas~x~y packed|>Result.get_ok done done;
            Prismel_next_resources.Canvas.save_png canvas filename
            |>Result.map_error(fun error->Format.asprintf"%a"Prismel_next_resources.pp_error error)))in
  Canvas_runtime.install~capture~save;
  resize_current:=Some(fun~width~height->
    get(Prismel_next_execution.resize coordinator~logical_width:width
      ~logical_height:height~drawable_width:width~drawable_height:height);
    logical_width:=width;logical_height:=height);
  let latest=ref None and last_scene=ref None in Scene.Private.install_renderer(fun scene->last_scene:=Some scene;let staged=Result.get_ok(Scene.Private.stage_native~width:!logical_width~height:!logical_height scene)in let scene2=get(Prismel_next_execution.lower_scene2 coordinator~density:1~resource:(fun id->List.assoc_opt id staged.resources)staged.scene2)in let scene3=List.concat_map(fun prepared->Array.to_list prepared.Scene_execution.entries|>List.map(fun(entry:Scene_execution.scene3_entry)->Prismel_next_execution.prepared_draw~family:(match entry.family with Scene3->Scene3|Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow|Scene3_stencil->Scene3_stencil|Scene3_textured_stencil->Scene3_textured_stencil|Scene3_shadow_stencil->Scene3_shadow_stencil|Scene2->Scene2|Scene2_textured->Scene2_textured)~blend:(match entry.blend with Replace->Replace|Alpha->Alpha|Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract)?texture:entry.texture?auxiliary:entry.auxiliary~samples:entry.samples entry.draw))staged.scene3 in latest:=Some(scene2@scene3));
  let cleanup()=Fun.protect~finally:(fun()->resize_current:=None;Canvas_runtime.clear();Option.iter Scene.Private.release !last_scene;ignore(Prismel_next_execution.destroy coordinator);Runtime_diagnostics.Private.record coordinator)(fun()->on_stop!model)in
  Fun.protect~finally:cleanup(fun()->
    let limit=max_frames in let count=ref 0 in while not !stopped&&Option.fold~none:true~some:(fun limit-> !count<limit)limit do
      Time.update();let events=Event.poll_events()in incr count;let dt=match config.clock with Realtime->Time.get_delta_time()|Fixed value->value in
      let base=frame config !count(match config.clock with Realtime->Time.now()|Fixed _->float !count*.dt)dt events in
      let facts={base with width= !logical_width;height= !logical_height;size=(!logical_width,!logical_height);drawable_width= !logical_width;drawable_height= !logical_height;drawable_size=(!logical_width,!logical_height)}in
      model:=update !model facts;Scene.render(view !model facts);ignore(get(Prismel_next_execution.step coordinator(Option.value!latest~default:[])));after_present !model facts;Time.limit_frame_rate()done;!model)
let run_state ?config ?max_frames ~init~update~view ?on_stop()=
  Parallel.run ?domains:(Option.bind config(fun value->value.domains))(fun()->run_state_internal?config?max_frames~init~update~view?on_stop())
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
