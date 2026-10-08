open Editor_document
include Core_panes

let sync_views value =
  let lowered = snd value.doc.Document.workspace in
  match value.view_key with
  | Some (previous, probes, previews) when previous == lowered && probes == value.probes
      && previews == value.previews -> value
  | _ when Document.Int_map.is_empty value.previews ->
      { value with viewed = Document.Int_map.empty; view_key = Some (lowered, value.probes, value.previews) }
  | _ ->
      let records = Flow_graph.Probe.make ~dynamic:(Flow_sop.Lower.zone_count lowered) lowered.evaluated in
      let previews, viewed = Document.Int_map.fold (fun object_id (preview : preview) (previews, viewed) ->
        let probes = List.map (fun path -> Option.value ~default:0
          (Layout_by_path.Path_map.find_opt path value.probes)) preview.chain in
        let viewed_node = Option.bind (Flow_graph.Probe.plan_node records preview.path ~probes) (fun node ->
          Option.bind (Document.Int_map.find_opt object_id value.doc.Document.networks)
            (fun network -> lowered.preview ~node ~probes network.graph)) in
        match viewed_node with
        | Some viewed_node ->
            Document.Int_map.add object_id preview previews,
            Document.Int_map.add object_id viewed_node viewed
        | None -> previews, viewed) value.previews (Document.Int_map.empty, Document.Int_map.empty) in
      { value with previews; viewed; view_key = Some (lowered, value.probes, previews) }

let view_node value path =
  match value.scope_key with
  | Some key ->
      let chain = Option.value ~default:[] (Hashtbl.find_opt (Flow_graph.Probe.chains key.scope) path) in
      let probes = List.map (fun path -> Option.value ~default:0
        (Layout_by_path.Path_map.find_opt path value.probes)) chain in
      let node = Option.bind key.records (fun records -> Flow_graph.Probe.plan_node records path ~probes) in
      let owner = Option.bind node (fun node ->
        let lowered = snd value.doc.workspace in
        let owns id = Option.bind (Document.Int_map.find_opt id value.doc.networks)
          (fun network -> lowered.preview ~node ~probes network.graph) <> None in
        match value.level with
        | Inside id when owns id -> Some id
        | _ -> Document.Int_map.fold (fun id _ found ->
            match found with Some _ -> found | None -> if owns id then Some id else None)
            value.doc.networks None) in
      (match owner with
       | Some owner -> sync_views { value with previews = Document.Int_map.add owner { path; chain } value.previews }
       | None -> value)
  | None -> value

(* Lay the workspace pane out again when the document, the probes or the
   graph changed; the footers are rebuilt when the recording evaluation, the
   cook's geometry counts or (a live document) the time changed.  The
   evaluation is retained by lowering, never repeated by a pane or a frame. *)
let sync_scope value =
  let value = sync_views value in
  let value = match value.scope_key with
    | Some key -> { value with scope_view = Pxui_graph.Scope.with_display (viewed_path value key.scope) value.scope_view }
    | None -> value in
  match graph_name value, value.doc.Document.workspace, Lazy.force value.flow_catalog with
  | Some name, (ws, lowered), Some catalog ->
      let module M = Layout_by_path.Path_map in
      let previous = value.scope_key in
      let arguments = Option.bind previous (fun k -> if k.graph <> name then None else
        match Workspace_doc.literal_changes ~previous:k.ws ws with
        | Some _ as changes -> changes
        | None when Flow_graph.Projection.same_graph k.ws.checked ws.checked name -> Some []
        | None -> None) in
      let edits = Option.value ~default:[] arguments |> List.map (fun (change : Literal_edit.change) ->
        change.path, Flow_graph.Flow_edit.Kw change.field, change.expr) in
      let same k = k.graph = name && k.ws.layout == ws.layout && Option.is_some arguments in
      let moved = match previous with
        | Some k -> not (same k && k.probe_map == value.probes) | None -> true in
      let evaluated = match previous with
        | Some k when Option.fold ~none:false ~some:(( == ) lowered.evaluated) k.evaluated -> k.evaluated
        | _ -> Some lowered.evaluated in
      let time = if not (Flow.Workspace.Paths.is_empty ws.checked.live)
        then Some {value.live_frame with Frame_input.t = Sketch_support.Timeline.time value.timeline;
          frame = Int64.to_int (Sketch_support.Timeline.frame value.timeline)} else None in
      let summaries = value.cook.Cook.summaries in
      let executions = Flow_ir.Profile.executions lowered.profile in
      let fresh = match previous with
        | Some k -> not (k.evaluated == evaluated && k.summaries == summaries && k.executions == executions
            && Option.equal Frame_input.equal k.time time)
        | None -> true in
      if not moved && not fresh then value else begin
        let scope = match previous with
          | Some k when Option.is_some arguments ->
              if edits = [] then k.scope else Flow_graph.Projection.with_arguments edits k.scope
          | _ -> Flow_graph.Projection.of_graph catalog ws.checked name in
        let wires = match Option.bind value.doc.Document.shell (fun s -> s.Document.wires) with
          | Some "rect" -> `Rect
          | _ -> `Straight in
        let scope_view = if not moved then
          Pxui_graph.Scope.with_arguments edits value.scope_view |> Pxui_graph.Scope.with_wires wires else begin
          let layout = ws.layout in
          let display = viewed_path value scope in
          let layouts = match value.doc.Document.shell with
            | Some { switch = Some _; _ } when Option.map (fun (g : Flow.Workspace.graph) -> g.name)
                (Workspace_doc.editor_graph (fst value.doc.Document.workspace)) = Some name -> List.map fst (layouts value)
            | _ -> [] in
          Flow.Phase_timer.measure Layout (fun () -> Pxui_graph.Scope.with_scope ~wires ~layouts ~key:name scope value.scope_view
            ~imported:(Workspace_doc.imported_file ws)
            ~at:(fun path -> M.find_opt path layout.at)
            ~level:(fun path -> match M.find_opt path layout.level, M.find_opt path layout.pinned with
              | None, None -> None
              | level, pinned -> Some (Option.value ~default:Flow_graph.Projection.Card level,
                                       Option.value ~default:false pinned))
            ~pin:(fun path label -> Option.bind (M.find_opt path layout.rows) (Layout_by_path.String_map.find_opt label))
            ~collapsed:(fun path -> Option.value ~default:false (M.find_opt path layout.collapsed))
            ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes))
            ~frames:(fun path -> List.map (fun (f : Layout_by_path.frame) -> f.title, f.at, f.size)
              (Option.value ~default:[] (M.find_opt path layout.frames)))
            ?display) end in
        let geometry id = Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled)
          (fun node_id -> Option.bind (node_owner value node_id) (fun object_id ->
            Cook.geometry value.cook ~object_id ~node_id)) in
        (* a pick in another graph's geometry asked for its node to be selected here *)
        let scope_view, select_later =
          if value.select_later <> [] && List.for_all (fun p -> List.hd p = name) value.select_later
          then Pxui_graph.Scope.select value.select_later scope_view, [] else scope_view, value.select_later in
        let element zone k = Option.map (fun (name, (x, y, z)) -> [ name, Flow.Eval.Vec3 (x, y, z) ])
          (Flow_sop.Lower.zone_element lowered zone k) in
        let resolve = Flow_sop.Attribute_kernel.resolve ~geometry:(fun id ->
          Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled) (fun node_id ->
            Option.bind (node_owner value node_id) (fun object_id ->
              Cook.source value.cook ~object_id ~node_id))) in
        let rec covers site path = match site, path with
          | [a], b :: _ -> a = b || String.starts_with ~prefix:(a ^ "#") b
          | a :: rest, b :: tail when a = b -> covers rest tail
          | _ -> false in
        let rec prefix xs ys = match xs, ys with
          | [], _ -> true | x :: xs, y :: ys -> x = y && prefix xs ys | _ -> false in
        let execution path ~probes =
          let instance = Array.find_index (fun (i : Flow.Eval.instance) -> i.graph = name && i.default)
            lowered.plan.instances in
          let found = List.fold_left (fun best (report : Flow_ir.execution) ->
            List.fold_left (fun best (origin, site, iter) ->
              if not ((origin < 0 || instance = Some origin) && covers site path && prefix iter probes) then best else
              let score = List.fold_left (fun n s -> n + String.length s + 1) 0 site in
              match best with Some (previous, _) when previous >= score -> best
                | _ -> Some (score, report)) best report.sites) None executions in
          match found with
          | Some (_, report) -> Some Flow_graph.Probe.{
              tier = (match report.tier with Interp -> "Interp" | Closure -> "Closure" | Cpu_kernel -> "CPU"
                |Gpu->"GPU"|Gpu_compile->"Gpu_compile"|Gpu_readback->"Readback"|Cooked -> "Cooked");
              group = fst report.owner;
              seconds = if fst report.owner = path then Some report.seconds else None}
          | None -> None in
        let records = Option.map (Flow_graph.Probe.make ~state:value.cook.state ?live:time ~geometry ~resolve ~execution
          ~image:(Flow_sop.Lower.image_metadata lowered.plan)
          ~dynamic:(Flow_sop.Lower.zone_count lowered) ~element) evaluated in
        let scope_view = match records with
          | Some records when fresh || moved -> Pxui_graph.Scope.with_records records scope_view
          | _ -> scope_view in
        let targets = match records, previous with
          | Some _, Some k when not moved && (k.evaluated == evaluated ||
              Option.fold ~none:false ~some:(fun ev -> ev.Flow.Eval.records == lowered.evaluated.records) k.evaluated) -> k.targets
          | Some records, _ ->
              List.filter_map (fun id ->
                Option.bind (Flow_sop.Network.Int_map.find_opt id lowered.compiled) (fun node_id ->
                  Option.map (fun object_id -> object_id, node_id) (node_owner value node_id)))
                (Flow_graph.Probe.geometry_targets records scope
                   ~probe:(fun path -> Option.value ~default:0 (M.find_opt path value.probes)))
          | None, _ -> [] in
        { value with scope_view; select_later; scope_key = Some { ws; probe_map = value.probes; graph = name;
            evaluated; summaries; executions; time; records; scope; targets } }
      end
  | _ -> value
