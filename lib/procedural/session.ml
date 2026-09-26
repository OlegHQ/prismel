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
  retained_entries : int;
  retained_payload_bytes : int;
  last_node : node_timing option;
}

type output = {
  geometry : Pdk.Geometry.t;
  diagnostics : Diagnostic.t list;
}

type entry = {
  output : output;
  components : (int * int) list;
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
  mutable evictions : int;
  mutable last_node : node_timing option;
  mutable closed : bool;
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
    last_node = None; closed = false;
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

let insert session key output =
  let components = Pdk.Geometry.payload_components output.geometry in
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
    Entry_cache.add session.cache key { output; components };
    while payload.bytes > session.max_payload_bytes
          && Entry_cache.drop_oldest session.cache do () done;
    session.evictions <- session.evictions + before
      + (if replaced then 0 else 1) - Entry_cache.length session.cache
  end

(* An opaque, unambiguous cache identity: integers are fixed-width binary and
   every variable-length string is length-prefixed, so no field boundary can
   shift. It avoids [Printf] and [string_of_int] on this per-node, per-cook
   path. *)
let cache_key node context inputs =
  let parameters = Node.parameters node
  and parameter_key = Node.parameter_key node in
  let buffer = Buffer.create (64 + String.length parameters
      + String.length parameter_key + (8 * Array.length inputs)) in
  let add_int value = Buffer.add_int64_le buffer (Int64.of_int value) in
  let add_sized value =
    add_int (String.length value); Buffer.add_string buffer value in
  add_int (Node.id node);
  add_int (Node.version node);
  add_sized (Node.operation node);
  add_sized parameters;
  add_sized parameter_key;
  add_int (Array.length inputs);
  Array.iter (fun geometry -> add_int (Pdk.Geometry.data_id geometry)) inputs;
  Buffer.add_string buffer
    (Context.cache_projection (Node.dependencies node) context);
  Buffer.contents buffer

let timing node ~seconds ~cache_hit = {
  node_id = Node.id node;
  label = Node.label node;
  operation = Node.operation node;
  seconds;
  cache_hit;
}

let cancellation_error node =
  Diagnostic.error ~code:"cancelled" "procedural cook was cancelled"
  |> Diagnostic.prepend_trace (Node.trace node)

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
            geometries.(index) <- Some output.geometry;
            input_diagnostics := output.diagnostics :: !input_diagnostics;
            cook_inputs (index + 1)
    in
    match cook_inputs 0 with
    | Error _ as error -> error
    | Ok () ->
        let geometries = Array.map Option.get geometries in
        let key = cache_key node context geometries in
        match Entry_cache.find session.cache key with
        | entry ->
            session.hits <- session.hits + 1;
            session.last_node <- Some (timing node ~seconds:0. ~cache_hit:true);
            Ok entry.output
        | exception Not_found ->
            session.misses <- session.misses + 1;
            session.cooks <- session.cooks + 1;
            let started = Unix.gettimeofday () in
            let cooked =
              try Node.Private.cook node context geometries with exn ->
                Error (Diagnostic.error ~code:"uncaught_node_exception"
                  ~cause:(Printexc.to_string exn)
                  "a procedural node raised an exception while cooking")
            in
            let seconds = max 0. (Unix.gettimeofday () -. started) in
            session.last_node <- Some (timing node ~seconds ~cache_hit:false);
            match cooked with
            | Error error -> Error (Diagnostic.prepend_trace (Node.trace node) error)
            | Ok _ when Context.cancelled context -> Error (cancellation_error node)
            | Ok cooked ->
                let diagnostics =
                  List.concat (List.rev (cooked.diagnostics :: !input_diagnostics))
                in
                let output = { geometry = cooked.geometry; diagnostics } in
                insert session key output;
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
    Prismel_math.Parallel.run ~domains:(Context.domains context) (fun () ->
      match evaluate (Hashtbl.create 64) session context node with
      | Error _ as error -> error
      | Ok output -> Ok { output with diagnostics = deduplicate output.diagnostics })

let stats session = {
  cooks = session.cooks;
  hits = session.hits;
  misses = session.misses;
  evictions = session.evictions;
  retained_entries = Entry_cache.length session.cache;
  retained_payload_bytes = session.payload.bytes;
  last_node = session.last_node;
}

let clear session =
  session.inspection_cache <- [];
  Entry_cache.clear session.cache;
  Hashtbl.clear session.payload.refs;
  session.payload.bytes <- 0

let close session =
  if not session.closed then begin
    clear session;
    session.closed <- true
  end

let is_closed session = session.closed
