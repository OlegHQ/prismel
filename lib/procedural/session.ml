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
  mesh_hits : int;
  mesh_misses : int;
  retained_meshes : int;
  last_node : node_timing option;
}

type output = {
  geometry : Pdk.Geometry.t;
  diagnostics : Diagnostic.t list;
}

type entry = {
  key : string;
  output : output;
  components : (int * int) list;
  mutable newer : entry option;
  mutable older : entry option;
}

type mesh_entry = {
  mesh : Prismel.Mesh.t;
  bytes : int;
  mutable stamp : int;
}

type t = {
  max_entries : int;
  max_payload_bytes : int;
  cache : (string, entry) Hashtbl.t;
  payload_refs : (int, int * int) Hashtbl.t;
  mesh_cache : (int, mesh_entry) Hashtbl.t;
  mutable newest : entry option;
  mutable oldest : entry option;
  mutable retained_payload_bytes : int;
  mutable retained_mesh_bytes : int;
  mutable mesh_clock : int;
  mutable mesh_hits : int;
  mutable mesh_misses : int;
  mutable cooks : int;
  mutable hits : int;
  mutable misses : int;
  mutable evictions : int;
  mutable last_node : node_timing option;
  mutable closed : bool;
}

let create ~max_entries ~max_payload_bytes =
  if max_entries < 0 then Error "Session.create: max_entries must be non-negative"
  else if max_payload_bytes < 0 then
    Error "Session.create: max_payload_bytes must be non-negative"
  else Ok {
    max_entries; max_payload_bytes;
    cache = Hashtbl.create (min max_entries 1024);
    payload_refs = Hashtbl.create (min (max_entries * 4) 4096);
    mesh_cache = Hashtbl.create (min max_entries 256);
    newest = None; oldest = None; retained_payload_bytes = 0;
    retained_mesh_bytes = 0; mesh_clock = 0; mesh_hits = 0; mesh_misses = 0;
    cooks = 0; hits = 0; misses = 0; evictions = 0;
    last_node = None; closed = false;
  }

let detach session entry =
  (match entry.newer with
   | None -> session.newest <- entry.older
   | Some newer -> newer.older <- entry.older);
  (match entry.older with
   | None -> session.oldest <- entry.newer
   | Some older -> older.newer <- entry.newer);
  entry.newer <- None;
  entry.older <- None

let attach_newest session entry =
  entry.newer <- None;
  entry.older <- session.newest;
  (match session.newest with None -> () | Some old -> old.newer <- Some entry);
  session.newest <- Some entry;
  if session.oldest = None then session.oldest <- Some entry

let touch session entry =
  let already_newest = match session.newest with
    | Some newest -> newest == entry
    | None -> false
  in
  if not already_newest then begin
    detach session entry;
    attach_newest session entry
  end

let remove session entry =
  detach session entry;
  Hashtbl.remove session.cache entry.key;
  List.iter (fun (id, bytes) ->
    match Hashtbl.find_opt session.payload_refs id with
    | None -> ()
    | Some (_, 1) ->
        Hashtbl.remove session.payload_refs id;
        session.retained_payload_bytes <- session.retained_payload_bytes - bytes
    | Some (_, references) ->
        Hashtbl.replace session.payload_refs id (bytes, references - 1))
    entry.components

let rec evict_to_limits session =
  if Hashtbl.length session.cache > session.max_entries
     || session.retained_payload_bytes > session.max_payload_bytes
  then match session.oldest with
    | None -> ()
    | Some entry ->
        remove session entry;
        session.evictions <- session.evictions + 1;
        evict_to_limits session

let insert session key output =
  let components = Pdk.Geometry.payload_components output.geometry in
  if session.max_entries > 0 then begin
    (match Hashtbl.find_opt session.cache key with
     | None -> ()
     | Some old -> remove session old);
    let entry = { key; output; components; newer = None; older = None } in
    Hashtbl.add session.cache key entry;
    attach_newest session entry;
    List.iter (fun (id, bytes) ->
      match Hashtbl.find_opt session.payload_refs id with
      | None ->
          Hashtbl.add session.payload_refs id (bytes, 1);
          session.retained_payload_bytes <- session.retained_payload_bytes + bytes
      | Some (known_bytes, references) ->
          Hashtbl.replace session.payload_refs id (known_bytes, references + 1))
      components;
    evict_to_limits session
  end

let cache_key node context inputs =
  let buffer = Buffer.create 128 in
  Printf.bprintf buffer "%d|%s|%d|%s|" (Node.id node) (Node.operation node)
    (Node.version node) (Node.parameters node);
  Array.iter (fun geometry ->
    Printf.bprintf buffer "%d," (Pdk.Geometry.data_id geometry)) inputs;
  Buffer.add_char buffer '|';
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

let rec evaluate session context node =
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
      else match evaluate session context selected.(index) with
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
        match Hashtbl.find_opt session.cache key with
        | Some entry ->
            touch session entry;
            session.hits <- session.hits + 1;
            session.last_node <- Some (timing node ~seconds:0. ~cache_hit:true);
            Ok entry.output
        | None ->
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
    Prismel.Parallel.run ~domains:(Context.domains context) (fun () ->
      match evaluate session context node with
      | Error _ as error -> error
      | Ok output -> Ok { output with diagnostics = deduplicate output.diagnostics })

let evict_oldest_mesh session =
  let oldest = Hashtbl.fold (fun id entry current ->
    match current with
    | None -> Some (id, entry)
    | Some (_, old) when entry.stamp < old.stamp -> Some (id, entry)
    | Some _ -> current) session.mesh_cache None in
  match oldest with
  | None -> ()
  | Some (id, entry) ->
      Hashtbl.remove session.mesh_cache id;
      session.retained_mesh_bytes <- session.retained_mesh_bytes - entry.bytes

let rec evict_meshes session =
  if Hashtbl.length session.mesh_cache > session.max_entries
     || session.retained_mesh_bytes > session.max_payload_bytes
  then begin evict_oldest_mesh session; evict_meshes session end

let mesh ?cancel session geometry =
  if session.closed then Error (Pdk.Error.make ~operation:"session_mesh"
      ~code:"session_closed" "Session.mesh: session is closed")
  else
    let id = Pdk.Geometry.data_id geometry in
    session.mesh_clock <- session.mesh_clock + 1;
    match Hashtbl.find_opt session.mesh_cache id with
    | Some entry ->
        entry.stamp <- session.mesh_clock;
        session.mesh_hits <- session.mesh_hits + 1;
        Ok entry.mesh
    | None ->
        session.mesh_misses <- session.mesh_misses + 1;
        Result.bind (Pdk.Prismel_mesh.to_mesh ?cancel geometry) (fun mesh ->
          match cancel with
          | Some token when Pdk.Cancel.is_cancelled token ->
              Error (Pdk.Error.make ~operation:"session_mesh" ~code:"cancelled"
                "mesh conversion was cancelled")
          | _ ->
          let bytes = Pdk.Geometry.payload_bytes geometry in
          if session.max_entries > 0 && bytes <= session.max_payload_bytes then begin
            Hashtbl.replace session.mesh_cache id
              { mesh; bytes; stamp = session.mesh_clock };
            session.retained_mesh_bytes <- session.retained_mesh_bytes + bytes;
            evict_meshes session
          end;
          Ok mesh)

let stats session = {
  cooks = session.cooks;
  hits = session.hits;
  misses = session.misses;
  evictions = session.evictions;
  retained_entries = Hashtbl.length session.cache;
  retained_payload_bytes = session.retained_payload_bytes;
  mesh_hits = session.mesh_hits;
  mesh_misses = session.mesh_misses;
  retained_meshes = Hashtbl.length session.mesh_cache;
  last_node = session.last_node;
}

let clear session =
  Hashtbl.clear session.cache;
  Hashtbl.clear session.payload_refs;
  session.newest <- None;
  session.oldest <- None;
  session.retained_payload_bytes <- 0;
  Hashtbl.clear session.mesh_cache;
  session.retained_mesh_bytes <- 0

let close session =
  if not session.closed then begin
    clear session;
    session.closed <- true
  end

let is_closed session = session.closed
