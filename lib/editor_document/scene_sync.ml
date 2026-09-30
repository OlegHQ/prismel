(* Edits of the derived scene and World, written back to the workspace text (plan W10).

   The inspector, the handles, the scene list (reparent, rename, delete, hide), the World keys and
   the camera follow all edit the document's derived objects.  Nothing else holds them: the text
   is the truth, so [reconcile] compares the edited document with the one it came from, turns
   each difference into [Flow_edit] ops on the graph that declares the object (an inline call is
   unfolded into a binding first), and lowers the new text again.  Objects that only the host
   made (its camera and lights, a scene of one geometry object per [sop] graph, a World given by
   [?world]) have no text: the first explicit edit of one writes its kind as a graph, once. *)
open Procedural
module S = Flow.Syntax
module F = Flow_sop.Flow_edit
module Param = Editor_core.Param
module Edit = Edit_graph

exception Stop of string
let stop fmt = Printf.ksprintf (fun message -> raise (Stop message)) fmt

let mk node = S.make node
let sym name = mk (S.Sym name)

(* ---- values as text ---- *)

let number x =
  let text = Printf.sprintf "%.6g" x in
  mk (S.Num (if String.exists (function '.' | 'e' | 'n' | 'i' -> true | _ -> false) text
             then text else text ^ ".0"))

let scalar : Param.value -> S.t = function
  | Float_value x -> number x
  | Int_value i -> mk (S.Num (string_of_int i))
  | Bool_value b -> sym (string_of_bool b)
  | Text_value t | Choice_value t -> mk (S.Str t)

let value_syntax (fields : Param.field_view list) = match fields with
  | [ field ] -> scalar field.current
  | fields -> mk (S.Vec (List.map (fun (field : Param.field_view) -> scalar field.current) fields))

let current fields name = List.find_map (fun (f : Param.field_view) ->
  if f.name = name then Some f.current else None) fields

(* the keywords a node's fields say, with [keep] deciding which fields are written *)
let ports node = match Flow_sop.Port.parameters (Contexts.group_triples (Node.parameter_fields node)) with
  | Ok ports -> ports | Error _ -> []

let differing ~before node =
  let before = Node.parameter_fields before in
  List.filter_map (fun (p : Flow_sop.Port.parameter) ->
    if List.exists (fun (f : Param.field_view) -> current before f.name <> Some f.current) p.fields
    then Some (p.path, Some (value_syntax p.fields)) else None) (ports node)

let non_default node =
  List.filter_map (fun (p : Flow_sop.Port.parameter) ->
    if List.exists (fun (f : Param.field_view) -> f.current <> f.default) p.fields
    then Some (p.path, value_syntax p.fields) else None) (ports node)

(* ---- applying ops to the text ---- *)

type state = { catalog : Flow.Check.catalog; mutable workspace : Workspace_doc.t;
               mutable unfolded : (Document.home * F.path) list  (* homes already made bindings *) }

let apply st op = match Workspace_doc.edit st.catalog st.workspace op with
  | Ok workspace -> st.workspace <- workspace
  | Error (d : Flow.Diagnostic.t) -> stop "%s" d.message

(* The binding of a home; an inline call is unfolded into one first. *)
let rec bind st : Document.home -> F.path = function
  | Bound_at path -> path
  | Looped -> stop "It is made by a loop or an expression; edit the text."
  | Inline_in (parent, key) as home ->
      (match List.assoc_opt home st.unfolded with
       | Some path -> path
       | None ->
           let node = bind st parent in
           apply st (F.Unfold { node; key; sub = [] });
           (match F.arg_text st.workspace.source node key with
            | Some { S.node = S.Sym name; _ } ->
                let path = List.rev (name :: List.tl (List.rev node)) in
                st.unfolded <- (home, path) :: st.unfolded; path
            | _ -> stop "The call could not be named."))

let set st home edits =
  if edits <> [] then begin
    let node = bind st home in
    List.iter (fun (key, value) -> match value with
      | Some value -> apply st (F.Set_arg { node; key = F.Kw key; sub = []; value })
      | None -> apply st (F.Disconnect { node; key = F.Kw key; fallback = None })) edits
  end

(* ---- the scene ---- *)

let label graph id = Option.map Node.label (Edit.find graph ~node_id:id)

let object_edits ~before ~after id nb na =
  let parent graph = Option.bind (Objects.parent graph id) (label graph) in
  let name = if Node.label nb <> Node.label na then [ "name", Some (mk (S.Str (Node.label na))) ] else [] in
  let under = if parent before = parent after then []
    else [ "parent", Option.map (fun p -> mk (S.Str p)) (parent after) ] in
  name @ under @ differing ~before:nb na

let homed (doc : Document.t) id = match List.assoc_opt id doc.homes.objects with
  | Some Document.Looped -> Contexts.graph_of (fst doc.workspace) Flow.Workspace.Scene <> None
  | Some _ -> true
  | None -> false

let unique graph id =
  match Option.bind (label graph id) (fun l ->
      List.find_opt (fun (i : Edit.node_info) -> i.id <> id && i.label = l && i.operation <> "world")
        (Edit.inspect graph)) with
  | Some _ -> stop "Two objects are named %S. Rename one of them first." (Option.value ~default:"" (label graph id))
  | None -> ()

let objects st (before : Document.t) (after : Document.t) =
  let b = Document.scene_graph before and a = Document.scene_graph after in
  let gone = ref [] in
  List.iter (fun (id, home) -> if homed before id then
    match Edit.find b ~node_id:id, Edit.find a ~node_id:id with
    | Some nb, Some na ->
        let edits = object_edits ~before:b ~after:a id nb na in
        if List.mem_assoc "parent" edits then Option.iter (unique a) (Objects.parent a id);
        set st home edits
    | Some _, None -> gone := home :: !gone
    | None, _ -> ()) before.homes.objects;
  (* deletions: an inline call leaves its merge (the last one first, so positions hold), then a
     binding goes whole *)
  let bound, inline = List.partition (function Document.Bound_at _ -> true | _ -> false) !gone in
  let position = function Document.Inline_in (_, F.Pos i) -> i | _ -> -1 in
  List.iter (function
    | Document.Inline_in (parent, (F.Pos _ as key)) ->
        apply st (F.Disconnect { node = bind st parent; key; fallback = None })
    | _ -> stop "That object is made by a loop; edit the text.")
    (List.sort (fun x y -> compare (position y) (position x)) inline);
  List.iter (function
    | Document.Bound_at path -> apply st (F.Delete_nodes { nodes = [ path ] })
    | _ -> ()) bound;
  if before.active_camera <> after.active_camera then begin
    (match Option.bind before.active_camera (fun id -> List.assoc_opt id before.homes.objects) with
     | Some home when Option.fold ~none:false ~some:(fun id -> Edit.find a ~node_id:id <> None) before.active_camera ->
         set st home [ "active", None ]
     | _ -> ());
    (match Option.bind after.active_camera (fun id -> List.assoc_opt id before.homes.objects) with
     | Some home -> set st home [ "active", Some (sym "true") ]
     | None -> ())
  end

(* ---- the World ---- *)

let world_id (doc : Document.t) = List.nth_opt (Objects.ids "world" (Document.scene_graph doc)) 0

(* layer ids from the top down *)
let order (network : Document.network) =
  let graph = network.graph.geometry in
  let infos = Edit.inspect graph in
  let consumed = List.concat_map (fun (i : Edit.node_info) ->
    List.filter_map Fun.id (Array.to_list i.inputs)) infos in
  let rec down id acc =
    let acc = id :: acc in
    match Edit.inputs graph ~node_id:id with
    | Some inputs when Array.length inputs > 0 && inputs.(0) <> None
        && not (List.mem (Option.get inputs.(0)) acc) -> down (Option.get inputs.(0)) acc
    | _ -> acc in
  match List.filter (fun (i : Edit.node_info) -> not (List.mem i.id consumed)) infos with
  | top :: _ -> List.rev (down top.id [])
  | [] -> []

(* ---- objects the text does not have ---- *)

(* a name for a binding: the label as a lowercase symbol, unused in [used] *)
let fresh used base =
  let clean = String.map (function 'a' .. 'z' | '0' .. '9' | '_' as c -> c
    | 'A' .. 'Z' as c -> Char.lowercase_ascii c | _ -> '_') base in
  let clean = if clean = "" || not (clean.[0] >= 'a' && clean.[0] <= 'z') then "n" ^ clean else clean in
  let rec go n =
    let candidate = if n = 1 then clean else clean ^ "_" ^ string_of_int n in
    if List.mem candidate !used || Flow.Workspace.name_taken candidate then go (n + 1) else candidate in
  let name = go 1 in
  used := name :: !used; name

(* [(kind slots... :name "label" :field value ...)] for a derived node; only what differs from the
   kind's defaults is written. *)
let call_of ~kind ~label ~default_label ?(slots = []) ?(extra = []) node =
  let name = if label = default_label then [] else [ mk (S.Kw "name"); mk (S.Str label) ] in
  mk (S.List (sym kind :: slots @ name @ extra
    @ List.concat_map (fun (key, value) -> [ mk (S.Kw key); value ]) (non_default node)))

let graph_form name context body =
  mk (S.List [ sym "graph"; sym name; mk (S.Kw "context"); sym context; body ])

let let_star bindings result =
  mk (S.List [ sym "let*"; mk (S.Vec (List.concat_map (fun (n, e) -> [ sym n; e ]) bindings)); result ])

let default_label node = String.lowercase_ascii (Node.operation node)

(* the geometry graph an object's network was lowered from *)
let source_graph (doc : Document.t) id =
  let _, (lowered : Flow_sop.Lower.t) = doc.workspace in
  Option.bind (Document.Int_map.find_opt id doc.networks) (fun (n : Document.network) ->
    List.find_map (fun (g : Flow_sop.Lower.graph) -> if g.network == n.graph then Some g.name else None)
      lowered.graphs)

let object_binding (doc : Document.t) used id (info : Edit.node_info) =
  let graph = Document.scene_graph doc in
  let parent = Objects.parent graph id in
  let slots = if info.operation = "geometry" then
      (match source_graph doc id with
       | Some g -> [ mk (S.List [ sym "ref"; sym g ]) ]
       | None -> stop "%s has no graph of its own to place." info.label)
    else [] in
  let parent = match Option.bind parent (label graph) with
    | Some p -> [ mk (S.Kw "parent"); mk (S.Str p) ] | None -> [] in
  let active = if doc.active_camera = Some id && info.operation = "camera"
    then [ mk (S.Kw "active"); sym "true" ] else [] in
  let default_label = match info.operation, slots with
    | "geometry", [ { S.node = S.List [ _; { S.node = S.Sym g; _ } ]; _ } ] -> g
    | _ -> default_label info.node in
  fresh used info.label,
  call_of ~kind:("scene/" ^ info.operation) ~label:info.label ~default_label ~slots
    ~extra:(parent @ active) info.node

(* the text of every object no binding holds, into the scene graph (made when there is none) *)
let adopt_objects st (doc : Document.t) =
  let graph = Document.scene_graph doc in
  let unhomed = List.filter (fun (i : Edit.node_info) ->
    i.operation <> "world" && not (homed doc i.id)) (Edit.inspect graph) in
  if unhomed <> [] then begin
    let used = ref [] in
    let bindings = List.map (fun (i : Edit.node_info) -> object_binding doc used i.id i) unhomed in
    match Contexts.graph_of st.workspace Flow.Workspace.Scene with
    | None ->
        let names = List.map (fun (n, _) -> sym n) bindings in
        let body = let_star bindings (mk (S.List (sym "scene/merge" :: names))) in
        apply st (F.Set_graph { name = "scene"; form = graph_form "scene" "scene" body })
    | Some g ->
        List.iter2 (fun (name, expr) (i : Edit.node_info) ->
          ignore i;
          apply st (F.Add_node { scope = [ g.name ]; name; expr })) bindings unhomed
  end

(* the World of the derived document as a world graph: layers bound bottom first, the world call last *)
let adopt_world st (doc : Document.t) =
  match world_id doc with
  | None -> ()
  | Some wid ->
      let graph = Document.scene_graph doc in
      let network = Document.Int_map.find wid doc.networks in
      let g = network.graph.geometry in
      let used = ref [] in
      let bindings = List.map (fun id ->
        let info = List.find (fun (i : Edit.node_info) -> i.id = id) (Edit.inspect g) in
        id, fresh used info.label, info) (List.rev (order network)) in
      let layers = List.mapi (fun i (_, name, (info : Edit.node_info)) ->
        let below = if i = 0 then [] else [ sym (let _, n, _ = List.nth bindings (i - 1) in n) ] in
        name, call_of ~kind:("world/" ^ info.operation) ~label:info.label
          ~default_label:(Edit.factory_label (List.assoc ("world/" ^ info.operation) Contexts.world_kinds)) ~slots:below info.node)
        bindings in
      let top = match List.rev layers with (name, _) :: _ -> [ sym name ] | [] -> [] in
      let node = Option.get (Edit.find graph ~node_id:wid) in
      let world = call_of ~kind:"world/world" ~label:(Node.label node) ~default_label:"World" ~slots:top node in
      let body = if layers = [] then world else let_star layers world in
      apply st (F.Set_graph { name = "world"; form = graph_form "world" "world" body })

(* ---- the whole reconciliation ---- *)

let world st (before : Document.t) (after : Document.t) =
  match world_id before, before.homes.world with
  | Some wid, Some home ->
      let b = Document.scene_graph before and a = Document.scene_graph after in
      (match Edit.find b ~node_id:wid, Edit.find a ~node_id:wid with
       | Some nb, Some na ->
           let name = if Node.label nb <> Node.label na then [ "name", Some (mk (S.Str (Node.label na))) ] else [] in
           set st home (name @ differing ~before:nb na)
       | _ -> ());
      (match Document.Int_map.find_opt wid before.networks, Document.Int_map.find_opt wid after.networks with
       | Some bn, Some an ->
           let g (n : Document.network) = n.graph.geometry in
           let known = List.map fst before.homes.layers in
           let surviving = List.filter (fun id -> Edit.find (g an) ~node_id:id <> None) known in
           let removed = List.filter (fun id -> not (List.mem id surviving)) known in
           let stack n = List.filter (fun id -> List.mem id surviving) (order n) in
           if List.exists (fun (i : Edit.node_info) -> not (List.mem i.id known)) (Edit.inspect (g an)) then
             (* new layers (a preset): the World is written out whole *)
             adopt_world st after
           else begin
             List.iter (fun id -> match Edit.find (g bn) ~node_id:id, Edit.find (g an) ~node_id:id with
               | Some nb, Some na ->
                   let name = if Node.label nb <> Node.label na then [ "name", Some (mk (S.Str (Node.label na))) ] else [] in
                   set st (List.assoc id before.homes.layers) (name @ differing ~before:nb na)
               | _ -> ()) surviving;
             let reordered = stack bn <> stack an in
             if removed <> [] || reordered then begin
               (* every layer is a binding of its own before the stack is rewired *)
               let path id = bind st (List.assoc id before.homes.layers) in
               let paths = List.map (fun id -> id, path id) known in
               List.iter (fun id -> apply st (F.Delete_nodes { nodes = [ List.assoc id paths ] })) removed;
               if reordered then begin
                 let bottom_first = List.rev (stack an) in
                 let name id = List.nth (List.assoc id paths) (List.length (List.assoc id paths) - 1) in
                 ignore (List.fold_left (fun below id ->
                   (match below with
                    | Some b -> apply st (F.Connect { node = List.assoc id paths; key = F.Pos 0; src = name b; iter = false })
                    | None -> apply st (F.Disconnect { node = List.assoc id paths; key = F.Pos 0; fallback = None }));
                   Some id) None bottom_first);
                 match List.rev bottom_first with
                 | top :: _ ->
                     apply st (F.Connect { node = bind st home; key = F.Pos 0; src = name top; iter = false })
                 | [] -> ()
               end
             end
           end
       | _ -> ())
  | _ -> ()

(* ---- settings ---- *)

let settings st (before : Document.t) (after : Document.t) =
  match before.homes.settings with
  | Some home when before.settings != after.settings ->
      let changed = List.filter_map (fun (f : Param.field_view) ->
        if current (Settings.fields before.settings) f.name <> Some f.current
        then Some (f.name, Some (scalar f.current)) else None) (Settings.fields after.settings) in
      set st home changed
  | _ -> ()

let unhomed_changes (before : Document.t) (after : Document.t) =
  let b = Document.scene_graph before and a = Document.scene_graph after in
  List.exists (fun (i : Edit.node_info) ->
    i.operation <> "world" && not (homed before i.id)
    && (match Edit.find b ~node_id:i.id with
        | Some nb -> object_edits ~before:b ~after:a i.id nb i.node <> []
                     || Objects.parent b i.id <> Objects.parent a i.id
        | None -> false)) (Edit.inspect a)
  || List.exists (fun (i : Edit.node_info) ->
       i.operation <> "world" && not (homed before i.id) && Edit.find a ~node_id:i.id = None) (Edit.inspect b)

let world_changed (before : Document.t) (after : Document.t) =
  match world_id before with
  | None -> world_id after <> None
  | Some wid ->
      Document.Int_map.find_opt wid before.networks != Document.Int_map.find_opt wid after.networks
      || (match Edit.find (Document.scene_graph before) ~node_id:wid, Edit.find (Document.scene_graph after) ~node_id:wid with
          | Some nb, Some na -> Node.label nb <> Node.label na || differing ~before:nb na <> []
          | _ -> false)

(* [after] is [before] edited in place (its scene, World networks, active camera or settings);
   the result is [after] with the edit written to its text and lowered again.  [adopt]: an
   explicit edit of an object the text lacks writes it (a follow-the-viewport camera move is
   not one, so it stays the host's). *)
let reconcile ~factories ?(adopt = true) (before : Document.t) (after : Document.t) =
  if before.scene == after.scene && before.networks == after.networks
     && before.active_camera = after.active_camera && before.settings == after.settings
  then Ok after
  else
    let ( let* ) = Result.bind in
    let* catalog = Result.map_error Flow.Diagnostic.to_string
        (Contexts.catalog ~version:Flow_sop.Manifest.version factories) in
    let st = { catalog; workspace = fst before.workspace; unfolded = [] } in
    try
      objects st before after;
      world st before after;
      settings st before after;
      if adopt && unhomed_changes before after then adopt_objects st after;
      if adopt && before.homes.world = None && world_changed before after then adopt_world st after;
      if st.workspace == fst before.workspace then Ok after
      else Contexts.of_workspace ~factories ~previous:after st.workspace
           |> Result.map_error Flow.Diagnostic.to_string
    with Stop message -> Error message
