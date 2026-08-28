open Runtime_next_orchestrator

let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let unsupported operation () = Error (Ogpu.Error.make operation Ogpu.Error.Unsupported "unsupported")
let initial_facts={title="fake";logical_width=4;logical_height=4;drawable_width=4;drawable_height=4;
  position=None;pixel_density=1.;display_scale=1.;refresh_rate=None;vsync=false}
let backend_stats={uploaded_bytes=7L;cache_entries=2;gpu_timing_supported=false;gpu_duration_seconds=0.;
  gpu_sample_count=0L;retained_plan_builds=0L;retained_plan_hits=0L;retained_plan_misses=0L;
  retained_plan_evictions=0L;retained_plan_executions=0L;retained_plan_entries=0;retained_plan_capacity=0}
let backend_create _ =
  let destroyed=ref false in
  Ok {facts=initial_facts;stats=(fun()->backend_stats);diagnostics=(fun()->{active=not !destroyed;cache_entries=2;
    release_queue_pending=None;release_queue_live_handles=None;release_queue_total_created=None;
    release_queue_total_released=None});render=(fun _->Ok true);render_prepared=(fun _->Ok true);
    resize=(fun~logical_width:_~logical_height:_~drawable_width:_~drawable_height:_->Ok());
    capture=(fun~bytes_per_row->Ok(Bytes.make bytes_per_row '\000'));
    set_title=(fun _->Ok());set_position=(fun~x:_~y:_->Ok());center=(fun()->Ok());
    set_bordered=(fun _->Ok());set_resizable=(fun _->Ok());set_always_on_top=(fun _->Ok());
    set_fullscreen=(fun _->Ok());show=(fun()->Ok());hide=(fun()->Ok());visible=(fun()->Ok false);
    minimize=(fun()->Ok());maximize=(fun()->Ok());restore=(fun()->Ok());web_url=unsupported"url";
    web_client_count=unsupported"clients";drain_web_events=unsupported"events";
    register_web_bytes=(fun?content_type:_ _->Error(Ogpu.Error.make"bytes"Unsupported"unsupported"));
    remove_web_asset=(fun _->Error(Ogpu.Error.make"asset"Unsupported"unsupported"));
    send_web_audio=(fun _->Error(Ogpu.Error.make"audio"Unsupported"unsupported"));
    download_web_frame=(fun~filename:_->Error(Ogpu.Error.make"download"Unsupported"unsupported"));
    set_text_input_regions=(fun _->Error(Ogpu.Error.make"regions"Unsupported"unsupported"));
    destroy=(fun()->destroyed:=true;Ok())}

let () =
  let configuration={target=Headless;logical_width=4;logical_height=4;drawable_width=4;
    drawable_height=4;web_configuration=None}in
  (match Runtime_next_orchestrator.create configuration with Error{Ogpu.Error.kind=Unsupported;_}->()|_->failwith"missing provider accepted");
  if Private.register_provider{abi_version=Runtime_next_provider.abi_version;target=Headless;name="fake";create=backend_create}<>Ok()then failwith"provider registration";
  let runtime=get(Runtime_next_orchestrator.create configuration)in
  if not(get(render runtime[]))then failwith"provider render";
  if (get(pacing runtime)).frames<>1L||(get(stats runtime)).uploaded_bytes<>7L then failwith"provider accounting";
  get(resize runtime~logical_width:8~logical_height:8~drawable_width:8~drawable_height:8);
  if (get(facts runtime)).logical_width<>8 then failwith"provider resize facts";
  get(destroy runtime);get(destroy runtime);
  print_endline"runtime-next operational provider boundary passed"
