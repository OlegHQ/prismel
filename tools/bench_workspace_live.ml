(* Live workspace playback (plan W2b).
   dune exec tools/bench_workspace_live.exe -- [frames] [domains] [cases-dir]
   Per case: p50 / p99 frame cost split into resolve (Value_lane), compile
   (compile_all + compiled_node), submit (Async_cook.submit) and cook (await
   of the worker, i.e. Session cook + prepare), plus Session hits / misses. *)
open Flow_sop

let factories = Sop_catalog.Editor.factories
let ok = function Ok v -> v | Error d -> failwith (Flow.Diagnostic.to_string d)
let now = Unix.gettimeofday
let read path = In_channel.with_open_bin path In_channel.input_all

let replace text ~from ~by =
  match Str.search_forward (Str.regexp_string from) text 0 with
  | _ -> Str.replace_first (Str.regexp_string from) (String.concat "\\\\" (String.split_on_char '\\' by)) text
  | exception Not_found -> failwith ("no " ^ from)

let percentile sorted p =
  sorted.(min (Array.length sorted - 1) (int_of_float (p *. float (Array.length sorted))))

let run ~frames ~domains name source =
  let forms = ok (Flow.Syntax.parse source) in
  let lowered = ok (Lower.workspace ~factories forms) in
  let graph = List.find (fun (g : Lower.graph) -> g.root <> None) lowered.graphs in
  let root = Option.get graph.root in
  let worker = Result.get_ok (Procedural.Async_cook.create ~max_entries:512
    ~max_payload_bytes:(256 * 1024 * 1024)) in
  Procedural.Async_cook.set_volatile worker (Lower.is_volatile lowered);
  let lane = Value_lane.create () in
  let previous = ref None in
  let columns = Array.init 5 (fun _ -> Array.make frames 0.) in
  let live = List.length lowered.pending in
  for n = 0 to frames - 1 do
    let time = float n /. 60. in
    let t0 = now () in
    let resolved = ok (Value_lane.resolve lane ~time graph.network) in
    let t1 = now () in
    let compiled = Procedural.Edit_graph.compile_all ?previous:!previous resolved.geometry in
    previous := Some compiled;
    let node = Result.get_ok (Procedural.Edit_graph.compiled_node compiled ~node_id:root) in
    let t2 = now () in
    let context = Result.get_ok (Procedural.Context.create ~domains ~grain:256 ~seed:1L ()) in
    (* BENCH_PROBES: the footers' request, up to 64 upstream nodes cooked after the display (cache and volatile hits) *)
    let probes = if Sys.getenv_opt "BENCH_PROBES" = None then [] else
      List.take 64 (List.filter_map (fun (info : Procedural.Graph.info) ->
        if info.id = root then None else Procedural.Graph.find node ~node_id:info.id) (Procedural.Graph.inspect node)) in
    ignore (Result.get_ok (Procedural.Async_cook.submit_all worker ~context ~nodes:(node :: probes)
      ~prepare:(fun outputs -> Ok (List.hd outputs).geometry)));
    let t3 = now () in
    (match (Procedural.Async_cook.await worker).result with
     | Ok _ -> () | Error e -> failwith (Procedural.Async_cook.error_to_string e));
    let t4 = now () in
    List.iteri (fun i v -> columns.(i).(n) <- v *. 1000.)
      [t1 -. t0; t2 -. t1; t3 -. t2; t4 -. t3; t4 -. t0]
  done;
  (* the evaluator share of resolve: force every live argument once *)
  let force_ms = let t0 = now () in
    for n = 0 to 49 do List.iter (fun (p : Lower.pending) ->
      ignore (ok (Flow.Eval.force p.value ~live:{Flow.Eval.t = float n /. 60.}))) lowered.pending done;
    (now () -. t0) *. 1000. /. 50. in
  let stats = Procedural.Async_cook.stats worker in
  Procedural.Async_cook.close worker;
  let cell i p = let sorted = Array.copy columns.(i) in
    Array.sort Float.compare sorted; percentile sorted p in
  Printf.printf "%-10s Eval.force of all live args: %.3f ms\n" name force_ms;
  Printf.printf "%-10s live args %3d volatile nodes %3d | p50 ms: resolve %6.3f compile %6.3f submit %6.3f cook %7.3f total %7.3f | p99 total %7.3f | hits %d misses %d (volatile %d/%d) evicted %d retained %d+%d\n%!"
    name live (Network.Int_map.cardinal lowered.volatile)
    (cell 0 0.5) (cell 1 0.5) (cell 2 0.5) (cell 3 0.5) (cell 4 0.5) (cell 4 0.99)
    stats.hits stats.misses stats.volatile_hits stats.volatile_misses stats.evictions
    stats.retained_entries stats.volatile_entries

let () =
  let frames = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 600 in
  let domains = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 1 in
  let dir = if Array.length Sys.argv > 3 then Sys.argv.(3) else "specification/workspace/cases" in
  Printf.printf "frames %d domains %d (available %d)\n" frames domains
    (Domain.recommended_domain_count ());
  let only = Sys.getenv_opt "BENCH_CASE" in
  let run ~frames ~domains name source =
    if only = None || only = Some name then run ~frames ~domains name source in
  let case name = read (Filename.concat dir (name ^ ".lisp")) in
  run ~frames ~domains "orrery" (case "orrery");
  run ~frames ~domains "wave" (case "wave");
  run ~frames ~domains "sunflower" (case "sunflower");
  run ~frames ~domains "sunflower-live"
    (replace (case "sunflower") ~from:"(* spread (sqrt i))"
       ~by:"(* (* spread (+ 1 (* 0.3 (sin t)))) (sqrt i))")
