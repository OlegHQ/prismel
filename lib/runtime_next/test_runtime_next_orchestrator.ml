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
      scissor = (0, 0, extent, extent) } }

let configuration ?wap_config target extent =
  { Orchestrator.target; logical_width = extent; logical_height = extent;
    drawable_width = extent; drawable_height = extent; wap_config }

let exercise runtime extent =
  for frame = 1 to 600 do
    ignore (get (Orchestrator.render runtime [ draw extent ]));
    if List.mem frame [ 1; 2; 60; 600 ] then begin
      let pixels =
        get (Orchestrator.capture runtime ~bytes_per_row:(extent * 4))
      in
      if Bytes.get_int32_be pixels 0 <> 0x4080bfffl then
        failwith "neutral capture did not return rendered pixels"
    end
  done

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
  exercise headless 4;
  get (Orchestrator.resize headless ~logical_width:4 ~logical_height:4
         ~drawable_width:8 ~drawable_height:8);
  exercise headless 8;
  get (Orchestrator.destroy headless);
  let wap_config =
    { Wap.default_config with interface = "127.0.0.1"; port = 0;
      compress_frames = false }
  in
  let web =
    get (Orchestrator.create (configuration ~wap_config Orchestrator.Web 4))
  in
  exercise web 4;
  get (Orchestrator.destroy web);
  begin
    match Orchestrator.create (configuration Orchestrator.Native 4) with
    | Error _ -> print_endline "runtime_next selector: native smoke skipped"
    | Ok native ->
        exercise native 4;
        get (Orchestrator.destroy native)
  end;
  print_endline "runtime_next selector: precedence, headless/web facts passed"
