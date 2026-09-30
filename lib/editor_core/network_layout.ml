module Int_map = Map.Make (Int)
module String_map = Map.Make (String)
module String_set = Set.Make (String)
module Port = struct type t = int * string let compare = compare end
module Port_map = Map.Make (Port)
module Port_set = Set.Make (Port)

type level = Point | Chip | Card | Full
type t = {
  at : (float * float) Int_map.t;
  level : level Int_map.t;
  pinned : bool Int_map.t;
  rows : bool String_map.t Int_map.t;
  split : String_set.t Int_map.t;
  bends : (float * float) list Port_map.t;
  wireless : Port_set.t;
}
let empty = {
  at = Int_map.empty; level = Int_map.empty; pinned = Int_map.empty;
  rows = Int_map.empty; split = Int_map.empty; bends = Port_map.empty;
  wireless = Port_set.empty;
}
let snap x = Float.round (x /. 12.) *. 12.
let slot node index = node, "in" ^ string_of_int index

let remove_nodes ids t =
  let removed = Int_map.of_list (List.map (fun id -> id, ()) ids) in
  let keep id = not (Int_map.mem id removed) in
  { at = Int_map.filter (fun id _ -> keep id) t.at;
    level = Int_map.filter (fun id _ -> keep id) t.level;
    pinned = Int_map.filter (fun id _ -> keep id) t.pinned;
    rows = Int_map.filter (fun id _ -> keep id) t.rows;
    split = Int_map.filter (fun id _ -> keep id) t.split;
    bends = Port_map.filter (fun (id, _) _ -> keep id) t.bends;
    wireless = Port_set.filter (fun (id, _) -> keep id) t.wireless }

let edit ~nodes ~ports ~source t =
  let copy from into = List.fold_left (fun into id ->
    match Int_map.find_opt id from with
    | Some value when Int_map.find_opt id into = Some value -> into
    | Some value -> Int_map.add id value into
    | None -> Int_map.remove id into) into nodes in
  let next = { at = copy source.at t.at; level = copy source.level t.level;
    pinned = copy source.pinned t.pinned; rows = copy source.rows t.rows;
    split = copy source.split t.split;
    bends = List.fold_left (fun into port ->
      match Port_map.find_opt port source.bends with
      | Some points when Port_map.find_opt port into = Some points -> into
      | Some points -> Port_map.add port points into
      | None -> Port_map.remove port into) t.bends ports;
    wireless = List.fold_left (fun into port ->
      if Port_set.mem port source.wireless then Port_set.add port into
      else Port_set.remove port into) t.wireless ports } in
  if next.at == t.at && next.level == t.level && next.pinned == t.pinned
      && next.rows == t.rows && next.split == t.split && next.bends == t.bends
      && next.wireless == t.wireless then t else next
