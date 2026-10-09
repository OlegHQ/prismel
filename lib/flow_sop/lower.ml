open Flow
module Edit = Procedural.Edit_graph
module Zone = Procedural.Zone
module E = Eval

let source_attribute = "__flow_src"

type pending = { node : int; field : string; value : E.value }
type origin = { merge : int; input : int; source : int; site : Workspace.path; iter : int list }
type zone = { cid : int; site : Workspace.path; iter : int list; body_site : Workspace.path;
              base : int; count : int Atomic.t; ekey : string option;
              positions : (float * float * float) array Atomic.t }
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
  states : E.value list;
  evaluated : E.t;
  approx : Workspace.Paths.t;
  approx_reasons : (Workspace.path * Diagnostic.t list) list;
  profile : Flow_ir.Profile.t;
  preview : node:int -> probes:int list -> Network.t -> (Network.t * int) option;
}

exception Fail of Diagnostic.t
let fail code message = raise (Fail (Diagnostic.error ~code message))
let ok = function Ok value -> value | Error diagnostic -> raise (Fail diagnostic)
let edit = function Ok value -> value | Error message -> fail "E_LOWER" message

type image_resolver = E.plan -> state:E.state -> live:Frame_input.t -> E.value ->
  (Procedural.Image.t, Diagnostic.t) result
type images = {resolve:image_resolver; metadata:E.plan -> int -> (int * int) option}
let image_provider = Domain.DLS.new_key (fun () -> None)
let with_images ?(metadata=fun _ _->None) resolver run =
  let previous=Domain.DLS.get image_provider in
  Domain.DLS.set image_provider (Some {resolve=resolver;metadata});
  Fun.protect ~finally:(fun()->Domain.DLS.set image_provider previous) run
let image_metadata plan = match Domain.DLS.get image_provider with
  |None->(fun _->None)|Some images->images.metadata plan
let resource_image operation result =
  Procedural.Node.Private.make ~operation ~version:1
    ~parameters:(match result with Ok image->string_of_int(Procedural.Image.data_id image)|Error _->"unbound")
    ~cook_mode:Procedural.Node.Generator ~dependencies:Procedural.Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ _ _->match result with
      |Ok image->Ok Procedural.Node.Private.{payload=Procedural.Payload.Image image;instances=None;diagnostics=[]}
      |Error diagnostic->Error(Procedural.Diagnostic.error ~code:diagnostic.Diagnostic.code diagnostic.message))

type kernel_input = {index : int; cid : int; identity : int;
  signature : Ty.fn_signature; fn : E.fn; sources : int list}

type prepared = {
  cid : int;
  factory : Edit.factory;
  slots : (int * int) list;  (* slot index, source plan id *)
  arity : int;
  changes : (string * Param.value) list;
  dynamic : (E.value * (E.value -> (string * Param.value) list)) list;
      (* a template node: arguments that read the element, forced for each one *)
  zone : zinfo option;
  kernels : kernel_input list;
}
and zinfo = { plan_id : int; lo : int; hi : int;
              preview : (int * int list) option;
              root : int; order : int list; live : bool; stateful : bool;
              captures : int list; ekey : string option; kind : Zone.kind;
              key : string option; base : int; count : int Atomic.t;
              positions : (float * float * float) array Atomic.t }

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
  if E.is_live value then ok (E.force value ~live:(Frame_input.at_time (0.))) else value

let is_zone kind = kind = "zone/points" || kind = "zone/pieces"
let geo_of args = List.filter_map (function _, E.Deferred (ty, j) when Ty.is_cooked ty -> Some j | _ -> None) args

let is_volatile lowered id = Network.Int_map.mem id lowered.volatile

let objects lowered = List.filter_map (fun (graph : graph) ->
  Option.map (fun root -> graph.instance, graph.network, root) graph.root)
  lowered.graphs

let of_checked ~factories ?(reference = false) ?(compiled_ids = Instance_path.Map.empty)
    ?(sites = []) ?inputs checked =
  Phase_timer.measure Lower (fun () ->
  try
    let checked, evaluated = ok (Flow_ir.qualify_workspace ~record:true ?inputs checked) in
    let profile = Flow_ir.Profile.create ~clock:Unix.gettimeofday in
    (* Kernel bodies are cache inputs as well as their captures. The digest is
       lazy so ordinary catalog edits retain their existing pipeline counts.
       ponytail: the whole source invalidates kernels; narrow to body/defn cones
       if unrelated structural edits measurably recook them. *)
    let kernel_source = lazy (Digest.string (fst (Lisp.print checked.source))) in
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
    (* does an argument of a template node read [t] (not only its element)? *)
    let reads_t = E.frame_dependent in
    let templ = Array.make (Array.length plan.nodes) false in
    Array.iter (fun (n : E.node) -> if is_zone n.kind then
      for id = int_arg n "lo" to int_arg n "hi" - 1 do templ.(id) <- true done) plan.nodes;
    (* what a zone reads: its collection and the outside geometry of its template *)
    let zinfos = Hashtbl.create 8 in
    let rec deps (n : E.node) =
      if is_zone n.kind then (match n.args with (_, E.Deferred ((Flow.Ty.Named "geometry"), src)) :: _ -> src | _ -> fail "E_LOWER" "Zone without geometry")
        :: (zinfo n).captures
      else if n.kind = "sop/with_attr" then
        let geometry = List.assoc "geometry" n.args in
        let root = match geometry with E.Deferred (_, id) -> Some id | E.No_geo -> None
          | _ -> fail "E_LOWER" "Attribute write without geometry" in
        Option.to_list root @ List.filter (fun id -> Some id <> root)
          (Attribute_kernel.sources (List.assoc "values" n.args))
      else let direct = geo_of n.args in
        direct @ (List.concat_map (function
          | _, (E.Fn _ as value) -> Attribute_kernel.sources value | _ -> []) n.args
          |> List.sort_uniq Int.compare |> List.filter (fun id -> not (List.mem id direct)))
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
          let live = let rec any id = id < hi
              && (List.exists (fun (_, v) -> reads_t v) plan.nodes.(id).args || any (id + 1)) in
            any lo in
          let stateful = let rec any id = id < hi
              && (List.exists (fun (_, v) -> E.state_dependent v) plan.nodes.(id).args || any (id + 1)) in
            any lo in
          let z = { plan_id = n.id; lo; hi; preview = None; root; live; stateful;
            order = Hashtbl.fold (fun id () l -> id :: l) seen [] |> List.sort Int.compare;
            captures = List.rev !caps; ekey;
            kind = if n.kind = "zone/points" then Zone.Points else Zone.Pieces;
            key = (match List.assoc_opt "key" n.args with Some (E.Text k) -> Some k | _ -> None);
            base = 0; count = Atomic.make (-1); positions = Atomic.make [||] } in
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
          let resource = node.kind="image/load" || node.kind="image/render" || node.kind="image/map" in
          if not template && node.kind <> "sop/with_attr" && not resource then
            pending := List.rev_append (List.map (fun (field, value) ->
              {node = cid; field; value}) live) !pending;
          (* a template node keeps its live arguments: each element forces them *)
          let args = if template || node.kind = "sop/with_attr" || resource then node.args
            else List.map (fun (n, v) -> n, at_zero v) node.args in
          let args = if node.kind <> "sop/material" then args else
            List.concat_map (function
              | "material", E.Struct ("material/standard", _, fields) ->
                  let get name default = Option.value ~default (List.assoc_opt name fields) in
                  ["material", get "name" (E.Text "");
                   "color", get "color" (E.Vec3 (1.,1.,1.));
                   "roughness", get "roughness" (E.Float 0.4);
                   "emission", get "emission" (E.Vec3 (0.,0.,0.))]
              | arg -> [arg]) args in
          let dynamic = ref [] in
          let p = match node.kind with
            | "image/load" | "image/render" | "image/map" ->
                let factory=Edit.factory ~key:node.kind ~label:node.kind ~category:["Image"] ~arity:0
                  (fun _->resource_image node.kind (Error(Diagnostic.error ~code:"E_IMAGE"
                    "This image needs an initial-domain image resolver.")))in
                {cid;factory;slots=[];arity=0;changes=[];dynamic=[];zone=None;kernels=[]}
            | "sop/with_attr" ->
                let name = match List.assoc "attribute" args with
                  | E.Text name -> name | _ -> fail "E_LOWER" "Attribute name must be static text" in
                let values = List.assoc "values" args in
                let sources = match List.assoc "geometry" args with
                  | E.No_geo -> -1 :: deps node | _ -> deps node in
                let factory = Edit.factory ~key:"flow.with_attr" ~label:"Write attribute"
                  ~category:["Flow"] ~arity:(List.length sources)
                  (Attribute_kernel.node ~reference ~profile ~source:(Lazy.force kernel_source) ~name ~values ~sources) in
                {cid; factory; arity = List.length sources; changes = []; dynamic = []; zone = None; kernels = [];
                  slots = List.filter_map (fun (i, source) -> if source < 0 then None else Some (i, source))
                    (List.mapi (fun i source -> i, source) sources)}
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
                {cid; factory; arity; changes = []; dynamic = []; zone = None; kernels = [];
                 slots = List.mapi (fun i s -> i, s) sources}
            | "sop/curve" ->
                let encode points = [Curve.parameter, Param.Text_value (Curve.encode (curve_points points))] in
                let changes = match List.assoc_opt "points" args with
                  | Some points when E.is_live points ->
                      dynamic := [ points, (fun v -> encode [ "points", v ]) ]; []
                  | _ -> encode args in
                {cid; factory = Curve.factory; arity = 0; slots = []; changes;
                 dynamic = []; zone = None; kernels = []}
            | "zone/points" | "zone/pieces" ->
                let z = { (zinfo node) with base = !tags; count = Atomic.make (-1);
                                            positions = Atomic.make [||] } in
                tags := z.base + Zone.max_elements;
                let sources = (match geo_of (List.filter (fun (k, _) -> k = "geometry") args) with
                  | [ src ] -> src | _ -> fail "E_LOWER" "Zone without geometry") :: z.captures in
                List.iter (fun id -> let n = plan.nodes.(id) in
                  if n.kind <> "zone/element" then ignore (prepare n)) z.order;
                let base_site = plan.nodes.(z.root).site in
                zones := {cid; site = node.site; iter = node.iter; body_site = base_site;
                          base = z.base; count = z.count; ekey = z.ekey;
                          positions = z.positions} :: !zones;
                let factory = Edit.factory_slots ~key:"zone" ~label:"Loop over geometry"
                  ~slots:["input"] ~category:["Copy"] ~inputs:[Edit.Rest]
                  (fun nodes -> make_zone ~outer:[] z (Array.of_list (List.filter_map Fun.id nodes))) in
                {cid; factory; arity = List.length sources; changes = []; dynamic = []; kernels = [];
                 zone = Some z; slots = List.mapi (fun i s -> i, s) sources}
            | kind ->
                let args = if kind="image/noise" then List.map(fun(name,value)->
                  (if name="freq" then "frequency" else name),value)args else args in
                let key = match String.split_on_char '/' kind with
                  | ["sop"; key] -> key
                  | ["image"; "noise"] -> "image_noise"
                  | _ -> fail "E_LOWER" ("Cannot lower " ^ kind) in
                let factory = if key = "image_noise" then Procedural.Image_nodes.noise_factory else find_factory key in
                let names = Edit.factory_slot_names factory
                and parameters = parameters factory in
                let rest = List.find_index (function Edit.Rest | Optional_rest -> true | _ -> false)
                  (Edit.factory_inputs factory) in
                let arity = ref (List.length names) in
                let next_rest = ref (Option.value ~default:0 rest) in
                let slots = ref [] and changes = ref [] and kernels = ref [] in
                let rec add_rest = function
                  | E.No_geo -> ()
                  | E.Deferred (ty, id) when Ty.is_cooked ty ->
                      slots := (!next_rest,id) :: !slots;
                      incr next_rest; arity := max !arity !next_rest
                  | E.List values -> Array.iter add_rest values
                  | _ -> fail "E_LOWER" "Repeated inputs need geometry" in
                List.iter (fun (name, value) ->
                  match List.find_index (( = ) name) names, value with
                  | Some index, value when Some index = rest -> add_rest value
                  | Some _, E.No_geo -> ()
                  | Some index, E.Deferred (ty, id) when Ty.is_cooked ty -> slots := (index, id) :: !slots
                  | Some index, E.Fn fn ->
                      let signature = match Ty.of_string (List.nth (Edit.factory_input_types factory) index) with
                        | Some (Ty.Fn (Some signature)) -> signature
                        | _ -> fail "E_LOWER" ("Input " ^ name ^ " does not declare a function signature") in
                      let cid = compiled_id {node with site = node.site @ ["~kernel:" ^ name]} in
                      kernels := {index; cid; signature; fn;
                        identity = Procedural.Node.Private.fresh_id ();
                        sources = Attribute_kernel.sources (E.Fn fn)} :: !kernels
                  | Some _, _ -> fail "E_LOWER" ("Slot " ^ name ^ " needs geometry")
                  | None, value ->
                      let parameter = ok (Port.find_parameter parameters name) in
                      if E.is_live value then
                        dynamic := (value, changes_of parameter) :: !dynamic
                      else changes := List.rev_append (changes_of parameter value)
                        !changes) args;
                {cid; factory; arity = !arity; dynamic = []; zone = None;
                 slots = List.rev !slots; changes = List.rev !changes; kernels = List.rev !kernels} in
          let p = { p with dynamic = List.rev !dynamic } in
          Hashtbl.add prepared node.id p; p
    (* the zone node of a lowered graph: it cooks [z.root] once per element *)
    and kernel_node ?state ?elems (k : kernel_input) inputs =
      Function_kernel.node ?state ~reference ?elems ~identity:k.identity
        ~signature:k.signature ~fn:k.fn ~sources:k.sources inputs
      |> Procedural.Node.Private.restore_id k.cid |> edit
    and make_zone ?state ~outer z inputs =
      let stamp = Option.fold ~none:"" ~some:E.state_stamp state in
      let stamp = match z.preview with
        | None -> stamp
        | Some choice -> stamp ^ ";preview=" ^ Digest.to_hex (Digest.string (Marshal.to_string choice [])) in
      let select = Option.bind z.preview (fun (_, probes) ->
        List.nth_opt probes (List.length plan.nodes.(z.plan_id).iter)) in
      Zone.node ~report:(fun elements ->
          Atomic.set z.count (Array.length elements);
          Atomic.set z.positions (Array.map (fun (e : Zone.element) -> e.position) elements))
        ~live:z.live ~stamp ~kind:z.kind ?key:z.key ?select ~source_attribute
        ~source_base:z.base ~inputs ~body:(fun ~inputs ~context ->
          instantiate ?state ~outer ~live:(Procedural.Context.input context) z ~inputs) ()
    (* Re-root a geometry-loop template at the selected node. Unused bindings
       may have different captures from the authored result, so follow its cone. *)
    and focus z target probes =
      let contains z = target >= z.lo && target < z.hi in
      let inner = ref None in
      for id = z.lo to z.hi - 1 do
        if is_zone plan.nodes.(id).kind then begin
          let candidate = Option.get (prepare plan.nodes.(id)).zone in
          if contains candidate then match !inner with
            | Some old when old.hi - old.lo >= candidate.hi - candidate.lo -> ()
            | _ -> inner := Some candidate
        end
      done;
      let root = match !inner with Some inner -> inner.plan_id | None -> target in
      let seen = Hashtbl.create 16 and captures = ref [] in
      let rec visit id =
        if id >= z.lo && id < z.hi then begin
          if not (Hashtbl.mem seen id) then begin
            Hashtbl.add seen id ();
            let node = plan.nodes.(id) in
            let sources = if id = root && is_zone node.kind then
              let inner = focus (Option.get (prepare node).zone) target probes in
              int_geo node :: inner.captures else deps node in
            List.iter visit sources
          end
        end else if not (List.mem id !captures) then captures := id :: !captures in
      visit root;
      { z with root; preview = Some (target, probes); captures = List.rev !captures;
        order = Hashtbl.fold (fun id () order -> id :: order) seen [] |> List.sort Int.compare }
    and int_geo node = match geo_of (List.filter (fun (key, _) -> key = "geometry") node.E.args) with
      | [id] -> id | _ -> fail "E_LOWER" "Zone without geometry"
    (* one element's copy of the template, over the zone's own inputs *)
    and instantiate ?state ~outer ~live z ~inputs =
      let build ~outer bound id =
        let n = plan.nodes.(id) in
        let p = prepare n in
        let options = List.init p.arity (fun i ->
          match List.find_opt (fun (k : kernel_input) -> k.index = i) p.kernels with
          | Some k -> Some (kernel_node ?state ~elems:outer k
              (List.map (Hashtbl.find bound) k.sources))
          | None -> Option.bind (List.assoc_opt i p.slots) (Hashtbl.find_opt bound)) in
        let node = match p.zone with
          | Some inner ->
              let inner = match z.preview with
                | Some (target, probes) when target >= inner.lo && target < inner.hi -> focus inner target probes
                | _ -> inner in
              let options = int_geo n :: inner.captures
                |> List.map (Hashtbl.find_opt bound) in
              make_zone ?state ~outer inner (Array.of_list (List.filter_map Fun.id options))
          | None when n.kind = "sop/with_attr" && List.assoc "geometry" n.args <> E.No_geo ->
              let name = match List.assoc "attribute" n.args with
                | E.Text name -> name | _ -> fail "E_LOWER" "Attribute name must be static text" in
              Attribute_kernel.node ?state ~reference ~profile ~elems:outer ~source:(Lazy.force kernel_source) ~name
                ~values:(List.assoc "values" n.args) ~sources:(deps n)
                (List.filter_map Fun.id options)
          | None -> edit (Edit.instantiate_optional p.factory options) in
        let node = edit (Procedural.Node.Private.restore_id p.cid node) in
        let changes = p.changes @ List.concat_map (fun (v, changes) ->
          changes (match E.force ?state:(Option.map E.fork_state state) ~elems:outer v ~live with
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
           || (n.kind = "sop/with_attr" && E.is_live (List.assoc "values" n.args))
           (* ponytail: all function inputs vary in a zone; narrow to actual
              element captures if rebuilding constant functions becomes costly. *)
           || (prepare n).kernels <> []
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
      Option.fold ~none:false ~some:(fun context -> Ty.is_cooked (Flow.Context.result context))
        (List.assoc_opt i.graph contexts) in
    (* every plan node gets its id up front, in plan order, so ids do not
       depend on which network asks first *)
    Array.iter (fun (node : E.node) ->
      if sop_instance plan.instances.(node.inst) && Ty.is_cooked node.ty then
        compiled.(node.id) <- compiled_id node) plan.nodes;
    (* volatile: live, or fed by a volatile node (plan order: inputs first).  A loop over geometry
       whose body reads [t] is live, and so are the template nodes its elements are copies of (a copy
       keeps the template's id, so the elements share one volatile slot per node) *)
    let volatile_nodes = ref Network.Int_map.empty in
    let volatile = Array.make (Array.length plan.nodes) false in
    Array.iter (fun (node : E.node) ->
      if compiled.(node.id) <> 0
         && (List.exists (fun j -> volatile.(j)) (deps node)
              || (is_zone node.kind && (zinfo node).live)
              || (not (is_zone node.kind)
                  && List.exists (fun (_, v) -> if templ.(node.id) || node.kind = "sop/with_attr"
                      then reads_t v || E.state_dependent v else E.is_live v ||
                        (match v with E.Fn _ -> reads_t v || E.state_dependent v | _ -> false)) node.args)) then begin
        volatile.(node.id) <- true;
        volatile_nodes := Network.Int_map.add compiled.(node.id) () !volatile_nodes
      end) plan.nodes;
    let live_network network graph =
      let network = Network.with_states evaluated.states network |> Network.with_profile profile
        |> Network.with_reference reference |> Network.with_approx checked.approx in
      let frame_nodes = Hashtbl.fold (fun _ (p : prepared) nodes -> match p.zone with
        | Some z when z.stateful && Edit.find graph ~node_id:p.cid <> None ->
            Network.Int_map.add p.cid (fun state _live node ->
              let snapshot = E.fork_state state in
              Ok(Procedural.Node.Private.adopt_identity ~source:node
                (make_zone ~state:snapshot ~outer:[] z (Procedural.Node.Private.input_array node)))) nodes
        | _ -> nodes) prepared Network.Int_map.empty in
      let frame_nodes = Hashtbl.fold (fun _ (p : prepared) nodes ->
        List.fold_left (fun nodes (k : kernel_input) ->
          if not (E.state_dependent (E.Fn k.fn)) || Edit.find graph ~node_id:k.cid = None then nodes
          else Network.Int_map.add k.cid (fun state _live node ->
            Ok (kernel_node ~state:(E.fork_state state) k (Procedural.Node.inputs node))) nodes)
          nodes p.kernels) prepared frame_nodes in
      let frame_nodes = Array.fold_left (fun nodes (n : E.node) ->
        let values = List.assoc_opt "values" n.args in
        if n.kind <> "sop/with_attr" || Edit.find graph ~node_id:compiled.(n.id) = None then nodes
        else let values=Option.get values in
          let program=ok(Flow_ir.Executor.compile ~profile ~approx:checked.approx
            ~sink:Flow_ir.Sop_input values) in
          let ir=Flow_ir.Executor.graph program in
          let eligible = Attribute_kernel.sources values=[] &&
            (match ir.nodes.(ir.roots.(0)).kind with
             |Flow_ir.Kernel {body=(Packed_map _ | Readback);_}->true |_->false) in
          if not eligible && not(E.state_dependent values) then nodes else
          Network.Int_map.add compiled.(n.id) (fun state live node ->
          let name = match List.assoc "attribute" n.args with E.Text name -> name | _ -> assert false in
          (* Only input-independent producers can materialize before SOP cooking.
             Attribute-reading cones keep their existing cooked-input CPU path. *)
          Result.bind (if eligible then Flow_ir.Executor.try_display ~reference ~state program ~live
            else Ok None) (fun selected ->
          let values=match selected with
            |Some(Flow_ir.Executor.Cpu value)->value
            |None->values
            |Some(Flow_ir.Executor.Gpu _)->assert false in
          if selected=None && not(E.state_dependent values) then Ok node else
          Ok(Procedural.Node.Private.adopt_identity ~source:node
            (Attribute_kernel.node ~reference ~profile ~state:(E.fork_state state) ~source:(Lazy.force kernel_source) ~name
              ~values ~sources:(deps n) (Procedural.Node.inputs node))))) nodes)
        frame_nodes plan.nodes in
      let frame_nodes=Array.fold_left(fun nodes (n:E.node)->
        if (n.kind<>"image/load" && n.kind<>"image/render" && n.kind<>"image/map") || Edit.find graph ~node_id:compiled.(n.id)=None
          then nodes else Network.Int_map.add compiled.(n.id)(fun state live node->
            match Domain.DLS.get image_provider with
            |None->Error(Diagnostic.error ~code:"E_IMAGE" "Image resources need an initial-domain resolver.")
            |Some images->Result.map(fun image->
                if Procedural.Node.parameters node=string_of_int(Procedural.Image.data_id image) then node else
                Procedural.Node.Private.adopt_identity ~source:node (resource_image n.kind (Ok image)))
              (images.resolve plan ~state ~live (E.Deferred(Ty.image,n.id))))nodes)
        frame_nodes plan.nodes in
      let network = Network.with_frame_nodes frame_nodes network in
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
        if node.inst = index && Ty.is_cooked node.ty && not templ.(node.id) then reach node.id) plan.nodes;
      (match instance.result with E.Deferred (ty, j) when Ty.is_cooked ty -> reach j | _ -> ());
      let order = Hashtbl.fold (fun id () l -> id :: l) seen []
        |> List.sort Int.compare in
      let graph = List.fold_left (fun graph id ->
        let p = prepare plan.nodes.(id) in
        let resources = List.map (fun (k : kernel_input) ->
          let inputs = List.map (fun source ->
            match Edit.find graph ~node_id:compiled.(source) with
            | Some node -> node | None -> fail "E_LOWER" "Function capture was not built before its consumer") k.sources in
          k.index, kernel_node k inputs) p.kernels in
        let graph = List.fold_left (fun graph (_, node) -> edit (Edit.add_node node graph)) graph resources in
        let options = List.init p.arity (fun index ->
          match List.assoc_opt index resources with
          | Some node -> Some node
          | None -> match List.assoc_opt index p.slots with
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
        | E.Deferred (ty, id) when Ty.is_cooked ty -> Some compiled.(id)
        | No_geo -> None
        | _ -> fail "E_LOWER" ("Graph " ^ instance.graph ^ " does not return geometry") in
      let graph = match root with
        | Some id -> edit (Edit.set_root id graph) | None -> graph in
      {name = instance.graph; instance = index; default = instance.default; inputs = instance.inputs;
       network = live_network (Network.of_geometry graph) graph; root} in
    let graphs = List.concat (List.mapi (fun index instance ->
      if sop_instance instance then [build index instance] else [])
      (Array.to_list plan.instances)) in
    Hashtbl.iter (fun _ (p : prepared) -> List.iter (fun (k : kernel_input) ->
      if E.frame_dependent (E.Fn k.fn) || E.state_dependent (E.Fn k.fn)
          || List.exists (fun id -> volatile.(id)) k.sources then
        volatile_nodes := Network.Int_map.add k.cid () !volatile_nodes) p.kernels) prepared;
    (* Previewing an unused template must not allocate provenance or zones after
       this immutable lowering has been handed to the document. *)
    Array.iter (fun (node : E.node) -> if compiled.(node.id) <> 0 && node.kind <> "zone/element"
      && Ty.is_cooked node.ty then ignore (prepare node)) plan.nodes;
    let preview ~node:target ~probes network =
      if target < 0 || target >= Array.length compiled || compiled.(target) = 0
        || List.compare_lengths probes plan.nodes.(target).iter <> 0 then None
      else if not templ.(target) then
        if Edit.find network.Network.geometry ~node_id:compiled.(target) = None then None
        else Some (network, compiled.(target))
      else
        let outer = Array.find_opt (fun (node : E.node) -> is_zone node.kind && not templ.(node.id)
          && target >= int_arg node "lo" && target < int_arg node "hi"
          && Edit.find network.geometry ~node_id:compiled.(node.id) <> None) plan.nodes in
        Option.map (fun (node : E.node) ->
          let original = Option.get (prepare node).zone in
          let z = focus original target probes in
          let sources = int_geo node :: z.captures in
          let inputs = Array.of_list (List.map (fun id ->
            match Edit.find network.geometry ~node_id:compiled.(id) with
            | Some node -> node | None -> fail "E_LOWER" "Preview capture is not in the owning network") sources) in
          let viewed = make_zone ~outer:[] z inputs in
          let root = Procedural.Node.id viewed in
          let geometry = edit (Edit.add_node viewed network.geometry) in
          let network = ok (Network.with_geometry geometry network) in
          let frames = if not z.stateful then network.frame_nodes else
            Network.Int_map.add root (fun state _live node ->
              Ok(Procedural.Node.Private.adopt_identity ~source:node
                (make_zone ~state:(E.fork_state state) ~outer:[] z (Procedural.Node.Private.input_array node))))
              network.frame_nodes in
          Network.with_frame_nodes frames network, root) outer in
    Ok {graphs; compiled_ids = !ids; sites = List.rev !site_list;
        compiled = Array.to_list compiled
          |> List.mapi (fun i id -> i, id)
          |> List.filter (fun (i, id) -> id <> 0 && not templ.(i))
          |> List.fold_left (fun m (i, id) -> Network.Int_map.add i id m)
               Network.Int_map.empty;
        pending = List.rev !pending; provenance = !provenance; zones = List.rev !zones;
        volatile = !volatile_nodes; plan; states = evaluated.states; evaluated;
        approx = checked.approx; approx_reasons = checked.approx_reasons; profile; preview}
  with Fail diagnostic -> Error diagnostic)

let workspace ~factories ?extra ?(ops = Operators.all) ?reference ?compiled_ids ?sites ?inputs source =
  Result.bind (Catalog.of_factories ~version:Manifest.version ?extra factories) (fun catalog ->
    match Workspace.check ~ops catalog source with
    | Some checked, _ -> of_checked ~factories ?reference ?compiled_ids ?sites ?inputs checked
    | None, diagnostics -> Error (match List.find_opt (fun (d : Diagnostic.t) ->
        d.severity = Diagnostic.Error) diagnostics with
      | Some d -> d
      | None -> Diagnostic.error ~code:"E_LOWER" "Workspace did not check"))

let counts lowered =
  let live = Network.Int_map.fold (fun _ id n ->
    if Network.Int_map.mem id lowered.volatile then n + 1 else n) lowered.compiled 0 in
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

let zone_element lowered site k =
  List.find_map (fun (z : zone) ->
    if z.site = site then
      (match z.ekey with
       | Some key ->
           let positions = Atomic.get z.positions in
           if k >= 0 && k < Array.length positions then Some (key, positions.(k)) else None
       | None -> None)
    else None) lowered.zones

let field_calls ?state ~live ~resolve lowered =
  let state = Option.map E.fork_state state in
  let defaults = Procedural.Edit_graph.factory_fields Procedural.Nodes.Iso_surface.factory in
  let vector (node : E.node) name =
    match List.assoc_opt name node.args with
    | Some value -> (match E.Private.force_reference ?state ~resolve value ~live with
        | Ok (E.Vec3 (x,y,z)) -> Some (x,y,z) | _ -> None)
    | None ->
        let component suffix = List.find_map (fun (f : Procedural.Parameter.field_view) ->
          if f.name = name ^ suffix then match f.current with
            | Float_value value -> Some value | _ -> None else None) defaults in
        Option.bind (component "_x") (fun x -> Option.bind (component "_y")
          (fun y -> Option.map (fun z -> x,y,z) (component "_z"))) in
  fun zone outer ->
    let offset = ref 0 in
    Array.to_list lowered.plan.nodes |> List.filter_map (fun (node : E.node) ->
      if node.kind <> "sop/iso_surface" then None else
      match List.assoc_opt "field" node.args with
      | Some (E.Fn fn) when E.Private.function_scope fn = Some (zone, outer) ->
          (match vector node "resolution", vector node "min", vector node "max" with
           | Some (rx,ry,rz), Some (lx,ly,lz), Some (hx,hy,hz) ->
               let valid n = Float.is_finite n && n >= 1. && Float.floor n = n
                   && n < float (Sys.max_array_length / 3) in
               if not (valid rx && valid ry && valid rz) then None else
               let nx = int_of_float rx + 1 and ny = int_of_float ry + 1 and nz = int_of_float rz + 1 in
               let limit = Sys.max_array_length / 3 in
               if nx > limit / ny || nx * ny > limit / nz then None else
               let count = nx * ny * nz and start = !offset in
               if count > max_int - start then None else begin
                 offset := start + count;
                 let at k =
                   if k < 0 || k >= count then Error (Flow.Diagnostic.error ~code:"E_LIST_RANGE"
                     "Probe index is outside the field grid.") else
                   let p = [|lx +. float (k mod nx) *. ((hx -. lx) /. rx);
                     ly +. float ((k / nx) mod ny) *. ((hy -. ly) /. ry);
                     lz +. float (k / (nx * ny)) *. ((hz -. lz) /. rz)|] in
                   Result.bind (E.Private.map_function ~signature:Flow.Ty.{params = [Vec3]; result = Float}
                     fn [E.Vec3_array p]) (function
                     | E.Residual residual -> Result.bind (E.Private.map_probe ?state ~resolve
                         ~offset:(start + k) residual ~live) (fun (_, at) -> at 0)
                     | _ -> assert false) in
                 Some (start, count, at)
               end
           | _ -> None)
      | _ -> None)
