type target = Native | Headless | Web
type implementation = Native_runtime of Runtime_next.t
  | Headless_runtime of Runtime_next_headless.t | Web_runtime of Runtime_next_web.t
type web_configuration=Runtime_next_web.web_configuration={interface:string;port:int;title:string;resizable:bool;
  max_events:int; max_clients:int; max_connections:int; max_message_bytes:int;
  max_queued_event_bytes:int; max_frame_pool_bytes:int; compress_frames:bool }
let default_web_configuration=Runtime_next_web.default_web_configuration
type configuration = { target:target;logical_width:int;logical_height:int;
  drawable_width:int;drawable_height:int;web_configuration:web_configuration option }
type facts = { title:string;logical_width:int;logical_height:int;drawable_width:int;
  drawable_height:int;position:(int*int)option;pixel_density:float;display_scale:float;
  refresh_rate:float option;vsync:bool }
type pacing = {frames:int64;presented:int64;last_presented:bool}
type stats={frames:int64;presented:int64;logical_draws:int64;logical_passes:int64;
  logical_submissions:int64;uploaded_bytes:int64;cache_entries:int}
type family=Scene2|Scene3|Scene3_textured|Scene3_shadow|Scene3_stencil
  |Scene3_textured_stencil|Scene3_shadow_stencil
type blend=Replace|Alpha|Add|Multiply|Screen|Subtract
type prepared={family:family;blend:blend;texture:Scene_execution.sampled_texture option;
  auxiliary:Scene_execution.auxiliary_resource option;samples:int;draw:Scene_execution.draw}
type text_input_region=Runtime_next_web.text_input_region={x:int;y:int;width:int;height:int;focused:bool}
type mouse_button=Runtime_next_web.mouse_button=Left|Middle|Right|X1|X2
type web_event=Runtime_next_web.web_event=Pointer_moved of int*int|Pointer_pressed of mouse_button*int*int
  |Pointer_released of mouse_button*int*int|Pointer_cancelled of mouse_button
  |Wheel of int*int|Key_pressed of string|Key_released of string|Text_input of string
  |Text_editing of{text:string;start:int;length:int}|Resized of int*int|Focus_lost
  |File_uploaded of{name:string;contents:bytes}
type audio_command=Runtime_next_web.audio_command=Audio_master_volume of float|Audio_stop_all
  |Audio_sample_play of{asset:string;channel:int;loops:int;volume:float}
  |Audio_sample_volume of{asset:string;volume:float}|Audio_sample_stop of int
  |Audio_sample_pause of int|Audio_sample_resume of int
  |Audio_music_play of{asset:string;loops:int;fade_ms:int}|Audio_music_volume of float
  |Audio_music_pause|Audio_music_resume|Audio_music_stop of int|Audio_asset_remove of string
type t={target:target;implementation:implementation;mutable facts:facts;
  mutable pacing:pacing;mutable logical_draws:int64;mutable logical_passes:int64;
  mutable logical_submissions:int64;mutable dead:bool}
let target_of_string value=match String.lowercase_ascii(String.trim value)with
  |"native"->Ok Native|"headless"->Ok Headless|"web"->Ok Web
  |invalid->Error(Printf.sprintf"unknown render target %S (expected native, headless, or web)"invalid)
let enabled value=match String.lowercase_ascii(String.trim value)with"1"|"true"|"yes"|"on"->true|_->false
let select_with getenv=let explicit=match getenv"PRISMEL_RENDER_TARGET"with
  |Some value->Some("PRISMEL_RENDER_TARGET",value)|None->Option.map(fun value->"PRISMAL_RENDER_TARGET",value)(getenv"PRISMAL_RENDER_TARGET")in
  match explicit with Some(name,value)->Result.map_error(fun message->name^": "^message)(target_of_string value)
  |None->(match getenv"HEADLESS"with Some value when enabled value->Ok Headless|_->Ok Native)
let selected()=select_with Sys.getenv_opt
let error operation kind message=Error(Ogpu.Error.make operation kind message)
let invalid operation message=error operation Ogpu.Error.Invalid_argument message
let unsupported operation target=error operation Ogpu.Error.Unsupported
  (Printf.sprintf"operation is unsupported for %s target"(match target with Native->"native"|Headless->"headless"|Web->"web"))
let initial_facts (c:configuration)={title="Prismel runtime-next";logical_width=c.logical_width;logical_height=c.logical_height;
  drawable_width=c.drawable_width;drawable_height=c.drawable_height;position=None;
  pixel_density=float c.drawable_width/.float c.logical_width;
  display_scale=float c.drawable_width/.float c.logical_width;refresh_rate=None;vsync=true}
let create (c:configuration)=let op="Runtime_next_orchestrator.create"in
  if c.logical_width<=0||c.logical_height<=0||c.drawable_width<=0||c.drawable_height<=0
  then invalid op"dimensions must be positive"else let finish implementation facts=
    Ok{target=c.target;implementation;facts;pacing={frames=0L;presented=0L;last_presented=false};logical_draws=0L;logical_passes=0L;logical_submissions=0L;dead=false}in
  match c.target with
  |Native->(match Runtime_next.create~width:c.logical_width~height:c.logical_height with Error _ as e->e|Ok runtime->
      (match Runtime_next.set_title runtime "Prismel runtime-next",Runtime_next.set_resizable runtime true with
       |Ok(),Ok()->(match Runtime_next.window_facts runtime~vsync:true with
          |Ok f->finish(Native_runtime runtime){title=f.title;logical_width=f.logical_width;logical_height=f.logical_height;drawable_width=f.drawable_width;drawable_height=f.drawable_height;position=Some f.position;pixel_density=f.pixel_density;display_scale=f.display_scale;refresh_rate=f.refresh_rate;vsync=f.vsync}
          |Error e->ignore(Runtime_next.destroy runtime);Error e)
       |Error e,_|_,Error e->ignore(Runtime_next.destroy runtime);Error e))
  |Headless->Result.map(fun runtime->{target=Headless;implementation=Headless_runtime runtime;
      facts=initial_facts c;pacing={frames=0L;presented=0L;last_presented=false};logical_draws=0L;logical_passes=0L;logical_submissions=0L;dead=false})
      (Runtime_next_headless.create~logical_width:c.logical_width~logical_height:c.logical_height
        ~drawable_width:c.drawable_width~drawable_height:c.drawable_height)
  |Web->let configuration=c.web_configuration in
    Result.map(fun runtime->{target=Web;implementation=Web_runtime runtime;facts=initial_facts c;
      pacing={frames=0L;presented=0L;last_presented=false};logical_draws=0L;logical_passes=0L;logical_submissions=0L;dead=false})
      (Runtime_next_web.create_configured?configuration~logical_width:c.logical_width~logical_height:c.logical_height
        ~drawable_width:c.drawable_width~drawable_height:c.drawable_height())
let ensure operation value=if value.dead then error operation Ogpu.Error.Stale_handle"runtime is destroyed"else Ok()
let target value=value.target
let is_native value=value.target=Native
let is_headless value=value.target=Headless
let is_web value=value.target=Web
let is_displayless value=value.target<>Native
let facts value=Result.map(fun()->value.facts)(ensure"Runtime_next_orchestrator.facts"value)
let pacing value=Result.map(fun()->value.pacing)(ensure"Runtime_next_orchestrator.pacing"value)
let stats value=match ensure"Runtime_next_orchestrator.stats"value with Error _ as e->e|Ok()->
  let uploaded_bytes,cache_entries=match value.implementation with Native_runtime runtime->let s=Runtime_next.stats runtime in s.uploaded_bytes,s.mesh_cache_entries|Headless_runtime runtime->Runtime_next_headless.resource_stats runtime|Web_runtime runtime->Runtime_next_web.resource_stats runtime in
  Ok{frames=value.pacing.frames;presented=value.pacing.presented;logical_draws=value.logical_draws;
    logical_passes=value.logical_passes;logical_submissions=value.logical_submissions;uploaded_bytes;cache_entries}
let account value draw_count result =
  (match result with Ok presented->value.pacing<-{frames=Int64.succ value.pacing.frames;
    presented=(if presented then Int64.succ value.pacing.presented else value.pacing.presented);
    last_presented=presented};value.logical_draws<-Int64.add value.logical_draws(Int64.of_int draw_count);
    value.logical_passes<-Int64.succ value.logical_passes;value.logical_submissions<-Int64.succ value.logical_submissions|Error _->());result
let render value draws=match ensure"Runtime_next_orchestrator.render"value with Error _ as e->e|Ok()->
  account value(List.length draws)(match value.implementation with Native_runtime x->Runtime_next.render x draws
    |Headless_runtime x->Runtime_next_headless.render x draws|Web_runtime x->Runtime_next_web.render x draws)
let scene_family=function Scene2->Scene_execution.Scene2|Scene3->Scene3
  |Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow
  |Scene3_stencil->Scene3_stencil|Scene3_textured_stencil->Scene3_textured_stencil
  |Scene3_shadow_stencil->Scene3_shadow_stencil
let pipeline_blend=function Replace->Ogpu.Pipeline.Replace|Alpha->Alpha|Add->Add
  |Multiply->Multiply|Screen->Screen|Subtract->Subtract
let render_prepared value draws=match ensure"Runtime_next_orchestrator.render_prepared"value with Error _ as e->e|Ok()->
  let draws=List.map(fun x->scene_family x.family,pipeline_blend x.blend,x.texture,x.auxiliary,x.samples,x.draw)draws in
  account value(List.length draws)(match value.implementation with
    |Native_runtime x->Runtime_next.render_sampled_resources x draws
    |Headless_runtime x->Runtime_next_headless.render_sampled_resources x draws
    |Web_runtime x->Runtime_next_web.render_sampled_resources x draws)
let resize value~logical_width~logical_height~drawable_width~drawable_height=
  match ensure"Runtime_next_orchestrator.resize"value with Error _ as e->e|Ok()->let result=
    match value.implementation with Native_runtime x->Runtime_next.resize x~width:logical_width~height:logical_height
    |Headless_runtime x->Runtime_next_headless.resize x~logical_width~logical_height~drawable_width~drawable_height
    |Web_runtime x->Runtime_next_web.resize x~logical_width~logical_height~drawable_width~drawable_height in
    (match result with Ok()->value.facts<-{value.facts with logical_width;logical_height;drawable_width;drawable_height;
      pixel_density=float drawable_width/.float logical_width;display_scale=float drawable_width/.float logical_width}|Error _->());result
let capture value~bytes_per_row=match ensure"Runtime_next_orchestrator.capture"value with Error _ as e->e|Ok()->
  match value.implementation with Native_runtime x->Runtime_next.read_pixels x~bytes_per_row
  |Headless_runtime x->Runtime_next_headless.read_pixels x~bytes_per_row|Web_runtime x->Runtime_next_web.read_pixels x~bytes_per_row
let native_call operation value call=match ensure operation value with Error _ as e->e|Ok()->match value.implementation with
  |Native_runtime runtime->call runtime|Headless_runtime _|Web_runtime _->unsupported operation value.target
let set_title value title=match native_call"Runtime_next_orchestrator.set_title"value(fun x->Runtime_next.set_title x title)with
  |Ok()->value.facts<-{value.facts with title};Ok()|Error _ as e->e
let set_position value~x~y=match native_call"Runtime_next_orchestrator.set_position"value(fun r->Runtime_next.set_position r~x~y)with
  |Ok()->value.facts<-{value.facts with position=Some(x,y)};Ok()|Error _ as e->e
let center value=native_call"Runtime_next_orchestrator.center"value Runtime_next.center
let set_bordered value x=native_call"Runtime_next_orchestrator.set_bordered"value(fun r->Runtime_next.set_bordered r x)
let set_resizable value x=native_call"Runtime_next_orchestrator.set_resizable"value(fun r->Runtime_next.set_resizable r x)
let set_always_on_top value x=native_call"Runtime_next_orchestrator.set_always_on_top"value(fun r->Runtime_next.set_always_on_top r x)
let set_fullscreen value x=native_call"Runtime_next_orchestrator.set_fullscreen"value(fun r->Runtime_next.set_fullscreen r x)
let show value=native_call"Runtime_next_orchestrator.show"value Runtime_next.show
let hide value=native_call"Runtime_next_orchestrator.hide"value Runtime_next.hide
let minimize value=native_call"Runtime_next_orchestrator.minimize"value Runtime_next.minimize
let maximize value=native_call"Runtime_next_orchestrator.maximize"value Runtime_next.maximize
let restore value=native_call"Runtime_next_orchestrator.restore"value Runtime_next.restore
let web_call operation value call=match ensure operation value with Error _ as e->e|Ok()->match value.implementation with
  |Web_runtime runtime->call runtime|Native_runtime _|Headless_runtime _->unsupported operation value.target
let web_url value=web_call"Runtime_next_orchestrator.web_url"value Runtime_next_web.url
let web_client_count value=web_call"Runtime_next_orchestrator.web_client_count"value Runtime_next_web.client_count
let drain_web_events value=web_call"Runtime_next_orchestrator.drain_web_events"value Runtime_next_web.drain_events_typed
let register_web_bytes value?content_type bytes=web_call"Runtime_next_orchestrator.register_web_bytes"value(fun r->Runtime_next_web.register_asset_bytes r?content_type bytes)
let remove_web_asset value id=web_call"Runtime_next_orchestrator.remove_web_asset"value(fun r->Runtime_next_web.remove_asset_checked r id)
let send_web_audio value command=web_call"Runtime_next_orchestrator.send_web_audio"value(fun r->Runtime_next_web.send_audio_typed r command)
let download_web_frame value~filename=web_call"Runtime_next_orchestrator.download_web_frame"value(fun r->Runtime_next_web.download_frame r~filename)
let set_text_input_regions value regions=web_call"Runtime_next_orchestrator.set_text_input_regions"value(fun r->Runtime_next_web.set_regions r regions)
let destroy value=if value.dead then Ok()else(value.dead<-true;match value.implementation with Native_runtime x->Runtime_next.destroy x
  |Headless_runtime x->Runtime_next_headless.destroy x|Web_runtime x->Runtime_next_web.destroy x)
