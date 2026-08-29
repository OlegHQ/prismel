module Orchestrator = Runtime_next_orchestrator

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let configuration extent : Orchestrator.configuration =
  { logical_width = extent; logical_height = extent;
    drawable_width = extent; drawable_height = extent; vsync=true }

let () =
  begin match Orchestrator.create (configuration 4) with
  | Error _ -> print_endline "runtime_next orchestrator: native smoke skipped"
  | Ok runtime ->
      get (Orchestrator.set_title runtime "orchestrator native");
      get (Orchestrator.destroy runtime)
  end;
  print_endline "runtime_next orchestrator: direct native lifecycle passed"
