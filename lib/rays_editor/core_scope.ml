open Editor_document
include Core_panes

(* Lay the workspace pane out again when the document, the probes or the
   graph changed; the footers are rebuilt when the recording evaluation, the
   cook's geometry counts or (a live document) the time changed.  The
   evaluation runs once per checked source, never per move or per frame. *)
let sync_scope value = match graph_name value, value.doc.Document.workspace, Lazy.force value.flow_catalog with
  | Some name, (ws, lowered), Some catalog ->
      let module M = Layout_by_path.Path_map in
      let previous = value.scope_key in
      let same k = k.ws == ws && k.graph = name in
      let moved = match previous with
        | Some k -> not (same k && k.probe_map == value.probes) | None -> true in
      let evaluated = match previous with
        | Some k when k.ws.checked == ws.checked -> k.evaluated
        | _ -> Result.to_option (Flow.Eval.static ~record:true ws.checked) in
      let time = if fst (Flow_sop.Lower.counts lowered) > 0
        then Some (Sketch_support.Timeline.time value.timeline) else None in
      let summaries = value.cook.Cook.summaries in
      let fresh = match previous with
        | Some k -> not (k.evaluated == evaluated && k.summaries == summaries && k.time = time)
        | None -> true in
      if not moved && not fresh then value else begin
        let scope = match previous with
          | Some k when not moved -> k.scope
          | _ -> Flow_sop.Projection.of_graph catalog ws.checked name in
        let wires = match Option.bind value.doc.Document.shell (fun s -> s.Document.wires) with
          | Some "rect" -> `Rect
          | _ -> `Straight in
        let scope_view = if not moved then Pxui_graph.Scope.with_wires wires value.scope_view else begin
          let layout = ws.layout in
          let display = match scope.result with
            | Link target -> Some [ name; target ]
            | Node target_path -> Some target_path
            | Literal _ -> None in
          let layouts = match value.doc.Document.shell with
            | Some { switch = Some _; _ } when Option.map (fun (g : Flow.Workspace.graph) -> g.name)
                (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) = Some name -> List.map fst (layouts value)
            | _ -> [] in
          Pxui_graph.Scope.with_scope ~wires ~layouts ~key:name scope value.scope_view
            ~at:(fun path -> M.find_opt path layout.at)
            ~level:(fun path -> match M.find_opt path layout.level, M.find_opt path layout.pinned with
              | None, None -> None
              | level, pinned -> Some (Option.value ~default:Flow_sop.Projection.Card level,
                                       Option.value ~default:false pinned))
            ~pin:(fun path label -> Option.bind (M.find_opt path layout.rows) (Layout_by_path.String_map.find_opt label))
            ~collapsed:(fun path -> Option.value ~default:false (M.find_opt path layout.collapsed))
            ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes))
            ~frames:(fun path -> List.map (fun (f : Layout_by_path.frame) -> f.title, f.at, f.size)
              (Option.value ~default:[] (M.find_opt path layout.frames)))
            ?display end in
        let geometry id = Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled)
          (fun node_id -> Option.bind (node_owner value node_id) (fun object_id ->
            Cook.geometry value.cook ~object_id ~node_id)) in
        (* a pick in another graph's geometry asked for its node to be selected here *)
        let scope_view, select_later =
          if value.select_later <> [] && List.for_all (fun p -> List.hd p = name) value.select_later
          then Pxui_graph.Scope.select value.select_later scope_view, [] else scope_view, value.select_later in
        let element zone k = Option.map (fun (name, (x, y, z)) -> [ name, Flow.Eval.Vec3 (x, y, z) ])
          (Flow_sop.Lower.zone_element lowered zone k) in
        let records = Option.map (Flow_sop.Probe.make ?time ~geometry
          ~dynamic:(Flow_sop.Lower.zone_count lowered) ~element) evaluated in
        let scope_view = match records with
          | Some records when fresh || moved -> Pxui_graph.Scope.with_records records scope_view
          | _ -> scope_view in
        let targets = match records, previous with
          | Some _, Some k when not moved && k.evaluated == evaluated -> k.targets
          | Some records, _ ->
              List.filter_map (fun id ->
                Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled) (fun node_id ->
                  Option.map (fun object_id -> object_id, node_id) (node_owner value node_id)))
                (Flow_sop.Probe.geometry_targets records scope
                   ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes)))
          | None, _ -> [] in
        { value with scope_view; select_later; scope_key = Some { ws; probe_map = value.probes; graph = name;
            evaluated; summaries; time; records; scope; targets } }
      end
  | _ -> value

