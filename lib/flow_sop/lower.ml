open Flow
module Edit = Procedural.Edit_graph
module Zone = Procedural.Zone
module E = Eval

let source_attribute = "__flow_src"

type pending = { node : int; field : string; value : E.value }
type origin = { merge : int; input : int; source : int; site : Workspace.path; iter : int list }
type zone = { cid : int; site : Workspace.path; iter : int list; body_site : Workspace.path;
              base : int; count : int Atomic.t }
type graph = {
  name : string; instance : int; default : bool; inputs : (string * E.value) list;
  network : Network.t; root : int option;
}
type t = {
  graphs : graph list;
  compiled_ids : int Instance_path.Map.t;
  sites : Workspace.path list;
  compiled : int Network.Int_map.t;
  pending : pending list;
  provenance : origin Network.Int_map.t;
  zones : zone list;
  volatile : unit Network.Int_map.t;
  plan : E.plan;
}

exception Fail of Diagnostic.t
let fail code message = raise (Fail (Diagnostic.error ~code message))
let ok = function Ok value -> value | Error diagnostic -> raise (Fail diagnostic)
let edit = function Ok value -> value | Error message -> fail "E_LOWER" message

type prepared = {
  cid : int;
  factory : Edit.factory;
  slots : (int * int) list;  (* slot index, source plan id *)
  arity : int;
  changes : (string * Param.value) list;
  dynamic : (E.value * (E.value -> (string * Param.value) list)) list;
      (* a template node: arguments that read the element, forced for each one *)
  zone : zinfo option;
}
and zinfo = { root : int; order : int list;
              captures : int list; ekey : string option; kind : Zone.kind;
              key : string option; base : int; count : int Atomic.t }

let hex text = match Port.color_of_text text with
  | Some (r, g, b) -> E.Vec3 (r, g, b)
  | None -> fail "E_LOWER" ("Bad colour " ^ text)

let typed = function
  | E.Int n -> Port_type.Int_value n
  | Float f -> Float_value f
  | Bool b -> Bool_value b
  | Vec3 (x, y, z) -> Vec3_value (x, y, z)
  | _ -> fail "E_LOWER" "Argument is not a number, bool or vec3"

let changes_of (parameter : Port.parameter) value =
  match parameter.ty, value with
  | None, E.Text text ->
      let literal = match parameter.fields with
        | [{Param.kind = Param.Choice_view _; _}] -> Param.Choice_value text
        | _ -> Param.Text_value text in
      ok (Port.literal_changes parameter (Port.Scalar literal))
  | None, _ -> fail "E_LOWER" ("Port " ^ parameter.path ^ " takes text")
  | Some _, E.Text text -> snd (ok (Port.normalize parameter (typed (hex text))))
  | Some _, value -> snd (ok (Port.normalize parameter (typed value)))

let changes parameter value = try Ok (changes_of parameter value) with Fail d -> Error d

let at_zero value =
  if E.is_live value then ok (E.force value ~live:{E.t = 0.}) else value

let is_zone kind = kind = "zone/points" || kind = "zone/pieces"
let geo_of args = List.filter_map (function _, E.Geo j -> Some j | _ -> None) args

let is_volatile lowered id = Network.Int_map.mem id lowered.volatile

let objects lowered = List.filter_map (fun (graph : graph) ->
  Option.map (fun root -> graph.instance, graph.network, root) graph.root)
  lowered.graphs

let workspace ~factories ?extra ?(compiled_ids = Instance_path.Map.empty)
    ?(sites = []) ?inputs source =
  try
    let catalog = ok (Catalog.of_factories ~version:Manifest.version ?extra factories) in
    let checked = match Workspace.check catalog source with
      | Some checked, _ -> checked
      | None, diagnostics ->
          (match List.find_opt (fun (d : Diagnostic.t) ->
              d.severity = Diagnostic.Error) diagnostics with
           | Some d -> raise (Fail d)
           | None -> fail "E_LOWER" "Workspace did not check") in
    let evaluated = ok (E.static ?inputs checked) in
    let plan = evaluated.plan in
    let ids = ref compiled_ids and site_table = Hashtbl.create 64
    and site_list = ref (List.rev sites) and site_count = ref (List.length sites) in
    List.iteri (fun i path -> Hashtbl.replace site_table path i) sites;
    let site_index path = match Hashtbl.find_opt site_table path with
      | Some i -> i
      | None ->
          let i = !site_count in
          incr site_count; Hashtbl.add site_table path i;
          site_list := path :: !site_list; i in
    let compiled_id (node : E.node) =
      let key = node.inst :: site_index node.site
        :: List.map (fun k -> -(k + 1)) node.iter in
      match Instance_path.Map.find_opt key !ids with
      | Some id -> id
      | None ->
          let id = Procedural.Node.Private.fresh_id () in
          ids := Instance_path.Map.add key id !ids; id in
    let compiled = Array.make (Array.length plan.nodes) 0 in
    let int_arg (n : E.node) k = match List.assoc_opt k n.args with
      | Some (E.Int i) -> i | _ -> fail "E_LOWER" ("Zone node without " ^ k) in
    let templ = Array.make (Array.length plan.nodes) false in
    Array.iter (fun (n : E.node) -> if is_zone n.kind then
      for id = int_arg n "lo" to int_arg n "hi" - 1 do templ.(id) <- true done) plan.nodes;
    (* what a zone reads: its collection and the outside geometry of its template *)
    let zinfos = Hashtbl.create 8 in
    let rec deps (n : E.node) =
      if is_zone n.kind then (match n.args with (_, E.Geo src) :: _ -> src | _ -> fail "E_LOWER" "Zone without geometry")
        :: (zinfo n).captures
      else geo_of n.args
    and zinfo (n : E.node) = match Hashtbl.find_opt zinfos n.id with
      | Some z -> z
      | None ->
          let lo = int_arg n "lo" and hi = int_arg n "hi" and root = int_arg n "body" in
          let seen = Hashtbl.create 16 and caps = ref [] in
          let rec visit j =
            if j >= lo && j < hi then begin
              if not (Hashtbl.mem seen j) then begin
                Hashtbl.add seen j (); List.iter visit (deps plan.nodes.(j)) end
            end else if not (List.mem j !caps) then caps := j :: !caps in
          visit root;
          let ekey = match List.assoc_opt "element" n.args with Some (E.Text k) -> Some k | _ -> None in
          let z = { root;
            order = Hashtbl.fold (fun id () l -> id :: l) seen [] |> List.sort Int.compare;
            captures = List.rev !caps; ekey;
            kind = if n.kind = "zone/points" then Zone.Points else Zone.Pieces;
            key = (match List.assoc_opt "key" n.args with Some (E.Text k) -> Some k | _ -> None);
            base = 0; count = Atomic.make (-1) } in
          Hashtbl.add zinfos n.id z; z in
    let params_cache = Hashtbl.create 32 in
    let parameters factory =
      let key = Edit.factory_key factory in
      match Hashtbl.find_opt params_cache key with
      | Some parameters -> parameters
      | None ->
          let parameters = ok (Port.parameters (Edit.factory_fields factory)) in
          Hashtbl.add params_cache key parameters; parameters in
    let find_factory key = match List.find_opt (fun factory ->
        Edit.factory_key factory = key) factories with
      | Some factory -> factory
      | None -> fail "E_LOWER" ("Linked catalog has no " ^ key) in
    let pending = ref [] and provenance = ref Network.Int_map.empty and tags = ref 0
    and zones = ref [] in
    let prepared = Hashtbl.create 256 in
    let curve_points args = match List.assoc_opt "points" args with
      | Some (E.List values) -> Array.map (function
          | E.Vec3 (x, y, z) -> x, y, z
          | _ -> fail "E_LOWER" "sop/curve points must be vec3") values
      | _ -> fail "E_LOWER" "sop/curve needs :points" in
    let rec prepare (node : E.node) =
      match Hashtbl.find_opt prepared node.id with
      | Some p -> p
      | None ->
          let template = templ.(node.id) in
          let cid = compiled.(node.id) in
          let live = List.filter (fun (_, v) -> E.is_live v) node.args in
          if not template then
            pending := List.rev_append (List.map (fun (field, value) ->
              {node = cid; field; value}) live) !pending;
          (* a template node keeps its live arguments: each element forces them *)
          let args = if template then node.args
            else List.map (fun (n, v) -> n, at_zero v) node.args in
          let dynamic = ref [] in
          let p = match node.kind with
            | "sop/merge" ->
                let sources = geo_of args in
                let base = !tags in
                tags := base + List.length sources;
                List.iteri (fun index source ->
                  let s = plan.nodes.(source) in
                  provenance := Network.Int_map.add (base + index)
                    {merge = cid; input = index; source = compiled.(source);
                     site = s.site; iter = s.iter} !provenance) sources;
                (* the catalog's merge (one rest slot) plus the provenance attribute *)
                let arity = max 1 (List.length sources) in
                let factory = Edit.factory_slots ~key:"merge" ~label:"Merge"
                  ~slots:["input"] ~category:["Copy"] ~inputs:[Edit.Rest]
                  (fun nodes -> Procedural.Sop.merge ~source_attribute ~source_base:base
                    (List.filter_map Fun.id nodes)) in
                {cid; factory; arity; changes = []; dynamic = []; zone = None;
                 slots = List.mapi (fun i s -> i, s) sources}
            | "sop/curve" ->
                let encode points = [Curve.parameter, Param.Text_value (Curve.encode (curve_points points))] in
                let changes = match List.assoc_opt "points" args with
                  | Some points when E.is_live points ->
                      dynamic := [ points, (fun v -> encode [ "points", v ]) ]; []
                  | _ -> encode args in
                {cid; factory = Curve.factory; arity = 0; slots = []; changes;
                 dynamic = []; zone = None}
            | "zone/points" | "zone/pieces" ->
                let z = { (zinfo node) with base = !tags; count = Atomic.make (-1) } in
                tags := z.base + Zone.max_elements;
                let sources = (match geo_of (List.filter (fun (k, _) -> k = "geometry") args) with
                  | [ src ] -> src | _ -> fail "E_LOWER" "Zone without geometry") :: z.captures in
                List.iter (fun id -> let n = plan.nodes.(id) in
                  if n.kind <> "zone/element" then ignore (prepare n)) z.order;
                (* the body reads [t] only through elements, until a per-element live lane exists *)
                let dummy = List.filter_map (fun (n : E.node) -> match n.kind, List.assoc_opt "element" n.args with
                  | "zone/points", Some (E.Text k) -> Some (k, E.Vec3 (0.3, 0.7, 0.1)) | _ -> None)
                  (Array.to_list plan.nodes) in
                List.iter (fun id -> match Hashtbl.find_opt prepared id with
                  | Some q -> List.iter (fun (v, _) ->
                      let at t = ok (E.force ~elems:dummy v ~live:{E.t}) in
                      if at 0. <> at 1. then fail "E_ZONE_LIVE"
                        (Printf.sprintf "%s reads t inside a loop over geometry; per-element animation is not lowered yet."
                          (String.concat "/" plan.nodes.(id).site))) q.dynamic
                  | None -> ()) z.order;
                let base_site = plan.nodes.(z.root).site in
                zones := {cid; site = node.site; iter = node.iter; body_site = base_site;
                          base = z.base; count = z.count} :: !zones;
                let factory = Edit.factory_slots ~key:"zone" ~label:"Loop over geometry"
                  ~slots:["input"] ~category:["Copy"] ~inputs:[Edit.Rest]
                  (fun nodes -> make_zone ~outer:[] z (Array.of_list (List.filter_map Fun.id nodes))) in
                {cid; factory; arity = List.length sources; changes = []; dynamic = [];
                 zone = Some z; slots = List.mapi (fun i s -> i, s) sources}
            | kind ->
                let key = match String.split_on_char '/' kind with
                  | ["sop"; key] -> key
                  | _ -> fail "E_LOWER" ("Cannot lower " ^ kind) in
                let factory = find_factory key in
                let names = Edit.factory_slot_names factory
                and parameters = parameters factory in
                let slots = ref [] and changes = ref [] in
                List.iter (fun (name, value) ->
                  match List.find_index (( = ) name) names, value with
                  | Some _, E.No_geo -> ()
                  | Some index, E.Geo id -> slots := (index, id) :: !slots
                  | Some _, _ -> fail "E_LOWER" ("Slot " ^ name ^ " needs geometry")
                  | None, value ->
                      let parameter = ok (Port.find_parameter parameters name) in
                      if E.is_live value then
                        dynamic := (value, changes_of parameter) :: !dynamic
                      else changes := List.rev_append (changes_of parameter value)
                        !changes) args;
                {cid; factory; arity = List.length names; dynamic = []; zone = None;
                 slots = List.rev !slots; changes = List.rev !changes} in
          let p = { p with dynamic = List.rev !dynamic } in
          Hashtbl.add prepared node.id p; p
    (* the zone node of a lowered graph: it cooks [z.root] once per element *)
    and make_zone ~outer z inputs =
      Zone.node ~report:(Atomic.set z.count) ~kind:z.kind ?key:z.key ~source_attribute
        ~source_base:z.base ~inputs ~body:(instantiate ~outer z) ()
    (* one element's copy of the template, over the zone's own inputs *)
    and instantiate ~outer z ~inputs =
      let build ~outer bound id =
        let n = plan.nodes.(id) in
        let p = prepare n in
        let options = List.init p.arity (fun i ->
          Option.bind (List.assoc_opt i p.slots) (Hashtbl.find_opt bound)) in
        let node = match p.zone with
          | Some inner ->
              make_zone ~outer inner (Array.of_list (List.filter_map Fun.id options))
          | None -> edit (Edit.instantiate_optional p.factory options) in
        let node = edit (Procedural.Node.Private.restore_id p.cid node) in
        let changes = p.changes @ List.concat_map (fun (v, changes) ->
          changes (match E.force ~elems:outer v ~live:{E.t = 0.} with
            | Ok v -> v | Error d -> failwith (Diagnostic.to_string d))) p.dynamic in
        let node = if changes = [] then node
          else fst (edit (Procedural.Node.apply_parameters node changes)) in
        Hashtbl.replace bound id node in
      (* what does not read the element is built once per cook of the zone *)
      let shared = Hashtbl.create 16 and varies = Hashtbl.create 16 in
      List.iteri (fun k j -> Hashtbl.replace shared j inputs.(k + 1)) z.captures;
      List.iter (fun id ->
        let n = plan.nodes.(id) in
        if n.kind = "zone/element" || is_zone n.kind || (prepare n).dynamic <> []
           || List.exists (Hashtbl.mem varies) (deps n)
        then Hashtbl.replace varies id ()
        else build ~outer:[] shared id) z.order;
      fun (element : Zone.element) ->
        let outer = match z.ekey with
          | Some key -> let x, y, z = element.position in (key, E.Vec3 (x, y, z)) :: outer
          | None -> outer in
        let bound = Hashtbl.copy shared in
        List.iter (fun id ->
          if Hashtbl.mem varies id then
            if plan.nodes.(id).kind = "zone/element" then
              Hashtbl.replace bound id (Zone.element_node element)
            else build ~outer bound id) z.order;
        Hashtbl.find bound z.root in
    let contexts = List.map (fun (g : Workspace.graph) -> g.name, g.context)
      checked.graphs in
    let sop_instance (i : E.instance) =
      List.assoc_opt i.graph contexts = Some Workspace.Sop in
    (* every plan node gets its id up front, in plan order, so ids do not
       depend on which network asks first *)
    Array.iter (fun (node : E.node) ->
      if sop_instance plan.instances.(node.inst) then
        compiled.(node.id) <- compiled_id node) plan.nodes;
    (* volatile: live, or fed by a volatile node (plan order: inputs first) *)
    let volatile_nodes = ref Network.Int_map.empty in
    let volatile = Array.make (Array.length plan.nodes) false in
    Array.iter (fun (node : E.node) ->
      if compiled.(node.id) <> 0 && not templ.(node.id)
         && (List.exists (fun j -> volatile.(j)) (deps node)
              || List.exists (fun (_, v) -> E.is_live v) node.args) then begin
        volatile.(node.id) <- true;
        volatile_nodes := Network.Int_map.add compiled.(node.id) () !volatile_nodes
      end) plan.nodes;
    let live_network network graph =
      let drives = List.fold_left (fun drives (p : pending) ->
        if Edit.find graph ~node_id:p.node = None then drives
        else Port.Map.add Port.{node = p.node; path = p.field}
          p.value drives) Port.Map.empty (List.rev !pending) in
      if Port.Map.is_empty drives then network else ok (Network.with_drives drives network) in
    let build index (instance : E.instance) =
      let seen = Hashtbl.create 64 in
      let rec reach id =
        if not (Hashtbl.mem seen id) then begin
          Hashtbl.add seen id ();
          List.iter reach (deps plan.nodes.(id))
        end in
      Array.iter (fun (node : E.node) ->
        if node.inst = index && not templ.(node.id) then reach node.id) plan.nodes;
      (match instance.result with E.Geo j -> reach j | _ -> ());
      let order = Hashtbl.fold (fun id () l -> id :: l) seen []
        |> List.sort Int.compare in
      let graph = List.fold_left (fun graph id ->
        let p = prepare plan.nodes.(id) in
        let options = List.init p.arity (fun index ->
          match List.assoc_opt index p.slots with
          | Some source -> Edit.find graph ~node_id:compiled.(source)
          | None -> None) in
        let node = edit (Edit.instantiate_optional p.factory options) in
        let node = edit (Procedural.Node.Private.restore_id p.cid node) in
        let inputs = Array.of_list (List.map (Option.map Procedural.Node.id)
          options) in
        let graph = edit (Edit.add_node ~factory:p.factory ~inputs node graph) in
        if p.changes = [] then graph
        else fst (edit (Edit.apply_parameters graph ~node_id:p.cid p.changes)))
        Edit.empty order in
      let root = match instance.result with
        | E.Geo id -> Some compiled.(id)
        | No_geo -> None
        | _ -> fail "E_LOWER" ("Graph " ^ instance.graph ^ " does not return geometry") in
      let graph = match root with
        | Some id -> edit (Edit.set_root id graph) | None -> graph in
      {name = instance.graph; instance = index; default = instance.default; inputs = instance.inputs;
       network = live_network (Network.of_geometry graph) graph; root} in
    let graphs = List.concat (List.mapi (fun index instance ->
      if sop_instance instance then [build index instance] else [])
      (Array.to_list plan.instances)) in
    Ok {graphs; compiled_ids = !ids; sites = List.rev !site_list;
        compiled = Array.to_list compiled
          |> List.mapi (fun i id -> i, id)
          |> List.filter (fun (i, id) -> id <> 0 && not templ.(i))
          |> List.fold_left (fun m (i, id) -> Network.Int_map.add i id m)
               Network.Int_map.empty;
        pending = List.rev !pending; provenance = !provenance; zones = List.rev !zones;
        volatile = !volatile_nodes; plan}
  with Fail diagnostic -> Error diagnostic

let counts lowered =
  let live = Network.Int_map.cardinal lowered.volatile in
  live, Network.Int_map.cardinal lowered.compiled - live

let status lowered ~seconds =
  match counts lowered with
  | 0, _ -> None
  | live, cached -> Some (Printf.sprintf "t %d live · %d cached · cook %.1f ms" live cached (seconds *. 1000.))

let origin lowered tag =
  match Network.Int_map.find_opt tag lowered.provenance with
  | Some _ as found -> found
  | None ->
      List.find_map (fun (z : zone) ->
        let index = tag - z.base in
        if index >= 0 && index < Zone.max_elements then
          Some {merge = z.cid; input = index; source = z.cid; site = z.body_site;
                iter = z.iter @ [ index ]}
        else None) lowered.zones

let tags lowered ~site ~iter =
  let plain = Network.Int_map.fold (fun tag (o : origin) tags ->
    if o.site = site && o.iter = iter then tag :: tags else tags) lowered.provenance [] in
  let n = List.length iter in
  List.fold_left (fun tags (z : zone) ->
    if z.site = site && z.iter = iter then
      List.init (max 0 (Atomic.get z.count)) (fun i -> z.base + i) @ tags
    else if z.body_site = site && List.compare_length_with z.iter (n - 1) = 0
       && List.for_all2 ( = ) z.iter (List.filteri (fun i _ -> i < n - 1) iter)
    then z.base + List.nth iter (n - 1) :: tags else tags) plain lowered.zones

let zone_count lowered site =
  List.find_map (fun (z : zone) ->
    if z.site = site && Atomic.get z.count >= 0 then Some (Atomic.get z.count) else None)
    lowered.zones
