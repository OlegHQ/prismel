module S = Flow.Syntax
module W = Flow.Workspace
module Ty = Flow.Ty
module E = Flow_edit

type path = W.path
type chip = No_value | Const | Name of string | Inline of { glyph : string; text : string }
type row_kind = Arg | Rest | Add | Hole | Binder | Group_reader | Group_writer

type row = {
  label : string; key : E.arg_key; ty : Ty.t option; expr : S.t option; chip : chip;
  default : string option; socket : bool; kind : row_kind;
}

type zone_kind = For | Fold | Scan | Sum | Let | Fn
type role = Var | Acc | Param | Capture

type rail_row = {
  name : string; names : string list; role : role; ty : Ty.t option;
  expr : S.t option; key : E.arg_key option;
}

type input = { path : path; name : string; ty : Ty.t; default : S.t option }

type lens = { steps : string array; error : string option; template : string }

type node = {
  path : path; name : string; binds : string list; head : string; rows : row list;
  outputs : (string * Ty.t) list; ty : Ty.t; note : string option; bypass : bool;
  macro : string option; lens : lens option; live : bool; invariant : bool; synthetic : bool;
  zone : zone option;
}
and zone = { kind : zone_kind; rail : rail_row list; scope : scope; yield_label : string;
             order : string option }
and scope = { path : path; inputs : input list; nodes : node list; result : result }
and result = Link of string | Node of path | Literal of S.t

(* the call, then each [expand_once] of it (at most 12 steps, like the study's lens) *)
let head_sym_of (e : S.t) = match e.node with
  | S.List ({ S.node = S.Sym h; _ } :: _) -> Some h | _ -> None

let macro_lens (w : W.t) (call : S.t) =
  let state = Flow.Macro.state () in
  let text f = let t = fst (Flow.Lisp.print [ f ]) in
    if String.ends_with ~suffix:"\n" t then String.sub t 0 (String.length t - 1) else t in
  let rec go cur acc n =
    if n = 12 then acc, None else
    match Flow.Macro.expand_once ~state w.macros cur with
    | Error (d : Flow.Diagnostic.t) -> acc, Some d.message
    | Ok next -> if next == cur then acc, None else go next (text next :: acc) (n + 1) in
  let steps, error = go call [ text call ] 0 in
  let template = match head_sym_of call with
    | Some name -> (match List.find_opt (fun (m : S.t) -> match S.children m with
        | _ :: { S.node = S.Sym n; _ } :: _ -> n = name | _ -> false) w.macros with
        | Some m -> text m | None -> "")
    | None -> "" in
  { steps = Array.of_list (List.rev steps); error; template }

(* ---- what the projection reads ---- *)

type cx = {
  w : W.t;
  catalog : Flow.Check.catalog;
  ctx : W.context;
  macros : (string * S.t) list;
  terms : (path, W.term) Hashtbl.t;  (* every bound term of the graph, by path *)
}

let rec pairs = function a :: b :: r -> (a, b) :: pairs r | _ -> []
let head_sym (e : S.t) = match e.node with
  | S.List ({ S.node = S.Sym h; _ } :: _) -> Some h | _ -> None
let last (e : S.t) = List.nth (S.children e) (List.length (S.children e) - 1)
let root_of s = match String.index_opt s '.' with Some i -> String.sub s 0 i | None -> s
let is_zone_head = function "for" | "fold" | "scan" | "sum" -> true | _ -> false

(* positional arguments, then :keyword pairs *)
let split_args l =
  let rec go acc = function
    | ({ S.node = S.Kw _; _ } :: _) as rest -> List.rev acc, rest
    | x :: r -> go (x :: acc) r
    | [] -> List.rev acc, [] in
  let pos, rest = go [] l in
  pos, List.filter_map (fun ((k : S.t), v) -> match k.node with S.Kw k -> Some (k, v) | _ -> None) (pairs rest)

let subterms (t : W.term) = match t.node with
  | Lit _ | Text _ | Nil | Time | Ref_binding _ | Fn_ref _ -> []
  | Vec l | List_lit l | Str l | List_op (_, l) | Hof (_, l) -> l
  | Call { args; _ } | Op { args; _ } -> List.map snd args
  | Call_fn { args; _ } -> args
  | Graph_ref { inputs; _ } -> List.map snd inputs
  | Let (bs, r) -> List.map snd bs @ [ r ]
  | Loop { accs; clauses; body; _ } -> List.map snd accs @ List.map snd clauses @ [ body ]
  | If (a, b, c) -> [ a; b; c ]
  | Cond (arms, d) -> List.concat_map (fun (a, b) -> [ a; b ]) arms @ [ d ]
  | Case (s, arms, d) -> (s :: List.map snd arms) @ [ d ]
  | Fn { body; _ } -> [ body ]
  | Record fs -> List.map snd fs
  | Get (t, _) -> [ t ]
  | Assoc (t, fs) -> t :: List.map snd fs
  | Bypass t -> [ t ]
  | Expanded { body; _ } -> [ body ]

let rec collect tbl (t : W.term) =
  Option.iter (fun p -> Hashtbl.replace tbl p t) t.path;
  List.iter (collect tbl) (subterms t)

(* ---- chips and rows ---- *)

let chip c (e : S.t option) = match e with
  | None -> No_value
  | Some e ->
      let inline glyph = Inline { glyph; text = Flow.Lisp.flat e } in
      (match e.node with
       | S.Sym ("t" | "pi" | "true" | "false" | "nil") -> Const
       | S.Sym s -> Name s
       | S.Num _ | S.Str _ | S.Vec _ | S.Kw _ | S.Quote _ -> Const
       | S.Map _ -> inline "{}"
       | S.List _ ->
           (match head_sym e with
            | Some ("for") -> inline "for"
            | Some "sum" -> inline "Σ"
            | Some ("fold" | "scan") -> inline "⟲"
            | Some "fn" -> inline "λ"
            | Some h when List.mem_assoc h c.macros -> inline "◆"
            | _ -> inline "ƒ"))

let row c ?ty ?default ?(socket = true) ?(kind = Arg) label key expr =
  { label; key; ty; expr; chip = chip c expr; default; socket; kind }

let add c label key ?(socket = true) ty =
  row c ?ty ~socket ~kind:Add label key None

let ty_of_port = function
  | Flow.Port_type.Geometry -> Ty.Geometry | Float -> Ty.Float | Int -> Ty.Int
  | Bool -> Ty.Bool | Vec3 -> Ty.Vec3

let show_value = function
  | Param.Bool_value b -> string_of_bool b
  | Int_value i -> string_of_int i
  | Float_value f -> Printf.sprintf "%g" f
  | Text_value s | Choice_value s -> s

let default_text (p : Flow.Check.parameter) = match p.fields with
  | [ (_, _, v) ] -> Some (show_value v)
  | [ _; _; _ ] as fs -> Some ("[" ^ String.concat " " (List.map (fun (_, _, v) -> show_value v) fs) ^ "]")
  | _ -> None

(* a macro parameter the template uses as a loop or scope name *)
let rec binder p (e : S.t) =
  let unquoted (x : S.t) = match x.node with
    | S.Quote (S.Unquote, { S.node = S.Sym n; _ }) -> n = p | _ -> false in
  (match e.node with
   | S.List ({ S.node = S.Sym h; _ } :: vs) when is_zone_head h || h = "let*" ->
       List.exists (fun (v : S.t) -> match v.node with
         | S.Vec l -> List.exists (fun (b, _) -> unquoted b) (pairs l) | _ -> false) vs
   | _ -> false)
  || List.exists (binder p) (S.children e)

let macro_rows c (m : S.t) pos =
  let npos = List.length pos in
  match Flow.Macro.params m with
  | Error _ -> []
  | Ok (req, rest) ->
      let template = last m in
      let req_rows = List.mapi (fun i p ->
        row c ~kind:(if binder p template then Binder else Hole) p (E.Pos i) (List.nth_opt pos i)) req in
      let rest_rows = match rest with
        | None -> []
        | Some r ->
            let n = List.length req in
            List.filteri (fun i _ -> i >= n) pos |> List.mapi (fun j a ->
              row c ~kind:Rest (if j = 0 then r else Printf.sprintf "%s %d" r (j + 1)) (E.Pos (n + j)) (Some a))
            |> fun rows -> rows @ [ add c ("+ " ^ r) (E.Pos npos) None ] in
      req_rows @ rest_rows

let catalog_context : W.context -> Flow.Context.t = function
  | Sop -> Sop | Scene -> Scene | World -> World | Settings -> Settings | Value | Editor -> Value

let kind_rows c (k : Flow.Check.kind) pos kws =
  let npos = List.length pos in
  let slot_ty = if k.context = Flow.Context.World then Ty.World else Ty.Geometry in
  let slot_rows = List.concat (List.mapi (fun i (s : Flow.Check.slot) ->
    if s.rest then
      List.filteri (fun j _ -> j >= i) pos |> List.mapi (fun j a ->
        row c ~ty:slot_ty ~kind:Rest (if j = 0 then s.name else Printf.sprintf "%s %d" s.name (j + 1))
          (E.Pos (i + j)) (Some a))
      |> fun rows -> rows @ [ add c ("+ " ^ s.name) (E.Pos (max npos i)) (Some slot_ty) ]
    else match List.nth_opt pos i, List.assoc_opt s.name kws with
      | Some a, _ -> [ row c ~ty:slot_ty s.name (E.Pos i) (Some a) ]
      | None, Some a -> [ row c ~ty:slot_ty s.name (E.Kw s.name) (Some a) ]
      | None, None ->
          [ row c ~ty:slot_ty s.name (if s.required && i = npos then E.Pos i else E.Kw s.name) None ])
    k.slots) in
  let param_rows = List.map (fun (p : Flow.Check.parameter) ->
    let kind = if W.group_reader p then Group_reader else if W.group_writer k p then Group_writer else Arg in
    row c ~ty:(match p.ty with Some t -> ty_of_port t | None -> Ty.Text) ?default:(default_text p)
      ~socket:(p.ty <> None) ~kind p.name (E.Kw p.name) (List.assoc_opt p.name kws)) k.parameters in
  slot_rows @ param_rows

let input_rows c (inputs : (string * Ty.t * W.term option) list) pos kws =
  List.mapi (fun i (n, ty, d) ->
    let default = Option.map (fun (t : W.term) -> Flow.Lisp.flat t.form) d in
    match List.nth_opt pos i with
    | Some a -> row c ~ty n (E.Pos i) (Some a)
    | None -> row c ~ty ?default n (E.Kw n) (List.assoc_opt n kws)) inputs

let call_rows c (e : S.t) h args =
  let pos, kws = split_args args in
  let npos = List.length pos in
  let at i = List.nth_opt pos i in
  let posrow ?ty ?socket label i = row c ?ty ?socket label (E.Pos i) (at i) in
  let kwrow ?ty label = row c ?ty label (E.Kw label) (List.assoc_opt label kws) in
  let items label prefix ty =
    List.mapi (fun i a -> row c ?ty ~kind:Rest (label i) (E.Pos i) (Some a)) pos
    @ [ add c prefix (E.Pos npos) ty ] in
  let list_ty = Some (Ty.List Ty.Any) in
  match h with
  | "if" -> [ posrow ~ty:Ty.Bool "if" 0; posrow "then" 1; posrow "else" 2 ]
  | "list" -> items string_of_int "+ item" None
  | "str" -> items (fun _ -> "part") "+ part" None
  | "concat" -> items (fun i -> Printf.sprintf "list %d" (i + 1)) "+ list" list_ty
  | "cond" ->
      List.concat_map (fun i -> [ posrow ~ty:Ty.Bool "when" i; posrow "then" (i + 1) ])
        (List.filter (fun i -> i mod 2 = 0) (List.init npos Fun.id))
      @ [ kwrow "else" ]
  | "case" ->
      posrow "of" 0
      :: List.concat_map (fun i -> [ posrow "is" i; posrow "then" (i + 1) ])
           (List.filter (fun i -> i mod 2 = 1) (List.init npos Fun.id))
      @ [ kwrow "else" ]
  | "map" | "filter" | "reduce" | "sort-by" ->
      let labels = match h with
        | "map" -> [ "f"; "list"; "list 2"; "list 3" ] | "filter" -> [ "keep if"; "list" ]
        | "reduce" -> [ "f"; "start"; "list" ] | _ -> [ "key"; "list" ] in
      List.concat (List.mapi (fun i l ->
        if i < 2 || at i <> None || h = "reduce" then
          [ posrow ?ty:(if i = 0 then Some Ty.Fn else if String.starts_with ~prefix:"list" l then list_ty else None) l i ]
        else []) labels)
      @ (if h = "map" && npos < 4 then [ add c "+ list" (E.Pos npos) list_ty ] else [])
  | "get" -> [ posrow "record" 0; posrow ~socket:false "field" 1 ]
  | "assoc" -> posrow "record" 0 :: List.map (fun (k, _) -> kwrow k) kws
  | "values" -> List.map (fun (k, _) -> kwrow k) kws @ [ add c "+ output" (E.Kw "") ~socket:false None ]
  | "ref" ->
      let g = match at 0 with Some { S.node = S.Sym n; _ } -> List.find_opt (fun (g : W.graph) -> g.name = n) c.w.graphs
        | _ -> None in
      row c ~socket:false "graph" (E.Pos 0) (at 0)
      :: (match g with Some g -> input_rows c g.inputs [] kws | None -> [])
  | _ ->
      (match List.find_opt (fun (d : W.graph) -> d.name = h) c.w.defs with
       | Some d -> input_rows c d.inputs pos kws
       | None ->
           match List.assoc_opt h c.macros with
           | Some m -> macro_rows c m pos
           | None ->
               match W.op_signature c.ctx h with
               | Some o ->
                   let np = List.length o.pos in
                   List.concat (List.mapi (fun i (l, ty) -> if i < np || i < npos then [ posrow ~ty l i ] else [])
                     (o.pos @ o.opt))
                   @ (match o.rest with
                      | Some (rn, ty) ->
                          List.filteri (fun i _ -> i >= np) pos |> List.mapi (fun j a ->
                            row c ~ty ~kind:Rest (if j = 0 then rn else Printf.sprintf "%s %d" rn (j + 1)) (E.Pos (np + j)) (Some a))
                          |> fun rows -> rows @ [ add c ("+ " ^ rn) (E.Pos (max npos np)) (Some ty) ]
                      | None -> [])
                   @ List.map (fun (n, ty) -> kwrow ~ty n) o.kw
               | None ->
                   match Flow.Check.resolve_kind c.catalog (catalog_context c.ctx) h with
                   | Ok k -> kind_rows c k pos kws
                   | Error _ -> ignore e; List.mapi (fun i a -> row c (Printf.sprintf "arg%d" (i + 1)) (E.Pos i) (Some a)) pos)

let rows_of c (e : S.t) = match e.node, head_sym e with
  | S.Map l, _ ->
      List.filter_map (fun ((k : S.t), v) -> match k.node with
        | S.Kw k -> Some (row c k (E.Field k) (Some v)) | _ -> None) (pairs l)
      @ [ add c "+ field" (E.Field "") ~socket:false None ]
  | S.List (_ :: args), Some h -> call_rows c e h args
  | S.Sym s, _ when not (List.mem s [ "t"; "pi"; "true"; "false"; "nil" ]) -> [ row c "from" E.Whole (Some e) ]
  | _ -> [ row c "value" E.Whole (Some e) ]

let head_label c (e : S.t) = match e.node with
  | S.Map _ -> "record" | S.Num _ -> "number" | S.Str _ -> "text" | S.Sym _ -> "link" | S.Vec _ -> "vector"
  | _ -> Option.value (head_sym e) ~default:(ignore c; "form")

(* ---- nodes, zones and scopes ---- *)

let scope_form (e : S.t) = match e.node, e.meta with
  | S.List [ { S.node = S.Sym "let*"; _ }; { S.node = S.Vec bs; _ }; res ], []
    when List.length bs mod 2 = 0 -> Some (pairs bs, res)
  | _ -> None

let zone_kind (pat : S.t option) (e : S.t) =
  if e.meta <> [] then None
  else match head_sym e, pat with
    | Some "for", _ -> Some For | Some "fold", _ -> Some Fold | Some "scan", _ -> Some Scan
    | Some "sum", _ -> Some Sum
    | Some "let*", _ when scope_form e <> None -> Some Let
    | Some "fn", Some { S.node = S.Sym _; _ } -> Some Fn
    | _ -> None

let outputs (pat : S.t option) ty = match pat with
  | None -> []
  | Some pat ->
      (match pat.node, ty with
       | S.Sym _, Ty.Record fs -> fs
       | S.Sym _, _ -> []
       | S.Vec _, _ ->
           let t = match ty with Ty.List e -> e | Ty.Vec3 -> Ty.Float | _ -> Ty.Any in
           List.map (fun n -> n, t) (E.pat_names pat)
       | _ -> List.map (fun n -> n, (match ty with Ty.Record fs -> Option.value (List.assoc_opt n fs) ~default:Ty.Any
                                      | _ -> Ty.Any)) (E.pat_names pat))

let rail_of c (kind : zone_kind) (e : S.t) (t : W.term option) ~visible =
  let bound = ref [] in
  let clause_ty k = match t with
    | Some { W.node = Loop { clauses; _ }; _ } ->
        Option.bind (List.nth_opt clauses k) (fun (_, (ct : W.term)) -> Ty.elem ct.ty)
    | _ -> None in
  let vars first = match List.nth_opt (S.children e) first with
    | Some { S.node = S.Vec l; _ } ->
        List.mapi (fun k ((p : S.t), x) ->
          bound := E.pat_names p @ !bound;
          { name = E.pat_key p; names = E.pat_names p; role = Var; ty = clause_ty k; expr = Some x;
            key = Some (E.Bv (first, 2 * k + 1)) }) (pairs l)
    | _ -> [] in
  let rows = match kind with
    | For | Sum -> vars 1
    | Fold | Scan ->
        let acc = match List.nth_opt (S.children e) 1 with
          | Some { S.node = S.Vec [ p; init ]; _ } ->
              bound := E.pat_names p @ !bound;
              let ty = match t with
                | Some { W.node = Loop { accs = (_, (a : W.term)) :: _; _ }; _ } -> Some a.ty | _ -> None in
              [ { name = E.pat_key p; names = E.pat_names p; role = Acc; ty; expr = Some init;
                  key = Some (E.Bv (1, 1)) } ]
          | _ -> [] in
        acc @ vars 2
    | Fn ->
        (match List.nth_opt (S.children e) 1 with
         | Some { S.node = S.Vec ps; _ } ->
             List.mapi (fun k (p : S.t) ->
               let pat = match p.node with S.List [ pat; { S.node = S.Sym ":"; _ }; _ ] -> pat | _ -> p in
               bound := E.pat_names pat @ !bound;
               let ty = match t with
                 | Some { W.node = Fn { params; _ }; _ } -> Option.bind (List.nth_opt params k) snd
                 | _ -> None in
               { name = E.pat_key pat; names = E.pat_names pat; role = Param; ty; expr = None; key = None }) ps
         | _ -> [])
    | Let -> [] in
  let body = if kind = Let then e else last e in
  let captures = List.filter (fun n -> List.mem n visible && not (List.mem n !bound)) (E.free_names body) in
  ignore c;
  rows @ List.map (fun n ->
    { name = n; names = [ n ]; role = Capture; ty = None; expr = None; key = None }) captures

let yield_label = function
  | For | Scan -> "collect" | Fold -> "next" | Sum -> "add" | Let -> "result" | Fn -> "return"

let rec scope_of c ~visible ~inputs (path : path) (body : S.t) : scope =
  let binds, res = match scope_form body with
    | Some (bs, res) -> bs, res
    | None -> [], body in
  let visible = List.concat_map (fun (p, _) -> E.pat_names p) binds @ visible in
  let nodes = List.map (fun (pat, e) -> node_of c ~visible path (Some pat) e) binds in
  let result, extra = match res.node with
    | S.Sym s when List.mem (root_of s) visible -> Link s, []
    | S.List _ | S.Map _ ->
        let n = node_of c ~visible path None res in
        Node n.path, [ n ]
    | _ -> Literal res, [] in
  { path; inputs; nodes = nodes @ extra; result }

and node_of c ~visible (scope_path : path) (pat : S.t option) (e : S.t) : node =
  let name = match pat with Some p -> E.pat_key p | None -> "@result" in
  let p = scope_path @ [ name ] in
  let term = Hashtbl.find_opt c.terms p in
  let ty = match term with Some t -> t.ty | None -> Ty.Any in
  let kind = zone_kind pat e in
  let zone = Option.map (fun k ->
    let rail = rail_of c k e term ~visible in
    let inner_visible = List.concat_map (fun (r : rail_row) -> if r.role = Capture then [] else r.names) rail @ visible in
    let body = if k = Let then e else last e in
    (* a loop over the points or pieces of geometry says how its elements are ordered *)
    let order = List.find_map (fun (r : rail_row) -> match r.role, r.expr with
      | Var, Some { S.node = S.List ({ S.node = S.Sym ("sop/point_list" | "sop/piece_list"); _ } :: args); _ } ->
          let rec key = function
            | { S.node = S.Kw "key"; _ } :: { S.node = S.Str k; _ } :: _ -> Some ("by " ^ k)
            | _ :: rest -> key rest
            | [] -> None in
          Some (Option.value ~default:"by index" (key args))
      | _ -> None) rail in
    { kind = k; rail; yield_label = yield_label k; order;
      scope = scope_of c ~visible:inner_visible ~inputs:[] p body }) kind in
  let macro = match head_sym e with Some h when List.mem_assoc h c.macros -> Some h | _ -> None in
  let lens = Option.map (fun _ -> macro_lens c.w e) macro in
  { path = p; name; binds = (match pat with Some pt -> E.pat_names pt | None -> [ name ]);
    head = (match kind with
      | Some Let -> "let*" | Some _ -> Option.get (head_sym e) | None -> head_label c e);
    rows = (if kind = None then rows_of c e else []); outputs = outputs pat ty; ty;
    note = (match pat with Some { S.notes = (_ :: _ as l); _ } -> Some (String.concat "\n" l) | _ -> None);
    bypass = List.mem "bypass" e.meta; macro; lens;
    live = W.Paths.mem p c.w.live; invariant = W.Paths.mem p c.w.invariant;
    synthetic = pat = None; zone }

let bypassable (n : node) =
  n.zone = None && (not n.synthetic) && n.macro = None
  && not (List.mem n.head [ "record"; "number"; "text"; "link"; "vector"; "list"; "str"; "if"; "cond"; "case" ])
  && (n.bypass
      || (match List.find_opt (fun (r : row) -> r.kind = Arg) n.rows with
          | Some { ty = Some ty; _ } -> Ty.fits ty n.ty
          | _ -> false))

let of_graph catalog (w : W.t) name =
  let def = String.starts_with ~prefix:"def:" name in
  let bare = if def then String.sub name 4 (String.length name - 4) else name in
  let g = match List.find_opt (fun (g : W.graph) -> g.name = bare) (if def then w.defs else w.graphs @ w.defs) with
    | Some g -> g
    | None -> invalid_arg ("Projection.of_graph: no graph " ^ name) in
  let root = [ (if List.exists (fun (d : W.graph) -> d == g) w.defs then "def:" ^ g.name else g.name) ] in
  let terms = Hashtbl.create 64 in
  collect terms g.body;
  let macros = List.filter_map (fun (m : S.t) -> match S.children m with
    | _ :: { S.node = S.Sym n; _ } :: _ -> Some (n, m) | _ -> None) w.macros in
  let c = { w; catalog; ctx = g.context; macros; terms } in
  let inputs = List.map (fun (n, ty, d) ->
    { path = root @ [ ":" ^ n ]; name = n; ty; default = Option.map (fun (t : W.term) -> t.form) d }) g.inputs in
  scope_of c ~visible:(List.map (fun (i : input) -> i.name) inputs) ~inputs root (last g.form)

let rec zones (s : scope) = List.concat_map (fun (n : node) -> match n.zone with
  | Some z -> n :: zones z.scope | None -> []) s.nodes

let rec find (s : scope) path = List.find_map (fun (n : node) ->
  if n.path = path then Some n
  else match n.zone with Some z -> find z.scope path | None -> None) s.nodes

(* ---- layout ---- *)

let row_height = 24.
let head_height = 24.
let foot_height = 20.
let node_width = 196.
let rail_width = 176.
let yield_width = 104.
let strip_height = 34.
let pad = 14.
let gap = 34.

type item = Input of input | Item of node | Return

type placed = {
  item : item; path : path; x : float; y : float; w : float; h : float;
  collapsed : bool; inner : layout option;
}
and layout = { placed : placed list; w : float; h : float }

let strip (n : node) = match n.zone with Some { kind = Let; _ } | None -> 0. | Some _ -> strip_height
let rail_top (n : node) = head_height +. strip n +. 4.
let nrows n = float_of_int (List.length n.rows)
let count l = float_of_int (List.length l)

let lens_width = 400.
let lens_height (l : lens) ~step =
  let shown = if step >= Array.length l.steps then l.template
    else l.steps.(max 0 step) in
  let lines = match l.error with Some _ when step < Array.length l.steps -> 2 | _ ->
    min 16 (1 + String.fold_left (fun a c -> if c = '\n' then a + 1 else a) 0 shown) in
  row_height +. 10. +. float lines *. 15. +. row_height

let rec size ~at ~collapsed ~lens (it : item) : float * float * bool * layout option = match it with
  | Input _ -> node_width, head_height +. row_height +. foot_height, false, None
  | Return -> node_width -. 40., head_height +. row_height, false, None
  | Item ({ zone = Some z; _ } as n) ->
      let rail = count z.rail in
      if collapsed n.path then
        node_width, head_height +. Float.max 1. rail *. row_height +. foot_height, true, None
      else
        let (l : layout) = layout ~at ~collapsed ~lens z.scope in
        let body = Float.max (Float.max (rail *. row_height +. 8.) l.h) (row_height +. 14.) in
        rail_width +. pad +. Float.max l.w 72. +. pad +. yield_width,
        head_height +. strip n +. body +. (if z.kind = Fold || z.kind = Scan then 22. else 10.)
        +. (if z.kind = Let then 0. else foot_height),  (* the zone's own footer *)
        false, Some l
  | Item n ->
      let open_lens = match n.lens, lens n.path with
        | Some l, Some step -> Some (l, step) | _ -> None in
      (match open_lens with Some _ -> Float.max node_width lens_width | None -> node_width),
      head_height +. (if n.note <> None then row_height else 0.) +. (nrows n +. count n.outputs) *. row_height
      +. foot_height
      +. (match open_lens with Some (l, step) -> lens_height l ~step | None -> 0.), false, None

and layout ?(at = fun _ -> None) ?(collapsed = fun _ -> false) ?(lens = fun _ -> None) (s : scope) : layout =
  let root = s.inputs <> [] in
  let items =
    List.map (fun (i : input) -> Input i, i.path, [], [ i.name ]) s.inputs
    @ List.map (fun (n : node) ->
        let deps = List.concat_map (fun (r : row) -> match r.expr with Some e -> E.free_names e | None -> []) n.rows
          @ (match n.zone with
             | Some z -> List.concat_map (fun (r : rail_row) ->
                 match r.role, r.expr with
                 | Capture, _ -> [ r.name ] | _, Some e -> E.free_names e | _ -> []) z.rail
             | None -> []) in
        Item n, n.path, deps, n.binds) s.nodes
    @ (if root then [ Return, s.path @ [ "@return" ],
        (match s.result with Link l -> [ root_of l ]
                           | Node _ -> [ "@result" ] | Literal _ -> []), [] ] else []) in
  let by_name = Hashtbl.create 16 in
  List.iteri (fun k (_, _, _, names) -> List.iter (fun n -> Hashtbl.replace by_name n k) names) items;
  let arr = Array.of_list items in
  let level = Array.make (Array.length arr) (-1) in
  let rec lv k =
    if level.(k) >= 0 then level.(k)
    else begin
      level.(k) <- 0;
      let it, _, deps, _ = arr.(k) in
      let base = match it with Input _ -> 0 | _ -> if s.inputs <> [] then 1 else 0 in
      level.(k) <- List.fold_left (fun l d -> match Hashtbl.find_opt by_name d with
        | Some j when j <> k -> max l (lv j + 1) | _ -> l) base deps;
      level.(k)
    end in
  Array.iteri (fun k _ -> ignore (lv k)) arr;
  let cols = Array.fold_left max 0 level + 1 in
  let placed = ref [] and x = ref 12. and w = ref 0. and h = ref 0. in
  for l = 0 to cols - 1 do
    let y = ref 12. and cw = ref 0. in
    Array.iteri (fun k (it, path, _, _) ->
      if level.(k) = l then begin
        let iw, ih, coll, inner = size ~at ~collapsed ~lens it in
        let px, py = match at path with Some (ax, ay) -> ax, ay | None -> !x, !y in
        placed := { item = it; path; x = px; y = py; w = iw; h = ih; collapsed = coll; inner } :: !placed;
        y := !y +. ih +. 18.; cw := Float.max !cw iw;
        w := Float.max !w (px +. iw); h := Float.max !h (py +. ih)
      end) arr;
    if !cw > 0. then x := !x +. !cw +. gap
  done;
  { placed = List.rev !placed; w = !w +. 12.; h = !h +. 12. }

let place (l : layout) =
  let rec go ox oy (l : layout) = List.concat_map (fun (p : placed) ->
    let ax = ox +. p.x and ay = oy +. p.y in
    (p.path, (ax, ay, p.w, p.h))
    :: (match p.inner, p.item with
        | Some inner, Item n -> go (ax +. rail_width +. pad) (ay +. rail_top n) inner
        | _ -> [])) l.placed in
  go 0. 0. l
