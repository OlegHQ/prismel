type configuration = { logical_width:int;logical_height:int;
  drawable_width:int;drawable_height:int;title:string;vsync:bool }
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
type t={runtime:Runtime_next.t;mutable facts:facts;
  mutable pacing:pacing;mutable logical_draws:int64;mutable logical_passes:int64;
  mutable logical_submissions:int64;mutable dead:bool}
let error operation kind message=Error(Ogpu.Error.make operation kind message)
let invalid operation message=error operation Ogpu.Error.Invalid_argument message
let create (c:configuration)=let op="Runtime_next_orchestrator.create"in
  if c.logical_width<=0||c.logical_height<=0||c.drawable_width<=0||c.drawable_height<=0
  then invalid op"dimensions must be positive"else let finish runtime facts=
    Ok{runtime;facts;pacing={frames=0L;presented=0L;last_presented=false};logical_draws=0L;logical_passes=0L;logical_submissions=0L;dead=false}in
  match Runtime_next.create~vsync:c.vsync~hidden:false~title:c.title
      ~width:c.logical_width~height:c.logical_height() with Error _ as e->e|Ok runtime->
      (match Runtime_next.set_title runtime c.title,Runtime_next.set_resizable runtime true with
       |Ok(),Ok()->(match Runtime_next.window_facts runtime~vsync:c.vsync with
          |Ok f->finish runtime {title=f.title;logical_width=f.logical_width;logical_height=f.logical_height;drawable_width=f.drawable_width;drawable_height=f.drawable_height;position=Some f.position;pixel_density=f.pixel_density;display_scale=f.display_scale;refresh_rate=f.refresh_rate;vsync=f.vsync}
          |Error e->ignore(Runtime_next.destroy runtime);Error e)
       |Error e,_|_,Error e->ignore(Runtime_next.destroy runtime);Error e)
let ensure operation value=if value.dead then error operation Ogpu.Error.Stale_handle"runtime is destroyed"else Ok()
let facts value=Result.map(fun()->value.facts)(ensure"Runtime_next_orchestrator.facts"value)
let pacing value=Result.map(fun()->value.pacing)(ensure"Runtime_next_orchestrator.pacing"value)
let stats value=match ensure"Runtime_next_orchestrator.stats"value with Error _ as e->e|Ok()->
  let s=Runtime_next.stats value.runtime in
  let uploaded_bytes,cache_entries,gpu_timing_supported,gpu_duration_seconds,gpu_sample_count,retained_plan_builds,retained_plan_hits,retained_plan_misses,retained_plan_evictions,retained_plan_executions,retained_plan_entries,retained_plan_capacity=s.uploaded_bytes,s.mesh_cache_entries,s.gpu_timing_supported,s.gpu_duration_seconds,s.gpu_sample_count,s.retained_plan_builds,s.retained_plan_hits,s.retained_plan_misses,s.retained_plan_evictions,s.retained_plan_executions,s.retained_plan_entries,s.retained_plan_capacity in
  Ok{frames=value.pacing.frames;presented=value.pacing.presented;logical_draws=value.logical_draws;
    logical_passes=value.logical_passes;logical_submissions=value.logical_submissions;uploaded_bytes;cache_entries;gpu_timing_supported;gpu_duration_seconds;gpu_sample_count;retained_plan_builds;retained_plan_hits;retained_plan_misses;retained_plan_evictions;retained_plan_executions;retained_plan_entries;retained_plan_capacity}
let native_release_queue()=match Metal.Release_queue.stats()with
  |Ok stats->Some(stats.pending,stats.live_handles,stats.total_created,stats.total_released)
  |Error _->None
let diagnostics value=
  let s=Runtime_next.stats value.runtime in
  let cache_entries=s.mesh_cache_entries+s.pipeline_cache_entries in
  let release_queue=native_release_queue() in
  {active=not value.dead;cache_entries;
   release_queue_pending=Option.map(fun(pending,_,_,_)->pending)release_queue;
   release_queue_live_handles=Option.map(fun(_,live,_,_)->live)release_queue;
   release_queue_total_created=Option.map(fun(_,_,created,_)->created)release_queue;
   release_queue_total_released=Option.map(fun(_,_,_,released)->released)release_queue}
let account value draw_count result =
  (match result with Ok presented->value.pacing<-{frames=Int64.succ value.pacing.frames;
    presented=(if presented then Int64.succ value.pacing.presented else value.pacing.presented);
    last_presented=presented};value.logical_draws<-Int64.add value.logical_draws(Int64.of_int draw_count);
    value.logical_passes<-Int64.succ value.logical_passes;value.logical_submissions<-Int64.succ value.logical_submissions|Error _->());result
let render value draws=match ensure"Runtime_next_orchestrator.render"value with Error _ as e->e|Ok()->
  account value(List.length draws)(Runtime_next.render value.runtime draws)
let scene_family=function Scene2->Scene_execution.Scene2|Scene2_textured->Scene2_textured|Scene3->Scene3
  |Scene3_textured->Scene3_textured|Scene3_shadow->Scene3_shadow
  |Scene3_stencil->Scene3_stencil|Scene3_textured_stencil->Scene3_textured_stencil
  |Scene3_shadow_stencil->Scene3_shadow_stencil
let pipeline_blend=function Replace->Ogpu.Pipeline.Replace|Alpha->Alpha|Add->Add
  |Multiply->Multiply|Screen->Screen|Subtract->Subtract
let pull_window_facts value=
  let live=Runtime_next.frame_facts value.runtime in
  value.facts<-{value.facts with logical_width=live.logical_width;
    logical_height=live.logical_height;drawable_width=live.drawable_width;
    drawable_height=live.drawable_height;
    pixel_density=live.pixel_scale_x;display_scale=live.pixel_scale_x}
let render_prepared ?after_prepare ?clear value draws=match ensure"Runtime_next_orchestrator.render_prepared"value with Error _ as e->Option.iter(fun f->f())after_prepare;e|Ok()->
  let draws=List.map(fun x->scene_family x.family,pipeline_blend x.blend,x.texture,x.auxiliary,x.samples,x.draw)draws in
  let result=account value(List.length draws)(Runtime_next.render_sampled_resources ?after_prepare ?clear value.runtime draws)in
  (match result with Ok _->pull_window_facts value|Error _->());result
let render_retained ?after_prepare ?clear ~identity ~version value draws=
  match ensure"Runtime_next_orchestrator.render_retained"value with Error _ as e->Option.iter(fun f->f())after_prepare;e|Ok()->
  let draws=List.map(fun x->scene_family x.family,pipeline_blend x.blend,x.texture,x.auxiliary,x.samples,x.draw)draws in
  let result=account value(List.length draws)
    (Runtime_next.render_prepared_sampled_resources ?after_prepare ?clear ~identity ~version value.runtime draws)in
  (match result with Ok _->pull_window_facts value|Error _->());result
let replay_retained ?clear ~identity ~version value=
  match ensure"Runtime_next_orchestrator.replay_retained"value with
  |Error _ as e->e
  |Ok()->match Runtime_next.replay_prepared_sampled_resources ?clear ~identity
      ~version value.runtime with
    |Error _ as e->e
    |Ok None->pull_window_facts value;Ok None
    |Ok(Some(presented,draw_count))->
        pull_window_facts value;
        Result.map Option.some(account value draw_count(Ok presented))
let resize value~logical_width~logical_height~drawable_width~drawable_height=
  match ensure"Runtime_next_orchestrator.resize"value with Error _ as e->e|Ok()->let result=
    Runtime_next.resize value.runtime~width:logical_width~height:logical_height in
    (match result with
     |Error _->()
     |Ok()->
        ignore(drawable_width,drawable_height);
        match Runtime_next.window_facts value.runtime~vsync:value.facts.vsync with
        |Error _->()
        |Ok facts->value.facts<-
            {title=facts.title;logical_width=facts.logical_width;
             logical_height=facts.logical_height;
             drawable_width=facts.drawable_width;drawable_height=facts.drawable_height;
             position=Some facts.position;pixel_density=facts.pixel_density;
             display_scale=facts.display_scale;refresh_rate=facts.refresh_rate;
             vsync=facts.vsync});result
let capture value~bytes_per_row=match ensure"Runtime_next_orchestrator.capture"value with Error _ as e->e|Ok()->
  Runtime_next.read_pixels value.runtime~bytes_per_row
let capture_into value~bytes_per_row~destination=
  match ensure"Runtime_next_orchestrator.capture_into"value with Error _ as e->e|Ok()->
  Runtime_next.read_pixels_into value.runtime~bytes_per_row~destination
let native_call operation value call=match ensure operation value with Error _ as e->e|Ok()->
  call value.runtime
let set_title value title=match native_call"Runtime_next_orchestrator.set_title"value(fun x->Runtime_next.set_title x title)with
  |Ok()->value.facts<-{value.facts with title};Ok()|Error _ as e->e
let set_position value~x~y=match native_call"Runtime_next_orchestrator.set_position"value(fun r->Runtime_next.set_position r~x~y)with
  |Ok()->value.facts<-{value.facts with position=Some(x,y)};Ok()|Error _ as e->e
let center value=native_call"Runtime_next_orchestrator.center"value Runtime_next.center
let set_bordered value x=native_call"Runtime_next_orchestrator.set_bordered"value(fun r->Runtime_next.set_bordered r x)
let set_resizable value x=native_call"Runtime_next_orchestrator.set_resizable"value(fun r->Runtime_next.set_resizable r x)
let set_always_on_top value x=native_call"Runtime_next_orchestrator.set_always_on_top"value(fun r->Runtime_next.set_always_on_top r x)
let set_fullscreen value x=native_call"Runtime_next_orchestrator.set_fullscreen"value(fun r->Runtime_next.set_fullscreen r x)
let show value=match native_call"Runtime_next_orchestrator.show"value Runtime_next.show with
  |Error _ as error->error|Ok()->pull_window_facts value;Ok()
let hide value=native_call"Runtime_next_orchestrator.hide"value Runtime_next.hide
let visible value=native_call"Runtime_next_orchestrator.visible"value Runtime_next.visible
let minimize value=native_call"Runtime_next_orchestrator.minimize"value Runtime_next.minimize
let maximize value=native_call"Runtime_next_orchestrator.maximize"value Runtime_next.maximize
let restore value=native_call"Runtime_next_orchestrator.restore"value Runtime_next.restore
let destroy value=if value.dead then Ok()else(value.dead<-true;Runtime_next.destroy value.runtime)
