module Orchestrator = Runtime_next_orchestrator

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let environment bindings name = List.assoc_opt name bindings

let configuration extent : Orchestrator.configuration =
  { target = Native; logical_width = extent; logical_height = extent;
    drawable_width = extent; drawable_height = extent }

let () =
  if Orchestrator.target_of_string " native " <> Ok Native then
    failwith "native target parsing drift";
  List.iter (fun removed ->
      match Orchestrator.target_of_string removed with
      | Error _ -> ()
      | Ok _ -> failwith (removed ^ " target remained selectable"))
    [ "headless"; "web" ];
  if Orchestrator.select_with (environment []) <> Ok Native then
    failwith "native default selection drift";
  if Orchestrator.select_with (environment ["HEADLESS", "1"]) <> Ok Native then
    failwith "removed HEADLESS fallback remained active";
  begin match Orchestrator.select_with
      (environment ["PRISMEL_RENDER_TARGET", "web"]) with
  | Error _ -> ()
  | Ok _ -> failwith "removed explicit web target was accepted"
  end;
  begin match Orchestrator.create (configuration 4) with
  | Error _ -> print_endline "runtime_next orchestrator: native smoke skipped"
  | Ok runtime ->
      if not (Orchestrator.is_native runtime) then
        failwith "native target predicate drift";
      get (Orchestrator.set_title runtime "orchestrator native");
      get (Orchestrator.destroy runtime)
  end;
  print_endline "runtime_next orchestrator: native-only selection passed"
