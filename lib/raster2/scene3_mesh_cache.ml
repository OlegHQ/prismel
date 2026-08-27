type key = { id : int64; version : int64; layout : int64 }
type counters = { preparation_bytes : int64; upload_intent_bytes : int64; replacements : int64; evictions : int64 }
type prepared_mesh = { topology : Scene3.topology; vertices : Scene3.vertex array; indices : int array }
type entry = { key : key; mesh : prepared_mesh }
type t = { capacity : int; mutable entries : entry list; mutable preparation_bytes : int64;
  mutable upload_intent_bytes : int64; mutable replacements : int64; mutable evictions : int64 }
type error = Invalid_capacity | Invalid_key | Invalid_mesh | Geometry_error of Scene3.error

let create ~capacity = if capacity <= 0 then Error Invalid_capacity else Ok { capacity; entries=[];
  preparation_bytes=0L; upload_intent_bytes=0L; replacements=0L; evictions=0L }
let valid_key key = key.id >= 0L && key.version >= 0L && key.layout >= 0L
let finite x = Float.is_finite x
let vertex_bytes = 48L
let mesh_bytes vertices indices = Int64.add (Int64.mul (Int64.of_int (Array.length vertices)) vertex_bytes)
  (Int64.mul (Int64.of_int (Array.length indices)) 4L)
let remove key entries = List.filter (fun entry -> entry.key <> key) entries
let find t key =
  match List.find_opt (fun entry -> entry.key = key) t.entries with
  | None -> None
  | Some entry -> t.entries <- remove key t.entries @ [entry]; Some entry.mesh
let prepare t ~key ~topology ~vertices ~indices =
  if not (valid_key key) then Error Invalid_key else match find t key with Some mesh -> Ok mesh | None ->
  if not (Array.for_all (fun (v:Scene3.vertex) -> finite v.x && finite v.y && finite v.z && finite v.u && finite v.v) vertices)
  || Array.exists (fun index -> index < 0 || index >= Array.length vertices) indices then Error Invalid_mesh else
  let cardinality_ok = match topology with Scene3.Triangle_list -> Array.length indices mod 3 = 0
    | Triangle_strip | Triangle_fan -> Array.length indices = 0 || Array.length indices >= 3 in
  if not cardinality_ok then Error Invalid_mesh else
  let bytes = mesh_bytes vertices indices in
  let mesh = { topology; vertices=Array.copy vertices; indices=Array.copy indices } in
  let replaced = List.exists (fun entry -> entry.key.id = key.id && entry.key.layout = key.layout) t.entries in
  if replaced then begin t.entries <- List.filter (fun entry -> entry.key.id <> key.id || entry.key.layout <> key.layout) t.entries;
    t.replacements <- Int64.succ t.replacements end;
  if List.length t.entries >= t.capacity then begin t.entries <- List.tl t.entries; t.evictions <- Int64.succ t.evictions end;
  t.entries <- t.entries @ [{key;mesh}];
  t.preparation_bytes <- Int64.add t.preparation_bytes bytes;
  t.upload_intent_bytes <- Int64.add t.upload_intent_bytes bytes;
  Ok mesh
let prepare_view mesh ~matrix ~viewport ~scissor =
  match Scene3.prepare ~matrix ~viewport ~scissor ~topology:mesh.topology ~vertices:mesh.vertices ~indices:mesh.indices with
  | Ok value -> Ok value | Error error -> Error (Geometry_error error)
let invalidate t key = t.entries <- remove key t.entries
let invalidate_mesh t ~id = t.entries <- List.filter (fun entry -> entry.key.id <> id) t.entries
let clear t = t.entries <- []
let length t = List.length t.entries
let keys_lru t = List.map (fun entry -> entry.key) t.entries
let counters t = { preparation_bytes=t.preparation_bytes;upload_intent_bytes=t.upload_intent_bytes;
  replacements=t.replacements;evictions=t.evictions }
