open Flow
module Edit = Procedural.Edit_graph
module E = Eval

let source_attribute = "__flow_src"

type pending = { node : int; field : string; value : E.value }
type origin = { source : int; site : Workspace.path; iter : int list }
module Origins = Map.Make (struct type t = int * int let compare = compare end)
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
  provenance : origin Origins.t;
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
}

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

let at_zero value =
  if E.is_live value then ok (E.force value ~live:{E.t = 0.}) else value

let is_volatile lowered id = Network.Int_map.mem id lowered.volatile

let objects lowered = List.filter_map (fun (graph : graph) ->
  Option.map (fun root -> graph.instance, graph.network, root) graph.root)
  lowered.graphs

let workspace ~factories ?(compiled_ids = Instance_path.Map.empty)
    ?(sites = []) ?inputs source =
  try
    let catalog = ok (Catalog.of_factories ~version:Manifest.version factories) in
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
    let pending = ref [] and provenance = ref Origins.empty in
    let prepared = Hashtbl.create 256 in
    let prepare (node : E.node) =
      match Hashtbl.find_opt prepared node.id with
      | Some p -> p
      | None ->
          let cid = compiled.(node.id) in
          let geo_ids = List.filter_map (fun (_, v) -> match v with
            | E.Geo id -> Some id | No_geo -> None
            | _ -> None) in
          let live = List.filter (fun (_, v) -> E.is_live v) node.args in
          pending := List.rev_append (List.map (fun (field, value) ->
            {node = cid; field; value}) live) !pending;
          let args = List.map (fun (n, v) -> n, at_zero v) node.args in
          let p = match node.kind with
            | "sop/merge" ->
                let sources = geo_ids args in
                List.iteri (fun index source ->
                  let s = plan.nodes.(source) in
                  provenance := Origins.add (cid, index)
                    {source = compiled.(source); site = s.site; iter = s.iter}
                    !provenance) sources;
                (* the catalog's merge (one rest slot) plus the provenance attribute *)
                let arity = max 1 (List.length sources) in
                let factory = Edit.factory_slots ~key:"merge" ~label:"Merge"
                  ~slots:["input"] ~category:["Copy"] ~inputs:[Edit.Rest]
                  (fun nodes -> Procedural.Sop.merge ~source_attribute
                    (List.filter_map Fun.id nodes)) in
                {cid; factory; arity; changes = [];
                 slots = List.mapi (fun i s -> i, s) sources}
            | "sop/curve" ->
                let points = match List.assoc_opt "points" args with
                  | Some (E.List values) -> Array.map (function
                      | E.Vec3 (x, y, z) -> x, y, z
                      | _ -> fail "E_LOWER" "sop/curve points must be vec3")
                      values
                  | _ -> fail "E_LOWER" "sop/curve needs :points" in
                {cid; factory = Curve.factory; arity = 0; slots = [];
                 changes = [Curve.parameter, Param.Text_value (Curve.encode points)]}
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
                      changes := List.rev_append (changes_of parameter value)
                        !changes) args;
                {cid; factory; arity = List.length names;
                 slots = List.rev !slots; changes = List.rev !changes} in
          Hashtbl.add prepared node.id p; p in
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
      if compiled.(node.id) <> 0 && List.exists (fun (_, v) -> match v with
          | E.Geo j -> volatile.(j) | v -> E.is_live v) node.args then begin
        volatile.(node.id) <- true;
        volatile_nodes := Network.Int_map.add compiled.(node.id) () !volatile_nodes
      end) plan.nodes;
    let live_network network graph =
      let drives = List.fold_left (fun drives (p : pending) ->
        if Edit.find graph ~node_id:p.node = None then drives
        else Port.Map.add Port.{node = p.node; path = p.field}
          (Drive.Live p.value) drives) Port.Map.empty (List.rev !pending) in
      if Port.Map.is_empty drives then network
      else ok (Network.of_parts ~geometry:network.Network.geometry
        ~values:network.values ~drives ~geometry_outputs:network.geometry_outputs
        ~instances:network.instances) in
    let build index (instance : E.instance) =
      let seen = Hashtbl.create 64 in
      let rec reach id =
        if not (Hashtbl.mem seen id) then begin
          Hashtbl.add seen id ();
          List.iter (fun (_, v) -> match v with
            | E.Geo j -> reach j | _ -> ()) plan.nodes.(id).args
        end in
      Array.iter (fun (node : E.node) ->
        if node.inst = index then reach node.id) plan.nodes;
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
          |> List.filter (fun (_, id) -> id <> 0)
          |> List.fold_left (fun m (i, id) -> Network.Int_map.add i id m)
               Network.Int_map.empty;
        pending = List.rev !pending; provenance = !provenance;
        volatile = !volatile_nodes; plan}
  with Fail diagnostic -> Error diagnostic

let counts lowered =
  let live = Network.Int_map.cardinal lowered.volatile in
  live, Network.Int_map.cardinal lowered.compiled - live

let status lowered ~seconds =
  match counts lowered with
  | 0, _ -> None
  | live, cached -> Some (Printf.sprintf "t %d live · %d cached · cook %.1f ms" live cached (seconds *. 1000.))
