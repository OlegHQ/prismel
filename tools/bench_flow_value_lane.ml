open Flow_sop
let ok = function Ok value -> value | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
let geometry_ok = function Ok value -> value | Error message -> failwith message
let schema = Param.schema ~name:"lane-benchmark" ~default:1.
  [Param.field ~name:"v" ~kind:(Param.floating ~min:(-100.) ~max:100. ()) ~default:1.
    ~get:Fun.id ~set:(fun value _ -> value) ()]
let rec build value = Procedural.Sop.points [|value,0.,0.|]
  |> Procedural.Node.parameterize ~schema ~values:value ~rebuild:(fun ~label:_ ~inputs:_ value -> build value)
let () =
  let rows = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 200 in
  let frames = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 1000 in
  if rows < 1 || frames < 1 then invalid_arg "rows and frames must be positive";
  let ids = ref [] in
  let geometry = List.init rows Fun.id |> List.fold_left (fun geometry _ ->
    let node = build 1. in
    ids := Procedural.Node.id node :: !ids;
    geometry_ok (Procedural.Edit_graph.add_node node geometry)) Procedural.Edit_graph.empty in
  let base = Network.of_geometry geometry in
  let timed, time_id = ok (Network.add_value_node Flow.Value_kind.Time base) in
  let timed = List.fold_left (fun network node -> ok (Network.connect_value
      ~source:Port.{node = time_id; path = "t"} ~target:Port.{node; path = "v"} network)) timed !ids in
  let expression = ok (Flow.Expr.num 2.) in
  let static = List.fold_left (fun network node -> ok (Network.set_expr
      ~target:Port.{node; path = "v"} expression network)) base !ids in
  let sample label network advancing =
    let lane = Value_lane.create () in
    for frame = 1 to 64 do ignore (ok (Value_lane.resolve lane ~time:(float_of_int frame /. 60.) network)) done;
    let measurements = Array.init 7 (fun _ ->
      Gc.compact ();
      let allocation = Gc.allocated_bytes () and start = Unix.gettimeofday () in
      for frame = 1 to frames do
        let result = if advancing then Value_lane.resolve lane ~time:(float_of_int frame /. 60.) network
          else Value_lane.resolve lane ~time:2. network in
        match result with Ok _ -> () | Error diagnostic -> failwith (Flow.Diagnostic.to_string diagnostic)
      done;
      let elapsed = Unix.gettimeofday () -. start in
      elapsed *. 1000. /. float_of_int frames, (Gc.allocated_bytes () -. allocation) /. float_of_int frames) in
    let median index = let values = Array.map index measurements in
      Array.sort Float.compare values; values.(3) in
    Printf.printf "%s: median of 7 frame averages %.6f ms; %.3f bytes/frame (%d rows, %d frames/sample, 1 domain)\n%!"
      label (median fst) (median snd) rows frames in
  sample "no drives" base false;
  sample "static drives" static false;
  sample "time drives" timed true
