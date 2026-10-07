open Procedural
open Editor_document
include Core_shell

(* ---- levels ---- *)

let scene value = Document.scene_graph value.doc

(* Membership is shared by drawing, lighting, picking and framing. *)
let view_wants value view id =
  let views = match value.doc.Document.shell with Some s -> s.views | None -> [] in
  match view with
    | `All -> true
    | `Primary -> not (List.exists (fun (_, ids) -> List.mem id ids) views)
    | `Only key -> (match List.assoc_opt key views with Some ids -> List.mem id ids | None -> false)

let kind value id = Option.map Node.operation (Edit_graph.find (scene value) ~node_id:id)

let level_key = function
  | Document.Scene -> "scene"
  | Inside id -> "object:" ^ string_of_int id

(* The kinds the node menu offers where the pane shows a graph of [context]. *)
let catalog value = function
  | Flow.Workspace.Scene -> Objects.catalog
  | World -> Layers.catalog
  | Draw -> []
  | _ -> value.factories

(* the open level's network; the scene's if the level is gone (every path resolves the level first) *)
let network value =
  Option.value ~default:value.doc.Document.scene (Document.network value.doc value.level)
let document value = (network value).graph.geometry

(* A named pane or Navigator can show a SOP graph while the scene list is open. Its
   compiled nodes belong to an object's network, independent of the list's level. *)
let node_owner value node_id =
  let owns (network : Document.network) = Edit_graph.find network.graph.geometry ~node_id <> None in
  match value.level with
  | Inside id when Option.fold ~none:false ~some:owns (Document.Int_map.find_opt id value.doc.networks) -> Some id
  | _ ->
      (* ponytail: scan owners on this fallback; add an ownership index if large scenes need it. *)
      Document.Int_map.fold (fun id network found ->
        match found with Some _ -> found | None -> if owns network then Some id else None)
        value.doc.networks None

let compiled_node value node_id =
  let owned = Option.bind (node_owner value node_id) (fun id ->
    let graph = match Cook.applied value.cook id with
      | Some resolved -> resolved.Flow_sop.Value_lane.geometry
      | None -> (Document.Int_map.find id value.doc.networks).graph.geometry in
    Edit_graph.find graph ~node_id) in
  match owned with
  | Some _ -> owned
  | None -> List.find_map (fun (g : Flow_sop.Lower.graph) -> Edit_graph.find g.network.geometry ~node_id)
      (snd value.doc.workspace).graphs

(* A new material graph: a free name and its Set_graph ([Material] in the add menu, "new material"
   in the inspector). *)
let new_material value =
  let ws, _ = value.doc.Document.workspace in
  let taken n = List.exists (fun (g : Flow.Workspace.graph) -> g.name = n) (ws.checked.graphs @ ws.checked.defs) in
  let rec pick i = let n = if i = 1 then "material" else "material_" ^ string_of_int i in
    if taken n then pick (i + 1) else n in
  let name = pick 1 in
  let module S = Flow.Syntax in
  let list items = S.make (S.List items) and sym s = S.make (S.Sym s) and kw k = S.make (S.Kw k) in
  (* (graph name :context material (material/standard :name "name" :color "#cccccc" :roughness 0.4)) *)
  let form = list [ sym "graph"; sym name; kw "context"; sym "material";
    list [ sym "material/standard"; kw "name"; S.make (S.Str name); kw "color"; S.make (S.Str "#cccccc");
           kw "roughness"; S.make (S.Num "0.4") ] ] in
  name, Flow_graph.Flow_edit.Set_graph { name; form }

(* "=(* 2 t)" typed in a row: the expression after the "=", any Lisp expression *)
let expression_text text =
  match Flow.Syntax.parse (String.sub text 1 (String.length text - 1)) with
  | Ok [ expr ] -> Ok expr
  | Ok _ -> Error "Write one expression after the ="
  | Error d -> Error ("Expression: " ^ d.Flow.Diagnostic.message)

(* 1204 as "1 204" *)
let group_digits n =
  let text = string_of_int (abs n) in
  let len = String.length text in
  let b = Buffer.create (len + 4) in
  if n < 0 then Buffer.add_char b '-';
  String.iteri (fun i c -> if i > 0 && (len - i) mod 3 = 0 then Buffer.add_char b ' '; Buffer.add_char b c) text;
  Buffer.contents b

(* the section of a kind's arguments that have no folder: its own name ("sop/copy_to_points" is Copy to points) *)
let kind_label head =
  let leaf = match String.rindex_opt head '/' with
    | Some i -> String.sub head (i + 1) (String.length head - i - 1) | None -> head in
  String.capitalize_ascii (String.map (fun c -> if c = '_' then ' ' else c) leaf)

(* The arguments of a kind the editor has no compiled node for (a scene or material node), as the
   fields a node would give: the checked kind's parameters, valued by what is written in [authored]. *)
let kind_fields value graph head authored =
  let module S = Flow.Syntax in
  let ws, _ = value.doc.Document.workspace in
  let context = Option.bind (List.find_opt (fun (g : Flow.Workspace.graph) -> g.name = graph)
      (ws.checked.graphs @ ws.checked.defs)) (fun (g : Flow.Workspace.graph) -> match g.context with
    | Flow.Workspace.Sop -> Some Flow.Context.Sop | Scene -> Some Flow.Context.Scene
    | World -> Some Flow.Context.World | Settings -> Some Flow.Context.Settings
    | Material -> Some Flow.Context.Material | _ -> None) in
  match Lazy.force value.flow_catalog, context with
  | _ when head = "material/standard" ->
      (* a built-in of the workspace, not a catalog kind: its four keywords *)
      let number (e : S.t) = match e.node with S.Num t -> float_of_string_opt t | _ -> None in
      let field name default view =
        let current = match authored name, default with
          | Some { S.node = S.Str t; _ }, Parameter.Text_value _ -> Parameter.Text_value t
          | Some e, Parameter.Float_value _ -> (match number e with Some f -> Parameter.Float_value f | None -> default)
          | _ -> default in
        { Parameter.name; label = name; description = None; folder = []; impact = Parameter.Cook; primary = false;
          unit = None; vec3 = None; kind = view; default; current } in
      Some [ field "name" (Parameter.Text_value "") Parameter.Text_view;
             field "color" (Parameter.Text_value "#cccccc") Parameter.Text_view;
             field "roughness" (Parameter.Float_value 0.5)
               (Parameter.Floating_view { soft_min = 0.; soft_max = 1.; hard_min = Some 0.; hard_max = Some 1. });
             field "emission" (Parameter.Text_value "#000000") Parameter.Text_view ]
  | Some catalog, Some context ->
      (match Flow.Check.resolve_kind catalog context head with
       | Error _ -> None
       | Ok (k : Flow.Check.kind) ->
           let number (e : S.t) = match e.node with S.Num t -> float_of_string_opt t | _ -> None in
           Some (List.concat_map (fun (p : Flow.Check.parameter) ->
             let written = authored p.name in
             let three = List.length p.fields = 3 && p.ty = Some Flow.Port_type.Vec3 in
             List.mapi (fun i (name, view, default) ->
               let current = match written, default with
                 | Some { S.node = S.Vec [ a; b; c ]; _ }, Parameter.Float_value _ when three ->
                     (match number (List.nth [ a; b; c ] i) with Some f -> Parameter.Float_value f | None -> default)
                 | Some e, Parameter.Float_value _ when not three ->
                     (match number e with Some f -> Parameter.Float_value f | None -> default)
                 | Some { S.node = S.Num t; _ }, Parameter.Int_value _ ->
                     (match int_of_string_opt t with Some n -> Parameter.Int_value n | None -> default)
                 | Some { S.node = S.Str t; _ }, Parameter.Choice_value _ -> Parameter.Choice_value t
                 | Some { S.node = S.Str t; _ }, Parameter.Text_value _ -> Parameter.Text_value t
                 | Some { S.node = S.Sym ("true" | "false" as b); _ }, Parameter.Bool_value _ ->
                     Parameter.Bool_value (b = "true")
                 | _ -> default in
               { Parameter.name; label = (if three then name else p.label); description = None; folder = p.folder;
                 impact = Parameter.Cook; primary = false; unit = (if three then None else p.unit);
                 vec3 = (if three then Some (p.name, i) else None); kind = view; default; current })
               p.fields) k.parameters))
  | _ -> None

(* The iterations the zones around a node of the pane's graph probe, outermost first, and the
   compiled node it lowers to there.  [chains] is {!Flow_graph.Probe.chains} of the scope, made once
   by the caller (it walks the whole scope). *)
let probes_of value chains path =
  List.map (fun zone -> Option.value ~default:0 (Layout_by_path.Path_map.find_opt zone value.probes))
    (Option.value ~default:[] (Hashtbl.find_opt chains path))

let compiled_at value chains records path =
  Option.bind (Flow_graph.Probe.plan_node records path ~probes:(probes_of value chains path)) (fun plan ->
    Flow_sop.Network.Int_map.find_opt plan (snd value.doc.Document.workspace).compiled)

(* The inspector of the node selected in the workspace pane: its
   value at the probe, whether it recooks every frame, the list of its
   iterations (a click moves the zone's probe), and the catalog parameters of
   the lowered node at that iteration.  An edit is a [Set_arg] on the authored
   argument; an argument that is not a literal shows its expression and is
   locked.  Returns the graph requests and the probe moves. *)
let workspace_inspector ?(window = false) ?(on_choice = fun _ _ -> ()) ?(resized = fun _ _ -> None) ?(follows = fun _ -> None) value ui ~width path =
  let module P = Flow_graph.Projection in
  let module Probe = Flow_graph.Probe in
  let module S = Flow.Syntax in
  match value.scope_key, value.doc.Document.workspace with
  | Some { scope; records = Some records; graph; _ }, _ ->
      (match P.find scope path with
       | None ->
           (* a graph input: its type, and its default as one Lisp form (the pane's field, here) *)
           (match List.find_opt (fun (i : P.input) -> i.path = path) scope.inputs with
            | None -> [], []
            | Some input ->
                ignore (Pxui.Ui.inspector_header ui ~key:"ws-input" ~kind:"input" ~title:input.name
                  ~detail:(Flow.Ty.to_string input.ty) ());
                let shown = match input.default with Some d -> Flow.Lisp.flat d | None -> "" in
                let text = Pxui.Ui.inspector_body ui (fun () ->
                  let box, cx, cy, cw = Pxui.Ui.inspector_row ui ~width ~key:"ws-input-default" ~label:"default" () in
                  Pxui.Ui.within ui box (fun () ->
                    match input.default with
                    | Some { S.node = S.Num _; _ } ->
                        (* a number: the pane's own field, so it drags here as it does on the card *)
                        Option.value ~default:shown
                          (Pxui_graph.Scope.num_field ui ~at:(cx, cy) ~w:cw ~h:20.
                             (* the input's type decides the step: a float written [1] scrubs by fractions *)
                             ?kind:(match input.ty with
                               | Flow.Ty.Int -> Some Editor_core.Number.Int
                               | Flow.Ty.Float -> Some Editor_core.Number.Float | _ -> None)
                             "ws-input-default-field" shown)
                    | _ ->
                        fst (Pxui.Ui.value_field ui ~at:(cx, cy) ~w:cw ~h:20.
                          ~left:(float_of_string_opt shown = None)
                          ~valid:(fun t -> String.trim t <> "") "ws-input-default-field" shown))) in
                (match (if text = shown then Ok [] else Flow.Syntax.parse text) with
                 | Ok [ form ] ->
                     [ Syntax_edit (Flow_graph.Flow_edit.Set_input_default { form = graph; input = input.name; value = form }) ], []
                 | Ok [] -> [], []
                 | Ok _ -> [ Declined "A default is one Lisp form" ], []
                 | Error d -> [ Declined ("Default: " ^ d.Flow.Diagnostic.message) ], []))
       | Some n ->
           let chains = Probe.chains scope in
           let chain = Option.value ~default:[] (Hashtbl.find_opt chains n.path) in
           let probes = probes_of value chains n.path in
           let footer = Probe.footer records n ~probes in
           (* a loop or scope says what it is, then the rows of its rail (what it runs over, what it feeds back,
              what it only reads), as the study's inspector does *)
           let zone_text = Option.map (fun (z : P.zone) -> match z.kind with
             | P.For -> "repeat · collect a list", Printf.sprintf "Runs its body once for every %s and collects the results into a list."
             | Fold -> "iterate · feed back", Printf.sprintf "Runs its body for every %s and hands the result to the next run."
             | Scan -> "scan · keep every step", Printf.sprintf "Runs its body for every %s and keeps each step's result in a list."
             | Sum -> "sum · add up", Printf.sprintf "Runs its body for every %s and adds the results."
             | Let -> "scope · names for its result", (fun _ -> "Names shared by its result; it runs once.")
             | State -> "state · fold frames", (fun _ -> "Reads the previous frame's value and stores this frame's result.")
             | Fn -> "function · runs per call", (fun _ -> "A function: its body runs each time it is called.")) n.zone in
           (* a bypassed node passes its input through: the plan node is the upstream one, so it
              has no number, cook or arguments of its own to show here *)
           let node_id = if n.bypass then None else compiled_at value chains records n.path in
           let node = Option.bind node_id (compiled_node value) in
           let literal = function
             | { S.node = S.Num _ | S.Str _ | S.Sym ("true" | "false"); _ } -> true
             | { S.node = S.Vec l; _ } -> List.for_all (fun (e : S.t) -> match e.node with S.Num _ -> true | _ -> false) l
             | _ -> false in
           let authored_row key =
             Option.bind (List.find_opt (fun (r : P.row) -> r.key = Flow_graph.Flow_edit.Kw key) n.rows)
               (fun (r : P.row) -> r.expr) in
           let authored (parameter : Flow_sop.Port.parameter) = authored_row parameter.path in
           (* the arguments: a compiled node's own fields, else (a scene or material node, which
              has none) the checked kind's parameters, valued by what is written *)
           let fields = match node with
             | Some node -> Node.parameter_fields node
             | None -> Option.value ~default:[] (kind_fields value graph n.head authored_row) in
           let parameters = Result.value ~default:[] (Flow_sop.Port.parameters fields) in
           (* the docked column under ~340 points (workspace.html) has no number and no bar; the
              window follows windows.html (no bar); the 380 column (inspector.html) has both *)
           let narrow = width < 340. in
           let doc_layout = (fst value.doc.Document.workspace).layout in
           let pin_of (r : P.row) = Option.bind (Layout_by_path.Path_map.find_opt n.path doc_layout.rows)
             (Layout_by_path.String_map.find_opt r.label) in
           let row_of path = List.find_opt (fun (r : P.row) -> r.key = Flow_graph.Flow_edit.Kw path) n.rows in
           let on_card_row path = match row_of path with
             | Some r -> P.row_shown ?pin:(pin_of r) r | None -> false in
           let geo = Option.bind node_id (fun id -> Option.bind (node_owner value id) (fun object_id ->
             Cook.geometry value.cook ~object_id ~node_id:id)) in
           (* the node shown in the viewport: the graph's result *)
           let displayed = match scope.result with
             | P.Link target -> Some [ graph; target ]
             | Node p -> Some p
             | Literal _ -> None in
           let readouts = Probe.readouts records n ~probes in
           (* the head: the kind, VIEW while displayed, the node's number; the name edited in
              place; what the probe and the cook know; the flags the card has as buttons *)
           let follow = follows n.path in
           (* the active camera: the one the scene's root names as its :camera *)
           let root_node = List.find_opt (fun (m : P.node) -> m.head = "scene/root") scope.nodes in
           let active_camera = n.head = "scene/camera" && (match root_node with
             | Some root -> List.exists (fun (r : P.row) -> r.key = Flow_graph.Flow_edit.Kw "camera" && (match r.expr with
                 | Some { S.node = S.Sym name; _ } -> name = List.nth n.path (List.length n.path - 1)
                 | _ -> false)) root.rows
             | None -> false) in
           (* a scene or material node says its state: the active camera is `active`, the rest how it cooks *)
           let scene_state = if not (String.starts_with ~prefix:"scene/" n.head || String.starts_with ~prefix:"material/" n.head)
             then None else Some (if active_camera then "active" else
               Option.value ~default:"cached" (List.assoc_opt "cook" readouts)) in
           let buttons =
             (if n.ty = Flow.Ty.Geometry && List.length n.path = 2 && not n.synthetic then
                [ { Pxui.Ui.caption = "View"; keycap = "V"; active = displayed = Some n.path; usable = true }, `View ]
              else [])
             @ (if P.bypassable n then
                  [ { Pxui.Ui.caption = "Bypass"; keycap = "B"; active = n.bypass; usable = true }, `Bypass ] else [])
             @ (match root_node with
                | Some root when n.head = "scene/camera" ->
                    [ { Pxui.Ui.caption = "Active"; keycap = ""; active = active_camera; usable = not active_camera },
                      `Activate root.path ]
                | _ -> [])
             @ (if follow <> None then
                  [ { Pxui.Ui.caption = "Enter"; keycap = "I"; active = false; usable = true }, `Enter ] else []) in
           let head = Pxui.Ui.inspector_header ui ~key:"ws-header" ~kind:n.head
             ?badge:(if displayed = Some n.path then Some "view" else None)
             ?index:(if narrow || window then None else Option.map (Printf.sprintf "NO. %04d") node_id)
             ?rename:(if n.synthetic then None else Some Flow.Symbol.valid_name)
             ~actions:(List.map fst buttons)
             ~title:(Flow_graph.Projection.title n)
             ~detail:(match zone_text with
               | Some (kind, _) -> Printf.sprintf "%s · %s" kind (Flow.Ty.to_string n.ty)
               | None ->
                   (match geo with
                    | Some g ->
                        (* what the cook knows of the node: its points and primitives *)
                        let count k word = Printf.sprintf "%s %s" (group_digits k) word in
                        String.concat " · " ([ count g.points (if g.points = 1 then "point" else "points");
                          count g.prims (if g.prims = 1 then "prim" else "prims") ]
                          @ Option.to_list (Option.map (Printf.sprintf "cooked %.3f s") g.seconds))
                    | None ->
                   (match scene_state with
                    | Some state -> n.head ^ " · " ^ state
                    | None ->
                   (match String.concat " · " (List.map snd readouts) with
                    | "" -> Flow.Ty.to_string n.ty | text -> text)))) ~reset:"Reset all" ~reset_enabled:(List.exists (fun (parameter : Flow_sop.Port.parameter) -> authored parameter <> None) parameters) () in
           let pressed = Option.map (fun i -> snd (List.nth buttons i)) head.chosen in
           (* Reset all: every written argument of the node removed, one undoable entry *)
           let reset_all = if not head.reset_pressed then [] else
             match List.filter_map (fun (parameter : Flow_sop.Port.parameter) ->
               Option.map (fun _ -> Flow_graph.Flow_edit.Disconnect { node = n.path;
                 key = Flow_graph.Flow_edit.Kw parameter.path; fallback = None }) (authored parameter)) parameters with
             | [] -> []
             | [ op ] -> [ Syntax_edit op ]
             | ops -> [ Syntax_batch ("Reset all", ops) ] in
           (* the name: editing it is the pane's Rename (the text's binding name); a nested node
              has no name yet, giving it one binds it *)
           let rename = if n.synthetic || head.renamed = Flow_graph.Projection.title n then []
             else [ Syntax_edit (Flow_graph.Flow_edit.Rename { node = n.path; to_ = head.renamed }) ] in
           let flags = match pressed with
             | Some `Bypass -> [ Syntax_edit (Flow_graph.Flow_edit.Toggle_bypass { node = n.path }) ], []
             | Some `View -> [], [ Pxui_graph.Scope.Display_set n.path ]
             | Some `Enter -> [], [ Pxui_graph.Scope.Activated n.path ]
             | Some (`Activate root) ->
                 [ Syntax_edit (Flow_graph.Flow_edit.Set_arg { node = root; key = Flow_graph.Flow_edit.Kw "camera"; sub = [];
                     value = S.make (S.Sym (List.nth n.path (List.length n.path - 1))) }) ], []
             | None -> [], [] in
           let on_card = ref 0 in
           let requests, picks = Pxui.Ui.inspector_body ui (fun () ->
           (match n.zone, zone_text with
            | Some z, Some (_, sentence) ->
                let vars = List.filter_map (fun (r : P.rail_row) -> if r.role = P.Var then Some r.name else None) z.rail in
                Pxui.Ui.inspector_message ui ~key:"ws-zone-says"
                  (sentence (match vars with v :: _ -> v | [] -> "item"));
                List.iter (fun (r : P.rail_row) ->
                  let label = match r.role with P.Var -> r.name ^ " in" | Acc -> r.name ^ " (next)"
                    | Param -> r.name ^ " (input)" | Capture -> r.name in
                  Pxui.Ui.inspector_readout ui ~width ~key:("ws-rail-" ^ r.name) ~label
                    (match r.expr with Some e -> Flow.Lisp.flat e | None -> "same for all")) z.rail
            | _ -> ());
           (* the head's detail line says it for a node; a zone keeps its readout rows *)
           if zone_text <> None then
             List.iter (fun (label, text) ->
               Pxui.Ui.inspector_readout ui ~width ~key:("ws-" ^ label) ~label text) readouts;
           let hoist = if footer.invariant && Pxui.Ui.inspector_button ui ~key:"ws-hoist" "Move out of the loop"
             then [ Syntax_edit (Flow_graph.Flow_edit.Hoist { node = n.path }) ] else [] in
           (* a macro call: what it is, and the request the pane's lens button makes *)
           let macro = match n.macro with
             | Some name ->
                 Pxui.Ui.inspector_message ui ~key:"ws-macro"
                   ("Macro " ^ name ^ ": its rows are the holes.");
                 if Pxui.Ui.inspector_button ui ~key:"ws-inline" "Replace call with expansion"
                 then [ Syntax_edit (Flow_graph.Flow_edit.Inline_macro { node = n.path }) ] else []
             | None -> [] in
           (* the items of a list or a string: each can move up a place *)
           let movers = if n.synthetic || not (Flow_graph.Projection.reorderable n) then [] else
             List.concat_map (fun (r : P.row) -> match r.key with
               | Flow_graph.Flow_edit.Pos k when k >= 1 && k < 24 ->
                   if Pxui.Ui.inspector_button ui ~key:(Printf.sprintf "ws-move-%d" k)
                       (Printf.sprintf "Move item %d up" (k + 1))
                   then [ Syntax_edit (Flow_graph.Flow_edit.Move_item { node = n.path; pos = k }) ] else []
               | _ -> []) n.rows in
           if n.head = "settings/config" then Pxui.Ui.inspector_message ui ~key:"ws-startup-settings"
             "Title, size, frame rate and seed apply on restart.";
           let is_ref_slot (r : P.row) =
             (match r.expr with
              | Some { S.node = S.List [ { S.node = S.Sym "ref"; _ }; { S.node = S.Sym _; _ } ]; _ } -> true
              | _ -> false)
             || r.ty = Some Flow.Ty.Material
             || (r.ty = Some Flow.Ty.Geometry && String.starts_with ~prefix:"scene/" n.head) in
           let doc, _ = value.doc.Document.workspace in
           let sop_graphs = List.filter_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.Sop then Some g.name else None) doc.checked.graphs in
           let material_graphs = List.filter_map (fun (g : Flow.Workspace.graph) ->
             if g.context = Flow.Workspace.Material then Some g.name else None) doc.checked.graphs in
           let ref_rows = List.filter_map (fun (r : P.row) ->
             if not (is_ref_slot r) then None else
             let is_material = r.ty = Some Flow.Ty.Material in
             let target = match r.expr with
               | Some { S.node = S.List [ { S.node = S.Sym "ref"; _ }; { S.node = S.Sym name; _ } ]; _ } -> name
               | _ -> "" in
             let choices = match (if is_material then material_graphs else sop_graphs) with
               | [] when not is_material -> [| "(none)" |]
               | gs ->
                   let list = if target <> "" && not (List.mem target gs) then target :: gs else gs in
                   Array.of_list (if is_material then list @ [ "new material" ] else list) in
             let field_name = "@ref:" ^ r.label in
             let current_val = if target <> "" then target else choices.(0) in
             let field = {
               Parameter.name = field_name;
               label = String.capitalize_ascii r.label;
               description = Some (if is_material then "Material graph reference" else "SOP graph reference");
               folder = [];
               impact = Parameter.Cook;
               primary = false;
               unit = None;
               vec3 = None;
               kind = Parameter.Choice_view choices;
               default = Parameter.Choice_value choices.(0);
               current = Parameter.Choice_value current_val;
             } in
             Some (r, { Pxui_shell.Inspector.path = field_name; fields = [ field ]; shown = true; locked = false;
                        drive = None; live = None }))
             n.rows in
           (* a switch's :active is a choice among its layouts, named from their panels *)
           let layout_names = match n.head, value.doc.Document.shell with
             | "ui/switch", Some { switch = Some sw; _ }
               when List.length sw.layouts
                    = List.length (List.filter (fun (r : P.row) -> match r.key with Flow_graph.Flow_edit.Pos _ -> r.kind <> P.Add | _ -> false) n.rows) ->
                 Some (Array.of_list (Editor_core.Panels.labels sw.layouts), sw.active)
             | _ -> None in
           let layout_row = Option.map (fun (names, active) ->
             let field = { Parameter.name = "@layout"; label = "Layout"; description = Some "The layout shown";
               folder = []; impact = Parameter.View; primary = true; unit = None; vec3 = None; kind = Parameter.Choice_view names;
               default = Parameter.Choice_value names.(0); current = Parameter.Choice_value names.(active) } in
             { Pxui_shell.Inspector.path = "@layout"; fields = [ field ]; shown = true; locked = false;
               drive = None; live = None }) layout_names in
           (* a split is sized by ratio or with one side fixed: the choice converts it, keeping
              the sizes it shows (flow.md 11.11) *)
           let size_names = [| "By ratio"; "First side fixed"; "Second side fixed" |] in
           let size_row = if n.head <> "ui/split" && n.head <> "ui/split-at" then None else begin
             let given key = List.exists (fun (r : P.row) -> r.key = Flow_graph.Flow_edit.Kw key && r.expr <> None) n.rows in
             let now = if given "first_size" then 1 else if given "second_size" then 2 else 0 in
             let field = { Parameter.name = "@size"; label = "Size"; description = Some "What the split is sized by";
               folder = []; impact = Parameter.View; primary = true; unit = None; vec3 = None; kind = Parameter.Choice_view size_names;
               default = Parameter.Choice_value size_names.(0); current = Parameter.Choice_value size_names.(now) } in
             Some { Pxui_shell.Inspector.path = "@size"; fields = [ field ]; shown = true; locked = false;
                    drive = None; live = None }
           end in
           let rows = Option.to_list layout_row @ Option.to_list size_row @ List.map snd ref_rows @ List.map (fun (parameter : Flow_sop.Port.parameter) ->
             let wired = match authored parameter with Some e -> not (literal e) | None -> false in
             { Pxui_shell.Inspector.path = parameter.path; fields = parameter.fields; shown = on_card_row parameter.path; locked = false;
               (* a computed argument reads as its expression, "=" first: typing another one, or
                  a number, replaces it; the cross removes it *)
               (* a plain name is a link, read as "<- name"; anything else is an expression *)
               drive = (match authored parameter with
                 | Some { S.node = S.Sym name; _ } when wired -> Some name
                 | Some e when wired -> Some ("=" ^ Flow.Lisp.flat e)
                 | _ -> None);
               (* what the drive gives now: the node's value at the probe *)
               live = (match parameter.fields with
                 | [ { Parameter.current = Parameter.Int_value i; _ } ] -> Some (string_of_int i)
                 | [ { current = Parameter.Float_value f; _ } ] -> Some (Editor_core.Number.show f)
                 | [ { current = Parameter.Bool_value b; _ } ] -> Some (string_of_bool b)
                 | _ -> None) }) parameters in
           let expanded = List.filter_map (fun (f : Parameter.field_view) ->
             match f.folder with [] -> None | first :: _ -> Some first) fields |> List.sort_uniq String.compare in
           let num f =
S.make (S.Num (Flow.Lisp.float f)) in
           let edits = if rows = [] then [] else
             Pxui_shell.Inspector.flow_fields ui ~expanded ~width ~pins:true ~pin_click:true ~on_choice
               ~kind_label:(kind_label n.head)
               ~chips:(match value.scope_key with
                 | Some { evaluated = Some ev; _ } -> Navigator.chips ev
                 | _ -> []) rows
             |> List.filter_map (function
               | Pxui_shell.Inspector.Edited ("@layout", Param.Choice_value chosen) ->
                   Option.bind layout_names (fun (names, _) ->
                     Option.map (fun index -> Syntax_edit (Flow_graph.Flow_edit.Set_layout { graph; index }))
                       (Array.find_index (( = ) chosen) names))
               | Pxui_shell.Inspector.Edited ("@size", Param.Choice_value chosen) ->
                   Option.map (fun index ->
                     let how = List.nth [ `Ratio; `First; `Second ] index in
                     (* a split that is not on screen has no sizes to keep: half, or 240 points *)
                     let size = Option.value (resized n.path how) ~default:(match how with
                       | `Ratio -> `Ratio 0.5 | `First -> `First 240 | `Second -> `Second 240) in
                     Syntax_edit (Flow_graph.Flow_edit.Set_layout_size { node = n.path; size }))
                     (Array.find_index (( = ) chosen) size_names)
               | Pxui_shell.Inspector.Edited (name, edited) ->
                   (match List.find_opt (fun (r, _) -> ("@ref:" ^ r.P.label) = name) ref_rows with
                    | Some (r, _) ->
                        (match edited with
                         | Param.Choice_value "new material" ->
                             let name, make = new_material value in
                             Some (Syntax_batch ("New material", [ make; Flow_graph.Flow_edit.Set_arg
                               { node = n.path; key = r.key; sub = [];
                                 value = S.make (S.List [ S.make (S.Sym "ref"); S.make (S.Sym name) ]) } ]))
                         | Param.Choice_value chosen when chosen <> "(none)" && chosen <> "" ->
                             let syntax = S.make (S.List [ S.make (S.Sym "ref"); S.make (S.Sym chosen) ]) in
                             Some (Syntax_edit (Flow_graph.Flow_edit.Set_arg
                               { node = n.path; key = r.key; sub = []; value = syntax }))
                         | _ -> None)
                    | None ->
                        List.find_map (fun (parameter : Flow_sop.Port.parameter) ->
                          match List.find_index (fun (f : Parameter.field_view) -> f.name = name) parameter.fields with
                          | None -> None
                          | Some index ->
                              let syntax = match edited with
                                | Editor_core.Param.Float_value f -> num f
                                | Int_value i -> S.make (S.Num (string_of_int i))
                                | Bool_value b -> S.make (S.Sym (string_of_bool b))
                                | Text_value t | Choice_value t -> S.make (S.Str t) in
                              let syntax = if List.length parameter.fields <> 3 then syntax else
                                S.make (S.Vec (List.mapi (fun i (f : Parameter.field_view) ->
                                  if i = index then syntax else match f.current with
                                    | Editor_core.Param.Float_value x -> num x
                                    | Int_value x -> num (float x) | _ -> S.make (S.Num "0.0")) parameter.fields)) in
                              Some (Syntax_edit (Flow_graph.Flow_edit.Set_arg
                                { node = n.path; key = Flow_graph.Flow_edit.Kw parameter.path; sub = []; value = syntax })))
                          parameters)
               | Pxui_shell.Inspector.Pinned (path, want) ->
                   (* the dot: on the card or not; the default rule's own answer is stored as nothing *)
                   Option.map (fun (r : P.row) ->
                     Pin_row { node = n.path; label = r.label;
                               pin = if want = P.row_shown r then None else Some want }) (row_of path)
               | Pxui_shell.Inspector.Expression (path, text) ->
                   let key, sub = match String.index_opt path '.' with
                     | Some i -> String.sub path 0 i, List.filter_map Fun.id [ List.assoc_opt
                         (String.sub path (i + 1) (String.length path - i - 1)) [ "x", 0; "y", 1; "z", 2 ] ]
                     | None -> path, [] in
                   (match expression_text text with
                    | Ok value ->
                        Some (Syntax_edit (Flow_graph.Flow_edit.Set_arg { node = n.path;
                          key = Flow_graph.Flow_edit.Kw key; sub; value }))
                    | Error message -> Some (Declined message))
               | Pxui_shell.Inspector.Reset path ->
                   (match List.find_opt (fun (r, _) -> ("@ref:" ^ r.P.label) = path) ref_rows with
                    | Some (r, _) ->
                        Some (Syntax_edit (Flow_graph.Flow_edit.Set_arg
                          { node = n.path; key = r.key; sub = []; value = S.make (S.Sym "nil") }))
                    | None ->
                        Some (Syntax_edit (Flow_graph.Flow_edit.Disconnect { node = n.path;
                          key = Flow_graph.Flow_edit.Kw (List.hd (String.split_on_char '.' path)); fallback = None })))) in
           (* what the cook made of a geometry node: read-out rows, as the sheet's Output section *)
           (match geo with
            | Some (g : Flow_graph.Probe.geometry) ->
                ignore (Pxui.Ui.inspector_section ui ~key:"ws-output" ~expanded:true "Output" (fun () ->
                  Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-points" ~label:"points"
                    (group_digits g.points);
                  Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-prims" ~label:"prims"
                    (group_digits g.prims);
                  Option.iter (fun (x, y, z) ->
                    Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-bounds" ~label:"bounds"
                      (Printf.sprintf "%.1f \xc3\x97 %.1f \xc3\x97 %.1f" x y z)) g.extent;
                  if g.groups <> [] then
                    Pxui.Ui.inspector_readout ui ~width ~key:"ws-output-groups" ~label:"groups"
                      (String.concat ", " g.groups)))
            | None -> ());
           (* the note above the binding in the Lisp: one line here, typing is one history entry;
              the last section, closed *)
           let note = if n.synthetic || Flow_graph.Projection.anonymous n then [] else begin
             let current = Option.value n.note ~default:"" in
             Option.value ~default:[] (Pxui.Ui.inspector_section ui ~key:"ws-note-section" "Note" (fun () ->
               if String.contains current '\n' then begin
                 Pxui.Ui.inspector_message ui ~key:"ws-note-lines" "A note of several lines is edited in the text pane.";
                 []
               end else begin
                 let box, control_x, control_y, control_w = Pxui.Ui.inspector_row ui ~width ~key:"ws-note" ~label:"note" () in
                 let text = Pxui.Ui.within ui box (fun () ->
                   fst (Pxui.Ui.value_field ui ~at:(control_x, control_y) ~w:control_w ~h:20.
                     ~left:true ~valid:(fun _ -> true) "ws-note-field" current)) in
                 if text = current then []
                 else [ Syntax_edit (Flow_graph.Flow_edit.Set_note { node = n.path; text }) ]
               end)) end in
           let iterations = Probe.iterations records n ~probes in
           let zone = List.nth_opt (List.rev chain) 0 in
           let picks = match zone with
             | Some z when Array.length iterations > 0 ->
                 Pxui.Ui.inspector_message ui ~key:"ws-runs"
                   (Printf.sprintf "Inside %s: runs %d times. %s" (List.nth z (List.length z - 1))
                      (Option.value ~default:(Array.length iterations) footer.runs)
                      (if n.invariant then "The same every time, so it can move out of the loop."
                       else "It changes with the loop variable."));
                 let current = List.nth probes (List.length probes - 1) in
                 List.concat (List.init (min 64 (Array.length iterations)) (fun k ->
                   if Pxui.Ui.inspector_button ui ~key:(Printf.sprintf "ws-iter-%d" k)
                       (Printf.sprintf "%s%d  %s" (if k = current then "► " else "  ") (k + 1) iterations.(k))
                   then [ Pxui_graph.Scope.Probe_set { zone = z; index = k } ] else []))
             | _ -> [] in
           on_card := List.length (List.filter (fun (r : Pxui_shell.Inspector.flow_row) -> r.shown && r.path.[0] <> '@') rows);
           hoist @ macro @ note @ movers @ edits, picks) in
           (* the sheet's bar: what a field takes, and how many rows are on the card *)
           if not (window || narrow) then
             Pxui.Ui.inspector_bar ui ~hints:[ "s", "pin row to card"; "\xe2\x8c\xa5 click", "type a value" ] ~count:!on_card;
           fst flags @ rename @ reset_all @ requests, snd flags @ picks)
  | _ -> [], []

(* The node of the graph pane that a lowered node of the open object was made by, at the iterations
   the selectors probe. *)
let node_path value node_id =
  match value.scope_key, value.doc.Document.workspace with
  | Some { scope; records = Some records; _ }, _ ->
      let chains = Flow_graph.Probe.chains scope in
      let rec search (s : Flow_graph.Projection.scope) =
        List.find_map (fun (n : Flow_graph.Projection.node) ->
          if compiled_at value chains records n.path = Some node_id then Some n.path
          else Option.bind n.zone (fun (z : Flow_graph.Projection.zone) -> search z.scope)) s.nodes in
      search scope
  | _ -> None
