module S = Flow.Syntax
module W = Flow.Workspace

type path = W.path
type arg_key = Whole | Pos of int | Kw of string | Field of string | Bv of int * int
type loop = For | Fold

type op =
  | Set_arg of { node : path; key : arg_key; sub : int list; value : S.t }
  | Connect of { node : path; key : arg_key; src : string; iter : bool }
  | Disconnect of { node : path; key : arg_key; fallback : S.t option }
  | Set_input_default of { form : string; input : string; value : S.t }
  | Unfold of { node : path; key : arg_key; sub : int list }
  | Fold_into of { node : path }
  | Wrap of { nodes : path list; loop : loop }
  | Hoist of { node : path }
  | Rename of { node : path; to_ : string }
  | Make_local_fn of { nodes : path list }
  | Make_macro of { nodes : path list; name : string; holes : (int list * string) list }
  | Inline_macro of { node : path }
  | Toggle_bypass of { node : path }
  | Set_note of { node : path; text : string }
  | Add_item of { node : path }
  | Move_item of { node : path; pos : int }
  | Add_field of { node : path; name : string; value : S.t }
  | Add_node of { scope : path; name : string; expr : S.t }
  | Delete_nodes of { nodes : path list }
  | Set_layout_ratio of { node : path; ratio : float }
  | Split_panel of { node : path; axis : [ `H | `V ] }
  | Close_panel of { node : path }
  | Set_panel_kind of { node : path; kind : string }
  | Set_graph of { name : string; form : S.t }
  | Duplicate of { nodes : path list }
  | Remove_graph of { name : string }

exception Fail of Flow.Diagnostic.t

let fail ?(code = "E_EDIT") fmt =
  Printf.ksprintf (fun message -> raise (Fail (Flow.Diagnostic.error ~code message))) fmt

(* ---- syntax helpers ---- *)

let mk ?notes ?meta node = S.make ?notes ?meta node
let sym s = mk (S.Sym s)
let kwf s = mk (S.Kw s)
let vec l = mk (S.Vec l)
let call head args = mk (S.List (sym head :: args))
let num n = mk (S.Num (string_of_int n))
let unquote x = mk (S.Quote (S.Unquote, x))

let rec pairs = function a :: b :: r -> (a, b) :: pairs r | _ -> []
let flat_pairs ps = List.concat_map (fun (a, b) -> [ a; b ]) ps

let head_sym (e : S.t) = match e.node with
  | S.List ({ S.node = S.Sym h; _ } :: _) -> Some h
  | _ -> None

let map_children f (e : S.t) : S.t =
  { e with node = (match e.node with
    | S.List l -> S.List (List.map f l)
    | S.Vec l -> S.Vec (List.map f l)
    | S.Map l -> S.Map (List.map f l)
    | S.Quote (k, x) -> S.Quote (k, f x)
    | n -> n) }

let root_of s = match String.index_opt s '.' with Some i -> String.sub s 0 i | None -> s
let rec syms (e : S.t) acc = match e.node with
  | S.Sym s -> root_of s :: acc
  | _ -> List.fold_left (fun a c -> syms c a) acc (S.children e)
let sym_list e = List.rev (syms e [])
let dedup l = List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [ x ]) [] l
let count_refs name e = List.length (List.filter (( = ) name) (sym_list e))

let rec replace_ref name (by : S.t) (e : S.t) : S.t = match e.node with
  | S.Sym s when s = name -> by
  | _ -> map_children (replace_ref name by) e

let rec rename_ref old nw (e : S.t) : S.t = match e.node with
  | S.Sym s when root_of s = old ->
      { e with node = S.Sym (nw ^ String.sub s (String.length old) (String.length s - String.length old)) }
  | _ -> map_children (rename_ref old nw) e

let rec pat_names (p : S.t) = match p.node with
  | S.Sym n -> [ n ]
  | S.Vec l -> List.concat_map pat_names l
  | S.Map l -> List.concat_map (fun (x : S.t) -> match x.node with
      | S.Vec v -> List.concat_map pat_names v | _ -> []) l
  | _ -> []

let pat_key = Flow.Lisp.flat

(* every name a form declares: let and zone bindings, fn parameters, typed inputs *)
let rec declared (e : S.t) acc =
  let bound (vec : S.t) acc = match vec.node with
    | S.Vec bs -> List.fold_left (fun a (p, _) -> pat_names p @ a) acc (pairs bs)
    | _ -> acc in
  let acc = match e.node with
    | S.List ({ S.node = S.Sym "let*"; _ } :: v :: _) -> bound v acc
    | S.List ({ S.node = S.Sym ("for" | "scan" | "sum"); _ } :: v :: _) -> bound v acc
    | S.List ({ S.node = S.Sym "fold"; _ } :: a :: b :: _) -> bound b (bound a acc)
    | S.List ({ S.node = S.Sym "fn"; _ } :: { S.node = S.Vec ps; _ } :: _) ->
        List.fold_left (fun a (p : S.t) -> match p.node with
          | S.List ({ S.node = S.Sym n; _ } :: _) -> n :: a
          | _ -> pat_names p @ a) acc ps
    | S.List ({ S.node = S.Sym n; _ } :: { S.node = S.Sym ":"; _ } :: _) -> n :: acc
    | _ -> acc in
  List.fold_left (fun a c -> declared c a) acc (S.children e)

(* names read by a form and not declared inside it *)
let free e =
  let inner = declared e [] in
  List.filter (fun x -> not (List.mem x inner)) (sym_list e)

let nth_child e i = List.nth_opt (S.children e) i
let set_child (e : S.t) i v : S.t =
  let f = List.mapi (fun j c -> if j = i then v else c) in
  { e with node = (match e.node with
    | S.List l when i < List.length l -> S.List (f l)
    | S.Vec l when i < List.length l -> S.Vec (f l)
    | S.Map l when i < List.length l -> S.Map (f l)
    | S.Quote (k, _) when i = 0 -> S.Quote (k, v)
    | _ -> fail "This form has no part %d." i) }
let rec get_sub e = function
  | [] -> Some e
  | i :: r -> Option.bind (nth_child e i) (fun c -> get_sub c r)
let rec set_sub e sub v = match sub with
  | [] -> v
  | i :: r -> (match nth_child e i with
      | Some c -> set_child e i (set_sub c r v)
      | None -> fail "This form has no part %d." i)

let keep_notes (old : S.t) (v : S.t) = if v.notes = [] then { v with notes = old.notes } else v

(* ---- call arguments: positional ones, then :keyword pairs ---- *)

let is_kw (x : S.t) = match x.node with S.Kw _ -> true | _ -> false
let kw_name (k : S.t) = match k.node with S.Kw s -> s | _ -> ""
(* a call's arguments are positional ones and [:keyword value] pairs, in any order *)
let positional args =
  let rec go = function k :: _ :: r when is_kw k -> go r | x :: r -> x :: go r | [] -> [] in
  go args
let kw_get args k =
  let rec go = function
    | a :: b :: r -> if is_kw a && kw_name a = k then Some b else go (if is_kw a then r else b :: r)
    | _ -> None in
  go args
let with_kw args k v =
  let rec go = function
    | a :: b :: r when is_kw a ->
        if kw_name a = k then (match v with Some v -> a :: keep_notes b v :: r | None -> r)
        else a :: b :: go r
    | x :: r -> x :: go r
    | [] -> (match v with Some v -> [ kwf k; v ] | None -> []) in
  go args
let with_pos args i v =
  let n = List.length (positional args) in
  if i >= n then
    (match v with
     | None -> args
     | Some v ->
         (* after the last positional argument, else first *)
         let rec go seen = function
           | a :: b :: r when is_kw a -> a :: b :: go seen r
           | x :: r -> if seen + 1 = n then x :: v :: r else x :: go (seen + 1) r
           | [] -> [] in
         if n = 0 then v :: args else go 0 args)
  else
    let rec go k = function
      | a :: b :: r when is_kw a -> a :: b :: go k r
      | x :: r -> if k = i then (match v with Some v -> keep_notes x v :: r | None -> r) else x :: go (k + 1) r
      | [] -> [] in
    go 0 args

let arg_get (e : S.t) key = match key, e.node with
  | Whole, _ -> Some e
  | Bv (i, j), _ -> Option.bind (nth_child e i) (fun c -> nth_child c j)
  | Field k, S.Map l -> List.find_map (fun (a, b) -> if kw_name a = k then Some b else None) (pairs l)
  | Pos i, S.List (_ :: args) -> List.nth_opt (positional args) i
  | Kw k, S.List (_ :: args) -> kw_get args k
  | _ -> None

let set_pair ps k v =
  if List.exists (fun (a, _) -> kw_name a = k) ps then
    (match v with
     | Some v -> List.map (fun (a, b) -> if kw_name a = k then a, keep_notes b v else a, b) ps
     | None -> List.filter (fun (a, _) -> kw_name a <> k) ps)
  else match v with Some v -> ps @ [ kwf k, v ] | None -> ps

let arg_set (e : S.t) key (v : S.t option) : S.t = match key, e.node, v with
  | Whole, _, Some v -> keep_notes e v
  | Whole, _, None -> fail "A whole binding cannot be removed."
  | Bv (i, j), _, Some v ->
      (match nth_child e i with Some c -> set_child e i (set_child c j v) | None -> fail "This form has no part %d." i)
  | Bv _, _, None -> fail "A loop clause cannot be removed."
  | Field k, S.Map l, _ -> { e with node = S.Map (flat_pairs (set_pair (pairs l) k v)) }
  | Pos i, S.List (h :: args), _ -> { e with node = S.List (h :: with_pos args i v) }
  | Kw k, S.List (h :: args), _ -> { e with node = S.List (h :: with_kw args k v) }
  | _ -> fail "This form has no such input."

(* ---- scopes: a let* (or a bare expression) whose bindings are the nodes ---- *)

type scope = { form : S.t; vec : S.t; ps : (S.t * S.t) list; res : S.t }

let scope_of (e : S.t) = match e.node, e.meta with
  | S.List [ { S.node = S.Sym "let*"; _ }; ({ S.node = S.Vec bs; _ } as vec); res ], []
    when List.length bs mod 2 = 0 -> Some { form = e; vec; ps = pairs bs; res }
  | _ -> None
let ensure (e : S.t) = match scope_of e with
  | Some s -> s
  | None -> let v = vec [] in { form = mk (S.List [ sym "let*"; v; e ]); vec = v; ps = []; res = e }
let rebuild s ps res : S.t = match s.form.node with
  | S.List [ h; _; _ ] -> { s.form with node = S.List [ h; { s.vec with node = S.Vec (flat_pairs ps) }; res ] }
  | _ -> s.form
let collapse s ps res = if ps = [] then res else rebuild s ps res  (* an empty let* is its result *)
let find_pair s leaf = List.find_index (fun (p, _) -> pat_key p = leaf) s.ps

let is_zone (e : S.t) = e.meta = [] && (match head_sym e with
  | Some ("for" | "fold" | "scan" | "sum") -> true | _ -> false)

let last_child (e : S.t) = match List.rev (S.children e) with c :: _ -> c | [] -> fail "Empty form."
let set_last (e : S.t) v : S.t =
  let l = S.children e in
  { e with node = S.List (List.mapi (fun i c -> if i = List.length l - 1 then v else c) l) }

(* the scope inside a binding value: a let* itself, or a zone's body *)
let enter (e : S.t) : S.t * (S.t -> S.t) =
  if scope_of e <> None then e, Fun.id
  else if is_zone e then last_child e, set_last e
  else fail "That node is not a scope."

let rec descend (cur : S.t) names (f : S.t -> S.t) : S.t = match names with
  | [] -> f cur
  | name :: rest ->
      let child, back = match scope_of cur with
        | Some s when name = "@result" -> s.res, (fun r -> rebuild s s.ps r)
        | Some s ->
            (match find_pair s name with
             | Some j ->
                 let p, v = List.nth s.ps j in
                 v, (fun v' -> rebuild s (List.mapi (fun k q -> if k = j then p, v' else q) s.ps) s.res)
             | None -> fail "Binding %s no longer exists." name)
        | None when name = "@result" -> cur, Fun.id
        | None -> fail "Scope no longer exists." in
      let entered, out = enter child in
      back (out (descend entered rest f))

let workspace_parts (src : S.t list) = match src with
  | ({ S.node = S.List ({ S.node = S.Sym "workspace"; _ } :: _ :: items); _ } as ws) :: _ -> ws, items
  | _ -> fail "The source is not a (workspace ...)."

let root_name (item : S.t) = match item.node with
  | S.List ({ S.node = S.Sym ("graph" | "defn" as h); _ } :: { S.node = S.Sym n; _ } :: _) ->
      Some (if h = "defn" then "def:" ^ n else n)
  | _ -> None

let map_items (src : S.t list) f : S.t list = match src with
  | ({ S.node = S.List (w :: name :: items); _ } as ws) :: rest ->
      { ws with node = S.List (w :: name :: f items) } :: rest
  | _ -> fail "The source is not a (workspace ...)."

let with_root src seg (f : S.t -> S.t) =
  let hit = ref false in
  let out = map_items src (List.map (fun item ->
    if root_name item = Some seg then (hit := true; f item) else item)) in
  if not !hit then fail "No graph or definition %s." seg;
  out

let root_form src seg =
  let _, items = workspace_parts src in
  match List.find_opt (fun i -> root_name i = Some seg) items with
  | Some r -> r
  | None -> fail "No graph or definition %s." seg

let edit_scope src scope_path (g : S.t -> S.t) = match scope_path with
  | [] -> fail "No scope."
  | seg :: names -> with_root src seg (fun r -> set_last r (descend (last_child r) names g))

let split_node = function
  | [] | [ _ ] -> fail "Not a node."
  | node -> let r = List.rev node in List.rev (List.tl r), List.hd r

let get_node s leaf = match scope_of s with
  | Some sc when leaf = "@result" -> sc.res
  | Some sc -> (match find_pair sc leaf with Some j -> snd (List.nth sc.ps j)
      | None -> fail "Binding %s no longer exists." leaf)
  | None when leaf = "@result" -> s
  | None -> fail "Binding %s no longer exists." leaf

let reorder (s : S.t) = match scope_of s with
  | None -> s
  | Some sc ->
      let names = List.concat_map (fun (p, _) -> pat_names p) sc.ps in
      let rec go seen left out = match left with
        | [] -> List.rev out
        | _ ->
            (match List.find_opt (fun (_, e) ->
                List.for_all (fun x -> not (List.mem x names) || List.mem x seen) (free e)) left with
             | None -> fail ~code:"E_GRAPH_CYCLE" "That connection would make a cycle through %s."
                 (String.concat ", " (List.map (fun (p, _) -> pat_key p) left))
             | Some q ->
                 go (pat_names (fst q) @ seen) (List.filter (fun x -> x != q) left) (q :: out)) in
      rebuild sc (go [] sc.ps []) sc.res

let set_node s leaf e = match scope_of s with
  | Some sc when leaf = "@result" -> rebuild sc sc.ps (keep_notes sc.res e)
  | Some sc ->
      (match find_pair sc leaf with
       | Some j -> rebuild sc (List.mapi (fun k (p, v) -> if k = j then p, keep_notes v e else p, v) sc.ps) sc.res
       | None -> fail "Binding %s no longer exists." leaf)
  | None when leaf = "@result" -> e
  | None -> fail "Binding %s no longer exists." leaf

(* ---- names ---- *)

let sanitize base =
  let base = match String.rindex_opt base '/' with
    | Some i -> String.sub base (i + 1) (String.length base - i - 1) | None -> base in
  let b = Buffer.create 16 in
  String.iter (fun c -> match Char.lowercase_ascii c with
    | ('a' .. 'z' | '0' .. '9' | '_') as c -> Buffer.add_char b c
    | _ -> Buffer.add_char b '_') base;
  let s = Buffer.contents b in
  let n = String.length s in
  let i = ref 0 and j = ref n in
  while !i < n && s.[!i] = '_' do incr i done;
  while !j > !i && s.[!j - 1] = '_' do decr j done;
  let s = String.sub s !i (!j - !i) in
  if s = "" then "node" else if s.[0] >= 'a' && s.[0] <= 'z' then s else "n" ^ s

let fresh used base =
  let base = sanitize base in
  let rec go n =
    let name = if n = 1 then base else base ^ "_" ^ string_of_int n in
    if List.mem name !used || W.name_taken name then go (n + 1) else name in
  let name = go 1 in
  used := name :: !used;
  name

let root_used src seg = ref (List.concat_map (fun (i : S.t) ->
  if root_name i = Some seg then sym_list i else []) (snd (workspace_parts src)))

let fresh_name src ~root base = fresh (root_used src root) base

let valid_name n = Flow.Symbol.valid_name n

let default_for (ty : Flow.Ty.t) label = match ty with
  | Flow.Ty.Float -> Some (mk (S.Num "0.5"))
  | Int -> Some (mk (S.Num "1"))
  | Bool -> Some (sym "false")
  | Vec3 -> Some (vec [ mk (S.Num "0"); mk (S.Num "0"); mk (S.Num "0") ])
  | Text | Color -> Some (mk (S.Str (if label = "color" then "#285f77" else "text")))
  | Geometry -> Some (sym "nil")
  | _ -> None

let rec literals ?(path = []) (e : S.t) = match e.node with
  | S.Num _ | S.Str _ -> [ List.rev path, e ]
  | S.List _ | S.Vec _ | S.Map _ ->
      List.concat (List.mapi (fun i (c : S.t) ->
        if (i = 0 && (match e.node with S.List _ -> true | _ -> false))
           || (match c.node with S.Kw _ -> true | _ -> false) then []
        else literals ~path:(i :: path) c) (S.children e))
  | _ -> []
let literals e = literals e

(* ---- selections ---- *)

type selection = { sc : scope; sel : (S.t * S.t) list; keep : (S.t * S.t) list;
  first : int; out : S.t * S.t; out_name : string }

let scope_path_of nodes =
  match nodes with
  | [] -> fail "Select the nodes first."
  | first :: rest ->
      let sp, _ = split_node first in
      List.iter (fun n -> if fst (split_node n) <> sp then fail "Select nodes from one scope.") rest;
      sp

(* the bindings of [nodes] in scope expression [s], the one leaving them *)
let select s nodes what =
  let leaves = List.map (fun n -> snd (split_node n)) nodes in
  if List.mem "@result" leaves then fail "A result cannot be part of %s." what;
  let sc = ensure s in
  let sel = List.filter (fun (p, _) -> List.mem (pat_key p) leaves) sc.ps in
  if List.length sel <> List.length (dedup leaves) then fail "A selected node no longer exists.";
  let keep = List.filter (fun (p, _) -> not (List.mem (pat_key p) leaves)) sc.ps in
  let first = Option.get (List.find_index (fun (p, _) -> List.mem (pat_key p) leaves) sc.ps) in
  let mentions n e = List.mem n (free e) in
  let mentioned n = List.exists (fun (_, e) -> mentions n e) keep || mentions n sc.res in
  let outs = List.filter (fun (p, _) -> List.exists mentioned (pat_names p)) sel in
  if List.length outs > 1 then
    fail "%s needs one result leaving the selection; %s are all used outside." what
      (String.concat " and " (List.map (fun (p, _) -> pat_key p) outs));
  let out = match outs with [ o ] -> o | _ -> List.nth sel (List.length sel - 1) in
  let out_name = match (fst out).node with S.Sym n -> n | _ -> fail "The result of %s must be a name." what in
  { sc; sel; keep; first; out; out_name }

let body_of x =
  match x.sel with
  | [ (_, e) ] -> e
  | sel ->
      let others = List.filter (fun q -> q != x.out) sel in
      call "let*" [ vec (flat_pairs (others @ [ x.out ])); sym x.out_name ]

let insert_at keep i extra = List.filteri (fun j _ -> j < i) keep @ extra @ List.filteri (fun j _ -> j >= i) keep

let sel_names x = List.concat_map (fun (p, _) -> pat_names p) x.sel
let sel_declared x = List.fold_left (fun a (_, e) -> declared e a) [] x.sel

(* names the selection reads from outside, in order of appearance *)
let outside_names ~root x =
  let visible = declared root [] in
  let inner = sel_declared x and own = sel_names x in
  dedup (List.concat_map (fun (_, e) -> sym_list e) x.sel)
  |> List.filter (fun n -> List.mem n visible && not (List.mem n inner) && not (List.mem n own))

let fn_names root =
  let rec go (e : S.t) acc =
    let acc = match e.node with
      | S.List ({ S.node = S.Sym "let*"; _ } :: { S.node = S.Vec bs; _ } :: _) ->
          List.fold_left (fun a ((p : S.t), (v : S.t)) ->
            if head_sym v = Some "fn" then pat_names p @ a else a) acc (pairs bs)
      | _ -> acc in
    List.fold_left (fun a c -> go c a) acc (S.children e) in
  go root []

(* ---- the rewrites; each returns candidate sources, tried in order ---- *)

let first_pair_index sc leaf = match find_pair sc leaf with
  | Some j -> j | None -> fail "Binding %s no longer exists." leaf

let note_lines text =
  let text = String.trim text in
  if text = "" then [] else List.map String.trim (String.split_on_char '\n' text)

(* ---- scene objects and World layers: they join and leave their graph's result ---- *)

let starts_with prefix (h : string option) = match h with
  | Some h -> String.starts_with ~prefix h | None -> false

(* where the result of a scope is written: a named binding, or the result itself *)
let result_target sc = match sc.res.node with
  | S.Sym r -> (match find_pair sc r with Some j -> `At j, snd (List.nth sc.ps j) | None -> `Result, sc.res)
  | _ -> `Result, sc.res
let put_target sc ps = function
  | `At j, e -> rebuild sc (List.mapi (fun k (p, v) -> if k = j then p, keep_notes v e else p, v) ps) sc.res
  | `Result, e -> rebuild sc ps (keep_notes sc.res e)

(* a new scene object is one more argument of the scene's [scene/merge] (made when the result
   is something else); a new World layer goes on top of the stack: the [world/world] call
   takes it and it takes the layer that was on top.  [ps] holds the new binding last. *)
let attach sc ps name (expr : S.t) =
  let head = head_sym expr in
  let target, e = result_target sc in
  if starts_with "scene/" head && head <> Some "scene/merge" then
    (match head_sym e with
     | Some "scene/merge" ->
         let n = List.length (positional (List.tl (S.children e))) in
         put_target sc ps (target, arg_set e (Pos n) (Some (sym name))), expr
     | _ -> rebuild sc ps (call "scene/merge" [ sc.res; sym name ]), expr)
  else if starts_with "world/" head && head <> Some "world/world" && head_sym e = Some "world/world" then
    let top = arg_get e (Pos 0) in
    let layer = arg_set expr (Pos 0) top in
    put_target sc ps (target, arg_set e (Pos 0) (Some (sym name))), layer
  else rebuild sc ps sc.res, expr

(* a deleted object leaves the merge that held it; a deleted layer leaves the stack, the layer
   above it taking the one below *)
let rec detach name below (e : S.t) : S.t =
  let e = map_children (detach name below) e in
  match head_sym e with
  | Some "scene/merge" ->
      { e with node = S.List (List.filter (fun (c : S.t) -> c.node <> S.Sym name) (S.children e)) }
  | Some h when String.starts_with ~prefix:"world/" h ->
      (match arg_get e (Pos 0) with
       | Some { S.node = S.Sym n; _ } when n = name -> arg_set e (Pos 0) below
       | _ -> e)
  | _ -> e

(* the copies a duplicate makes: each selected binding with a fresh name; the copies read each
   other where the originals did *)
let duplicate_plan src nodes =
  let sp = scope_path_of nodes in
  let used = root_used src (List.hd sp) in
  let leaves = dedup (List.map (fun n -> snd (split_node n)) nodes) in
  if List.mem "@result" leaves then fail "The result cannot be duplicated.";
  sp, List.map (fun leaf -> leaf, fresh used leaf) leaves

let rewrite src op : (unit -> S.t list) list =
  let one f = [ f ] in
  match op with
  | Set_arg { node; key; sub; value } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        let arg = if sub = [] then value else
          (match arg_get e key with
           | Some cur -> set_sub cur sub value
           | None -> fail "That input is not set.") in
        reorder (set_node s leaf (arg_set e key (Some arg)))))
  | Connect { node; key; src = name; iter } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        if leaf = "@result" && key = Whole then
          (let sc = ensure s in reorder (rebuild sc sc.ps (sym name)))
        else
          let e = get_node s leaf in
          let step = match iter, arg_get e key with
            | true, Some ({ S.node = S.Num n; _ } as cur) when n <> "0" && n <> "1" && float_of_string_opt n <> Some 0.
                && float_of_string_opt n <> Some 1. -> call "*" [ sym name; cur ]
            | _ -> sym name in
          reorder (set_node s leaf (arg_set e key (Some step)))))
  | Disconnect { node; key; fallback } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        let v = match key, fallback with
          | (Kw _ | Field _), _ -> None
          | _, Some d -> Some d
          | Pos _, None -> None
          | _, None -> fail "Nothing to fall back to. Drag another output onto it instead." in
        reorder (set_node s leaf (arg_set e key v))))
  | Set_input_default { form; input; value } -> one (fun () ->
      with_root src form (fun r ->
        let hit = ref false in
        let r = map_children (fun (c : S.t) -> match c.node with
          | S.Vec ds -> { c with node = S.Vec (List.map (fun (d : S.t) -> match d.node with
              | S.List (({ S.node = S.Sym n; _ } as name) :: colon :: ty :: _) when n = input ->
                  hit := true; { d with node = S.List [ name; colon; ty; value ] }
              | _ -> d) ds) }
          | _ -> c) r in
        if not !hit then fail "No input %s." input;
        r))
  | Unfold { node; key; sub } -> one (fun () ->
      let sp, leaf = split_node node in
      let used = root_used src (List.hd sp) in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        let whole = match arg_get e key with Some w -> w | None -> fail "That input is not set." in
        let inner = match get_sub whole sub with Some i -> i | None -> fail "That part does not exist." in
        let h = match head_sym inner with
          | Some h when h <> "ref" -> h
          | _ -> fail "Only a call, loop or scope can be unfolded." in
        let base =
          if is_zone inner then
            (if leaf = "@result" then "each" else leaf ^ "_" ^ (if h = "sum" then "total" else "each"))
          else if h = "let*" then "block" else h in
        let name = fresh used base in
        let e' = arg_set e key (Some (set_sub whole sub (sym name))) in
        let sc = ensure (set_node s leaf e') in
        let at = if leaf = "@result" then List.length sc.ps else first_pair_index sc leaf in
        reorder (rebuild sc (insert_at sc.ps at [ sym name, inner ]) sc.res)))
  | Fold_into { node } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let sc = match scope_of s with Some sc -> sc | None -> fail "Fold needs a named node." in
        if leaf = "@result" then fail "A result cannot be folded.";
        let j = first_pair_index sc leaf in
        let p, e = List.nth sc.ps j in
        let name = match p.node with S.Sym n -> n | _ -> fail "Only a plain name can be folded." in
        let others = List.filteri (fun k _ -> k <> j) sc.ps in
        let uses = List.fold_left (fun n (_, x) -> n + count_refs name x) (count_refs name sc.res) others in
        if uses <> 1 then fail "Fold needs exactly one use of %s inside its scope." name;
        let rep = replace_ref name e in
        let ps = List.map (fun (q, x) -> q, rep x) others and res = rep sc.res in
        if List.exists (fun (_, x) -> count_refs name x > 0) ps || count_refs name res > 0 then
          fail "%s is read by field; it cannot be folded." name;
        collapse sc ps res))
  | Delete_nodes { nodes } -> one (fun () ->
      let by_depth = List.sort (fun a b -> compare (List.length b) (List.length a)) nodes in
      let out = List.fold_left (fun src node ->
        let sp, leaf = split_node node in
        let gone = ref None in
        let src = edit_scope src sp (fun s ->
          match scope_of s with
          | Some sc when leaf <> "@result" ->
              let j = first_pair_index sc leaf in
              gone := Some (snd (List.nth sc.ps j));
              collapse sc (List.filteri (fun k _ -> k <> j) sc.ps) sc.res
          | _ -> fail "Only a named node can be deleted.") in
        (* a scene object, World layer or loop of scene objects also leaves the result that held it *)
        match !gone with
        | Some e when starts_with "scene/" (head_sym e) || starts_with "world/" (head_sym e) || is_zone e ->
            with_root src (List.hd sp) (detach leaf (if is_zone e then None else arg_get e (Pos 0)))
        | _ -> src) src by_depth in
      List.iter (fun node ->
        let name = snd (split_node node) in
        if List.mem name (sym_list (root_form out (List.hd node))) then
          fail "%s still feeds another node. Disconnect it first." name) nodes;
      out)
  | Rename { node; to_ } -> one (fun () ->
      let sp, leaf = split_node node in
      let used = sym_list (root_form src (List.hd sp)) in
      if not (valid_name to_) || List.mem to_ used || W.name_taken to_ then
        fail "Pick a new lowercase name that is not used anywhere in this graph.";
      edit_scope src sp (fun s ->
        let sc = match scope_of s with Some sc -> sc | None -> fail "Rename needs a named node." in
        let j = first_pair_index sc leaf in
        let old = match (fst (List.nth sc.ps j)).node with S.Sym n -> n | _ -> fail "Only a plain name can be renamed." in
        let ps = List.mapi (fun k (p, v) ->
          if k = j then { p with S.node = S.Sym to_ }, v
          else if k > j then p, rename_ref old to_ v else p, v) sc.ps in
        rebuild sc ps (rename_ref old to_ sc.res)))
  | Hoist { node } -> one (fun () ->
      let sp, leaf = split_node node in
      let pp, owner = match sp with
        | [ _ ] | [] -> fail "Only a node inside a loop or scope can move out."
        | _ -> split_node sp in
      edit_scope src pp (fun ps_expr ->
        let out_scope = ensure ps_expr in
        let hoisted = ref None in
        let inner_edit (v : S.t) =
          let entered, back = enter v in
          let sc = match scope_of entered with Some sc -> sc | None -> fail "Nothing to move." in
          let j = first_pair_index sc leaf in
          let p, e = List.nth sc.ps j in
          let local = List.filter (fun x -> List.exists (fun (q, _) -> List.mem x (pat_names q)) sc.ps)
              (dedup (sym_list e)) in
          if local <> [] then
            fail "%s uses %s from inside this scope. Move that out first." leaf (String.concat ", " local);
          hoisted := Some (p, e);
          back (collapse sc (List.filteri (fun k _ -> k <> j) sc.ps) sc.res) in
        let ps, res, at =
          if owner = "@result" then out_scope.ps, inner_edit out_scope.res, List.length out_scope.ps
          else
            let k = first_pair_index out_scope owner in
            List.mapi (fun i (p, v) -> if i = k then p, inner_edit v else p, v) out_scope.ps, out_scope.res, k in
        let p, e = Option.get !hoisted in
        reorder (rebuild out_scope (insert_at ps at [ p, e ]) res)))
  | Wrap { nodes; loop } ->
      let sp = scope_path_of nodes in
      let root = List.hd sp in
      let rootf = root_form src root in
      let attempt build = fun () ->
        let used = root_used src root in
        edit_scope src sp (fun s ->
          let x = select s nodes "Repeat" in
          let iv = match List.find_opt (fun c -> not (List.mem c !used)
              && not (List.mem c (sel_declared x))) [ "i"; "j"; "k"; "n"; "idx" ] with
            | Some c -> used := c :: !used; c
            | None -> fresh used "i" in
          let added = build x iv used in
          reorder (rebuild x.sc (insert_at x.keep (min x.first (List.length x.keep)) added) x.sc.res)) in
      let zone_clause iv n = vec [ sym iv; call "range" [ num n ] ] in
      let zone h iv n body = call h [ zone_clause iv n; body ] in
      (match loop with
       | For ->
           (* ponytail: the checker is the type oracle, so try the geometry
              shape (collect and merge) and then the number shape (sum) *)
           [ attempt (fun x iv used ->
               let each = fresh used (x.out_name ^ "_each") in
               [ sym each, zone "for" iv 6 (body_of x); fst x.out, call "sop/merge" [ sym each ] ]);
             attempt (fun x iv _ -> [ fst x.out, zone "sum" iv 6 (body_of x) ]) ]
       | Fold ->
           (* every outside name the selection reads is a candidate to feed back *)
           let free = ref [] in
           ignore (edit_scope src sp (fun s ->
             free := outside_names ~root:rootf (select s nodes "Iterate"); s));
           if !free = [] then
             [ fun () -> fail "Iterate feeds the result back into an input of the same type; none of the selected nodes reads one from outside." ]
           else List.map (fun f -> attempt (fun x iv used ->
             let prev = fresh used "prev" in
             [ fst x.out, call "fold" [ vec [ sym prev; sym f ]; zone_clause iv 4;
                                        replace_ref f (sym prev) (body_of x) ] ])) !free)
  | Make_local_fn { nodes } -> one (fun () ->
      let sp = scope_path_of nodes in
      let root = List.hd sp in
      let rootf = root_form src root in
      let used = root_used src root in
      edit_scope src sp (fun s ->
        let x = select s nodes "A function" in
        let fns = fn_names rootf in
        let outer = outside_names ~root:rootf x |> List.filter (fun n -> not (List.mem n fns)) in
        let fname = fresh used (x.out_name ^ "_fn") in
        let params = List.map (fun n -> fresh used ("in_" ^ n)) outer in
        let body = List.fold_left2 (fun b n p -> replace_ref n (sym p) b) (body_of x) outer params in
        let added = [ sym fname, call "fn" [ vec (List.map sym params); body ];
                      fst x.out, call fname (List.map sym outer) ] in
        reorder (rebuild x.sc (insert_at x.keep (min x.first (List.length x.keep)) added) x.sc.res)))
  | Make_macro { nodes; name; holes } -> one (fun () ->
      let sp = scope_path_of nodes in
      let root = List.hd sp in
      let rootf = root_form src root in
      let _, items = workspace_parts src in
      let taken = List.filter_map (fun (i : S.t) -> match i.node with
        | S.List ({ S.node = S.Sym ("graph" | "defn" | "defmacro"); _ } :: { S.node = S.Sym n; _ } :: _) -> Some n
        | _ -> None) items in
      if not (Flow.Macro.valid_name name) || List.mem name taken || W.name_taken name then
        fail "Pick a new lowercase macro name.";
      let names = List.map snd holes in
      if List.exists (fun n -> not (valid_name n)) names || List.length (dedup names) <> List.length names then
        fail "Hole names must be distinct lowercase names.";
      let defn = ref None in
      let out = edit_scope src sp (fun s ->
        let x = select s nodes "A macro" in
        let tmpl = body_of x in
        let free = outside_names ~root:rootf x in
        let hole_vals = List.map (fun (path, _) -> match get_sub tmpl path with
          | Some v -> v | None -> fail "A hole is not in the template.") holes in
        let body = List.fold_left (fun b (path, n) -> set_sub b path (unquote (sym n))) tmpl holes in
        let body = List.fold_left (fun b f -> replace_ref f (unquote (sym f)) b) body free in
        let body = if List.length x.sel > 1
          then List.fold_left (fun b n -> replace_ref n (sym (n ^ "#")) b) body (sel_names x) else body in
        let params = names @ free in
        defn := Some (call "defmacro" [ sym name; vec (List.map sym params); mk (S.Quote (S.Quasi, body)) ]);
        let added = [ fst x.out, call name (hole_vals @ List.map sym free) ] in
        reorder (rebuild x.sc (insert_at x.keep (min x.first (List.length x.keep)) added) x.sc.res)) in
      map_items out (fun items -> Option.get !defn :: items))
  | Inline_macro { node } -> one (fun () ->
      let sp, leaf = split_node node in
      let _, items = workspace_parts src in
      let macros = List.filter (fun i -> head_sym i = Some "defmacro") items in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        match Flow.Macro.expand macros e with
        | Ok x -> reorder (set_node s leaf x)
        | Error d -> raise (Fail d)))
  | Toggle_bypass { node } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        (match e.node, head_sym e with
         | S.List _, Some h when not (is_zone e) && h <> "let*" && h <> "fn" -> ()
         | _ -> fail "Only an operator or function call can be bypassed.");
        let meta = if List.mem "bypass" e.meta then List.filter (( <> ) "bypass") e.meta else e.meta @ [ "bypass" ] in
        set_node s leaf { e with S.meta = meta }))
  | Set_note { node; text } -> one (fun () ->
      let notes = note_lines text in
      match node with
      | [ root ] -> with_root src root (fun r -> { r with S.notes = notes })
      | _ ->
          let sp, leaf = split_node node in
          edit_scope src sp (fun s ->
            match scope_of s with
            | Some sc when leaf = "@result" -> rebuild sc sc.ps { sc.res with S.notes = notes }
            | Some sc ->
                let j = first_pair_index sc leaf in
                rebuild sc (List.mapi (fun k (p, v) -> if k = j then { p with S.notes = notes }, v else p, v) sc.ps) sc.res
            | None when leaf = "@result" -> { s with S.notes = notes }
            | None -> fail "Notes attach to named bindings."))
  | Add_item { node } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        match e.node with
        | S.List (({ S.node = S.Sym ("list" | "str" as h); _ } as hd) :: args) ->
            let v = if h = "str" then mk (S.Str " ") else
              match List.rev args with
              | ({ S.node = S.Num a; _ } as last) :: { S.node = S.Num b; _ } :: _ ->
                  (match float_of_string_opt a, float_of_string_opt b with
                   | Some fa, Some fb ->
                       let x = Float.round ((2. *. fa -. fb) *. 1000.) /. 1000. in
                       if Float.is_integer fa then mk (S.Num (string_of_int (int_of_float x)))
                       else
                         let t = Printf.sprintf "%.12g" x in
                         mk (S.Num (if String.contains t '.' || String.contains t 'e' then t else t ^ ".0"))
                   | _ -> { last with notes = [] })
              | last :: _ -> { last with notes = [] }
              | [] -> mk (S.Num "0") in
            set_node s leaf { e with node = S.List (hd :: args @ [ v ]) }
        | _ -> fail "Only a list or str can take another item."))
  | Move_item { node; pos } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        match e.node with
        | S.List (h :: args) when pos >= 1 && pos < List.length args ->
            let args = List.mapi (fun i c ->
              if i = pos then List.nth args (pos - 1) else if i = pos - 1 then List.nth args pos else c) args in
            set_node s leaf { e with node = S.List (h :: args) }
        | _ -> fail "There is no item %d to move up." pos))
  | Add_field { node; name; value } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        let key = match e.node with S.Map _ -> Field name | _ -> Kw name in
        reorder (set_node s leaf (arg_set e key (Some value)))))
  | Add_node { scope; name; expr } -> one (fun () ->
      if not (valid_name name) || List.mem name (sym_list (root_form src (List.hd scope)))
         || W.name_taken name then fail "Pick a new lowercase name that is not used in this graph.";
      edit_scope src scope (fun s ->
        let sc = ensure s in
        let ps = sc.ps @ [ sym name, expr ] in
        let body, expr = if List.length scope = 1 then attach sc ps name expr else rebuild sc ps sc.res, expr in
        let body = match scope_of body with
          | Some b -> rebuild b (List.map (fun (p, v) -> if p.S.node = S.Sym name then p, expr else p, v) b.ps) b.res
          | None -> body in
        reorder body))

  | Set_layout_ratio { node; ratio } -> one (fun () ->
      let sp, leaf = split_node node in
      let ratio = Float.round (Float.max 0.1 (Float.min 0.9 ratio) *. 100.) /. 100. in
      let text = mk (S.Num (Printf.sprintf "%.2f" ratio |> fun t ->
        if String.ends_with ~suffix:"0" t then String.sub t 0 (String.length t - 1) else t)) in
      edit_scope src sp (fun s ->
        let e = get_node s leaf in
        set_node s leaf (match e.node with
          | S.List (({ S.node = S.Sym "ui/split-at"; _ } as h) :: axis :: _ :: rest) ->
              { e with node = S.List (h :: axis :: text :: rest) }
          | S.List ({ S.node = S.Sym "ui/split"; _ } :: axis :: rest) ->
              { e with node = S.List (sym "ui/split-at" :: axis :: text :: rest) }
          | _ -> fail "That panel is not a split.")))
  | Split_panel { node; axis } -> one (fun () ->
      let sp, leaf = split_node node in
      let used = root_used src (List.hd sp) in
      edit_scope src sp (fun s ->
        let sc = match scope_of s with
          | Some sc -> sc
          | None -> fail "This editor graph is a single expression. Edit it in Lisp." in
        let j = first_pair_index sc leaf in
        let a = fresh used (leaf ^ "_a") in
        let b = fresh used (leaf ^ "_b") in
        let p, orig = List.nth sc.ps j in
        let other = if head_sym orig = Some "ui/lisp" then "ui/graph" else "ui/lisp" in
        let split = call "ui/split-at"
          [ mk (S.Str (if axis = `H then "horizontal" else "vertical")); mk (S.Num "0.5");
            sym a; sym b ] in
        let before = List.filteri (fun k _ -> k < j) sc.ps
        and after = List.filteri (fun k _ -> k > j) sc.ps in
        reorder (rebuild sc (before @ [ sym a, orig; sym b, call other []; p, split ] @ after) sc.res)))
  | Close_panel { node } -> one (fun () ->
      let sp, leaf = split_node node in
      edit_scope src sp (fun s ->
        let sc = match scope_of s with
          | Some sc -> sc
          | None -> fail "This editor graph is a single expression. Edit it in Lisp." in
        let is_leaf (x : S.t) = x.node = S.Sym leaf in
        let sibling (e : S.t) = match e.node with
          | S.List ({ S.node = S.Sym ("ui/split" | "ui/split-at"); _ } :: args) ->
              (match List.rev args with
               | y :: x :: _ when is_leaf x -> Some y
               | y :: x :: _ when is_leaf y -> Some x
               | _ -> None)
          | _ -> None in
        match List.find_opt (fun (_, e) -> sibling e <> None) sc.ps with
        | None -> fail "Only a panel inside a split can close. Restore layout brings the shell back."
        | Some (pp, pe) ->
            let ps = List.filter_map (fun (p, e) ->
              if p == pp then Some (p, Option.get (sibling pe))
              else if pat_key p = leaf then None else Some (p, e)) sc.ps in
            reorder (rebuild sc ps sc.res)))
  | Duplicate { nodes } -> one (fun () ->
      let sp, names = duplicate_plan src nodes in
      edit_scope src sp (fun s ->
        let sc = ensure s in
        let selected = List.filter (fun (p, _) -> List.mem_assoc (pat_key p) names) sc.ps in
        if List.length selected <> List.length names then fail "A selected node no longer exists.";
        let rename e = List.fold_left (fun e (old, fresh) -> rename_ref old fresh e) e names in
        let copies = List.map (fun (p, e) -> match p.S.node with
          | S.Sym n -> { p with S.node = S.Sym (List.assoc n names); notes = [] }, rename e
          | _ -> fail "Only a named node can be duplicated.") selected in
        let last = List.fold_left max 0 (List.filter_map (fun (p, _) -> find_pair sc (pat_key p)) selected) in
        reorder (rebuild sc (insert_at sc.ps (last + 1) copies) sc.res)))
  | Remove_graph { name } -> one (fun () ->
      if not (List.exists (fun i -> root_name i = Some name) (snd (workspace_parts src))) then
        fail "No graph or definition %s." name;
      map_items src (List.filter (fun i -> root_name i <> Some name)))
  | Set_graph { name; form } -> one (fun () ->
      (* the whole [(graph name ...)] form: replaced, or appended when the workspace has none *)
      if root_name form <> Some name then fail "That form is not the graph %s." name;
      let exists = List.exists (fun i -> root_name i = Some name) (snd (workspace_parts src)) in
      map_items src (fun items ->
        if exists then List.map (fun i -> if root_name i = Some name then form else i) items
        else items @ [ form ]))
  | Set_panel_kind { node; kind } -> one (fun () ->
      let sp, leaf = split_node node in
      let rec context = function
        | { S.node = S.Kw "context"; _ } :: { S.node = S.Sym c; _ } :: _ -> Some c
        | _ :: rest -> context rest
        | [] -> None in
      let scene = List.find_map (fun (item : S.t) -> match item.node with
        | S.List ({ S.node = S.Sym "graph"; _ } :: { S.node = S.Sym n; _ } :: rest)
          when context rest = Some "scene" -> Some n
        | _ -> None) (snd (workspace_parts src)) in
      let expr = match kind with
        | "outline" | "graph" | "list" | "lisp" | "inspector" | "timeline" -> call ("ui/" ^ kind) []
        | "viewport" ->
            (match scene with
             | Some n -> call "ui/viewport" [ call "ref" [ sym n ] ]
             | None -> fail "A viewport needs a scene graph.")
        | _ -> fail "Unknown panel type %s." kind in
      edit_scope src sp (fun s -> set_node s leaf expr))

(* ---- the public functions ---- *)

let label = function
  | Set_arg _ -> "Edit value" | Connect _ -> "Connect" | Disconnect _ -> "Disconnect"
  | Set_input_default _ -> "Input default" | Unfold _ -> "Unfold" | Fold_into _ -> "Fold"
  | Wrap { loop = For; _ } -> "Repeat" | Wrap { loop = Fold; _ } -> "Iterate"
  | Hoist _ -> "Move out" | Rename _ -> "Rename" | Make_local_fn _ -> "Make function"
  | Make_macro _ -> "Make macro" | Inline_macro _ -> "Inline macro"
  | Toggle_bypass _ -> "Bypass" | Set_note _ -> "Note" | Add_item _ -> "Add item"
  | Move_item _ -> "Move item" | Add_field _ -> "Add field" | Add_node _ -> "Add node"
  | Delete_nodes _ -> "Delete"
  | Set_layout_ratio _ -> "Resize panel" | Split_panel _ -> "Split panel"
  | Close_panel _ -> "Close panel" | Set_panel_kind _ -> "Retype panel"
  | Set_graph _ -> "Edit graph"
  | Duplicate _ -> "Duplicate"
  | Remove_graph _ -> "Remove graph"

let key_text = function
  | Whole -> "" | Pos i -> string_of_int i | Kw k | Field k -> k | Bv (i, j) -> Printf.sprintf "%d.%d" i j

let gesture = function
  | Set_arg { node; key; sub; _ } ->
      Some (Printf.sprintf "scrub:%s:%s:%s" (String.concat "/" node) (key_text key)
        (String.concat "." (List.map string_of_int sub)))
  | Set_note { node; _ } -> Some ("note:" ^ String.concat "/" node)
  | _ -> None

type macro_draft = { literals : (int list * S.t) list; free : string list; name : string }

let macro_draft src nodes =
  try
    let sp = scope_path_of nodes in
    let root = List.hd sp in
    let rootf = root_form src root in
    let draft = ref None in
    ignore (edit_scope src sp (fun s ->
      let x = select s nodes "A macro" in
      draft := Some { literals = literals (body_of x); free = outside_names ~root:rootf x;
                      name = fresh_name src ~root (x.out_name ^ "_tpl") };
      s));
    Ok (Option.get !draft)
  with Fail d -> Error d

let macro_op draft ~nodes ~name choices =
  Make_macro { nodes; name; holes = List.filteri (fun i _ -> i < Array.length choices) draft.literals
    |> List.mapi (fun i (path, _) -> path, choices.(i))
    |> List.filter_map (fun (path, (on, hole)) -> if on then Some (path, hole) else None) }

let check catalog forms =
  let text, _ = Flow.Lisp.print forms in
  match S.parse text with
  | Error d -> Error d
  | Ok forms ->
      (match W.check catalog forms with
       | Some ws, _ -> Ok (forms, ws)
       | None, ds ->
           Error (match List.find_opt (fun (d : Flow.Diagnostic.t) -> d.severity = Flow.Diagnostic.Error) ds with
             | Some d -> d
             | None -> Flow.Diagnostic.error ~code:"E_EDIT" "The edit does not check."))

let apply_checked catalog src op =
  match rewrite src op with
  | exception Fail d -> Error d
  | candidates ->
      let rec first err = function
        | [] -> Error (Option.get err)
        | attempt :: rest ->
            (match attempt () with
             | exception Fail d -> first (if err = None then Some d else err) rest
             | forms -> (match check catalog forms with
                 | Ok _ as ok -> ok
                 | Error d -> first (if err = None then Some d else err) rest)) in
      first None candidates

let apply catalog src op = Result.map fst (apply_checked catalog src op)

let has_prefix ~prefix p =
  let n = List.length prefix in
  List.length p >= n && List.filteri (fun i _ -> i < n) p = prefix

let remap op p = match op with
  | Rename { node; to_ } when has_prefix ~prefix:node p ->
      let k = List.length node - 1 in
      Some (List.mapi (fun i s -> if i = k then to_ else s) p)
  | Hoist { node } when has_prefix ~prefix:node p && List.length node >= 3 ->
      let k = List.length node - 2 in
      Some (List.filteri (fun i _ -> i <> k) p)
  | Delete_nodes { nodes } when List.exists (fun n -> has_prefix ~prefix:n p) nodes -> None
  | Close_panel { node } when has_prefix ~prefix:node p -> None
  | _ -> Some p

let arg_text src node key =
  let sp, leaf = split_node node in
  let found = ref None in
  (try ignore (edit_scope src sp (fun s -> found := arg_get (get_node s leaf) key; s)) with Fail _ -> ());
  !found

let duplicated src nodes =
  match duplicate_plan src nodes with
  | exception Fail _ -> []
  | sp, names -> List.map (fun (_, fresh) -> sp @ [ fresh ]) names

let free_names e = dedup (free e)
let pat_names = pat_names
let pat_key = pat_key
