type node_timing = {
  node_id : int;
  label : string;
  operation : string;
  seconds : float;
  cache_hit : bool;
}

type stats = {
  cooks : int;
  hits : int;
  misses : int;
  evictions : int;
  volatile_hits : int;
  volatile_misses : int;
  retained_entries : int;
  volatile_entries : int;
  retained_payload_bytes : int;
  last_node : node_timing option;
}

type output = {
  geometry : Rdk.Geometry.t;
  diagnostics : Diagnostic.t list;
  instances : Rays_math.Mat4.t array option;
}

type delta = {
  source : int;
  positions : Rdk.Packed.Float3.t option;
  attributes : (Rdk.Attribute.owner * string * Rdk.Attribute.t option) list;
}
type entry = {
  output : output;
  components : (int * int) list;
  local_diagnostics : Diagnostic.t list;
  delta : delta option;
}

module Entry_cache = Lru.Make (String)

(* Cook outputs share packed payload planes; the pool counts each plane once. *)
type payload_pool = { refs : (int, int * int) Hashtbl.t; mutable bytes : int }

type inspection_entry = { root : Graph.t Weak.t; infos : Graph.info list;
  bytes : int }

let inspection_capacity = 64
let inspection_byte_capacity = 8 * 1024 * 1024

let rec find_inspection root = function
  | [] -> None
  | entry :: rest ->
      (match Weak.get entry.root 0 with
       | Some cached when cached == root -> Some entry.infos
       | None | Some _ -> find_inspection root rest)

type t = {
  max_entries : int;
  max_payload_bytes : int;
  cache : entry Entry_cache.t;
  payload : payload_pool;
  mutable inspection_cache : inspection_entry list;
  mutable cooks : int;
  mutable hits : int;
  mutable misses : int;
  mutable volatile : int -> bool;
  slots : (int, string * entry) Hashtbl.t;  (* volatile node id -> latest *)
  mutable volatile_hits : int;
  mutable volatile_misses : int;
  mutable evictions : int;
  mutable last_node : node_timing option;
  times : (int, float) Hashtbl.t;  (* node id -> its own seconds the last time it was really cooked *)
  times_lock : Mutex.t;
  mutable closed : bool;
  mutable materialized : (output * Rdk.Geometry.t) list;  (* see [input_geometry] *)
}

let release_components payload components =
  List.iter (fun (id, bytes) ->
    match Hashtbl.find_opt payload.refs id with
    | None -> ()
    | Some (_, 1) ->
        Hashtbl.remove payload.refs id;
        payload.bytes <- payload.bytes - bytes
    | Some (_, references) ->
        Hashtbl.replace payload.refs id (bytes, references - 1))
    components

let create ~max_entries ~max_payload_bytes =
  if max_entries < 0 then Error "Session.create: max_entries must be non-negative"
  else if max_payload_bytes < 0 then
    Error "Session.create: max_payload_bytes must be non-negative"
  else
    let payload = { refs = Hashtbl.create (min (max_entries * 4) 4096); bytes = 0 } in
    Ok {
    max_entries; max_payload_bytes;
    cache = Entry_cache.create max_entries
        ~release:(fun _ entry -> release_components payload entry.components);
    payload;
    inspection_cache = [];
    cooks = 0; hits = 0; misses = 0; evictions = 0;
    volatile = (fun _ -> false); slots = Hashtbl.create 16; volatile_hits = 0; volatile_misses = 0;
    last_node = None; times = Hashtbl.create 64; times_lock = Mutex.create (); closed = false; materialized = [];
  }

let inspect session root =
  if session.closed then invalid_arg "Session.inspect: session is closed";
  match find_inspection root session.inspection_cache with
  | Some infos -> infos
  | None ->
      let infos = Graph.inspect root in
      let bytes = List.fold_left (fun bytes (info : Graph.info) ->
          bytes + 96 + String.length info.label +
          String.length info.operation + String.length info.parameters +
          (16 * List.length info.input_ids)) 0 infos in
      let weak = Weak.create 1 in
      Weak.set weak 0 (Some root);
      let rec trim count bytes kept = function
        | [] -> List.rev kept
        | entry :: rest when Weak.check entry.root 0 &&
            count < inspection_capacity &&
            entry.bytes <= inspection_byte_capacity - bytes ->
            trim (count + 1) (bytes + entry.bytes) (entry :: kept) rest
        | _ :: rest -> trim count bytes kept rest in
      session.inspection_cache <- trim 0 0 []
          ({ root = weak; infos; bytes } :: session.inspection_cache);
      infos

let insert session key entry =
  let components = Rdk.Geometry.payload_components entry.output.geometry in
  if session.max_entries > 0 then begin
    let payload = session.payload in
    List.iter (fun (id, bytes) ->
      match Hashtbl.find_opt payload.refs id with
      | None ->
          Hashtbl.add payload.refs id (bytes, 1);
          payload.bytes <- payload.bytes + bytes
      | Some (known_bytes, references) ->
          Hashtbl.replace payload.refs id (known_bytes, references + 1))
      components;
    let before = Entry_cache.length session.cache
    and replaced = Option.is_some (Entry_cache.peek session.cache key) in
    Entry_cache.add session.cache key { entry with components };
    while payload.bytes > session.max_payload_bytes
          && Entry_cache.drop_oldest session.cache do () done;
    session.evictions <- session.evictions + before
      + (if replaced then 0 else 1) - Entry_cache.length session.cache
  end

let lookup session ~volatile node key =
  if not volatile then
    (match Entry_cache.find session.cache key with
     | entry -> Some entry | exception Not_found -> None)
  else match Hashtbl.find_opt session.slots (Node.id node) with
    | Some (latest, output) when String.equal latest key -> Some output
    | _ -> None

let store_volatile session node key entry =
  if session.max_entries > 0 then begin
    (* bounded: one slot per node id, dropped wholesale past max_entries *)
    if Hashtbl.length session.slots >= session.max_entries then
      Hashtbl.reset session.slots;
    Hashtbl.replace session.slots (Node.id node) (key, entry)
  end

let set_volatile session predicate =
  session.volatile <- predicate;
  Hashtbl.filter_map_inplace (fun id slot ->
    if predicate id then Some slot else None) session.slots

(* An opaque, unambiguous cache identity: integers are fixed-width binary and
   every variable-length string is length-prefixed, so no field boundary can
   shift. It avoids [Printf] and [string_of_int] on this per-node, per-cook
   path. *)
let selective node inputs =
  let facts = Node.facts node in
  Array.length inputs = 1 && Node.Private.expand node = None
  && facts.topology = Node.Preserved && not (List.mem "*" facts.reads || List.mem "*" facts.writes)
  && (facts.cook_mode = Node.Duplicate_input 0 || facts.cook_mode = Node.Passthrough 0)

let cache_key node context inputs =
  let parameters = Node.Private.cache_parameters node
  and parameter_key = Node.parameter_key node
  and facts_key = Node.Private.cache_facts node in
  let buffer = Buffer.create (64 + String.length parameters
      + String.length parameter_key + String.length facts_key + (8 * Array.length inputs)) in
  let add_int value = Buffer.add_int64_le buffer (Int64.of_int value) in
  let add_sized value =
    add_int (String.length value); Buffer.add_string buffer value in
  add_int (Node.id node);
  add_int (Node.version node);
  add_sized (Node.operation node);
  add_sized parameters;
  add_sized parameter_key;
  add_int (Array.length inputs);
  let facts = Node.facts node in
  add_sized facts_key;
  if not (selective node inputs) then begin
    add_int 0;
    Array.iter (fun geometry -> add_int (Rdk.Geometry.data_id geometry)) inputs
  end else begin
    add_int 1;
    let geometry = inputs.(0) in
    add_int (Rdk.Topology.data_id (Rdk.Geometry.topology geometry));
    add_int (if List.mem "P" facts.reads then Rdk.Packed.Float3.data_id (Rdk.Geometry.positions geometry) else 0);
    let attributes = List.filter (fun attribute -> List.mem (Rdk.Attribute.name attribute) facts.reads)
      (Rdk.Geometry.attributes geometry) in
    add_int (List.length attributes);
    List.iter (fun attribute -> add_int (Rdk.Attribute.data_id attribute)) attributes;
    (* Presence and order affect set-initial, normal removal and output order.
       Unread payload IDs remain absent from the key. *)
    let layout = Rdk.Geometry.attributes geometry in
    add_int (List.length layout);
    List.iter (fun attribute ->
      add_int (match Rdk.Attribute.owner attribute with Point -> 0 | Vertex -> 1 | Primitive -> 2 | Detail -> 3);
      add_sized (Rdk.Attribute.name attribute)) layout;
    let groups = Rdk.Geometry.groups geometry and edges = Rdk.Geometry.edge_groups geometry in
    add_int (List.length groups); List.iter (fun group -> add_int (Rdk.Group.data_id group)) groups;
    add_int (List.length edges); List.iter (fun group -> add_int (Rdk.Edge_group.data_id group)) edges
  end;
  Buffer.add_string buffer
    (Context.cache_projection (Node.dependencies node) context);
  Buffer.contents buffer

exception Invalid_facts of string

let refuse_facts message = raise_notrace (Invalid_facts message)

let node_result f =
  try f () with
  | Invalid_facts message -> Error (Diagnostic.error ~code:"E_NODE_FACTS" message)
  | exn -> Error (Diagnostic.error ~code:"uncaught_node_exception"
      ~cause:(Printexc.to_string exn)
      "a procedural node raised an exception while cooking")

let delta node inputs (cooked : Node.Private.cooked) =
  if not (selective node inputs) then None else
  let source = inputs.(0) in
  let geometry = cooked.geometry in
  if Option.is_some cooked.instances then
    refuse_facts "component-cached nodes must return unpacked geometry";
  if Rdk.Geometry.topology source != Rdk.Geometry.topology geometry then
    refuse_facts "Preserved topology was replaced";
  let module G = Rdk.Geometry in
  let module A = Rdk.Attribute in
  if List.map Rdk.Group.data_id (G.groups source) <> List.map Rdk.Group.data_id (G.groups geometry)
    || List.map Rdk.Edge_group.data_id (G.edge_groups source) <>
       List.map Rdk.Edge_group.data_id (G.edge_groups geometry) then
    refuse_facts "component-cached nodes must preserve groups and edge groups";
  let before = Hashtbl.create 8 and after = Hashtbl.create 8 in
  let key attribute = A.owner attribute, A.name attribute in
  List.iter (fun attribute -> Hashtbl.add before (key attribute) attribute) (G.attributes source);
  List.iter (fun attribute -> Hashtbl.add after (key attribute) attribute) (G.attributes geometry);
  let attributes = ref [] in
  List.iter (fun attribute ->
    let owner, name = key attribute in
    let changed = match Hashtbl.find_opt before (owner, name) with
      | Some previous -> A.data_id previous <> A.data_id attribute | None -> true in
    if changed then begin
      if not (List.mem name (Node.facts node).writes) then
        refuse_facts ("undeclared write " ^ name);
      attributes := (owner, name, Some attribute) :: !attributes
    end) (G.attributes geometry);
  List.iter (fun attribute ->
    let owner, name = key attribute in
    if not (Hashtbl.mem after (owner, name)) then begin
      if not (List.mem name (Node.facts node).writes) then
        refuse_facts ("undeclared deletion " ^ name);
      attributes := (owner, name, None) :: !attributes
    end) (G.attributes source);
  let positions = if G.positions source == G.positions geometry then None else begin
    if not (List.mem "P" (Node.facts node).writes) then refuse_facts "undeclared P write";
    Some (G.positions geometry)
  end in
  Some {source = G.data_id source; positions; attributes = List.rev !attributes}

let refresh inputs input_diagnostics entry =
  let geometry, delta = match entry.delta with
    | Some delta when delta.source <> Rdk.Geometry.data_id inputs.(0) ->
        let source = inputs.(0) in
        let module G = Rdk.Geometry in
        let module A = Rdk.Attribute in
        let values = Hashtbl.create 8 in
        List.iter (fun attribute -> Hashtbl.add values (A.owner attribute, A.name attribute) attribute)
          (G.attributes source);
        List.iter (fun (owner, name, value) -> match value with
          | Some attribute -> Hashtbl.replace values (owner, name) attribute
          | None -> Hashtbl.remove values (owner, name)) delta.attributes;
        let attributes = List.map (fun attribute ->
          Hashtbl.find values (A.owner attribute, A.name attribute)) (G.attributes entry.output.geometry) in
        let geometry = G.create ~positions:(Option.value ~default:(G.positions source) delta.positions)
          ~topology:(G.topology source) ~attributes
          ~groups:(G.groups source) ~edge_groups:(G.edge_groups source) ()
          |> function Ok geometry -> geometry | Error error ->
              refuse_facts ("cannot refresh cached components: " ^ error) in
        geometry, Some {delta with source = G.data_id source}
    | _ -> entry.output.geometry, entry.delta in
  let diagnostics = List.concat (List.rev (entry.local_diagnostics :: input_diagnostics)) in
  if geometry == entry.output.geometry && diagnostics = entry.output.diagnostics then entry
  else {entry with output = {entry.output with geometry; diagnostics}; delta}

let timing node ~seconds ~cache_hit = {
  node_id = Node.id node;
  label = Node.label node;
  operation = Node.operation node;
  seconds;
  cache_hit;
}

(* a cache hit keeps the node's last real cook time; bounded: a full table starts over *)
let times_capacity = 4096
let record_time session id seconds =
  Mutex.protect session.times_lock (fun () ->
    if Hashtbl.length session.times >= times_capacity then Hashtbl.reset session.times;
    Hashtbl.replace session.times id seconds)

let node_seconds session id =
  Mutex.protect session.times_lock (fun () -> Hashtbl.find_opt session.times id)

let cancellation_error node =
  Diagnostic.error ~code:"cancelled" "procedural cook was cancelled"
  |> Diagnostic.prepend_trace (Node.trace node)

exception Materialize of Diagnostic.error

(* A packed input reaches its consumer materialized (the explicit boundary),
   once per packed output: the copy keeps a stable data id, so downstream
   cache keys still hit. ponytail: the last 8 packed outputs are kept; an
   LRU keyed by output identity if graphs pack more than that. *)
let input_geometry session output = match output.instances with
  | None -> Ok output.geometry
  | Some transforms ->
      match List.assq_opt output session.materialized with
      | Some geometry -> Ok geometry
      | None ->
          match Rdk.Instance_copy.materialize_instances ~transforms output.geometry with
          | Error error -> Error (Diagnostic.error ~code:(Rdk.Error.code error)
              ~cause:(Rdk.Error.to_string error) "packed instances could not be materialized")
          | Ok geometry ->
              session.materialized <- (output, geometry)
                :: List.take 7 session.materialized;
              Ok geometry

(* [memo] holds this cook's results by node id so a node reachable through
   several paths is evaluated once; the physical check guards reused ids. *)
let rec evaluate memo session context node =
  match List.find_opt (fun (seen, _) -> seen == node)
      (Hashtbl.find_all memo (Node.id node)) with
  | Some (_, result) -> result
  | None ->
      let result = evaluate_uncached memo session context node in
      Hashtbl.add memo (Node.id node) (node, result);
      result

(* A zone node cooks the sub-graph of each element through this
   session, so an unchanged element is a cache hit, then merges their outputs.
   ponytail: sequential over elements; parallelise with [Parallel.map_array]
   only after a byte-identical test and a bench show a win. *)
and cook_node memo session context node geometries =
  match Node.Private.expand node with
  | None -> Node.Private.cook node context geometries
  | Some expand ->
      match expand context (Node.Private.input_array node) geometries with
      | Error _ as error -> error
      | Ok roots ->
          let outputs = Array.make (Array.length roots) None in
          let diagnostics = ref [] in
          let rec go index =
            if index = Array.length roots then Ok ()
            else match evaluate memo session context roots.(index) with
              | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
              | Ok output ->
                  (match input_geometry session output with
                   | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
                   | Ok geometry ->
                       outputs.(index) <- Some geometry;
                       diagnostics := output.diagnostics :: !diagnostics;
                       go (index + 1)) in
          match go 0 with
          | Error _ as error -> error
          | Ok () -> Result.map (fun (cooked : Node.Private.cooked) ->
              {cooked with diagnostics = List.concat (List.rev (cooked.diagnostics :: !diagnostics))})
              (Node.Private.cook node context (Array.map Option.get outputs))

and evaluate_uncached memo session context node =
  if Context.cancelled context then Error (cancellation_error node)
  else
    let all_inputs = Node.Private.input_array node in
    let selected = match Node.Private.input_policy node with
      | Node.Private.All -> all_inputs
      | Node.Private.Only index -> [| all_inputs.(index) |]
    in
    let count = Array.length selected in
    let geometries = Array.make count None in
    let input_diagnostics = ref [] in
    let rec cook_inputs index =
      if index = count then Ok ()
      else match evaluate memo session context selected.(index) with
        | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
        | Ok output ->
            (match input_geometry session output with
             | Error error -> raise_notrace (Materialize error)
             | Ok geometry -> geometries.(index) <- Some geometry);
            input_diagnostics := output.diagnostics :: !input_diagnostics;
            cook_inputs (index + 1)
    in
    match (try cook_inputs 0 with Materialize error ->
        Error (Diagnostic.prepend_trace (Node.trace node) error)) with
    | Error _ as error -> error
    | Ok () ->
        let geometries = Array.map Option.get geometries in
        let key = cache_key node context geometries in
        let volatile = session.volatile (Node.id node) in
        match lookup session ~volatile node key with
        | Some entry ->
            (match node_result (fun () -> Ok (refresh geometries !input_diagnostics entry)) with
            | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
            | Ok refreshed ->
            if refreshed != entry then
              (if volatile then store_volatile session node key refreshed else insert session key refreshed);
            session.hits <- session.hits + 1;
            if volatile then session.volatile_hits <- session.volatile_hits + 1;
            session.last_node <- Some (timing node ~seconds:0. ~cache_hit:true);
            Ok refreshed.output)
        | None ->
            session.misses <- session.misses + 1;
            if volatile then session.volatile_misses <- session.volatile_misses + 1;
            session.cooks <- session.cooks + 1;
            let started = Unix.gettimeofday () in
            let cooked =
              node_result (fun () ->
                match cook_node memo session context node geometries with
                | Error _ as error -> error
                | Ok cooked -> Ok (cooked, delta node geometries cooked))
            in
            let seconds = max 0. (Unix.gettimeofday () -. started) in
            session.last_node <- Some (timing node ~seconds ~cache_hit:false);
            record_time session (Node.id node) seconds;
            match cooked with
            | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
            | Ok _ when Context.cancelled context -> Error (cancellation_error node)
            | Ok (cooked, delta) ->
                let diagnostics =
                  List.concat (List.rev (cooked.diagnostics :: !input_diagnostics))
                in
                let output = { geometry = cooked.geometry; diagnostics;
                  instances = cooked.instances } in
                let entry = {output; components = []; local_diagnostics = cooked.diagnostics;
                  delta} in
                if volatile then store_volatile session node key entry
                else insert session key entry;
                Ok output

let deduplicate diagnostics =
  let seen = Hashtbl.create (List.length diagnostics) in
  List.filter (fun diagnostic ->
    let key = diagnostic.Diagnostic.severity, diagnostic.node.node_id,
      diagnostic.code, diagnostic.message in
    if Hashtbl.mem seen key then false
    else (Hashtbl.add seen key (); true)) diagnostics

let cook session ~context node =
  if session.closed then
    Error (Diagnostic.error ~code:"session_closed"
      "cannot cook with a closed procedural session"
      |> Diagnostic.prepend_trace (Node.trace node))
  else
    Rays_math.Parallel.run ~domains:(Context.domains context) (fun () ->
      match evaluate (Hashtbl.create 64) session context node with
      | Error _ as error -> error
      | Ok output -> Ok { output with diagnostics = deduplicate output.diagnostics })

let stats session = {
  cooks = session.cooks;
  hits = session.hits;
  misses = session.misses;
  evictions = session.evictions;
  volatile_hits = session.volatile_hits;
  volatile_misses = session.volatile_misses;
  retained_entries = Entry_cache.length session.cache;
  volatile_entries = Hashtbl.length session.slots;
  retained_payload_bytes = session.payload.bytes;
  last_node = session.last_node;
}

let clear session =
  Mutex.protect session.times_lock (fun () -> Hashtbl.reset session.times);
  session.inspection_cache <- [];
  Entry_cache.clear session.cache;
  Hashtbl.reset session.slots;
  Hashtbl.clear session.payload.refs;
  session.payload.bytes <- 0

let close session =
  if not session.closed then begin
    clear session;
    session.closed <- true
  end

let is_closed session = session.closed
