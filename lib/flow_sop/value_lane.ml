(* Live drives: the arguments of a lowered graph that depend on [t].  One cache retains the last
   plan and resolution; a static network reuses its result without recomputation. *)
type target = { port : Port.t; parameter : Port.parameter; value : Flow.Eval.value }
type plan = { network : Network.t; targets : target array; texts : target array;
  time_dependent : bool }
type resolved = {
  geometry : Procedural.Edit_graph.t;
  applied : Flow.Port_type.value Port.Map.t;
  applied_text : string Port.Map.t;
  time_dependent : bool;
}
type cache = { plan : plan; time : float; result : (resolved, Flow.Diagnostic.t) result }
type t = { mutable previous : cache option }
let create () = {previous = None}

let prepare network =
  if Port.Map.is_empty network.Network.drives then
    Ok {network; targets = [||]; texts = [||]; time_dependent = false}
  else Result.bind (Network.validate network) (fun () ->
    let targets = Port.Map.fold (fun port value targets -> Result.bind targets (fun targets ->
      Result.map (fun parameter -> {port; parameter; value} :: targets) (Network.parameter network port)))
      network.drives (Ok []) in
    Result.map (fun targets ->
      let ordered = List.rev targets in
      let text target = target.parameter.ty = None in
      {network; targets = Array.of_list (List.filter (fun t -> not (text t)) ordered);
       texts = Array.of_list (List.filter text ordered); time_dependent = true}) targets)

let live_error message = Error (Flow.Diagnostic.error ~code:"E_LIVE" message)
let live_port_value = function
  | Flow.Eval.Int n -> Ok (Flow.Port_type.Int_value n)
  | Float f -> Ok (Flow.Port_type.Float_value f)
  | Bool b -> Ok (Flow.Port_type.Bool_value b)
  | Vec3 (x, y, z) -> Ok (Flow.Port_type.Vec3_value (x, y, z))
  | Text text -> (match Port.color_of_text text with
      | Some (x, y, z) -> Ok (Flow.Port_type.Vec3_value (x, y, z))
      | None -> live_error ("Live value is not a colour: " ^ text))
  | _ -> live_error "Live value is not a number, bool, vec3 or colour"
(* A live text or list parameter: a list of vec3 is the curve's encoded points. *)
let live_text (parameter : Port.parameter) = function
  | Flow.Eval.List values ->
      let points = Array.map (function Flow.Eval.Vec3 (x, y, z) -> Some (x, y, z) | _ -> None) values in
      if Array.exists Option.is_none points then live_error "Live list must hold vec3"
      else Ok (Curve.encode (Array.map Option.get points))
  | Text text -> Ok text
  | _ -> live_error ("Live value does not fit " ^ parameter.path)
let force ~time value = Flow.Eval.force value ~live:{Flow.Eval.t = time}
let normalize_target ~time target =
  Result.bind (Result.bind (force ~time target.value) live_port_value) (Port.normalize target.parameter)
let apply_geometry geometry target changes =
  Result.map fst (Result.map_error (Flow.Diagnostic.error ~code:"E_TYPE")
    (Procedural.Edit_graph.apply_parameters geometry ~node_id:target.Port.node changes))

let compute previous plan ~time =
  if Array.length plan.targets = 0 && Array.length plan.texts = 0 then Ok {geometry = plan.network.geometry;
    applied = Port.Map.empty; applied_text = Port.Map.empty; time_dependent = false} else
  let applied = ref Port.Map.empty in
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
  let geometry = Array.fold_left (fun result target -> Result.bind result (fun geometry ->
    Result.bind (normalize_target ~time target) (fun (value, changes) ->
      applied := Port.Map.add target.port value !applied;
      if Procedural.Edit_graph.find plan.network.geometry ~node_id:target.port.node = None then Ok geometry
      else if same_geometry && (match previous with
        | Some (previous, _) -> Port.Map.find_opt target.port previous.applied = Some value | None -> false) then Ok geometry
      else apply_geometry geometry target.port changes))) restored plan.targets in
  let applied_text = ref Port.Map.empty in
  let geometry = Array.fold_left (fun result target -> Result.bind result (fun geometry ->
    Result.bind (force ~time target.value) (fun value ->
      Result.bind (live_text target.parameter value) (fun text ->
        applied_text := Port.Map.add target.port text !applied_text;
        if Procedural.Edit_graph.find plan.network.geometry ~node_id:target.port.node = None then Ok geometry
        else if same_geometry && (match previous with
          | Some (previous, _) -> Port.Map.find_opt target.port previous.applied_text = Some text
          | None -> false) then Ok geometry
        else
          let literal = match target.parameter.fields with
            | [{Param.kind = Param.Choice_view _; _}] -> Param.Choice_value text
            | _ -> Param.Text_value text in
          Result.bind (Port.literal_changes target.parameter (Port.Scalar literal))
            (apply_geometry geometry target.port))))) geometry plan.texts in
  Result.map (fun geometry -> {geometry; applied = !applied; applied_text = !applied_text;
    time_dependent = plan.time_dependent}) geometry

let resolve state ~time network = match state.previous with
  | Some previous when previous.plan.network == network
      && (not previous.plan.time_dependent || previous.time = time) -> previous.result
  | previous ->
      let plan = match previous with Some previous when previous.plan.network == network -> Ok previous.plan
        | _ -> prepare network in
      Result.bind plan (fun plan ->
        let result = compute previous plan ~time in
        state.previous <- Some {plan; time; result}; result)
