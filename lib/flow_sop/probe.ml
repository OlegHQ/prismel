module E = Flow.Eval
module P = Projection

type path = Flow.Workspace.path
type geometry = {
  points : int; prims : int; groups : string list; data_id : int;
  extent : (float * float * float) option;
  seconds : float option;
}
type summary = Value of E.value | Geometry of geometry

type footer = {
  value : string; spark : (float array * int) option; branch : string option;
  kept : string option; runs : int option; invariant : bool; live : bool;
}

type t = {
  time : float option;
  dynamic : path -> int option;
  element : path -> int -> (string * E.value) list option;
      (* the element [k] of the loop over geometry at this path, by its name *)
  geometry : int -> geometry option;
  raw : (path, (int list * E.value) list) Hashtbl.t;
  forced : (path, (int list * summary) array) Hashtbl.t;  (* memo: forcing is per lookup, not per frame *)
  across : (path * int list, summary array) Hashtbl.t;  (* memo of [series] *)
  feet : (path * int list, footer) Hashtbl.t;  (* memo of [footer]: the pane asks every frame *)
}

let make ?time ?(geometry = fun _ -> None) ?(dynamic = fun _ -> None)
    ?(element = fun _ _ -> None) (eval : E.t) =
  let raw = Hashtbl.create 64 in
  List.iter (fun (p, l) -> Hashtbl.replace raw p l) eval.records;
  { time; dynamic; element; geometry; raw; forced = Hashtbl.create 64; across = Hashtbl.create 64; feet = Hashtbl.create 64 }

let same_eval a b = a.raw == b.raw

let summarize t v =
  let v = match t.time with
    | Some time when E.is_live v -> (match E.force v ~live:{ E.t = time } with Ok v -> v | Error _ -> v)
    | _ -> v in
  match v with
  | E.Geo id -> (match t.geometry id with Some g -> Geometry g | None -> Value v)
  | v -> Value v

let plan_node t path ~probes =
  Option.bind (Hashtbl.find_opt t.raw path) (List.find_map (fun (it, v) ->
    match v with E.Geo id when it = probes -> Some id | _ -> None))

let records t path = match Hashtbl.find_opt t.forced path with
  | Some a -> a
  | None ->
      let a = match Hashtbl.find_opt t.raw path with
        | None -> [||]
        | Some l -> Array.of_list (List.map (fun (it, v) -> it, summarize t v) l) in
      Hashtbl.replace t.forced path a; a

(* ---- describe ---- *)

let num x =
  let s = Printf.sprintf "%.3f" x in
  let s = if String.contains s '.' then begin
    let n = ref (String.length s) in
    while s.[!n - 1] = '0' do decr n done;
    if s.[!n - 1] = '.' then decr n;
    String.sub s 0 !n end else s in
  if s = "-0" then "0" else s

let rec describe_value = function
  | E.Int i -> string_of_int i
  | Float f -> num f
  | Bool b -> string_of_bool b
  | Text s -> s
  | Vec3 (x, y, z) -> Printf.sprintf "[%s %s %s]" (num x) (num y) (num z)
  | List xs ->
      let n = Array.length xs in
      let numeric = function E.Int _ | Float _ -> true | _ -> false in
      let what =
        if n = 0 then "items"
        else if Array.for_all numeric xs then
          "[" ^ String.concat " " (List.init (min 4 n) (fun i -> describe_value xs.(i)))
          ^ (if n > 4 then " …]" else "]")
        else match xs.(0) with
          | Geo _ | No_geo -> "geometry" | Text _ -> "text" | Vec3 _ -> "vec3" | Bool _ -> "bool"
          | List _ -> "list" | Record _ -> "record" | Fn _ -> "function" | _ -> "value" in
      if n = 0 then "0 items" else Printf.sprintf "%d × %s" n what
  | Record fs -> "{" ^ String.concat " · " (List.map (fun (f, v) -> f ^ " " ^ describe_value v) fs) ^ "}"
  | Geo _ -> "geometry"
  | No_geo -> "nil"
  | Struct (op, _) -> op
  | Fn _ -> "function"
  | Residual _ -> "?"

let describe = function
  | Value v -> describe_value v
  | Geometry g ->
      Printf.sprintf "%d prim%s%s" g.prims (if g.prims = 1 then "" else "s")
        (if g.groups = [] then "" else " · groups " ^ String.concat ", " g.groups)

(* ---- chains, series ---- *)

let chains (s : P.scope) =
  let tbl = Hashtbl.create 64 in
  let rec go chain (s : P.scope) = List.iter (fun (n : P.node) ->
    Hashtbl.replace tbl n.path chain;
    match n.zone with
    | Some z -> go (if z.kind = P.Let then chain else chain @ [ n.path ]) z.scope
    | None -> ()) s.nodes in
  go [] s;
  tbl

let rec drop_last = function [] | [ _ ] -> [] | x :: r -> x :: drop_last r

(* the template record of [path] forced for element [k] of the loop over geometry at [zone] *)
let at_element t path zone k =
  let raw = List.find_map (fun (it, v) -> if List.for_all (( = ) 0) it then Some v else None)
      (Option.value ~default:[] (Hashtbl.find_opt t.raw path)) in
  match raw, t.element zone k with
  | Some raw, Some elems when E.is_live raw ->
      (match E.force ~elems raw ~live:{ E.t = Option.value ~default:0. t.time } with
       | Ok v -> Some (summarize t v) | Error _ -> None)
  | _ -> None

(* the record with exactly this tuple; inside a loop over geometry the body is one template
   record (its iteration is 0), which reads the element: with the element's position known (the
   zone cooked) the value is forced for it, else it reads [?] *)
let at t path ~probes =
  let rs = records t path in
  match Array.find_map (fun (it, s) -> if it = probes then Some s else None) rs with
  | Some _ as found -> found
  | None ->
      let zones = List.filter (fun i -> t.dynamic (List.filteri (fun j _ -> j < i) path) <> None)
        (List.init (max 0 (List.length path - 1)) succ) in
      if zones = [] then None
      else
        let template it = List.compare_lengths it probes = 0 && List.for_all2 (fun r p -> r = p || r = 0) it probes in
        let zone = List.filteri (fun j _ -> j < List.fold_left max 0 zones) path in
        let raw = List.find_map (fun (it, v) -> if template it then Some v else None)
            (Option.value ~default:[] (Hashtbl.find_opt t.raw path)) in
        let elems = if probes = [] then None else t.element zone (List.nth probes (List.length probes - 1)) in
        match raw, elems with
        | Some raw, Some elems when E.is_live raw ->
            (match E.force ~elems raw ~live:{ E.t = Option.value ~default:0. t.time } with
             | Ok v -> Some (summarize t v)
             | Error _ -> Array.find_map (fun (it, s) -> if template it then Some s else None) rs)
        | _ -> Array.find_map (fun (it, s) -> if template it then Some s else None) rs

(* the records whose tuple is [outer] followed by one more index, in order; in a loop over
   geometry the body has one template record, which is forced for each element once the zone
   cooked *)
let across t path ~outer =
  match Hashtbl.find_opt t.across (path, outer) with
  | Some a -> a
  | None ->
      let n = List.length outer in
      let matches it = List.compare_length_with it (n + 1) = 0
        && List.for_all2 ( = ) outer (List.filteri (fun i _ -> i < n) it) in
      let a = Array.of_seq (Seq.filter_map (fun (it, s) -> if matches it then Some s else None)
        (Array.to_seq (records t path))) in
      let a =
        if Array.length a > 1 || outer <> [] then a else
        let zones = List.filter (fun i -> t.dynamic (List.filteri (fun j _ -> j < i) path) <> None)
          (List.init (max 0 (List.length path - 1)) succ) in
        match zones with
        | [] -> a
        | _ ->
            let zone = List.filteri (fun j _ -> j < List.fold_left max 0 zones) path in
            (match t.dynamic zone with
             | Some count when count > 1 ->
                 let forced = Array.init count (fun k -> at_element t path zone k) in
                 if Array.for_all Option.is_some forced then Array.map Option.get forced else a
             | _ -> a) in
      Hashtbl.replace t.across (path, outer) a; a

let series t path ~probes = if probes = [] then [||] else across t path ~outer:(drop_last probes)

(* Where the probed iteration sits in [series]: the iterations a [:skip] left out have no record,
   so it is the number of recorded ones before it (the probe itself when none is missing). *)
let position t path ~probes ~len =
  let n = List.length probes - 1 in
  let outer = drop_last probes and p = List.nth probes n in
  let mine = List.filter (fun (it, _) ->
    List.compare_length_with it (n + 1) = 0 && List.filteri (fun i _ -> i < n) it = outer)
    (Array.to_list (records t path)) in
  (* a loop over geometry has one template record, forced for each element: no iteration is missing *)
  if List.length mine <> len then min p (len - 1)
  else min (List.length (List.filter (fun (it, _) -> List.nth it n < p) mine)) (len - 1)

let counts t (s : P.scope) ~probe =
  let chain = chains s in
  List.filter_map (fun (n : P.node) ->
    let z = Option.get n.zone in
    let outer = List.map probe (Option.value ~default:[] (Hashtbl.find_opt chain n.path)) in
    match t.dynamic n.path with Some count -> Some (n.path, count) | None ->
    List.find_map (fun (r : P.rail_row) ->
      if r.role = P.Capture then None
      else match across t (n.path @ [ ":" ^ List.hd r.names ]) ~outer with
        | a when Array.length a = 0 -> None
        | a -> Some (n.path, Array.length a)) z.rail) (P.zones s)

(* ---- footers ---- *)

let number = function
  | Value (E.Int i) -> Some (float i) | Value (Float f) -> Some f
  | Value (Bool b) -> Some (if b then 1. else 0.) | _ -> None

let arg (n : P.node) i = Option.bind (List.find_opt (fun (r : P.row) -> r.key = Flow_edit.Pos i) n.rows)
    (fun (r : P.row) -> match r.expr with Some { Flow.Syntax.node = Sym s; _ } -> Some s | _ -> None)

let compute_footer t (n : P.node) ~probes =
  let parent = drop_last n.path in
  let here = at t n.path ~probes in
  let value = match here with
    | Some s -> describe s
    | None -> if probes <> [] && Array.length (records t n.path) > 0 then "not run here" else Flow.Ty.to_string n.ty in
  let across_probes = series t in
  let spark =
    if probes = [] || n.invariant then None else
    let a = Array.map number (across_probes n.path ~probes) in
    if Array.length a < 2 || Array.exists Option.is_none a then None
    else Some (Array.map Option.get a, position t n.path ~probes ~len:(Array.length a)) in
  let branch =
    if probes = [] || n.head <> "if" then None else
    Option.bind (arg n 0) (fun c ->
      let cs = across_probes (parent @ [ c ]) ~probes in
      if Array.length cs = 0 then None else
      let yes = Array.fold_left (fun a s -> if s = Value (E.Bool true) then a + 1 else a) 0 cs in
      Some (Printf.sprintf "then %d · else %d" yes (Array.length cs - yes))) in
  let kept =
    if n.head <> "filter" then None else
    match here, Option.bind (arg n 1) (fun s -> at t (parent @ [ s ]) ~probes) with
    | Some (Value (E.List k)), Some (Value (E.List all)) ->
        Some (Printf.sprintf "kept %d of %d" (Array.length k) (Array.length all))
    | _ -> None in
  let invariant = probes <> [] && n.invariant in
  { value; spark; branch; kept; invariant; live = n.live;
    runs = if probes <> [] && not n.invariant then Some (Array.length (records t n.path)) else None }

let footer t (n : P.node) ~probes =
  match Hashtbl.find_opt t.feet (n.path, probes) with
  | Some f -> f
  | None -> let f = compute_footer t n ~probes in Hashtbl.replace t.feet (n.path, probes) f; f

let text f =
  String.concat " · " (List.filter_map Fun.id
    [ Some f.value; f.branch; f.kept; Option.map (Printf.sprintf "×%d") f.runs;
      (if f.invariant then Some "↑ same each time" else None); (if f.live then Some "t" else None) ])

let iterations t (n : P.node) ~probes = Array.map describe (series t n.path ~probes)

let geometry_targets t (s : P.scope) ~probe =
  let chain = chains s in
  let rec go (s : P.scope) = List.concat_map (fun (n : P.node) -> match n.zone with
    | Some z -> go z.scope
    | None when n.ty = Flow.Ty.Geometry ->
        Option.to_list (plan_node t n.path ~probes:(List.map probe (Hashtbl.find chain n.path)))
    | None -> []) s.nodes in
  go s

let readouts t (n : P.node) ~probes =
  [ (if probes = [] then "value" else "value at probe"), (footer t n ~probes).value;
    "cook", (if n.live then "live, recooks every frame" else "cached") ]
