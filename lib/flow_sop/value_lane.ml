module Int_map = Map.Make (Int)
module Int_set = Set.Make (Int)
type target = { port : Port.t; parameter : Port.parameter; drive : Drive.t }
type value_job = { node : Flow.Graph.node; inputs : target list }
type plan = { network : Network.t; targets : target array; jobs : value_job array; time_dependent : bool }
type resolved = {
  geometry : Procedural.Edit_graph.t;
  applied : Flow.Port_type.value Port.Map.t;
  outputs : Flow.Port_type.value Port.Map.t;
  time_dependent : bool;
}
type cache = { plan : plan; time : float; result : (resolved, Flow.Diagnostic.t) result }
type t = { mutable previous : cache option }
let create () = {previous = None}
let reset state = state.previous <- None
let error message = Error (Flow.Diagnostic.error ~code:"E_UNBOUND" message)

let prepare network =
  if Port.Map.is_empty network.Network.drives then
    Ok {network; targets = [||]; jobs = [||]; time_dependent = false}
  else Result.bind (Network.validate network) (fun () ->
    let targets = Port.Map.fold (fun port drive targets -> Result.bind targets (fun targets ->
      Result.map (fun parameter -> {port; parameter; drive} :: targets) (Network.parameter network port)))
      network.drives (Ok []) in
    Result.bind targets (fun targets ->
      let inputs = List.fold_left (fun inputs target ->
        Int_map.update target.port.node (fun current -> Some (target :: Option.value current ~default:[])) inputs)
        Int_map.empty targets in
      let rec reachable seen = function
        | [] -> seen | id :: rest when Int_set.mem id seen -> reachable seen rest
        | id :: rest ->
            let next = List.fold_left (fun rest target -> match target.drive with
              | Drive.Wire source -> source.node :: rest | Drive.Expr _ -> rest) rest
              (Option.value (Int_map.find_opt id inputs) ~default:[]) in
            reachable (Int_set.add id seen) next in
      let roots = List.fold_left (fun roots target ->
        let roots = if Flow.Graph.find network.values ~node_id:target.port.node <> None
          then target.port.node :: roots else roots in
        match target.drive with Drive.Wire source -> source.node :: roots | Drive.Expr _ -> roots) [] targets in
      let needed = reachable Int_set.empty roots in
      Result.map (fun order ->
        let jobs = List.filter_map (fun id -> if not (Int_set.mem id needed) then None else
          Option.map (fun node -> {node; inputs = Option.value (Int_map.find_opt id inputs) ~default:[]})
            (Flow.Graph.find network.values ~node_id:id)) order |> Array.of_list in
        let time_dependent = List.exists (fun target -> match target.drive with
          | Drive.Expr expression -> Flow.Expr.depends_on_time expression | Drive.Wire _ -> false) targets
          || Array.exists (fun job -> Flow.Value_kind.kind job.node.parameters = Flow.Value_kind.Time) jobs in
        {network; targets = Array.of_list (List.rev targets); jobs; time_dependent})
        (Network.topological_values network)))

let drive_value ~time outputs = function
  | Drive.Expr expression -> Result.map (fun value -> Flow.Port_type.Float_value value) (Flow.Expr.eval ~time expression)
  | Drive.Wire source -> match Port.Map.find_opt Port.{node = source.node; path = source.output} outputs with
      | Some value -> Ok value | None -> error (Printf.sprintf "No evaluated output %d.%s" source.node source.output)
let normalize_target ~time outputs target = Result.bind (drive_value ~time outputs target.drive)
  (Port.normalize target.parameter)
let apply_geometry geometry target changes =
  Result.map fst (Result.map_error (Flow.Diagnostic.error ~code:"E_TYPE")
    (Procedural.Edit_graph.apply_parameters geometry ~node_id:target.Port.node changes))

let compute previous plan ~time =
  if Array.length plan.targets = 0 then Ok {geometry = plan.network.geometry;
    applied = Port.Map.empty; outputs = Port.Map.empty; time_dependent = false} else
  let applied = ref Port.Map.empty and outputs = ref Port.Map.empty in
  let computed = Array.fold_left (fun result job -> Result.bind result (fun () ->
    let parameters = List.fold_left (fun result target -> Result.bind result (fun parameters ->
      Result.bind (normalize_target ~time !outputs target) (fun (value, changes) ->
        applied := Port.Map.add target.port value !applied;
        Result.map fst (Flow.Value_kind.apply_parameters parameters changes)))) (Ok job.node.parameters) job.inputs in
    Result.bind parameters (fun parameters -> Result.map (fun values -> List.iter (fun (path, value) ->
      outputs := Port.Map.add Port.{node = job.node.id; path} value !outputs) values)
      (Flow.Value_kind.eval ~time parameters)))) (Ok ()) plan.jobs in
  Result.bind computed (fun () ->
    let previous = Option.bind previous (fun cache -> Option.map
      (fun resolved -> resolved, cache.plan.network) (Result.to_option cache.result)) in
    let same_geometry = match previous with None -> false | Some (_, old_network) ->
      plan.network.geometry == old_network.Network.geometry in
    let geometry = if same_geometry then (Option.get previous |> fst).geometry else plan.network.geometry in
    let restored = if not same_geometry then Ok geometry else
      let previous, old_network = Option.get previous in
      Port.Map.fold (fun port _ result -> Result.bind result (fun geometry ->
        if Port.Map.mem port plan.network.drives
          || Procedural.Edit_graph.find geometry ~node_id:port.Port.node = None then Ok geometry
        else Result.bind (Network.parameter old_network port) (fun parameter ->
          Result.bind (Port.literal_changes parameter (Port.literal parameter)) (apply_geometry geometry port))))
        previous.applied (Ok geometry) in
    let normalized target = match Port.Map.find_opt target.port !applied with
      | Some value -> Result.bind (Port.literal_changes target.parameter
          (match value with
           | Flow.Port_type.Float_value value -> Port.Scalar (Param.Float_value value)
           | Int_value value -> Scalar (Param.Int_value value)
           | Bool_value value -> Scalar (Param.Bool_value value)
           | Vec3_value (x,y,z) -> Vector (x,y,z))) (fun changes -> Ok (value, changes))
      | None -> normalize_target ~time !outputs target in
    let geometry = Array.fold_left (fun result target -> Result.bind result (fun geometry ->
      Result.bind (normalized target) (fun (value, changes) ->
        applied := Port.Map.add target.port value !applied;
        if Procedural.Edit_graph.find plan.network.geometry ~node_id:target.port.node = None then Ok geometry
        else if same_geometry && (match previous with
          | Some (previous, _) -> Port.Map.find_opt target.port previous.applied = Some value | None -> false) then Ok geometry
        else apply_geometry geometry target.port changes))) restored plan.targets in
    Result.map (fun geometry -> {geometry; applied = !applied; outputs = !outputs; time_dependent = plan.time_dependent}) geometry)

let resolve state ~time network = match state.previous with
  | Some previous when previous.plan.network == network
      && (not previous.plan.time_dependent || previous.time = time) -> previous.result
  | previous ->
      let plan = match previous with Some previous when previous.plan.network == network -> Ok previous.plan
        | _ -> prepare network in
      Result.bind plan (fun plan ->
        let result = compute previous plan ~time in
        state.previous <- Some {plan; time; result}; result)
