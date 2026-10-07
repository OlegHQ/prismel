type phase = Print | Parse | Check | Evaluate | Lower | Project | Layout | Reduce | Cook
type entry = { phase : phase; calls : int; seconds : float }
type t = { total : float; entries : entry list }
let phases = [Print; Parse; Check; Evaluate; Lower; Project; Layout; Reduce; Cook]
let name = function
  | Print -> "print" | Parse -> "parse" | Check -> "check" | Evaluate -> "evaluate"
  | Lower -> "lower" | Project -> "project" | Layout -> "layout" | Reduce -> "reduce" | Cook -> "cook"
let empty = { total = 0.; entries = [] }
type scope = { mutable children : float }
type sample = { now : unit -> float; started : float; mutable entries : entry list; mutable stack : scope list }
let current = Domain.DLS.new_key (fun () -> None)
let measure phase run = match Domain.DLS.get current with
  | None -> run ()
  | Some sample ->
      let started = sample.now () in
      let parent = sample.stack and scope = { children = 0. } in
      sample.stack <- scope :: parent;
      Fun.protect run ~finally:(fun () ->
        let elapsed = sample.now () -. started in
        sample.stack <- parent;
        (match parent with p :: _ -> p.children <- p.children +. elapsed | [] -> ());
        let prior = List.find_opt (fun e -> e.phase = phase) sample.entries in
        let entry = { phase; calls = 1 + Option.fold ~none:0 ~some:(fun e -> e.calls) prior;
          seconds = max 0. (elapsed -. scope.children)
            +. Option.fold ~none:0. ~some:(fun e -> e.seconds) prior } in
        sample.entries <- entry :: List.filter (fun e -> e.phase <> phase) sample.entries)
let sample ~clock run =
  let snapshot sample = { total = sample.now () -. sample.started;
    entries = List.filter_map (fun phase -> List.find_opt (fun e -> e.phase = phase) sample.entries) phases } in
  match Domain.DLS.get current with
  | Some sample ->
      let value = run () in
      value, snapshot sample
  | None ->
      let last = ref (clock ()) in
      let now () = last := max !last (clock ()); !last in
      let sample = { now; started = !last; entries = []; stack = [] } in
      Domain.DLS.set current (Some sample);
      Fun.protect ~finally:(fun () -> Domain.DLS.set current None) (fun () ->
        let value = run () in
        value, snapshot sample)
let calls (t : t) phase = Option.fold ~none:0 ~some:(fun e -> e.calls)
  (List.find_opt (fun e -> e.phase = phase) t.entries)
let seconds (t : t) phase = Option.fold ~none:0. ~some:(fun e -> e.seconds)
  (List.find_opt (fun e -> e.phase = phase) t.entries)
let summary (t : t) = String.concat " · " (List.map (fun e ->
  Printf.sprintf "%s %.1f ms" (name e.phase) (e.seconds *. 1000.)) t.entries)
