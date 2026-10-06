(* Workspace lowering and cook.
   dune exec tools/bench_workspace_lower.exe -- [cases-dir] [repeats]
   Per fixture: check / eval / lower+cook medians.  Then, for Bloom, Sunflower,
   Wave and Tree: cold and warm cook at Session capacity 32 and 512. *)
open Flow_sop

let factories = Sop_catalog.Editor.factories
let ok = function Ok v -> v | Error d -> failwith (Flow.Diagnostic.to_string d)
let now = Unix.gettimeofday
let median f repeats =
  let times = Array.init repeats (fun _ -> let t = now () in ignore (f ()); now () -. t) in
  Array.sort Float.compare times; times.(repeats / 2) *. 1000.

let cook_graph ~session (graph : Lower.graph) =
  let compiled = Result.get_ok (Procedural.Edit_graph.compile_node
    graph.network.geometry ~node_id:(Option.get graph.root)) in
  let context = Result.get_ok (Procedural.Context.create ()) in
  match Procedural.Session.cook session ~context compiled with
  | Ok output -> output
  | Error e -> failwith (Procedural.Diagnostic.error_to_string e)

let () =
  let dir = if Array.length Sys.argv > 1 then Sys.argv.(1) else "_build/default/specification/workspace/cases" in
  let repeats = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 21 in
  Printf.printf "domains available %d, repeats %d (medians, ms)\n"
    (Domain.recommended_domain_count ()) repeats;
  let catalog = ok (Editor_document.Contexts.catalog ~version:Manifest.version factories) in
  Printf.printf "%-11s %8s %8s %8s %8s %8s %6s\n" "fixture" "check" "eval" "lower" "cook1" "l+cook" "nodes";
  let forms name = ok (Flow.Syntax.parse
    (In_channel.with_open_bin (Filename.concat dir (name ^ ".lisp")) In_channel.input_all)) in
  let all = List.filter_map (fun f ->
    if Filename.check_suffix f ".lisp" then Some (Filename.chop_suffix f ".lisp") else None)
    (List.sort compare (Array.to_list (Sys.readdir dir))) in
  List.iter (fun name ->
    let forms = forms name in
    let check () = match Flow.Workspace.check catalog forms with
      | Some ws, _ -> ws | None, _ -> failwith "check" in
    let ws = check () in
    let t_check = median check repeats in
    let t_eval = median (fun () -> ok (Flow.Eval.static ws)) repeats in
    let lower () = ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories forms) in
    let t_total = median lower repeats in
    let lowered = lower () in
    let graph = List.hd lowered.graphs in
    let nodes = List.fold_left (fun n (g : Lower.graph) ->
      n + List.length (Procedural.Edit_graph.inspect g.network.geometry)) 0 lowered.graphs in
    let cook () =
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      ignore (cook_graph ~session graph); Procedural.Session.close session in
    let t_cook = median cook (max 3 (repeats / 3)) in
    let both () = let l = lower () in
      let g = List.hd l.graphs in
      let session = Result.get_ok (Procedural.Session.create ~max_entries:512
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      ignore (cook_graph ~session g); Procedural.Session.close session in
    let t_both = median both (max 3 (repeats / 3)) in
    Printf.printf "%-11s %8.3f %8.3f %8.3f %8.3f %8.3f %6d\n%!" name t_check t_eval
      (t_total -. t_check -. t_eval) t_cook t_both nodes) all;
  print_endline "\nSession capacity: cold cook, then the same cook again (warm), per max_entries";
  Printf.printf "%-11s %8s %10s %10s %8s %8s %10s\n" "fixture" "entries" "cold ms" "warm ms" "retained" "evicted" "payload MB";
  List.iter (fun name ->
    let graph = List.hd (ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories (forms name))).graphs in
    List.iter (fun entries ->
      Gc.compact ();
      let session = Result.get_ok (Procedural.Session.create ~max_entries:entries
        ~max_payload_bytes:(256 * 1024 * 1024)) in
      let t = now () in ignore (cook_graph ~session graph);
      let cold = (now () -. t) *. 1000. in
      let warm = median (fun () -> cook_graph ~session graph) 7 in
      let stats = Procedural.Session.stats session in
      Printf.printf "%-11s %8d %10.3f %10.3f %8d %8d %10.2f  (heap %d MB)\n%!" name entries cold warm
        stats.retained_entries stats.evictions
        (float stats.retained_payload_bytes /. 1048576.)
        ((Gc.quick_stat ()).top_heap_words * 8 / 1048576);
      Procedural.Session.close session) [32; 512])
    ["bloom"; "sunflower"; "wave"; "tree"]
