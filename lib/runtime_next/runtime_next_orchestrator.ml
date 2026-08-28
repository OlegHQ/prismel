type target = Native | Headless | Web
type web_configuration={interface:string;port:int;title:string;resizable:bool;
  max_events:int; max_clients:int; max_connections:int; max_message_bytes:int;
  max_queued_event_bytes:int; max_frame_pool_bytes:int; compress_frames:bool }
let default_web_configuration={interface="0.0.0.0";port=8080;title="Prismel web";resizable=false;
  max_events=4096;max_clients=8;max_connections=64;max_message_bytes=16*1024*1024+4096;
  max_queued_event_bytes=32*1024*1024;max_frame_pool_bytes=256*1024*1024;compress_frames=true}
type configuration = { target:target;logical_width:int;logical_height:int;
  drawable_width:int;drawable_height:int;web_configuration:web_configuration option }
type facts = { title:string;logical_width:int;logical_height:int;drawable_width:int;
  drawable_height:int;position:(int*int)option;pixel_density:float;display_scale:float;
  refresh_rate:float option;vsync:bool }
type pacing = {frames:int64;presented:int64;last_presented:bool}
type stats={frames:int64;presented:int64;logical_draws:int64;logical_passes:int64;
  logical_submissions:int64;uploaded_bytes:int64;cache_entries:int;
  gpu_timing_supported:bool;gpu_duration_seconds:float;gpu_sample_count:int64;
  retained_plan_builds:int64;retained_plan_hits:int64;retained_plan_misses:int64;
  retained_plan_evictions:int64;retained_plan_executions:int64;
  retained_plan_entries:int;retained_plan_capacity:int}
type diagnostics={active:bool;cache_entries:int;release_queue_pending:int option;
  release_queue_live_handles:int option;release_queue_total_created:int64 option;
  release_queue_total_released:int64 option}
type family=Scene2|Scene2_textured|Scene3|Scene3_textured|Scene3_shadow|Scene3_stencil
  |Scene3_textured_stencil|Scene3_shadow_stencil
type blend=Replace|Alpha|Add|Multiply|Screen|Subtract
type prepared={family:family;blend:blend;texture:Scene_execution.sampled_texture option;
  auxiliary:Scene_execution.auxiliary_resource option;samples:int;draw:Scene_execution.draw}
type text_input_region={x:int;y:int;width:int;height:int;focused:bool}
type mouse_button=Left|Middle|Right|X1|X2
type web_event=Pointer_moved of int*int|Pointer_pressed of mouse_button*int*int
  |Pointer_released of mouse_button*int*int|Pointer_cancelled of mouse_button
  |Wheel of int*int|Key_pressed of string|Key_released of string|Text_input of string
  |Text_editing of{text:string;start:int;length:int}|Resized of int*int|Focus_lost
  |File_uploaded of{name:string;contents:bytes}
type audio_command=Audio_master_volume of float|Audio_stop_all
  |Audio_sample_play of{asset:string;channel:int;loops:int;volume:float}
  |Audio_sample_volume of{asset:string;volume:float}|Audio_sample_stop of int
  |Audio_sample_pause of int|Audio_sample_resume of int
  |Audio_music_play of{asset:string;loops:int;fade_ms:int}|Audio_music_volume of float
  |Audio_music_pause|Audio_music_resume|Audio_music_stop of int|Audio_asset_remove of string
type backend_stats={uploaded_bytes:int64;cache_entries:int;gpu_timing_supported:bool;
  gpu_duration_seconds:float;gpu_sample_count:int64;retained_plan_builds:int64;
  retained_plan_hits:int64;retained_plan_misses:int64;retained_plan_evictions:int64;
  retained_plan_executions:int64;retained_plan_entries:int;retained_plan_capacity:int}
type backend={facts:facts;stats:unit->backend_stats;diagnostics:unit->diagnostics;
  render:Scene_execution.draw list->(bool,Ogpu.Error.t)result;
  render_prepared:prepared list->(bool,Ogpu.Error.t)result;
  resize:logical_width:int->logical_height:int->drawable_width:int->drawable_height:int->(unit,Ogpu.Error.t)result;
  capture:bytes_per_row:int->(bytes,Ogpu.Error.t)result;
  set_title:string->(unit,Ogpu.Error.t)result;set_position:x:int->y:int->(unit,Ogpu.Error.t)result;
  center:unit->(unit,Ogpu.Error.t)result;set_bordered:bool->(unit,Ogpu.Error.t)result;
  set_resizable:bool->(unit,Ogpu.Error.t)result;set_always_on_top:bool->(unit,Ogpu.Error.t)result;
  set_fullscreen:bool->(unit,Ogpu.Error.t)result;show:unit->(unit,Ogpu.Error.t)result;
  hide:unit->(unit,Ogpu.Error.t)result;visible:unit->(bool,Ogpu.Error.t)result;
  minimize:unit->(unit,Ogpu.Error.t)result;maximize:unit->(unit,Ogpu.Error.t)result;
  restore:unit->(unit,Ogpu.Error.t)result;web_url:unit->(string,Ogpu.Error.t)result;
  web_client_count:unit->(int,Ogpu.Error.t)result;drain_web_events:unit->(web_event list,Ogpu.Error.t)result;
  register_web_bytes:?content_type:string->bytes->(string,Ogpu.Error.t)result;
  remove_web_asset:string->(bool,Ogpu.Error.t)result;send_web_audio:audio_command->(unit,Ogpu.Error.t)result;
  download_web_frame:filename:string->(unit,Ogpu.Error.t)result;
  set_text_input_regions:text_input_region list->(unit,Ogpu.Error.t)result;
  destroy:unit->(unit,Ogpu.Error.t)result}
type provider={abi_version:int;target:target;name:string;create:configuration->(backend,Ogpu.Error.t)result}
let providers : provider option array=Array.make 3 None
let target_index=function Native->0|Headless->1|Web->2
let register_provider provider=
  if provider.abi_version<>Runtime_next_provider.abi_version then Error"provider ABI mismatch"
  else let index=target_index provider.target in match providers.(index)with
    |Some _->Error"duplicate runtime provider"|None->providers.(index)<-Some provider;Ok()
type t={target:target;implementation:backend;mutable facts:facts;
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
  then invalid op"dimensions must be positive"else
  match providers.(target_index c.target)with
  |None->error op Ogpu.Error.Unsupported"selected runtime provider is not loaded"
  |Some provider->Result.map(fun implementation->{target=c.target;implementation;
      facts=implementation.facts;pacing={frames=0L;presented=0L;last_presented=false};
      logical_draws=0L;logical_passes=0L;logical_submissions=0L;dead=false})(provider.create c)
let ensure operation value=if value.dead then error operation Ogpu.Error.Stale_handle"runtime is destroyed"else Ok()
let target value=value.target
let is_native value=value.target=Native
let is_headless value=value.target=Headless
let is_web value=value.target=Web
let is_displayless value=value.target<>Native
let facts value=Result.map(fun()->value.facts)(ensure"Runtime_next_orchestrator.facts"value)
let pacing value=Result.map(fun()->value.pacing)(ensure"Runtime_next_orchestrator.pacing"value)
let stats value=match ensure"Runtime_next_orchestrator.stats"value with Error _ as e->e|Ok()->
  let s=value.implementation.stats()in let uploaded_bytes=s.uploaded_bytes and cache_entries=s.cache_entries and gpu_timing_supported=s.gpu_timing_supported and gpu_duration_seconds=s.gpu_duration_seconds and gpu_sample_count=s.gpu_sample_count and retained_plan_builds=s.retained_plan_builds and retained_plan_hits=s.retained_plan_hits and retained_plan_misses=s.retained_plan_misses and retained_plan_evictions=s.retained_plan_evictions and retained_plan_executions=s.retained_plan_executions and retained_plan_entries=s.retained_plan_entries and retained_plan_capacity=s.retained_plan_capacity in
  Ok{frames=value.pacing.frames;presented=value.pacing.presented;logical_draws=value.logical_draws;
    logical_passes=value.logical_passes;logical_submissions=value.logical_submissions;uploaded_bytes;cache_entries;gpu_timing_supported;gpu_duration_seconds;gpu_sample_count;retained_plan_builds;retained_plan_hits;retained_plan_misses;retained_plan_evictions;retained_plan_executions;retained_plan_entries;retained_plan_capacity}
let native_release_queue()=None
let diagnostics value=
  let d=value.implementation.diagnostics()in{d with active=not value.dead}
let account value draw_count result =
  (match result with Ok presented->value.pacing<-{frames=Int64.succ value.pacing.frames;
    presented=(if presented then Int64.succ value.pacing.presented else value.pacing.presented);
    last_presented=presented};value.logical_draws<-Int64.add value.logical_draws(Int64.of_int draw_count);
    value.logical_passes<-Int64.succ value.logical_passes;value.logical_submissions<-Int64.succ value.logical_submissions|Error _->());result
let render value draws=match ensure"Runtime_next_orchestrator.render"value with Error _ as e->e|Ok()->
  account value(List.length draws)(value.implementation.render draws)
let render_prepared value draws=match ensure"Runtime_next_orchestrator.render_prepared"value with Error _ as e->e|Ok()->
  account value(List.length draws)(value.implementation.render_prepared draws)
let resize value~logical_width~logical_height~drawable_width~drawable_height=
  match ensure"Runtime_next_orchestrator.resize"value with Error _ as e->e|Ok()->let result=
    value.implementation.resize~logical_width~logical_height~drawable_width~drawable_height in
    (match result with Ok()->value.facts<-{value.facts with logical_width;logical_height;drawable_width;drawable_height;
      pixel_density=float drawable_width/.float logical_width;display_scale=float drawable_width/.float logical_width}|Error _->());result
let capture value~bytes_per_row=match ensure"Runtime_next_orchestrator.capture"value with Error _ as e->e|Ok()->
  value.implementation.capture~bytes_per_row
let native_call operation value call=match ensure operation value with Error _ as e->e|Ok()->if value.target=Native then call()else unsupported operation value.target
let set_title value title=match native_call"Runtime_next_orchestrator.set_title"value(fun()->value.implementation.set_title title)with
  |Ok()->value.facts<-{value.facts with title};Ok()|Error _ as e->e
let set_position value~x~y=match native_call"Runtime_next_orchestrator.set_position"value(fun()->value.implementation.set_position~x~y)with
  |Ok()->value.facts<-{value.facts with position=Some(x,y)};Ok()|Error _ as e->e
let center value=native_call"Runtime_next_orchestrator.center"value value.implementation.center
let set_bordered value x=native_call"Runtime_next_orchestrator.set_bordered"value(fun()->value.implementation.set_bordered x)
let set_resizable value x=native_call"Runtime_next_orchestrator.set_resizable"value(fun()->value.implementation.set_resizable x)
let set_always_on_top value x=native_call"Runtime_next_orchestrator.set_always_on_top"value(fun()->value.implementation.set_always_on_top x)
let set_fullscreen value x=native_call"Runtime_next_orchestrator.set_fullscreen"value(fun()->value.implementation.set_fullscreen x)
let show value=native_call"Runtime_next_orchestrator.show"value value.implementation.show
let hide value=native_call"Runtime_next_orchestrator.hide"value value.implementation.hide
let visible value=native_call"Runtime_next_orchestrator.visible"value value.implementation.visible
let minimize value=native_call"Runtime_next_orchestrator.minimize"value value.implementation.minimize
let maximize value=native_call"Runtime_next_orchestrator.maximize"value value.implementation.maximize
let restore value=native_call"Runtime_next_orchestrator.restore"value value.implementation.restore
let web_call operation value call=match ensure operation value with Error _ as e->e|Ok()->if value.target=Web then call()else unsupported operation value.target
let web_url value=web_call"Runtime_next_orchestrator.web_url"value value.implementation.web_url
let web_client_count value=web_call"Runtime_next_orchestrator.web_client_count"value value.implementation.web_client_count
let drain_web_events value=web_call"Runtime_next_orchestrator.drain_web_events"value value.implementation.drain_web_events
let register_web_bytes value?content_type bytes=web_call"Runtime_next_orchestrator.register_web_bytes"value(fun()->value.implementation.register_web_bytes?content_type bytes)
let remove_web_asset value id=web_call"Runtime_next_orchestrator.remove_web_asset"value(fun()->value.implementation.remove_web_asset id)
let send_web_audio value command=web_call"Runtime_next_orchestrator.send_web_audio"value(fun()->value.implementation.send_web_audio command)
let download_web_frame value~filename=web_call"Runtime_next_orchestrator.download_web_frame"value(fun()->value.implementation.download_web_frame~filename)
let set_text_input_regions value regions=web_call"Runtime_next_orchestrator.set_text_input_regions"value(fun()->value.implementation.set_text_input_regions regions)
let destroy value=if value.dead then Ok()else(value.dead<-true;value.implementation.destroy())
module Private=struct
  type nonrec backend_stats=backend_stats
  type nonrec backend=backend
  type nonrec provider=provider
  let register_provider=register_provider
end
