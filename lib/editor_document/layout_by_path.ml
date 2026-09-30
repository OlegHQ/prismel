module S = Flow.Syntax

type path = Flow.Workspace.path
module Path_map = Map.Make (struct type t = path let compare = compare end)
module String_map = Map.Make (String)
module Port = struct type t = path * string let compare = compare end
module Port_map = Map.Make (Port)
module Port_set = Set.Make (Port)

type frame = { title : string; at : float * float; size : float * float }
type t = {
  at : (float * float) Path_map.t;
  pinned : bool Path_map.t;
  rows : bool String_map.t Path_map.t;
  bends : (float * float) list Port_map.t;
  wireless : Port_set.t;
  collapsed : bool Path_map.t;
  frames : frame list Path_map.t;
}

let empty = { at = Path_map.empty; pinned = Path_map.empty; rows = Path_map.empty;
  bends = Port_map.empty; wireless = Port_set.empty; collapsed = Path_map.empty;
  frames = Path_map.empty }

let is_empty t = t = empty

let remap f t =
  let keys m = Path_map.fold (fun k v acc -> match f k with Some k -> Path_map.add k v acc | None -> acc) m Path_map.empty in
  let port_keys m = Port_map.fold (fun (k, p) v acc -> match f k with
    | Some k -> Port_map.add (k, p) v acc | None -> acc) m Port_map.empty in
  { at = keys t.at; pinned = keys t.pinned; rows = keys t.rows; bends = port_keys t.bends;
    wireless = Port_set.filter_map (fun (k, p) -> Option.map (fun k -> k, p) (f k)) t.wireless;
    collapsed = keys t.collapsed; frames = keys t.frames }

(* ---- s-expression ---- *)

let mk node = S.make node
let str s = mk (S.Str s)
let kw s = mk (S.Kw s)
let sym s = mk (S.Sym s)
let vec l = mk (S.Vec l)
let bool b = sym (if b then "true" else "false")
let number x =
  let shortest = List.find_map (fun p ->
    let s = Printf.sprintf "%.*g" p x in if float_of_string s = x then Some s else None) [ 15; 16; 17 ] in
  mk (S.Num (Option.get shortest))
let pair (x, y) = vec [ number x; number y ]
let path_form p = vec (List.map str p)

let to_syntax t =
  let nodes = Path_map.empty
    |> Path_map.fold (fun p v -> Path_map.add p [ kw "at", pair v ]) t.at
    |> fun m -> Path_map.fold (fun p v m -> Path_map.add p (Option.value ~default:[] (Path_map.find_opt p m) @ [ kw "pinned", bool v ]) m) t.pinned m
    |> fun m -> Path_map.fold (fun p v m -> Path_map.add p (Option.value ~default:[] (Path_map.find_opt p m) @ [ kw "collapsed", bool v ]) m) t.collapsed m
    |> fun m -> Path_map.fold (fun p rows m ->
      Path_map.add p (Option.value ~default:[] (Path_map.find_opt p m)
        @ [ kw "rows", mk (S.Map (List.concat_map (fun (k, v) -> [ kw k; bool v ]) (String_map.bindings rows))) ]) m) t.rows m in
  let node_forms = List.map (fun (p, fields) ->
    mk (S.List (sym "node" :: path_form p :: List.concat_map (fun (k, v) -> [ k; v ]) fields)))
    (Path_map.bindings nodes) in
  let bends = List.map (fun ((p, port), pts) ->
    mk (S.List (sym "bend" :: path_form p :: str port :: List.map pair pts))) (Port_map.bindings t.bends) in
  let wireless = List.map (fun (p, port) -> mk (S.List [ sym "wireless"; path_form p; str port ]))
    (Port_set.elements t.wireless) in
  let frames = List.concat_map (fun (p, fs) -> List.map (fun f ->
    mk (S.List [ sym "frame"; path_form p; str f.title; kw "at"; pair f.at; kw "size"; pair f.size ])) fs)
    (Path_map.bindings t.frames) in
  mk (S.List (sym "layout" :: node_forms @ bends @ wireless @ frames))

let ( let* ) = Result.bind
let fail fmt = Printf.ksprintf (fun m -> Error ("layout: " ^ m)) fmt

let read_number (f : S.t) = match f.node with
  | S.Num s -> (match float_of_string_opt s with Some x when Float.is_finite x -> Ok x | _ -> fail "bad number %s" s)
  | _ -> fail "expected a number"
let read_pair (f : S.t) = match f.node with
  | S.Vec [ x; y ] -> let* x = read_number x in let* y = read_number y in Ok (x, y)
  | _ -> fail "expected [x y]"
let read_bool (f : S.t) = match f.node with
  | S.Sym "true" -> Ok true | S.Sym "false" -> Ok false | _ -> fail "expected true or false"
let read_str (f : S.t) = match f.node with S.Str s -> Ok s | _ -> fail "expected text"
let read_path (f : S.t) = match f.node with
  | S.Vec l -> List.fold_right (fun x acc -> let* acc = acc in let* s = read_str x in Ok (s :: acc)) l (Ok [])
  | _ -> fail "expected a path vector"
let rec all f = function [] -> Ok [] | x :: r -> let* y = f x in let* r = all f r in Ok (y :: r)

let of_syntax (form : S.t) = match form.node with
  | S.List ({ S.node = S.Sym "layout"; _ } :: items) ->
      List.fold_left (fun acc (item : S.t) ->
        let* t = acc in
        match item.node with
        | S.List ({ S.node = S.Sym "node"; _ } :: p :: fields) ->
            let* p = read_path p in
            let rec go t = function
              | [] -> Ok t
              | { S.node = S.Kw "at"; _ } :: v :: r -> let* v = read_pair v in go { t with at = Path_map.add p v t.at } r
              | { S.node = S.Kw "pinned"; _ } :: v :: r -> let* v = read_bool v in go { t with pinned = Path_map.add p v t.pinned } r
              | { S.node = S.Kw "collapsed"; _ } :: v :: r -> let* v = read_bool v in go { t with collapsed = Path_map.add p v t.collapsed } r
              | { S.node = S.Kw "rows"; _ } :: { S.node = S.Map kvs; _ } :: r ->
                  let rec rows m = function
                    | { S.node = S.Kw k; _ } :: v :: r -> let* v = read_bool v in rows (String_map.add k v m) r
                    | [] -> Ok m
                    | _ -> fail "bad rows" in
                  let* m = rows String_map.empty kvs in
                  go { t with rows = Path_map.add p m t.rows } r
              | _ -> fail "bad node entry" in
            go t fields
        | S.List ({ S.node = S.Sym "bend"; _ } :: p :: port :: pts) ->
            let* p = read_path p in let* port = read_str port in let* pts = all read_pair pts in
            Ok { t with bends = Port_map.add (p, port) pts t.bends }
        | S.List [ { S.node = S.Sym "wireless"; _ }; p; port ] ->
            let* p = read_path p in let* port = read_str port in
            Ok { t with wireless = Port_set.add (p, port) t.wireless }
        | S.List [ { S.node = S.Sym "frame"; _ }; p; title; { S.node = S.Kw "at"; _ }; at;
                   { S.node = S.Kw "size"; _ }; size ] ->
            let* p = read_path p in let* title = read_str title in
            let* at = read_pair at in let* size = read_pair size in
            let existing = Option.value ~default:[] (Path_map.find_opt p t.frames) in
            Ok { t with frames = Path_map.add p (existing @ [ { title; at; size } ]) t.frames }
        | _ -> fail "unknown entry %s" (Flow.Lisp.flat item)) (Ok empty) items
  | _ -> fail "expected (layout ...)"
