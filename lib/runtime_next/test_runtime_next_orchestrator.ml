module Orchestrator = Runtime_next_orchestrator

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let environment values name = List.assoc_opt name values

let expect_selection values expected =
  match Orchestrator.select_with (environment values) with
  | Ok actual when actual = expected -> ()
  | Ok _ -> failwith "target selector chose the wrong target"
  | Error message -> failwith message

let mesh extent =
  let vertices = Bytes.make 48 '\000' in
  let set index x y =
    let offset = index * 16 in
    Bytes.set_int64_le vertices offset (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (offset + 8) (Int64.bits_of_float y)
  in
  set 0 0. 0.;
  set 1 (float extent) 0.;
  set 2 0. (float extent);
  let indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  { Scene_execution.key = "selector"; vertices; vertex_count = 3; indices;
    index_count = 3 }

let draw extent =
  { Scene_execution.mesh = mesh extent;
    state = { viewport = (0, 0, extent, extent);
      scissor = (0, 0, extent, extent);
      cull = Ogpu.Render_pass.Cull_none;
      depth_compare = Ogpu.Render_pass.Always; depth_write = false;
      depth_load = Ogpu.Render_pass.Clear; depth_clear = 1.;
      transform_uniforms = None; stencil_state = None;
      stencil_load = Ogpu.Render_pass.Clear; stencil_clear = 0 } }

let configuration ?web_configuration target extent =
  { Orchestrator.target; logical_width = extent; logical_height = extent;
    drawable_width = extent; drawable_height = extent; web_configuration }

let exercise runtime extent =
  let prepared family = { Orchestrator.family; blend=Orchestrator.Replace;
    texture=None; auxiliary=None; samples=1; draw=draw extent } in
  let combined=List.map prepared[Orchestrator.Scene2;Scene3;Scene3_textured;
    Scene3_shadow;Scene3_stencil;Scene3_textured_stencil;Scene3_shadow_stencil]in
  for frame = 1 to 600 do
    ignore(get(if List.mem frame[1;2;60;600]then Orchestrator.render_prepared runtime combined
      else Orchestrator.render runtime[draw extent]));
    if List.mem frame [ 1; 2; 60; 600 ] then begin
      let pixels =
        get (Orchestrator.capture runtime ~bytes_per_row:(extent * 4))
      in
      if Bytes.get_int32_be pixels 0 <> 0x4080bfffl then
        failwith "neutral capture did not return rendered pixels"
    end
  done

let check_stats runtime =
  let stats=get(Orchestrator.stats runtime)in
  if stats.frames<>600L||stats.presented<>600L||stats.logical_passes<>600L
    ||stats.logical_submissions<>600L||stats.logical_draws<=600L
    ||stats.uploaded_bytes<=0L||stats.cache_entries<=0 then
    failwith"orchestrator typed stats mismatch"

let exercise_native runtime extent =
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  List.iteri(fun index(x,y)->let offset=index*16 in Bytes.set_int32_le vertices offset(Int32.bits_of_float x);Bytes.set_int32_le vertices(offset+4)(Int32.bits_of_float y);Bytes.set_int32_le vertices(offset+8)0x4080bfffl)[-1.,-1.;3.,-1.;-1.,3.];
  let mesh={Scene_execution.key="selector-native";vertices;vertex_count=3;indices;index_count=3}in
  ignore(get(Orchestrator.render runtime[{Scene_execution.mesh;state={viewport=(0,0,extent,extent);scissor=(0,0,extent,extent);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0}}]));
  if Bytes.get_int32_be(get(Orchestrator.capture runtime~bytes_per_row:(extent*4)))0<>0x4080bfffl then failwith"native capture did not return rendered pixels"

let expect_unsupported label = function
  | Error error when error.Ogpu.Error.kind = Ogpu.Error.Unsupported -> ()
  | Ok () | Error _ -> failwith (label ^ " was not Unsupported")

let unsupported_desktop_operations label runtime =
  List.iter (fun (name, operation) -> expect_unsupported (label ^ " " ^ name)
      (operation runtime))
    [ "title", (fun value -> Orchestrator.set_title value "unsupported");
      "position", (fun value -> Orchestrator.set_position value ~x:1 ~y:2);
      "center", Orchestrator.center;
      "bordered", (fun value -> Orchestrator.set_bordered value true);
      "resizable", (fun value -> Orchestrator.set_resizable value true);
      "always-on-top", (fun value -> Orchestrator.set_always_on_top value true);
      "fullscreen", (fun value -> Orchestrator.set_fullscreen value true);
      "show", Orchestrator.show; "hide", Orchestrator.hide;
      "minimize", Orchestrator.minimize; "maximize", Orchestrator.maximize;
      "restore", Orchestrator.restore ]

let () =
  List.iter (fun (text, target) ->
      match Orchestrator.target_of_string text with
      | Ok actual when actual = target -> ()
      | _ -> failwith "target parsing table drift")
    [ "native", Orchestrator.Native; " HEADLESS ", Orchestrator.Headless;
      "Web", Orchestrator.Web ];
  expect_selection [] Orchestrator.Native;
  expect_selection [ "HEADLESS", "yes" ] Orchestrator.Headless;
  expect_selection [ "PRISMAL_RENDER_TARGET", "web"; "HEADLESS", "1" ]
    Orchestrator.Web;
  expect_selection [ "PRISMEL_RENDER_TARGET", "native";
                     "PRISMAL_RENDER_TARGET", "web"; "HEADLESS", "1" ]
    Orchestrator.Native;
  begin
    match Orchestrator.select_with
        (environment [ "PRISMEL_RENDER_TARGET", "future" ]) with
    | Error message when String.length message > 0 -> ()
    | _ -> failwith "invalid explicit target was accepted"
  end;
  let environment_snapshot =
    [ "PRISMEL_RENDER_TARGET", "invalid"; "HEADLESS", "1" ]
  in
  begin
    match Orchestrator.select_with (environment environment_snapshot) with
    | Error _ -> ()
    | Ok _ -> failwith "selector accepted an invalid explicit target"
  end;
  if environment_snapshot
     <> [ "PRISMEL_RENDER_TARGET", "invalid"; "HEADLESS", "1" ]
  then failwith "selector mutated its environment source";
  let headless =
    get (Orchestrator.create (configuration Orchestrator.Headless 4))
  in
  if not (Orchestrator.is_headless headless)
      || not (Orchestrator.is_displayless headless) then
    failwith "headless target predicates changed";
  let headless_facts = get (Orchestrator.facts headless) in
  if headless_facts.logical_width <> 4 || not headless_facts.vsync then
    failwith "headless facts changed";
  unsupported_desktop_operations "headless" headless;
  exercise headless 4;
  get (Orchestrator.resize headless ~logical_width:4 ~logical_height:4
         ~drawable_width:8 ~drawable_height:8);
  exercise headless 8;
  let pacing = get (Orchestrator.pacing headless) in
  if pacing.frames <> 1_200L || pacing.presented <> 1_200L
      || not pacing.last_presented then failwith "headless pacing facts changed";
  get (Orchestrator.destroy headless);
  (match Orchestrator.facts headless with
   | Error error when error.Ogpu.Error.kind = Ogpu.Error.Stale_handle -> ()
   | Ok _ | Error _ -> failwith "destroyed headless facts remained accessible");
  let web_configuration =
    { Orchestrator.default_web_configuration with interface = "127.0.0.1"; port = 0;
      compress_frames = false }
  in
  let web =
    get (Orchestrator.create (configuration ~web_configuration Orchestrator.Web 4))
  in
  if not (Orchestrator.is_web web) || not (Orchestrator.is_displayless web)
      || get (Orchestrator.web_client_count web) <> 0
      || get (Orchestrator.drain_web_events web) <> [] then
    failwith "web target-neutral facts changed";
  unsupported_desktop_operations "web" web;
  if get (Orchestrator.web_url web) = "" then failwith "web URL is empty";
  let asset = get (Orchestrator.register_web_bytes web
      ~content_type:"application/octet-stream" (Bytes.of_string "asset")) in
  if not (get (Orchestrator.remove_web_asset web asset)) then
    failwith "web asset was not removed";
  get (Orchestrator.send_web_audio web Orchestrator.Audio_stop_all);
  get (Orchestrator.set_text_input_regions web
    [{Orchestrator.x=1;y=2;width=3;height=4;focused=true}]);
  exercise web 4;check_stats web;
  get (Orchestrator.destroy web);
  (match Orchestrator.stats web with Error e when e.kind=Ogpu.Error.Stale_handle->()|_->failwith"destroyed stats not stale");
  begin
    match Orchestrator.create (configuration Orchestrator.Native 4) with
    | Error _ -> print_endline "runtime_next selector: native smoke skipped"
    | Ok native ->
        if not (Orchestrator.is_native native)
            || Orchestrator.is_displayless native then
          failwith "native target predicates changed";
        get (Orchestrator.set_title native "orchestrator native renamed");
        let facts = get (Orchestrator.facts native) in
        if facts.title <> "orchestrator native renamed" then
          failwith "native title facts did not refresh";
        get (Orchestrator.set_bordered native false);
        get (Orchestrator.set_bordered native true);
        get (Orchestrator.set_resizable native false);
        get (Orchestrator.set_resizable native true);
        get (Orchestrator.set_always_on_top native true);
        get (Orchestrator.set_always_on_top native false);
        get (Orchestrator.center native);
        get (Orchestrator.show native);
        get (Orchestrator.hide native);
        get (Orchestrator.set_fullscreen native true);
        get (Orchestrator.set_fullscreen native false);
        get (Orchestrator.minimize native);
        get (Orchestrator.restore native);
        get (Orchestrator.maximize native);
        get (Orchestrator.restore native);
        exercise_native native 4;
        get (Orchestrator.destroy native)
  end;
  let lifecycle_iterations = match Sys.getenv_opt "PRISMEL_RUNTIME_NEXT_STRESS" with
    | Some "1" -> 10_000 | _ -> 100
  in
  for _ = 1 to lifecycle_iterations do
    let runtime = get (Orchestrator.create
      (configuration Orchestrator.Headless 1)) in
    get (Orchestrator.destroy runtime)
  done;
  print_endline "runtime_next selector: precedence, headless/web facts passed"
