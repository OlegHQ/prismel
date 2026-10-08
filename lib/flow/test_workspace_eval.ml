open Flow

let read path = In_channel.with_open_bin path In_channel.input_all
let catalog = match Check.catalog_of_manifest (read "../sop_catalog/flow_manifest.sexp") with
  | Ok (catalog, _) -> catalog
  | Error d -> failwith (Diagnostic.to_string d)
let cases = "../../specification/workspace/cases"

let parse source = match Syntax.parse source with
  | Ok forms -> forms
  | Error d -> failwith (Diagnostic.to_string d)
let errors ds = List.filter (fun (d : Diagnostic.t) -> d.severity = Diagnostic.Error) ds
let show_ds ds = String.concat "; " (List.map Diagnostic.to_string ds)
let check source = match Workspace.check catalog (parse source) with
  | Some ws, ds when errors ds = [] -> ws
  | _, ds -> failwith (source ^ "\n  rejected: " ^ show_ds ds)

let sop b = "(workspace w (graph g :context sop " ^ b ^ "))"
let value b = "(workspace w (graph g :context value " ^ b ^ "))"

(* each case is one check.cjs test (or one register rule); failures are collected *)
let passed = ref 0 and failed = ref []
let t name f =
  match f () with
  | () -> incr passed
  | exception e -> failed := (name, Printexc.to_string e) :: !failed

(* ---- running ---- *)
let ok = function Ok r -> r | Error d -> failwith (Diagnostic.to_string d)
let static ?record ?inputs ws = ok (Eval.static ?record ?inputs ws)
let run ?record ?inputs ?(time = 0.) ws = ok (Eval.run ?record ?inputs ~time ws)
let result (r : Eval.t) name = List.assoc name r.results
let g_value ?time src = result (run ?time (check src)) "g"

let rec same (a : Eval.value) (b : Eval.value) = match a, b with
  | (Int _ | Float _), (Int _ | Float _) ->
      let n = function Eval.Int n -> float_of_int n | Float f -> f | _ -> nan in
      n a = n b
  | List x, List y -> Array.length x = Array.length y && Array.for_all2 same x y
  | Record x, Record y ->
      List.length x = List.length y && List.for_all2 (fun (k, u) (l, v) -> k = l && same u v) x y
  | Vec3 (a, b, c), Vec3 (x, y, z) -> a = x && b = y && c = z
  | _ -> a = b
let is src want =
  let got = g_value src in
  if not (same got want) then
    failwith (Printf.sprintf "%s: got %s, want %s" src (Eval.show got) (Eval.show want))
let ints l = Eval.List (Array.of_list (List.map (fun n -> Eval.Int n) l))

(* an error at run time: the code, and text in the message *)
let err ?(text = "") ?inputs src code =
  let has (d : Diagnostic.t) =
    let n = String.length text and m = String.length d.message in
    let rec at i = i + n <= m && (String.sub d.message i n = text || at (i + 1)) in at 0 in
  match Eval.static ?inputs (check src) with
  | Error d when d.code = code && has d -> ()
  | Error d -> failwith (Printf.sprintf "%s\n  expected %s %S, got %s" src code text (Diagnostic.to_string d))
  | Ok _ -> failwith (src ^ "\n  ran; expected " ^ code)

let records ?(time = 0.) src =
  (run ~record:true ~time (check src)).records
let recs rs path = match List.assoc_opt path rs with Some l -> l | None -> failwith ("no records at " ^ String.concat "/" path)
let first_at rs path = snd (List.hd (recs rs path))
let bound src name = first_at (records src) [ "g"; name ]

let nodes_of (r : Eval.t) kind = List.filter (fun (n : Eval.node) -> n.kind = kind) (Array.to_list r.plan.nodes)
let arg (n : Eval.node) k = List.assoc k n.args
let count_of r kind = List.length (nodes_of r kind)

(* IR walk, for the static types *)
let rec walk f (x : Workspace.term) =
  f x;
  let all = List.iter (walk f) in
  let named l = List.iter (fun (_, x) -> walk f x) l in
  match x.node with
  | Workspace.Lit _ | Text _ | Nil | Time | Ref_binding _ | Fn_ref _ -> ()
  | Vec ts | List_lit ts | Str ts | List_op (_, ts) | Hof (_, ts) | Call_fn { args = ts; _ } -> all ts
  | Call { args; _ } | Op { args; _ } | Graph_ref { inputs = args; _ } | Record args -> named args
  | Let (bs, r) -> named bs; walk f r
  | State {init; step; _} -> all [init; step]
  | Loop { accs; clauses; body; _ } -> named accs; named clauses; walk f body
  | If (a, b, c) -> all [ a; b; c ]
  | Cond (arms, d) -> List.iter (fun (a, b) -> all [ a; b ]) arms; walk f d
  | Case (s, arms, d) -> walk f s; List.iter (fun (_, b) -> walk f b) arms; walk f d
  | Fn { body; _ } | Bypass body | Expanded { body; _ } -> walk f body
  | Get (r, _) -> walk f r
  | Assoc (r, us) -> walk f r; named us
let ty_at (ws : Workspace.t) path =
  let found = ref None in
  List.iter (fun (g : Workspace.graph) ->
    walk (fun x -> if x.path = Some path then found := Some x.ty) g.body) (ws.graphs @ ws.defs);
  match !found with Some ty -> Ty.to_string ty | None -> failwith ("no term at " ^ String.concat "/" path)

let fixtures () =
  Sys.readdir cases |> Array.to_list |> List.filter (fun f -> Filename.check_suffix f ".lisp")
  |> List.sort compare
  |> List.map (fun f -> (Filename.remove_extension f, read (Filename.concat cases f)))

let () = (* the 12 fixtures run, deterministically, with unique plan keys, at any time *)
  List.iter (fun (name, source) -> t ("case " ^ name ^ " runs") (fun () ->
    let ws = check source in
    let a = run ws and b = run ws in
    if a <> b then failwith "two runs differ";
    assert (Array.length a.authored = Array.length a.plan.nodes);
    let forms = Hashtbl.create 128 in
    let rec remember (form : Syntax.t) = Hashtbl.replace forms form.id (); List.iter remember (Syntax.children form) in
    List.iter remember ws.source;
    assert (Array.for_all (fun id -> id = 0 || Hashtbl.mem forms id) a.authored);
    assert (a.authored = (static ws).authored);
    let keys = Array.to_list a.plan.nodes |> List.map (fun (n : Eval.node) -> (n.inst, n.site, n.iter)) in
    if List.length (List.sort_uniq compare keys) <> List.length keys then failwith "plan keys collide";
    (* structure never depends on t: only argument values change *)
    let c = run ~time:3.1 ws in
    let shape (r : Eval.t) = Array.map (fun (n : Eval.node) -> (n.kind, n.site, n.iter)) r.plan.nodes in
    if shape a <> shape c then failwith "structure changed with t";
    if Array.length a.plan.nodes = 0 && name <> "kit" && name <> "variations" && name <> "tiles" then
      failwith "no nodes")) (fixtures ())


(* ---- check.cjs: value cases ---- *)

let () = (* the first block *)
  t "sum" (fun () -> is (value "(sum [k (range 4)] (* k 2))") (Eval.Int 12));
  t "int truncates, round is half away from zero, ceil and float" (fun () ->
    is (value "(int -2.7)") (Eval.Int (-2)); is (value "(round 2.5)") (Eval.Int 3);
    is (value "(round -2.5)") (Eval.Int (-3)); is (value "(ceil 2.1)") (Eval.Int 3);
    is (value "(float 3)") (Eval.Float 3.); is (value "(/ (float 3) 2)") (Eval.Float 1.5));
  t "sum of nothing is 0" (fun () -> is (value "(sum [k (range 0)] 1.5)") (Eval.Int 0));
  t "fold" (fun () -> is (value "(fold [a 1] [i (range 5)] (* a 2))") (Eval.Int 32));
  t "fold of nothing is its initial value" (fun () -> is (value "(fold [a 7] [i (range 0)] (* a 2))") (Eval.Int 7));
  t "scan collects each step" (fun () ->
    is (value "(let* [xs (scan [a 1] [i (range 3)] (+ a i))] (count xs))") (Eval.Int 3);
    assert (same (bound (value "(let* [z (scan [a 1] [i (range 4)] (* a 2))] 1)") "z") (ints [ 2; 4; 8; 16 ]));
    assert (same (bound (value "(let* [z (scan [a 1] [i (range 0)] (* a 2))] 1)") "z") (ints [])));
  t "product is row-major, last clause fastest" (fun () ->
    assert (same (bound (value "(let* [z (for [x (range 2) y (range 3)] (+ (* x 10) y))] (count z))") "z")
      (ints [ 0; 1; 2; 10; 11; 12 ])));
  t "later clauses read earlier names" (fun () ->
    is (value "(let* [z (for [x (range 4) y (range x)] y)] (count z))") (Eval.Int 6));
  t "graph inputs and ref overrides" (fun () ->
    let ws = check "(workspace w (graph a :context value [(n : int 2)] (* n 3)) (graph b :context value (+ (ref a) (ref a :n 5))))" in
    let r = static ws in
    assert (same (result r "b") (Eval.Int 21));
    (* a, b, and a with n=5: an override tuple is one cached instance *)
    assert (Array.length r.plan.instances = 3));
  t "rand is a pure hash" (fun () ->
    let a = g_value (value "(value/rand 3 4 5)") and b = g_value (value "(value/rand 3 4 5)") in
    match a, b with
    | Eval.Float x, Eval.Float y -> assert (x = y && x >= 0. && x < 1.)
    | _ -> failwith "not a float");
  t "per-iteration records carry their index" (fun () ->
    let bloom = read (Filename.concat cases "bloom.lisp") in
    let rs = records bloom in
    let r = recs rs [ "flower"; "ring"; "u" ] in
    assert (List.length r = 12 && fst (List.nth r 3) = [ 3 ]));
  t "loops tag what they make" (fun () ->
    let r = run (check (read (Filename.concat cases "bloom.lisp"))) in
    assert (Array.exists (fun (n : Eval.node) ->
      n.iter = [ 5 ] && List.filteri (fun i _ -> i < 2) n.site = [ "flower"; "ring" ]) r.plan.nodes));
  t "only the taken branch runs" (fun () ->
    (* the study runs a literal (range 9999) in the untaken arm; the checker rejects that literal,
       so the count is a graph input *)
    let src b = "(workspace w (graph g :context value [(n : int 9999)] " ^ b ^ "))" in
    is (src "(if (< 1 2) 1 (count (range n)))") (Eval.Int 1);
    err (src "(if (> 1 2) 1 (count (range n)))") "E_ITER_BOUND" ~text:"exceeds 4,096")

let () = (* 1. function values *)
  t "fn: let-bound function is called positionally" (fun () ->
    is (value "(let* [f (fn [a b] (+ a b))] (f 1 2))") (Eval.Int 3));
  t "fn: annotated parameters coerce" (fun () ->
    assert (bound (value "(let* [f (fn [(a : float) b] (* a b)) r (f 1 2)] 1)") "r" = Eval.Float 2.));
  t "fn: closures capture the lexical environment" (fun () ->
    is (value "(let* [k 10 f (fn [x] (+ x k))] (f 1))") (Eval.Int 11));
  t "fn: a local function wins over an operator of the same name" (fun () ->
    is (value "(let* [min (fn [a b] (+ a b))] (min 1 2))") (Eval.Int 3));
  t "fn: calls are iteration frames with per-call records" (fun () ->
    let src = value "(let* [f (fn [a] (let* [s (* a 2)] (+ s 1))) x (f 5) y (sum [i (range 3)] (f i))] (+ x y))" in
    let ws = check src in
    let rs = (run ~record:true ws).records in
    let at p = List.map (fun (it, v) -> (it, v)) (recs rs p) in
    assert (at [ "g"; "f"; "@result" ]
            = [ ([ 0 ], Eval.Int 11); ([ 0; 1 ], Eval.Int 1); ([ 1; 2 ], Eval.Int 3); ([ 2; 3 ], Eval.Int 5) ]);
    assert (List.map snd (at [ "g"; "f"; ":a" ]) = [ Eval.Int 5; Int 0; Int 1; Int 2 ]);
    assert (List.nth (at [ "g"; "f"; "s" ]) 3 = ([ 2; 3 ], Eval.Int 4));
    (* the IR types a fn body with its declared types, or Any: call-site refinement (int) is not kept *)
    assert (ty_at ws [ "g"; "f"; "s" ] = "float" && ty_at ws [ "g"; "f" ] = "fn"));
  t "fn: inline functions are recorded at their nested card path" (fun () ->
    let rs = records (value "(let* [xs (map (fn [x] (* x 2)) (list 1 2))] (count xs))") in
    assert (List.map snd (recs rs [ "g"; "xs#0"; ":x" ]) = [ Eval.Int 1; Int 2 ]));
  t "fn: map is typed statically through the function body" (fun () ->
    let ws = check (sop "(let* [cs (map (fn [x] (sop/box :size x)) (list 1 2))] (sop/merge cs))") in
    assert (ty_at ws [ "g"; "cs" ] = "list:geometry" && ty_at ws [ "g"; "cs#0"; "@result" ] = "geometry"));
  t "fn: map over a let-bound fn tags shapes with the call index" (fun () ->
    let r = run (check (sop "(let* [mk (fn [r] (sop/box :size r)) cs (map mk (list 0.1 0.2 0.3))] (sop/merge cs))")) in
    assert (List.map (fun (n : Eval.node) -> (n.site, n.iter)) (nodes_of r "sop/box")
            = List.map (fun k -> ([ "g"; "mk"; "@result" ], [ k ])) [ 0; 1; 2 ]));
  t "fn: maps inside opaque expressions keep distinct sites" (fun () ->
    let r = run (check (sop "(let* [unused (list (count (map (fn [x] (sop/box :size x)) (list 0.1))) (count (map (fn [x] (sop/box :size x)) (list 0.2))))] (sop/box))")) in
    let sites = List.map (fun (n : Eval.node) -> n.site, n.iter) (nodes_of r "sop/box") in
    assert (List.length sites = 3 && List.length (List.sort_uniq compare sites) = 3));
  t "fn: defn and operator names are function values" (fun () ->
    is "(workspace w (defn twice :context value [(x : float)] (* x 2)) (graph g :context value (+ (reduce + 0 (map twice (list 1 2 3))) (first (map sin (list 0))))))" (Eval.Int 12));
  t "reduce: an int seed keeps a float sum" (fun () ->
    is (value "(reduce + 0 (list 0.5 0.25))") (Eval.Float 0.75));
  t "fn: user HOF with a fn-typed defn input" (fun () ->
    let ring = "(defn ring :context sop [(n : int 8) (make : fn)] (sop/merge (map make (range n))))" in
    let r = run (check ("(workspace w " ^ ring ^ " (defn dot :context sop [(i : int)] (sop/box :size (* 0.1 (+ i 1)))) (graph g :context sop (sop/merge (ring :n 3 :make dot) (let* [mk (fn [i] (sop/box))] (ring :n 2 :make mk)))))")) in
    assert (count_of r "sop/box" = 5 && count_of r "sop/merge" = 3);
    (* the two ring call sites are distinct subtrees; mk's two calls are iterations 0 and 1 *)
    assert (List.sort compare (List.map (fun (n : Eval.node) -> n.iter) (nodes_of r "sop/box"))
            = [ [ 0 ]; [ 0 ]; [ 1 ]; [ 1 ]; [ 2 ] ]));
  t "fn: defn inputs typed as lists and records" (fun () ->
    is "(workspace w (defn tot :context value [(xs : (list float)) (r : {:k float})] (* r.k (reduce + 0 xs))) (graph g :context value (tot (list 1 2) {:k 2 :extra 1})))" (Eval.Int 6));
  t "hof: map zips up to three lists to the shortest" (fun () ->
    assert (same (bound (value "(let* [z (map (fn [a b c] (+ a (+ b c))) (list 1 2 3) (list 10 20) (list 100 200 300))] 1)") "z") (ints [ 111; 222 ])));
  t "hof: filter" (fun () ->
    assert (same (bound (value "(let* [z (filter (fn [x] (> x 1)) (list 1 2 3))] 1)") "z") (ints [ 2; 3 ])));
  t "hof: sort-by is stable on a numeric key" (fun () ->
    let l a b = Eval.List [| Eval.Int a; Int b |] in
    assert (same (bound (value "(let* [z (sort-by (fn [p] (first p)) (list (list 2 0) (list 1 1) (list 2 2) (list 1 3)))] 1)") "z")
      (Eval.List [| l 1 1; l 1 3; l 2 0; l 2 2 |])));
  t "hof: map of an empty list keeps its static type" (fun () ->
    let src = sop "(let* [z (map (fn [x] (sop/box :size x)) (list))] (sop/merge z))" in
    assert (same (bound src "z") (ints []));
    assert (ty_at (check src) [ "g"; "z" ] = "list:geometry"))

let () = (* 2. lists and destructuring *)
  t "list: int and float promote to float" (fun () ->
    let src = value "(let* [z (list 1 2.5)] 1)" in
    assert (bound src "z" = Eval.List [| Float 1.; Float 2.5 |]);
    assert (ty_at (check src) [ "g"; "z" ] = "list:float"));
  t "list: (list) is a list of any" (fun () ->
    let src = value "(let* [z (list)] 1)" in
    assert (bound src "z" = Eval.List [||] && ty_at (check src) [ "g"; "z" ] = "list:any"));
  t "list: first last rest nth concat reverse take drop" (fun () ->
    assert (bound (value "(let* [s (str (first (list 4 5)) (last (list 4 5)) (rest (list 1 2 3)) (nth (list 7 8) 1) (concat (list 1) (list) (list 2 3)) (reverse (list 1 2)) (take 2 (list 1 2 3)) (drop 2 (list 1 2 3)))] 1)") "s"
            = Eval.Text "45[2 3]8[1 2 3][2 1][1 2][3]"));
  t "list: nth out of range names index and length" (fun () ->
    err (value "(nth (list 1 2) 5)") "E_LIST_RANGE" ~text:"index 5 is out of range for a list of length 2";
    err (value "(nth (list 1 2) -1)") "E_LIST_RANGE");
  t "list: first of an empty list is an error" (fun () ->
    err (value "(first (list))") "E_LIST_RANGE" ~text:"empty list";
    err (value "(last (list))") "E_LIST_RANGE");
  t "pattern: [a b] in let* records whole and parts" (fun () ->
    let src = value "(let* [[a b] (list 1 2)] (+ a b))" in
    is src (Eval.Int 3);
    let rs = records src in
    assert (same (first_at rs [ "g"; "[a b]" ]) (ints [ 1; 2 ]) && first_at rs [ "g"; "b" ] = Eval.Int 2));
  t "pattern: [x y z] over a vec3 and {:keys} over a record" (fun () ->
    is (value "(let* [[x y z] [1 2 3] {:keys [a b]} {:a 10 :b 20}] (+ (* x a) (* z b)))") (Eval.Int 70));
  t "pattern: in zone clauses and fn parameters" (fun () ->
    let src = value "(let* [f (fn [[a b]] (* a b)) s (sum [[a b] (list (list 1 2) (list 3 4))] (+ (f (list a b)) 0))] s)" in
    is src (Eval.Int 14);
    let rs = records src in
    assert (same (snd (List.nth (recs rs [ "g"; "s"; ":[a b]" ]) 1)) (ints [ 3; 4 ]));
    assert (List.length (recs rs [ "g"; "s"; ":a" ]) = 2 && List.length (recs rs [ "g"; "s"; ":b" ]) = 2);
    assert (List.length (recs rs [ "g"; "f"; ":[a b]" ]) = 2));
  t "pattern: zoneVars reports the pattern and its names" (fun () ->
    let ws = check (value "(let* [z (for [[a b] (list (list 1 2)) {:keys [c]} (list {:c 1})] a)] 1)") in
    match (List.hd ws.graphs).body.node with
    | Workspace.Let ([ (_, { node = Workspace.Loop { clauses = [ (Workspace.Seq [ Name "a"; Name "b" ], _); (Keys [ "c" ], _) ]; _ }; _ }) ], _) -> ()
    | _ -> failwith "unexpected clause patterns")

let () = (* 3. records *)
  t "record: literal, dotted access and chains" (fun () ->
    let src = value "(let* [r {:a 1 :b {:c [1 2 3]}}] (+ r.a r.b.c.y))" in
    is src (Eval.Int 3);
    assert (ty_at (check src) [ "g"; "r" ] = "rec{a:int,b:rec{c:vec3}}"));
  t "record: get and assoc" (fun () -> is (value "(let* [r {:a 1} s (assoc r :a 5 :c 2)] (+ (get s :a) s.c))") (Eval.Int 7));
  t "record: values is a record literal" (fun () ->
    assert (bound (value "(let* [r (values :a 1 :b 2.5)] 1)") "r" = Eval.Record [ ("a", Int 1); ("b", Float 2.5) ]));
  t "record: a record accumulator carries several values" (fun () ->
    is (value "(let* [s (fold [{:keys [a b]} {:a 0 :b 1}] [i (range 10)] {:a b :b (+ a b)})] s.a)") (Eval.Int 55))

let () = (* 4. cond, case, str *)
  t "cond picks the first true arm" (fun () -> is (value "(cond (< 2 1) 1 (> 2 1) 2 :else 3)") (Eval.Int 2));
  t "cond is lazy at run time" (fun () ->
    is "(workspace w (graph g :context value [(n : int 9999)] (cond true 1 :else (count (range n)))))" (Eval.Int 1));
  t "case matches literals" (fun () ->
    is (value "(case 2 1 10 2 20 :else 0)") (Eval.Int 20);
    is (value "(case 9 1 10 :else 0)") (Eval.Int 0);
    is (value "(case \"b\" \"a\" 1 \"b\" 2 :else 0)") (Eval.Int 2);
    is (value "(case true false 1 true 2 :else 0)") (Eval.Int 2));
  t "str formats values" (fun () ->
    assert (bound (value "(let* [s (str \"a\" 1 2.5 true [1 2 3] 1.23456 (list 1 2) {:a 1} (/ 1 3))] 1)") "s"
            = Eval.Text "a12.5true[1 2 3]1.2346[1 2]{:a 1}0.3333"));
  t "str computes group names" (fun () ->
    let r = run (check (sop "(sop/blast (sop/group_bounds (sop/box) :name (str \"floor_\" 2)) :group (str \"floor_\" 2))")) in
    assert (arg (List.hd (nodes_of r "sop/blast")) "group" = Eval.Text "floor_2");
    assert (arg (List.hd (nodes_of r "sop/group_bounds")) "name" = Eval.Text "floor_2"))

let () = (* 5. macros *)
  let radial = "(defmacro radial [i n body] `(sop/merge (for [~i (range ~n)] (sop/transform ~body :rotate [0 (* (/ ~i ~n) 6.2832) 0]))))" in
  t "macro: caller symbols may bind; expansion runs at path~for" (fun () ->
    let src = "(workspace w " ^ radial ^ " (graph g :context sop (let* [ring (radial k 12 (sop/box :size (+ 0.1 (* k 0.01))))] ring)))" in
    let r = run ~record:true (check src) in
    assert (count_of r "sop/transform" = 12);
    assert (List.length (recs r.records [ "g"; "ring"; "~for"; ":k" ]) = 12));
  t "macro: rest parameters splice" (fun () ->
    is "(workspace w (defmacro all [& xs] `(+ 0 (+ ~@xs))) (graph g :context value (all 1 2)))" (Eval.Int 3));
  t "macro: legacy value templates still work" (fun () ->
    is "(workspace w (defmacro twice [x] `(+ ~x ~x)) (graph g :context value (twice 3)))" (Eval.Int 6))

let () = (* 6. bypass, notes *)
  t "bypass passes the first input through" (fun () ->
    let r = run (check (sop "(let* [a (sop/box) b ^:bypass (sop/transform a :translate [5 0 0])] b)")) in
    assert (Array.length r.plan.nodes = 1 && result r "g" = Eval.Deferred (Ty.geometry, 0));
    (* a bypassed value call passes its first input, coerced *)
    is (value "(let* [a 2 b ^:bypass (+ a 3)] b)") (Eval.Int 2));
  t "notes survive print and the workspace still runs" (fun () ->
    let noted = "; lead\n(workspace w\n  ; a helper\n  (defn f :context value [(x : float)] (* x 2))\n  (graph g :context value\n    (let* [; first\n           a 1\n           ; the pattern\n           [b c] (list 1 2)\n           q (f a)]\n      ; result note\n      (+ a (+ b (* c q)))))\n  ; tail\n  )" in
    let printed = fst (Lisp.print (parse noted)) in
    is printed (Eval.Int 6))

let () = (* 7. round trip and running the kitchen sink *)
  t "round trip: print(read(print(x))) is stable for every new construct" (fun () ->
    let radial = "(defmacro radial [i n body] `(sop/merge (for [~i (range ~n)] (sop/transform ~body :rotate [0 (* (/ ~i ~n) 6.2832) 0]))))" in
    let all = "(workspace kitchen\n  ; macros\n  " ^ radial ^ "\n  (defmacro all [& xs] `(sop/merge ~@xs))\n  (defmacro add1 [a] `(let* [t# ~a] (+ t# 1)))\n  (defmacro twice [x] `(+ ~x ~x))\n  (defn ring :context sop [(n : int 8) (make : fn) (opts : {:scale float :tags (list text)} {:scale 1.0 :tags (list \"a\")})]\n    (sop/transform (sop/merge (map make (range n))) :uniform_scale opts.scale))\n  (graph g :context sop [(seed : int 3)]\n    (let* [; a local function\n           petal (fn [(i : int) [w h]]\n                   (sop/transform (sop/box :size [w h 0.1]) :rotate [0 0 (* i 0.5)]))\n           sizes (map (fn [k] (list (+ 0.1 (* k 0.01)) 0.5)) (range 12))\n           petals (map petal (range 12) sizes)\n           {:keys [a b]} {:a 1 :b (twice 2)}\n           [x y z] [a b 3]\n           kind (cond (< a 1) \"small\"\n                      (< a 5) \"medium\"\n                      :else \"large\")\n           steps (case seed 1 4 2 8 :else 12)\n           order (sort-by (fn [p] (- 0 (nth p 0))) sizes)\n           kept (filter (fn [p] (> (first p) 0.12)) (concat (take 3 sizes) (drop 9 sizes) (reverse (rest sizes))))\n           total (reduce + 0 (map (fn [p] (last p)) kept))\n           name (str \"floor_\" (add1 steps) \"_\" kind)\n           state (fold [{:keys [n acc]} (values :n 0 :acc 1.0)]\n                       [i (range steps)]\n                   (assoc {:n (+ n 1) :acc (* acc 0.9)} :acc (get {:acc (* acc 0.9)} :acc)))\n           ring2 (radial k 6 (sop/box :size (+ 0.1 (* k 0.01))))\n           faded ^:bypass (sop/subdivide ring2 :iterations 2)\n           shapes (all (sop/merge petals) faded (ring :n 3 :make (fn [i] (sop/box :size 0.05))) (sop/group_bounds (sop/box) :name name))\n           ; unused but checked\n           spare (count (list))]\n      ; the result\n      (sop/transform shapes :uniform_scale (* state.acc (* x (+ y (+ z total)))))))\n  ; trailing\n  )" in
    let printed = fst (Lisp.print (parse all)) in
    assert (fst (Lisp.print (parse printed)) = printed);
    let ws = check printed in
    let r = run ~record:true ws in
    assert (Array.length r.plan.nodes > 0);
    assert (ty_at ws [ "g"; "state" ] = "rec{n:int,acc:float}");
    assert (same (first_at r.records [ "g"; "[x y z]" ]) (Eval.Vec3 (1., 4., 3.)) || same (first_at r.records [ "g"; "[x y z]" ]) (ints [ 1; 4; 3 ])))

let () = (* t: live values and the split evaluation *)
  t "t drives parameters: the same network shape at every time, different values" (fun () ->
    let ws = check (sop "(let* [n 5] (sop/merge (for [i (range n)] (sop/box :size 0.1 :center [(+ i (sin t)) 0 0]))))") in
    let a = run ~time:0. ws and b = run ~time:1.2 ws in
    assert (count_of a "sop/box" = 5 && count_of b "sop/box" = 5);
    assert (a.plan.nodes <> b.plan.nodes);
    let centre (r : Eval.t) = arg (List.nth (nodes_of r "sop/box") 2) "center" in
    assert (centre a = Eval.Vec3 (2., 0., 0.) && centre b <> centre a));
  t "the Orrery case keeps its shape over time" (fun () ->
    let ws = check (read (Filename.concat cases "orrery.lisp")) in
    let n time = Array.length (run ~time ws).plan.nodes in
    assert (n 0. = n 3.1 && n 0. > 0));
  t "static leaves live terms as residuals, forced by time" (fun () ->
    let ws = check (sop "(let* [a (sop/box) s (* t 2) b (sop/transform a :translate [s 0 0] :uniform_scale 2)] b)") in
    let r = static ws in
    let n = List.hd (nodes_of r "sop/transform") in
    (match arg n "translate", arg n "uniform_scale" with
     | Eval.Residual res, Eval.Int 2 ->
         assert (Eval.is_live (arg n "translate"));
         assert (Eval.residual_eval res ~live:(Frame_input.at_time (3. )) = Ok (Eval.Vec3 (6., 0., 0.)));
         assert (Eval.residual_eval res ~live:(Frame_input.at_time (0.5 )) = Ok (Eval.Vec3 (1., 0., 0.)))
     | _ -> failwith "translate is not a residual");
    assert (Eval.force (arg n "translate") ~live:(Frame_input.at_time (1. )) = Ok (Eval.Vec3 (2., 0., 0.)));
    assert (Eval.force (Eval.Int 4) ~live:(Frame_input.at_time (1. )) = Ok (Eval.Int 4)));
  t "residuals: values, if on values, fold, fn, ref and shared chains" (fun () ->
    let at src time = match Eval.run ~time (check src) with
      | Ok r -> result r "g" | Error d -> failwith (Diagnostic.to_string d) in
    let live_of src = result (static (check src)) "g" in
    assert (Eval.is_live (live_of (value "(* t 2)")));
    assert (not (Eval.is_live (live_of (value "(* 3 2)"))));
    assert (same (at (value "(if (> (sin t) 0.5) 1 0.5)") 1.6) (Eval.Float 1.));
    assert (same (at (value "(if (> (sin t) 0.5) 1 0.5)") 0.) (Eval.Float 0.5));
    assert (same (at (value "(fold [a 0] [i (range 3)] (+ a t))") 2.) (Eval.Int 6) || same (at (value "(fold [a 0] [i (range 3)] (+ a t))") 2.) (Eval.Float 6.));
    assert (same (at (value "(let* [f (fn [x] (+ x t)) a (f 1)] (* a 2))") 3.) (Eval.Float 8.));
    assert (same (at "(workspace w (graph a :context value [(n : int 2)] (* n t)) (graph g :context value (+ (ref a) (ref a :n 5))))" 2.) (Eval.Float 14.));
    (* a long chain that reads its predecessor twice is shared, not exponential *)
    let chain = String.concat " " (List.init 40 (fun i -> Printf.sprintf "a%d (+ a%d a%d)" (i + 1) i i)) in
    assert (same (at (value ("(let* [a0 t " ^ chain ^ "] (* a40 0))")) 1.) (Eval.Float 0.));
    (* structure is identical at every time *)
    let ws = check (sop "(sop/merge (for [i (range 4)] (sop/box :center [(sin (+ t i)) 0 0])))") in
    let shape time = Array.map (fun (n : Eval.node) -> (n.kind, n.site, n.iter)) (run ~time ws).plan.nodes in
    assert (shape 0. = shape 5.3 && shape 0. = shape 100.))

let () =
  t "named argument routing preserves 16 and 17 distinct slots" (fun () ->
    List.iter (fun count ->
      let fields = List.init count (fun index -> "slot" ^ string_of_int index, Ty.Float) in
      let operator = { (Option.get (Op.find "sin" Context.value)) with
        name = "test/slots"; signature = {pos=fields;opt=[];rest=None;kw=[]};
        out = (fun _ -> Ty.Float); any_num = false; arithmetic = None;
        body = (fun ~live:_ ~node:_ args ->
          assert (List.map fst args = List.map fst fields);
          Value.Float (List.fold_left (fun sum (_, value) -> sum +. Value.num value) 0. args)) } in
      let source = value ("(test/slots " ^ String.concat " " (List.init count (fun index -> string_of_int index ^ ".0")) ^ ")") in
      let workspace = match Workspace.check ~ops:[operator] catalog (parse source) with
        | Some workspace, [] -> workspace | _, ds -> failwith (show_ds ds) in
      assert (result (static workspace) "g" = Eval.Float (float (count * (count - 1) / 2)))) [16;17]);
  t "repeated named inputs preserve separate nested plan identities" (fun () ->
    let source = sop ("(sop/merge " ^ String.concat " " (List.init 17 (fun index ->
      Printf.sprintf "(sop/box :center [%d 0 0])" index)) ^ ")") in
    let evaluation = static (check source) in
    let nodes = nodes_of evaluation "sop/box" in
    assert (List.length nodes = 17);
    let keys = List.map (fun (node : Eval.node) -> node.inst, node.site, node.iter) nodes in
    assert (List.length (List.sort_uniq compare keys) = 17));
  t "residual capture retains two used bindings out of twenty" (fun () ->
    let bindings = String.concat " " (List.init 20 (fun i -> Printf.sprintf "b%d %d.0" i i)) in
    let ws = check (value ("(let* [" ^ bindings ^ "] (+ (+ b3 b17) t))")) in
    let residual = match result (static ws) "g" with Eval.Residual r -> r | _ -> assert false in
    assert (List.map fst (Eval.Private.residual_view residual).bindings = ["b17"; "b3"]);
    assert (Eval.residual_eval residual ~live:(Frame_input.at_time 2.) = Ok (Eval.Float 22.)));
  t "residual capture retains a nested function's outer binding" (fun () ->
    let ws = check (value "(let* [outer 7.0 unused 99.0 mapped (map (fn [x] (+ x (+ outer t))) (array/range 2))] 0.0)") in
    let residual = match List.hd (List.assoc ["g"; "mapped"] (static ~record:true ws).records) |> snd with
      | Eval.Residual r -> r | _ -> assert false in
    assert (List.map fst (Eval.Private.residual_view residual).bindings = ["outer"]);
    assert (Eval.residual_eval residual ~live:(Frame_input.at_time 2.) = Ok (Eval.Float_array [|9.; 10.|])));
  t "free-name walk respects sequential bindings and nested captures" (fun () ->
    let ws = check (value "(let* [outside 7.0 unused 8.0] (let* [local (+ outside t) f (fn [x] (+ x (+ local outside))) mapped (map f (list 1.0 2.0))] 0.0))") in
    let body = (List.hd ws.graphs).body in
    let term = match body.node with Workspace.Let (_, term) -> term | _ -> assert false in
    assert (Eval.Private.free_names term = ["outside"]);
    let walks = Eval.Private.free_name_walks () in
    ignore (Eval.Private.free_names term);
    assert (Eval.Private.free_name_walks () = walks));
  t "free-name walk includes destructured sources and state initial values" (fun () ->
    let ws = check (value "(let* [source (list 3.0 4.0) initial 2.0] (let* [[x y] source total (state [s initial] (+ s t))] (+ x (+ y total))))") in
    let term = match (List.hd ws.graphs).body.node with Workspace.Let (_, term) -> term | _ -> assert false in
    assert (Eval.Private.free_names term = ["initial"; "source"]))

(* the compiled residuals against the interpreter: same bits at every time *)
let () =
  let rec same_bits (a : Eval.value) (b : Eval.value) = match a, b with
    | Float x, Float y -> Int64.equal (Int64.bits_of_float x) (Int64.bits_of_float y)
    | Vec3 (a, b, c), Vec3 (x, y, z) ->
        List.for_all2 (fun p q -> Int64.equal (Int64.bits_of_float p) (Int64.bits_of_float q)) [ a; b; c ] [ x; y; z ]
    | List xs, List ys -> Array.length xs = Array.length ys && Array.for_all2 same_bits xs ys
    | Record fs, Record gs | Struct (_, _, fs), Struct (_, _, gs) ->
        List.length fs = List.length gs && List.for_all2 (fun (n, x) (m, y) -> n = m && same_bits x y) fs gs
    | Fn _, Fn _ -> true
    | a, b -> a = b in
  let run_with fast ws time =
    Eval.Private.compile_residuals := fast;
    Fun.protect ~finally:(fun () -> Eval.Private.compile_residuals := true) (fun () -> ok (Eval.run ~time ws)) in
  let same_run ws time =
    let a = run_with true ws time and b = run_with false ws time in
    Array.length a.plan.nodes = Array.length b.plan.nodes
    && Array.for_all2 (fun (x : Eval.node) (y : Eval.node) ->
         x.kind = y.kind && x.site = y.site && List.for_all2 (fun (_, p) (_, q) -> same_bits p q) x.args y.args)
         a.plan.nodes b.plan.nodes
    && List.for_all2 (fun (_, p) (_, q) -> same_bits p q) a.results b.results in
  let times = [ 0.; 0.37; 1.9; 6.28; 100.25; -3. ] in
  t "compiled residuals are the interpreter's, bit for bit (fixtures)" (fun () ->
    List.iter (fun name ->
      let ws = check (read (Filename.concat cases (name ^ ".lisp"))) in
      List.iter (fun time -> assert (same_run ws time)) times) [ "wave"; "orrery"; "sunflower"; "bloom"; "tiles" ];
    let wave = check (read (Filename.concat cases "wave.lisp")) in
    let s = static wave in
    let forced = List.fold_left (fun n (node : Eval.node) ->
      List.fold_left (fun n (_, v) -> ignore (Eval.force v ~live:(Frame_input.at_time (1.5 ))); n + Eval.Private.compiled v) n node.args)
      0 (Array.to_list s.plan.nodes) in
    assert (forced > 0));
  t "compiled residuals: loops, ifs, lets, vectors and shared chains" (fun () ->
    List.iter (fun src ->
      let ws = check (value src) in
      List.iter (fun time -> assert (same_run ws time)) times)
      [ "(sum [k (range 6)] (/ (sin (* (+ t k) (+ (* 2 k) 1))) (+ (* 2 k) 1)))";
        "(let* [a 3 b (* a 2)] (+ (* t b) (mod t 0.7)))";
        "(if (> (sin t) 0.2) (pow t 2) (- 0 t))";
        "(let* [v [(* t 2) (+ t 1) (min t 3)]] (+ v.x v.y))";
        "(nth (for [i (range 4)] (* i t)) 2)";
        "(sum [x (for [i (range 4)] (+ (* i t) 1))] (* x 2))";
        "(sum [i (range 5)] (sum [j (range 3)] (* (+ t i) j)))";
        "(let* [a t a1 (+ a a) a2 (+ a1 a1) a3 (+ a2 a2)] (* a3 0.5))";
        "(let* [c (value/lerp [1 2 3] [t 0 1] 0.25)] c.z)";
        "(sum [i (range 0)] t)";
        "(/ t 0)" ]);
  t "an error in a compiled residual is the interpreter's" (fun () ->
    let ws = check (value "(sqrt (/ (- t 2) 0))") in
    let msg fast = Eval.Private.compile_residuals := fast;
      Fun.protect ~finally:(fun () -> Eval.Private.compile_residuals := true) (fun () ->
        match Eval.run ~time:1. ws with Ok _ -> "ok" | Error d -> Diagnostic.to_string d) in
    assert (msg true = msg false))

let () = (* value/rand: the bit-exact hash (iteration.md 2.2) *)
  t "hash: vectors ported from the study's hash" (fun () ->
    let h = Eval.hash in
    assert (h [] = 0.435769 && h [ 0. ] = 0.009611 && h [ 3.; 4.; 5. ] = 0.706664);
    assert (h [ 1.5; -2. ] = 0.622571 && h [ 7.; 0.; 1. ] = 0.089347 && h [ 1e10 ] = 0.736254);
    assert (h [ -0.25; 12345.678 ] = 0.068138 && h [ 1.; 2.; 3.; 4.; 5.; 6. ] = 0.659002);
    assert (h [ 0.000001 ] = 0.954845 && h [ 1e300 ] = h [ 0. ]);
    assert (h [ 3.; 4.; 5. ] = h [ 3.; 4.; 5. ]));
  t "hash: value/rand reads Int, Float and Bool keys" (fun () ->
    assert (g_value (value "(value/rand 3 4 5)") = Eval.Float 0.706664);
    assert (g_value (value "(value/rand 1.5 -2)") = Eval.Float 0.622571);
    assert (g_value (value "(value/rand true)") = Eval.Float (Eval.hash [ 1. ])))

(* ---- register rules that run: positive and negative ---- *)

let () = (* L3: driven bounds *)
  let src b = "(workspace w (graph g :context value [(n : int 100)] " ^ b ^ "))" in
  t "L3: a driven range over 4,096 is an error naming the count" (fun () ->
    err ~inputs:[ ("g", [ ("n", Eval.Int 5000) ]) ] (src "(count (range n))") "E_ITER_BOUND" ~text:"range 0‥5000 exceeds 4,096";
    err (src "(count (linspace 0 1 (* n 100)))") "E_ITER_BOUND" ~text:"linspace exceeds 4,096";
    is (src "(count (range 4096))") (Eval.Int 4096));
  t "L3: a driven zone over 4,096 iterations is an error naming the zone" (fun () ->
    err (src "(sum [x (range n) y (range n)] 1)") "E_ITER_BOUND" ~text:"g/@result runs more than 4,096 iterations";
    ());
  t "L3: exactly 4,096 iterations run" (fun () ->
    is "(workspace w (graph g :context value [(n : int 64)] (sum [x (range n) y (range n)] 1)))" (Eval.Int 4096));
  t "L3: concat over 4,096 elements is an error" (fun () ->
    err "(workspace w (graph g :context value [(n : int 3000)] (count (concat (range n) (range n)))))" "E_ITER_BOUND" ~text:"concat exceeds 4,096";
    is "(workspace w (graph g :context value [(n : int 2048)] (count (concat (range n) (range n)))))" (Eval.Int 4096));
  t "L3: the step budget stops a runaway" (fun () ->
    err "(workspace w (graph g :context value [(n : int 4000)] (sum [i (range n)] (sum [j (range n)] 1))))" "E_EVAL_BUDGET" ~text:"600000";
    is "(workspace w (graph g :context value [(n : int 40)] (sum [i (range n)] (sum [j (range n)] 1))))" (Eval.Int 1600))

let () = (* D3 at run time, nonfinite math, and the panel checks *)
  t "D3: a pattern longer than a driven list is an error" (fun () ->
    err "(workspace w (graph g :context value [(n : int 2)] (let* [[a b c] (take n (list 1 2 3))] a)))" "E_PATTERN" ~text:"needs 3 elements; the list has 2";
    is "(workspace w (graph g :context value [(n : int 3)] (let* [[a b c] (take n (list 1 2 3))] c)))" (Eval.Int 3));
  t "nonfinite math is an error naming the operator" (fun () ->
    err (value "(pow 10 999)") "E_NONFINITE" ~text:"pow produced a nonfinite value";
    err (value "(* (pow 10 300) (pow 10 300))") "E_NONFINITE" ~text:"*";
    is (value "(pow 10 3)") (Eval.Int 1000);
    (* the study's rules: divide and mod by zero give 0, sqrt takes the absolute value *)
    is (value "(/ 1 0)") (Eval.Int 0);
    is (value "(mod 5 0)") (Eval.Int 0);
    is (value "(sqrt -4)") (Eval.Int 2));
  t "ui/tile holds 1 to 16 panels, split takes horizontal or vertical" (fun () ->
    let ed b = "(workspace w (graph g :context editor [(n : int 3)] (ui/workspace " ^ b ^ ")))" in
    let tile = ed "(ui/tile (for [i (range n)] (ui/graph)))" in
    ignore (static (check tile));
    err ~inputs:[ ("g", [ ("n", Eval.Int 20) ]) ] tile "E_RANGE" ~text:"1–16";
    err ~inputs:[ ("g", [ ("n", Eval.Int 0) ]) ] tile "E_RANGE" ~text:"1–16";
    ignore (static (check (ed "(ui/split (str \"hori\" \"zontal\") (ui/graph) (ui/lisp))")));
    err (ed "(ui/split (str \"dia\" \"gonal\") (ui/graph) (ui/lisp))") "E_RANGE" ~text:"axis";
    err (ed "(ui/split-at \"vertical\" (* n 0.5) (ui/graph) (ui/lisp))") "E_RANGE" ~text:"ratio";
    ignore (static (check (ed "(ui/split-at \"vertical\" (* n 0.1) (ui/graph) (ui/lisp))")));
    (* settings ranges are the schema's: Editor_document.Contexts checks them when it lowers *)
    ignore (static (check "(workspace w (graph g :context settings [(f : int 60)] (settings/config :fps f)))")))

let () = (* C2: str formatting *)
  t "C2: ints plain, floats up to 4 decimals, no trailing zeros, ties away from zero" (fun () ->
    let s src = match bound (value ("(let* [z (str " ^ src ^ ")] 1)")) "z" with Eval.Text s -> s | _ -> failwith "not text" in
    assert (s "3" = "3" && s "-3" = "-3" && s "2.0" = "2" && s "100.0" = "100");
    assert (s "0.1" = "0.1" && s "0.30000000000000004" = "0.3" && s "1.23456" = "1.2346");
    List.iter (fun (x, want) -> if s x <> want then failwith (x ^ " prints " ^ s x ^ ", want " ^ want))
      [ ("0.03125", "0.0313"); ("-0.03125", "-0.0313"); ("0.00005", "0.0001"); ("0.00015", "0.0001");
        ("1.00005", "1.0001"); ("0.09375", "0.0938"); ("0.15625", "0.1563"); ("2.00005", "2");
        ("0.00035", "0.0003"); ("0.000125", "0.0001"); ("123456789.123456", "123456789.1235") ];
    assert (s "-0.00001" = "0" && s "0.99999" = "1" && s "12345.6789" = "12345.6789");
    assert (s "true false" = "truefalse" && s "[1 2.5 3]" = "[1 2.5 3]" && s "(list)" = "[]");
    assert (s "{:a 1.5 :b [1 2 3]}" = "{:a 1.5 :b [1 2 3]}" && s "\"x\" 1" = "x1"));
  t "C2: what str prints for a vec3, a list of vec3 and a record of lists" (fun () ->
    let s src = match bound (value ("(let* [z (str " ^ src ^ ")] 1)")) "z" with Eval.Text s -> s | _ -> failwith "not text" in
    assert (s "[1 0.5 0.33333]" = "[1 0.5 0.3333]");
    assert (s "(list [1 2 3] [4 5 6])" = "[[1 2 3] [4 5 6]]");
    assert (s "{:p (list 1 2) :q {:r true}}" = "{:p [1 2] :q {:r true}}"))

let () = (* L2, L4, L5: product order, empty results, ints *)
  t "L2: three clauses, nested products and dependent ranges" (fun () ->
    assert (same (bound (value "(let* [z (for [a (range 2) b (range 2) c (range 2)] (+ (* a 4) (+ (* b 2) c)))] 1)") "z") (ints [ 0; 1; 2; 3; 4; 5; 6; 7 ]));
    assert (same (bound (value "(let* [z (for [a (range 3) b (range a 3)] (+ (* a 10) b))] 1)") "z") (ints [ 0; 1; 2; 11; 12; 22 ])));
  t "L4: empty loops" (fun () ->
    is (value "(count (for [i (range 0)] i))") (Eval.Int 0);
    let r = run (check (sop "(sop/merge (for [i (range 0)] (sop/box)))")) in
    (* merge of nothing: one merge node with no inputs *)
    assert (count_of r "sop/merge" = 1 && (List.hd (nodes_of r "sop/merge")).args = []));
  t "L5: range yields ints, linspace floats including both ends" (fun () ->
    assert (bound (value "(let* [z (range 3)] 1)") "z" = ints [ 0; 1; 2 ]);
    assert (bound (value "(let* [z (linspace 0 1 3)] 1)") "z" = Eval.List [| Float 0.; Float 0.5; Float 1. |]);
    assert (bound (value "(let* [z (linspace 2 5 1)] 1)") "z" = Eval.List [| Float 2. |]);
    is (value "(count (range 2 6))") (Eval.Int 4))

let () = (* L6, L14, F3: accumulators, ref overrides, sum types *)
  t "L6: an int seed does not round a float body; sum keeps int, float, vec3" (fun () ->
    assert (g_value (value "(fold [a 1] [i (range 3)] (* a 2.5))") = Eval.Float 15.625);
    assert (g_value (value "(fold [a 0] [i (range 3)] (+ a 0.5))") = Eval.Float 1.5);
    assert (g_value (value "(fold [a 0] [i (range 3)] (+ a i))") = Eval.Int 3);
    assert (bound (value "(let* [z (scan [a 0] [i (range 2)] (+ a 0.5))] 1)") "z" = Eval.List [| Float 0.5; Float 1. |]);
    assert (bound (value "(let* [z (sum [i (range 3)] [i 0 1])] 1)") "z" = Eval.Vec3 (3., 0., 3.));
    assert (g_value (value "(sum [i (range 3)] 0.5)") = Eval.Float 1.5);
    assert (g_value (value "(sum [i (range 3)] i)") = Eval.Int 3));
  t "L14: ref overrides are cached by value and coerced to the input type" (fun () ->
    let ws = check "(workspace w (graph a :context value [(n : float 2)] (* n 3)) (graph g :context value (+ (ref a :n 5) (+ (ref a :n 5) (ref a :n 5.0)))))" in
    let r = static ws in
    assert (same (result r "g") (Eval.Int 45));
    (* a, then a with n=5 once (5 and 5.0 are the same float) *)
    assert (Array.length r.plan.instances = 3));
  t "L14: a geometry ref makes one shared instance per override tuple" (fun () ->
    let ws = check "(workspace w (graph a :context sop [(n : int 2)] (sop/box :size n)) (graph g :context sop (sop/merge (ref a) (ref a :n 3) (ref a :n 3) (ref a))))" in
    let r = static ws in
    (* a with its default, a with n=3 *)
    assert (Array.length r.plan.instances = 3);
    let boxes = nodes_of r "sop/box" in
    assert (List.map (fun (n : Eval.node) -> n.inst) boxes = [ 0; 2 ]);
    let merge = List.hd (nodes_of r "sop/merge") in
    (* the two refs with the same tuple wire the same node *)
    match merge.args with
    | [ (_, Eval.Deferred (Ty.Named "geometry", a)); (_, Deferred (Ty.Named "geometry", b)); (_, Deferred (Ty.Named "geometry", c)); (_, Deferred (Ty.Named "geometry", d)) ] -> assert (a = d && b = c && a <> b)
    | _ -> failwith "merge inputs");
  t "L14: inputs override from OCaml and are coerced" (fun () ->
    let ws = check "(workspace w (graph g :context value [(n : float 2)] (* n 3)))" in
    let r = ok (Eval.static ~inputs:[ ("g", [ ("n", Eval.Int 4) ]) ] ws) in
    assert (result r "g" = Eval.Float 12.);
    assert ((r.plan.instances.(0)).inputs = [ ("n", Eval.Float 4.) ]))

let () = (* W5: records are bounded, per path and iteration tuple *)
  t "W5: at most 4,096 records per path; geometry as references" (fun () ->
    let rs = records (value "(sum [i (range 100)] (sum [j (range 100)] (let* [x (* i j)] x)))") in
    let longest = List.fold_left (fun m (_, l) -> max m (List.length l)) 0 rs in
    assert (longest = 4096);
    let inner = List.find (fun (p, l) -> List.length l = 4096 && List.mem "x" p) rs in
    assert (List.length (snd inner) = 4096);
    let rs = records (sop "(let* [a (sop/box)] a)") in
    assert (first_at rs [ "g"; "a" ] = Eval.Deferred (Ty.geometry, 0));
    (* nothing is recorded unless asked *)
    assert ((run (check (value "(sum [i (range 3)] i)"))).records = []))

let () = (* the Wave fixture's sop/curve: a plan node whose points are live *)
  t "Wave: sop/curve nodes carry their points, live through t" (fun () ->
    let ws = check (read (Filename.concat cases "wave.lisp")) in
    let s = static ws in
    let curves = nodes_of s "sop/curve" in
    assert (List.length curves = 6);
    (match arg (List.hd curves) "points" with
     | Eval.List pts -> assert (Array.length pts = 90 && Eval.is_live (Eval.List pts))
     | _ -> failwith "points");
    let r = run ~time:0.5 ws in
    (match arg (List.hd (nodes_of r "sop/curve")) "points" with
     | Eval.List pts -> assert (Array.for_all (function Eval.Vec3 _ -> true | _ -> false) pts)
     | _ -> failwith "points"))
let () = (* W8: a loop over geometry is one zone node with a template body *)
  t "W8: for over point_list is a zone node; the body is a template" (fun () ->
    let ws = check (sop "(let* [g (sop/grid) spots (sop/scatter g :count 5 :seed 3) dot (sop/box)
      dots (for [p (sop/point_list spots :key \"id\")] (sop/transform dot :translate p))
      result (sop/merge g dots)] result)") in
    let s = static ws in
    let zone = List.hd (nodes_of s "zone/points") in
    let lo, hi = match arg zone "lo", arg zone "hi" with Eval.Int a, Eval.Int b -> a, b | _ -> failwith "range" in
    assert (hi - lo = 1);
    assert (arg zone "key" = Eval.Text "id");
    (* the element is a residual, forced with the element bound *)
    let tr = List.hd (nodes_of s "sop/transform") in
    let p = arg tr "translate" in
    assert (Eval.is_live p);
    let key = Eval.element_key [ "g"; "dots" ] in
    (match Eval.force ~elems:[ (key, Eval.Vec3 (1., 2., 3.)) ] p ~live:(Frame_input.at_time (0. )) with
     | Ok (Eval.Vec3 (1., 2., 3.)) -> ()
     | _ -> failwith "element not bound");
    assert (Result.is_error (Eval.force p ~live:(Frame_input.at_time (0. ))));
    (* not a list: only sop/merge takes it, and the structure cannot read the element *)
    err (sop "(let* [g (sop/grid) n (count (for [p (sop/point_list g)] (sop/box)))] g)") "E_TYPE";
    err (sop "(let* [g (sop/grid)] (sop/merge (for [p (sop/point_list g)] (if (> p.x 0) (sop/box) (sop/grid)))))") "E_ZONE";
    err (sop "(let* [g (sop/grid)] (sop/merge (for [p (sop/point_list g) i (range 2)] (sop/box))))") "E_ZONE")

let () = (* register L16: :skip leaves iterations out; the others keep their tuples *)
  let nested l = Eval.List (Array.of_list (List.map ints l)) in
  let zs src want = if not (same (bound (value ("(let* [z " ^ src ^ "] 1)")) "z") want) then failwith src in
  t "skip: a for leaves out the listed iterations" (fun () ->
    zs "(for [i (range 5)] :skip [1 3] i)" (ints [ 0; 2; 4 ]);
    zs "(for [i (range 5)] :skip [[1] [3]] i)" (ints [ 0; 2; 4 ]);
    is (value "(count (for [i (range 5)] :skip [0 1 2 3 4] i))") (Eval.Int 0));
  t "skip: a product skips by its flat index, last clause fastest" (fun () ->
    zs "(for [i (range 2) j (range 3)] :skip [4] (+ (* 10 i) j))" (ints [ 0; 1; 2; 10; 12 ]));
  t "skip: a tuple is the enclosing iterations, then this loop's" (fun () ->
    zs "(for [i (range 3)] (for [j (range 2)] :skip [[1 0] [2 1]] (+ (* 10 i) j)))"
      (nested [ [ 0; 1 ]; [ 11 ]; [ 20 ] ]);
    zs "(for [i (range 2)] (for [j (range 2)] (for [k (range 2)] :skip [[1 0 1] [0 1 0]] (+ (* 100 i) (+ (* 10 j) k)))))"
      (Eval.List [| Eval.List [| ints [ 0; 1 ]; ints [ 11 ] |]; Eval.List [| ints [ 100 ]; ints [ 110; 111 ] |] |]));
  t "skip: a skipped iteration makes no plan node, the others keep site and tuple" (fun () ->
    let all = run (check (sop "(sop/merge (for [i (range 4)] (sop/box :size (+ 1 i))))")) in
    let some = run (check (sop "(sop/merge (for [i (range 4)] :skip [2] (sop/box :size (+ 1 i))))")) in
    let keys r = List.map (fun (n : Eval.node) -> (n.site, n.iter)) (nodes_of r "sop/box") in
    assert (count_of all "sop/box" = 4 && count_of some "sop/box" = 3);
    assert (keys some = List.filter (fun (_, it) -> it <> [ 2 ]) (keys all));
    (* the boxes that stay are the same plan nodes by key, with the same arguments *)
    List.iter (fun (n : Eval.node) ->
      let twin = List.find (fun (m : Eval.node) -> m.site = n.site && m.iter = n.iter) (nodes_of all "sop/box") in
      assert (n.args = twin.args)) (nodes_of some "sop/box"));
  t "skip: the loop variable is still recorded at a skipped iteration; the body is not" (fun () ->
    let rs = records (value "(let* [xs (for [i (range 4)] :skip [2] (* i 2))] (count xs))") in
    assert (List.length (recs rs [ "g"; "xs"; ":i" ]) = 4);
    assert (List.map fst (recs rs [ "g"; "xs"; "@result" ]) = [ [ 0 ]; [ 1 ]; [ 3 ] ]));
  t "skip: a scene/merge leaves out the arguments at the listed tuples" (fun () ->
    let scene body = "(workspace w (graph s :context scene " ^ body ^ "))" in
    let r body = List.assoc "s" (run (check (scene body))).results in
    let args = function Eval.Struct (_, _, a) -> List.length a | _ -> -1 in
    assert (args (r "(scene/merge (scene/light) (scene/light) (scene/light))") = 3);
    assert (args (r "(scene/merge (scene/light) (scene/light) (scene/light) :skip [1])") = 2);
    assert (args (r "(scene/merge (scene/light) (scene/light) :skip [[0] [1]])") = 0);
    (* inside a loop the tuple starts with the loop's iteration *)
    (match r "(scene/merge (for [i (range 2)] (scene/merge (scene/light) (scene/light) :skip [[1 0]])))" with
     | Eval.Struct (_, _, [ (_, a); (_, b) ]) -> assert (args a = 2 && args b = 1)
     | _ -> failwith "the merge of merges"))

let () =
  t "live packed accumulators defer the complete iteration" (fun () ->
    List.iter (fun body ->
      let workspace = check (value body) in
      let v = result (static workspace) "g" in
      (match v with
       | Eval.Residual r -> (match (Eval.Private.residual_view r).term.node with
           | Workspace.Loop {kind = `Fold; _} | Workspace.Hof (`Reduce, _) -> ()
           | _ -> failwith "accumulator was unrolled into per-element residuals")
       | _ -> failwith "live accumulator did not defer");
      assert (Eval.force v ~live:(Frame_input.at_time 0.5) = Ok (Eval.Float 1025.5)))
      ["(fold [a 0] [x (array/range 2051)] (+ a t))";
       "(reduce (fn [a x] (+ a t)) 0.0 (array/range 2051))"]);
  t "image constructors preserve live arguments in deferred image nodes" (fun () ->
    List.iter (fun (body, field, expected) ->
      let evaluated = static (check ("(workspace w (graph drawing :context draw (draw/background \"#000000\"))" ^
        " (graph g :context image " ^ body ^ "))")) in
      let id = match result evaluated "g" with
        | Eval.Deferred (ty, id) when ty = Ty.image -> id
        | _ -> failwith "live image constructor did not create a deferred image node" in
      let argument = List.assoc field evaluated.plan.nodes.(id).args in
      assert (Eval.is_live argument);
      assert (Eval.force argument ~live:(Frame_input.at_time 2.) = Ok expected))
      ["(image/noise :width 2 :height 2 :frequency (+ 0.3 t))", "frequency", Eval.Float 2.3;
       "(image/load (if (< t 1.0) \"before.png\" \"after.png\"))", "path", Eval.Text "after.png";
       "(image/render (ref drawing) :width (if (< t 1.0) 2 3) :height 2)", "width", Eval.Int 3]);
  t "operator function values use declaration argument names" (fun () ->
    is (value "(let* [lengths (map array/count (list (array/float 2) (array/float 4)))] (+ (first lengths) (last lengths)))")
      (Eval.Int 6));
  if !failed <> [] then begin
    List.iter (fun (n, e) -> prerr_endline ("FAIL " ^ n ^ ": " ^ e)) (List.rev !failed);
    exit 1
  end;
  Printf.printf "Flow workspace eval: %d value cases pass\n" !passed

let () = (* report.md L10, L18, L20: one bypass index, nonfinite guards, whole indices *)
  t "bypass passes the first positional input, after keyword pairs, for every call" (fun () ->
    is (value "(let* [f (fn [a b] (+ a b))] ^:bypass (f 2 3))") (Eval.Int 2));
  t "nonfinite values are refused where they are made" (fun () ->
    List.iter (fun source ->
      match Eval.static (check ("(workspace w (graph g :context value " ^ source ^ "))")) with
      | Error d -> assert (d.code = "E_NONFINITE")
      | Ok _ -> failwith (source ^ " was accepted"))
      [ "(value/lerp 0 (pow 10 308) 100)"; "(value/polar (pow 10 308) 0 0)"; "(* [1 2 3] (* (pow 10 308) 10))" ]);
  t "nth takes a whole index" (fun () ->
    match Eval.static (check "(workspace w (graph g :context value (nth (list 1 2 3 4) 2.5)))") with
    | Error d -> assert (d.code = "E_LIST_RANGE")
    | Ok _ -> failwith "nth 2.5 read an element")
