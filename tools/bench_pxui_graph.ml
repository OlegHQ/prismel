open Procedural

let repeats = 10_000

let percentile values fraction =
  Array.sort Float.compare values;
  values.(min (Array.length values - 1)
    (max 0 (int_of_float (Float.ceil
      (fraction *. float_of_int (Array.length values))) - 1)))

let graph count =
  let rec divisor candidate =
    if candidate <= 2 || count mod candidate = 0 then candidate
    else divisor (candidate - 1) in
  let width = divisor (min count 64) in
  let created = ref width in
  let generation = ref 0 in
  let layer = ref (Array.init width (fun index ->
    Sop.points ~label:(Printf.sprintf "source-%d" index)
      [|float_of_int index, 0., 0.|])) in
  while !created < count do
    let size = min width (count - !created) in
    let previous = !layer in
    layer := Array.init size (fun index ->
      let left = previous.(index mod Array.length previous)
      and right = previous.((index + 1) mod Array.length previous) in
      Sop.merge ~label:(Printf.sprintf "node-%d-%d" !generation index)
        [left; right]);
    created := !created + size;
    incr generation
  done;
  Sop.merge ~label:"output" (Array.to_list !layer)

let measure count =
  let view = Pxui_graph.create ~width:1200 ~height:760 (graph count) in
  let nodes = Pxui_graph.node_views view in
  let targets = nodes |> List.to_seq |> Seq.take 32 |> Array.of_seq
    |> Array.map (fun node ->
      let x, y, width, height = node.Pxui_graph.bounds in
      x + (width / 2), y + (height / 2)) in
  let wire_targets = Pxui_graph.Private.edge_query_points view ~limit:32 in
  let samples = Array.make repeats 0.
  and edge_samples = Array.make repeats 0. in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let hits = ref 0 and max_candidates = ref 0
  and max_edge_candidates = ref 0 in
  for index = 0 to repeats - 1 do
    let point = targets.(index mod Array.length targets) in
    let started = Unix.gettimeofday () in
    if Option.is_some (Pxui_graph.Private.hit_node_id view point) then incr hits;
    samples.(index) <- Unix.gettimeofday () -. started;
    max_candidates := max !max_candidates
      (Pxui_graph.Private.hit_candidates view point);
    max_edge_candidates := max !max_edge_candidates
      (Pxui_graph.Private.hit_edge_candidates view
        wire_targets.(index mod Array.length wire_targets));
    let edge_point = wire_targets.(index mod Array.length wire_targets) in
    let started = Unix.gettimeofday () in
    ignore (Pxui_graph.Private.hit_edge_id view edge_point);
    edge_samples.(index) <- Unix.gettimeofday () -. started
  done;
  let allocated = Gc.allocated_bytes () -. before in
  let stats = Pxui_graph.stats view in
  Printf.printf
    "pxui_graph,%d,%d,%d,%d,%.9f,%.9f,%.9f,%.0f,%d,%d,%d,%d,%d\n%!"
    count stats.nodes stats.wires !hits
    (percentile (Array.copy samples) 0.5)
    (percentile samples 0.99) (percentile edge_samples 0.99) allocated
    stats.visible_nodes
    !max_candidates !max_edge_candidates stats.spatial_cells
    stats.spatial_edge_cells

let () =
  Printf.printf
    "benchmark,requested_nodes,nodes,wires,hits,median_seconds,p99_seconds,edge_p99_seconds,allocated_bytes,visible_nodes,max_candidates,max_edge_candidates,spatial_cells,spatial_edge_cells\n%!";
  List.iter measure [100; 1_000; 10_000]
