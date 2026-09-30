(* W3: every graph gesture of the study as a pure rewrite of the workspace
   text: apply the op, compare the printed text.  A refused edit changes
   nothing. *)
open Flow_sop
module S = Flow.Syntax
module E = Flow_edit

let fail message = failwith ("test_workspace_edit: " ^ message)
let check condition message = if not condition then fail message
let read path = In_channel.with_open_bin path In_channel.input_all
let cases = "../specification/workspace/cases"
let catalog = Editor_document.Contexts.catalog ~version:1 Sop_catalog.Editor.factories |> Result.get_ok

let parse text = match S.parse text with
  | Ok forms -> forms | Error d -> fail (Flow.Diagnostic.to_string d)
let canon forms = fst (Flow.Lisp.print forms)
let norm text = canon (parse text)

let apply text op =
  match E.apply catalog (parse text) op with
  | Ok forms -> canon forms
  | Error d -> fail (E.label op ^ ": " ^ Flow.Diagnostic.to_string d)

let same name text op expected =
  let got = try apply text op with Failure m -> fail (name ^ ": " ^ m) and want = norm expected in
  if got <> want then fail (Printf.sprintf "%s\n--- got\n%s--- want\n%s" name got want)

let refused ?(code = "") name text op =
  match E.apply catalog (parse text) op with
  | Ok forms -> fail (name ^ " was accepted:\n" ^ canon forms)
  | Error d -> check (code = "" || d.code = code) (name ^ ": code " ^ d.code ^ " message " ^ d.message)

let has text sub =
  let n = String.length sub in
  let rec at i = i + n <= String.length text && (String.sub text i n = sub || at (i + 1)) in
  at 0
let g body = "(workspace w\n  (graph g :context sop [(n : int 4)]\n    " ^ body ^ "))"
let v body = "(workspace w\n  (graph g :context value [(n : int 4)]\n    " ^ body ^ "))"
let base = g "(let* [a (sop/uv_sphere :radius 0.5)\n           b (sop/transform a :translate [1 2 3])\n           c (sop/subdivide b :iterations 1)]\n      c)"
let num s = S.make (S.Num s)
let sym s = S.make (S.Sym s)
let node l = "g" :: l

let part1 () = (* scrub *)
  same "scrub" base (E.Set_arg { node = node [ "a" ]; key = Kw "radius"; sub = []; value = num "0.8" })
    (g "(let* [a (sop/uv_sphere :radius 0.8) b (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)");
  same "vector component" base (E.Set_arg { node = node [ "b" ]; key = Kw "translate"; sub = [ 1 ]; value = num "9" })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :translate [1 9 3]) c (sop/subdivide b :iterations 1)] c)");
  same "missing keyword is added" base (E.Set_arg { node = node [ "b" ]; key = Kw "scale"; sub = []; value = num "2" })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :translate [1 2 3] :scale 2) c (sop/subdivide b :iterations 1)] c)");
  let scrub v = E.Set_arg { node = node [ "a" ]; key = Kw "radius"; sub = []; value = num v } in
  check (E.gesture (scrub "1") = E.gesture (scrub "2") && E.gesture (scrub "1") <> None) "scrub merges into one gesture";
  check (E.gesture (E.Toggle_bypass { node = node [ "a" ] }) = None) "other ops do not merge";
  refused ~code:"E_UNKNOWN_PARAM" "unknown keyword" base
    (E.Set_arg { node = node [ "a" ]; key = Kw "nope"; sub = []; value = num "1" })

let part2 () = (* connect, disconnect, input defaults *)
  let fwd = g "(let* [a (sop/uv_sphere) c (sop/subdivide a) b (sop/transform a)] c)" in
  same "connect reorders" fwd (E.Connect { node = node [ "c" ]; key = Pos 0; src = "b"; iter = false })
    (g "(let* [a (sop/uv_sphere) b (sop/transform a) c (sop/subdivide b)] c)");
  refused ~code:"E_GRAPH_CYCLE" "connect cycle" (g "(let* [a (sop/transform nil) b (sop/transform a)] b)")
    (E.Connect { node = node [ "a" ]; key = Pos 0; src = "b"; iter = false });
  same "connect to result" fwd (E.Connect { node = node [ "@result" ]; key = Whole; src = "b"; iter = false })
    (g "(let* [a (sop/uv_sphere) c (sop/subdivide a) b (sop/transform a)] b)");
  let loop = g "(let* [ring (for [i (range n)] (sop/uv_sphere :radius 0.5)) m (sop/merge ring)] m)" in
  same "iteration step" loop (E.Connect { node = [ "g"; "ring"; "@result" ]; key = Kw "radius"; src = "i"; iter = true })
    (g "(let* [ring (for [i (range n)] (sop/uv_sphere :radius (* i 0.5))) m (sop/merge ring)] m)");
  same "iteration by name" loop (E.Connect { node = [ "g"; "ring"; "@result" ]; key = Kw "radius"; src = "i"; iter = false })
    (g "(let* [ring (for [i (range n)] (sop/uv_sphere :radius i)) m (sop/merge ring)] m)");
  same "disconnect keyword" (g "(let* [k 0.4 a (sop/uv_sphere :radius k)] a)")
    (E.Disconnect { node = node [ "a" ]; key = Kw "radius"; fallback = None })
    (g "(let* [k 0.4 a (sop/uv_sphere)] a)");
  same "disconnect positional with fallback" base
    (E.Disconnect { node = node [ "b" ]; key = Pos 0; fallback = E.default_for Flow.Ty.Geometry "geo" })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform nil :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)");
  same "input default" base (E.Set_input_default { form = "g"; input = "n"; value = num "8" })
    (String.concat "" [ "(workspace w (graph g :context sop [(n : int 8)] (let* [a (sop/uv_sphere :radius 0.5) ";
      "b (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)))" ]);
  refused "missing input" base (E.Set_input_default { form = "g"; input = "zz"; value = num "8" })

let part3 () = (* unfold and fold round trip *)
  let nested = g "(let* [b (sop/transform (sop/uv_sphere :radius 0.5) :translate [1 2 3])] b)" in
  let unfolded = g "(let* [uv_sphere (sop/uv_sphere :radius 0.5) b (sop/transform uv_sphere :translate [1 2 3])] b)" in
  same "unfold" nested (E.Unfold { node = node [ "b" ]; key = Pos 0; sub = [] }) unfolded;
  same "fold" unfolded (E.Fold_into { node = node [ "uv_sphere" ] }) nested;
  same "unfold a loop" (g "(let* [m (sop/merge (for [i (range 3)] (sop/uv_sphere)))] m)")
    (E.Unfold { node = node [ "m" ]; key = Pos 0; sub = [] })
    (g "(let* [m_each (for [i (range 3)] (sop/uv_sphere)) m (sop/merge m_each)] m)");
  same "unfold part of a vector" (g "(let* [b (sop/transform nil :translate [(+ 1 2) 0 0])] b)")
    (E.Unfold { node = node [ "b" ]; key = Kw "translate"; sub = [ 0 ] })
    (g "(let* [node (+ 1 2) b (sop/transform nil :translate [node 0 0])] b)");
  same "fold into the result" (g "(let* [a (sop/uv_sphere) b (sop/transform a)] b)") (E.Fold_into { node = node [ "b" ] })
    (g "(let* [a (sop/uv_sphere)] (sop/transform a))");
  refused "fold needs one use" (g "(let* [a (sop/uv_sphere) b (sop/transform a) c (sop/merge a b)] c)")
    (E.Fold_into { node = node [ "a" ] });
  refused "unfold an atom" base (E.Unfold { node = node [ "c" ]; key = Kw "iterations"; sub = [] })

let part4 () = (* repeat, iterate *)
  let two = g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :scale 0.8)] b)" in
  same "repeat geometry" two (E.Wrap { nodes = [ node [ "a" ] ]; loop = For })
    (g "(let* [a_each (for [i (range 6)] (sop/uv_sphere :radius 0.5)) a (sop/merge a_each) b (sop/transform a :scale 0.8)] b)");
  same "repeat numbers" (g "(let* [x (+ 1 2) y (* x 2) a (sop/uv_sphere :radius y)] a)")
    (E.Wrap { nodes = [ node [ "x" ] ]; loop = For })
    (g "(let* [x (sum [i (range 6)] (+ 1 2)) y (* x 2) a (sop/uv_sphere :radius y)] a)");
  same "iterate" two (E.Wrap { nodes = [ node [ "b" ] ]; loop = Fold })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (fold [prev a] [i (range 4)] (sop/transform prev :scale 0.8))] b)");
  refused "iterate needs an input to feed back" (g "(let* [a (sop/uv_sphere)] a)")
    (E.Wrap { nodes = [ node [ "a" ] ]; loop = Fold });
  refused "repeat needs one result" (g "(let* [a (sop/uv_sphere) b (sop/transform a) c (sop/merge a b)] c)")
    (E.Wrap { nodes = [ node [ "a" ]; node [ "b" ] ]; loop = For });
  same "repeat two bindings" (g "(let* [a (sop/uv_sphere) b (sop/transform a) c (sop/merge b)] c)")
    (E.Wrap { nodes = [ node [ "a" ]; node [ "b" ] ]; loop = For })
    (g "(let* [b_each (for [i (range 6)] (let* [a (sop/uv_sphere) b (sop/transform a)] b)) b (sop/merge b_each) c (sop/merge b)] c)")

let part5 () = (* hoist *)
  let src = g "(let* [ring (for [i (range n)] (let* [u (/ i n) k (sop/uv_sphere :radius 0.2) s (sop/transform k :translate [u 0 0])] s)) m (sop/merge ring)] m)" in
  same "hoist" src (E.Hoist { node = [ "g"; "ring"; "k" ] })
    (g "(let* [k (sop/uv_sphere :radius 0.2) ring (for [i (range n)] (let* [u (/ i n) s (sop/transform k :translate [u 0 0])] s)) m (sop/merge ring)] m)");
  refused "hoist a loop-dependent node" src (E.Hoist { node = [ "g"; "ring"; "u" ] });
  refused "hoist from the top" src (E.Hoist { node = node [ "m" ] });
  same "hoist the only binding" (g "(let* [ring (for [i (range 3)] (let* [k (sop/uv_sphere)] k)) m (sop/merge ring)] m)")
    (E.Hoist { node = [ "g"; "ring"; "k" ] })
    (g "(let* [k (sop/uv_sphere) ring (for [i (range 3)] k) m (sop/merge ring)] m)")

let part6 () = (* rename keeps notes and rewrites uses; layout keys follow *)
  let src = g "(let* [a (sop/uv_sphere :radius 0.5)\n           ; the moved one\n           b (sop/transform a :translate [1 2 3])] b)" in
  let want = g "(let* [a (sop/uv_sphere :radius 0.5)\n           ; the moved one\n           moved (sop/transform a :translate [1 2 3])] moved)" in
  same "rename" src (E.Rename { node = node [ "b" ]; to_ = "moved" }) want;
  same "rename a source" (g "(let* [a (sop/uv_sphere) b (sop/transform a)] b)") (E.Rename { node = node [ "a" ]; to_ = "ball" })
    (g "(let* [ball (sop/uv_sphere) b (sop/transform ball)] b)");
  refused "rename to a used name" src (E.Rename { node = node [ "b" ]; to_ = "a" });
  refused "rename to an operator" src (E.Rename { node = node [ "b" ]; to_ = "sin" });
  refused "rename to a bad name" src (E.Rename { node = node [ "b" ]; to_ = "Two" });
  let op = E.Rename { node = [ "g"; "ring" ]; to_ = "petals" } in
  check (E.remap op [ "g"; "ring"; "u" ] = Some [ "g"; "petals"; "u" ]) "rename remaps nested layout keys";
  check (E.remap op [ "g"; "other" ] = Some [ "g"; "other" ]) "rename leaves other keys";
  check (E.remap (E.Hoist { node = [ "g"; "ring"; "k" ] }) [ "g"; "ring"; "k" ] = Some [ "g"; "k" ]) "hoist remaps";
  check (E.remap (E.Delete_nodes { nodes = [ [ "g"; "a" ] ] }) [ "g"; "a" ] = None) "delete drops layout keys"

let part7 () = (* functions and macros *)
  same "make lambda" base (E.Make_local_fn { nodes = [ node [ "b" ] ] })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b_fn (fn [in_a] (sop/transform in_a :translate [1 2 3])) b (b_fn a) c (sop/subdivide b :iterations 1)] c)");
  let made = String.concat "" [ "(workspace w\n  (defmacro shifted [dx a] `(sop/transform ~a :translate [~dx 2 3]))\n";
    "  (graph g :context sop [(n : int 4)] (let* [a (sop/uv_sphere :radius 0.5) b (shifted 1 a) c (sop/subdivide b :iterations 1)] c)))" ] in
  same "make macro" base (E.Make_macro { nodes = [ node [ "b" ] ]; name = "shifted"; holes = [ [ 3; 0 ], "dx" ] }) made;
  same "inline macro" made (E.Inline_macro { node = node [ "b" ] })
    (String.concat "" [ "(workspace w\n  (defmacro shifted [dx a] `(sop/transform ~a :translate [~dx 2 3]))\n";
      "  (graph g :context sop [(n : int 4)] (let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)))" ]);
  let lits = E.literals (S.make (S.List [ sym "sop/transform"; sym "a"; S.make (S.Kw "translate");
    S.make (S.Vec [ num "1"; num "2"; num "3" ]) ])) in
  check (List.map fst lits = [ [ 3; 0 ]; [ 3; 1 ]; [ 3; 2 ] ]) "literals of an expression";
  refused "macro name taken" base (E.Make_macro { nodes = [ node [ "b" ] ]; name = "range"; holes = [] });
  (* several bindings: their own names become fresh names in the template *)
  let two = g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a) c (sop/subdivide b)] c)" in
  let out = apply two (E.Make_macro { nodes = [ node [ "a" ]; node [ "b" ] ]; name = "pair"; holes = [ [ 1; 1; 2 ], "r" ] }) in
  check (has out "a#") ("multi-binding macro uses fresh names:\n" ^ out)

(* W9: what the make-macro dialog answers is one Make_macro, and its draft lists the holes' candidates *)
let dialog () =
  let src = parse base in
  let draft = match E.macro_draft src [ node [ "b" ] ] with
    | Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d) in
  check (List.map fst draft.literals = [ [ 3; 0 ]; [ 3; 1 ]; [ 3; 2 ] ] && draft.free = [ "a" ]
         && draft.name = "b_tpl") "the draft of b";
  let op = E.macro_op draft ~nodes:[ node [ "b" ] ] ~name:"shifted" [| true, "dx"; false, "dy"; true, "dz" |] in
  check (op = E.Make_macro { nodes = [ node [ "b" ] ]; name = "shifted"; holes = [ [ 3; 0 ], "dx"; [ 3; 2 ], "dz" ] })
    "unticked literals are not holes";
  let out = apply base op in
  check (has out "(defmacro shifted [dx dz a]" && has out "b (shifted 1 3 a)") ("the dialog's macro:\n" ^ out);
  (match E.macro_draft src [ node [ "b" ]; node [ "@result" ] ] with
   | Error d -> check (d.code = "E_EDIT") "a result cannot be templated"
   | Ok _ -> fail "a result was templated");
  (* notes: typing merges into one history entry per node *)
  check (E.gesture (E.Set_note { node = node [ "b" ]; text = "x" }) = E.gesture (E.Set_note { node = node [ "b" ]; text = "xy" })
         && E.gesture (E.Set_note { node = node [ "b" ]; text = "x" }) <> None
         && E.gesture (E.Set_note { node = node [ "b" ]; text = "x" }) <> E.gesture (E.Set_note { node = node [ "c" ]; text = "x" }))
    "note typing is one gesture per node"

let part8 () = (* bypass and notes *)
  let by = apply base (E.Toggle_bypass { node = node [ "b" ] }) in
  check (norm by = norm (g "(let* [a (sop/uv_sphere :radius 0.5) b ^:bypass (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)")) "bypass on";
  same "bypass off" by (E.Toggle_bypass { node = node [ "b" ] }) base;
  refused "bypass a scope" (g "(let* [a (let* [x 1] x)] (sop/uv_sphere))") (E.Toggle_bypass { node = node [ "a" ] });
  let noted = apply base (E.Set_note { node = node [ "b" ]; text = "the moved one\nsecond line" }) in
  check (norm noted = norm (g "(let* [a (sop/uv_sphere :radius 0.5)\n           ; the moved one\n           ; second line\n           b (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1)] c)")) "note";
  same "note removed" noted (E.Set_note { node = node [ "b" ]; text = " " }) base;
  (* a note travels with its binding through a rename and a reorder *)
  let renamed = apply noted (E.Rename { node = node [ "b" ]; to_ = "moved" }) in
  check (has renamed "; the moved one\n") "note survives rename";
  let fwd = g "(let* [a (sop/uv_sphere)\n           ; keep me\n           c (sop/subdivide a)\n           b (sop/transform a)] c)" in
  let moved = apply fwd (E.Connect { node = node [ "c" ]; key = Pos 0; src = "b"; iter = false }) in
  check (norm moved = norm (g "(let* [a (sop/uv_sphere) b (sop/transform a)\n           ; keep me\n           c (sop/subdivide b)] c)")) "note follows its binding on reorder";
  let root_note = apply base (E.Set_note { node = [ "g" ]; text = "the graph" }) in
  check (has root_note "; the graph\n  (graph g") "graph note prints";
  let with_result = apply base (E.Set_note { node = node [ "@result" ]; text = "out" }) in
  check (has with_result "; out\n      c)") "result note"

let part9 () = (* lists and records *)
  let list = v "(let* [xs (list 0.2 0.4 0.6) k (count xs)] k)" in
  same "list continues a float step" list (E.Add_item { node = node [ "xs" ] })
    (v "(let* [xs (list 0.2 0.4 0.6 0.8) k (count xs)] k)");
  same "list continues an int step" (v "(let* [xs (list 1 2 3) k (count xs)] k)") (E.Add_item { node = node [ "xs" ] })
    (v "(let* [xs (list 1 2 3 4) k (count xs)] k)");
  same "list of one repeats" (v "(let* [xs (list 5) k (count xs)] k)") (E.Add_item { node = node [ "xs" ] })
    (v "(let* [xs (list 5 5) k (count xs)] k)");
  same "text adds a part" (v "(let* [s (str \"a\" n) k (count (list 1))] k)") (E.Add_item { node = node [ "s" ] })
    (v "(let* [s (str \"a\" n \" \") k (count (list 1))] k)");
  same "move up" list (E.Move_item { node = node [ "xs" ]; pos = 2 })
    (v "(let* [xs (list 0.2 0.6 0.4) k (count xs)] k)");
  refused "move the first" list (E.Move_item { node = node [ "xs" ]; pos = 0 });
  let record = g "(let* [r {:size 0.5 :count 6} a (sop/uv_sphere :radius r.size)] a)" in
  same "record field" record (E.Add_field { node = node [ "r" ]; name = "depth"; value = num "2" })
    (g "(let* [r {:size 0.5 :count 6 :depth 2} a (sop/uv_sphere :radius r.size)] a)");
  same "keyword field" base (E.Add_field { node = node [ "b" ]; name = "scale"; value = num "2" })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :translate [1 2 3] :scale 2) c (sop/subdivide b :iterations 1)] c)");
  same "record field scrub" record (E.Set_arg { node = node [ "r" ]; key = Field "size"; sub = []; value = num "0.9" })
    (g "(let* [r {:size 0.9 :count 6} a (sop/uv_sphere :radius r.size)] a)")

let part10 () = (* add and delete *)
  same "add node" base (E.Add_node { scope = [ "g" ]; name = "extra"; expr = S.make (S.List [ sym "sop/uv_sphere" ]) })
    (g "(let* [a (sop/uv_sphere :radius 0.5) b (sop/transform a :translate [1 2 3]) c (sop/subdivide b :iterations 1) extra (sop/uv_sphere)] c)");
  same "add node to a bare body" (g "(sop/uv_sphere)")
    (E.Add_node { scope = [ "g" ]; name = "x"; expr = num "1" })
    (g "(let* [x 1] (sop/uv_sphere))");
  refused "add a used name" base (E.Add_node { scope = [ "g" ]; name = "a"; expr = num "1" });
  same "delete an unused node" (g "(let* [a (sop/uv_sphere) u (sop/uv_sphere :radius 2) b (sop/transform a)] b)")
    (E.Delete_nodes { nodes = [ node [ "u" ] ] }) (g "(let* [a (sop/uv_sphere) b (sop/transform a)] b)");
  refused "delete a used node" base (E.Delete_nodes { nodes = [ node [ "a" ] ] });
  same "delete a chain" (g "(let* [a (sop/uv_sphere) u (sop/transform a) v (sop/transform u) b (sop/transform a)] b)")
    (E.Delete_nodes { nodes = [ node [ "u" ]; node [ "v" ] ] }) (g "(let* [a (sop/uv_sphere) b (sop/transform a)] b)")

let part11 () = (* atomic: a refused edit changes nothing; labels *)
  let before = norm base in
  (match E.apply catalog (parse base) (E.Rename { node = node [ "b" ]; to_ = "a" }) with
   | Error _ -> () | Ok _ -> fail "expected a refusal");
  check (canon (parse base) = before) "source unchanged after a refusal";
  List.iter (fun (op, label) -> check (E.label op = label) ("label " ^ label))
    [ E.Wrap { nodes = []; loop = For }, "Repeat"; E.Wrap { nodes = []; loop = Fold }, "Iterate";
      E.Unfold { node = []; key = Whole; sub = [] }, "Unfold";
      E.Make_macro { nodes = []; name = ""; holes = [] }, "Make macro";
      E.Rename { node = []; to_ = "" }, "Rename"; E.Hoist { node = [] }, "Move out";
      E.Toggle_bypass { node = [] }, "Bypass"; E.Fold_into { node = [] }, "Fold" ]

let part12 () = (* the 12 fixtures: notes survive, edits round trip *)
  let files = Sys.readdir cases |> Array.to_list |> List.filter (fun f -> Filename.check_suffix f ".lisp")
    |> List.sort compare in
  check (List.length files = 12) "12 fixtures";
  List.iter (fun file ->
    let text = read (Filename.concat cases file) in
    let forms = parse text in
    let graph = match forms with
      | [ { S.node = S.List (_ :: _ :: items); _ } ] ->
          List.find_map (fun (i : S.t) -> match i.node with
            | S.List ({ S.node = S.Sym "graph"; _ } :: { S.node = S.Sym n; _ } :: _) -> Some n
            | _ -> None) items |> Option.get
      | _ -> fail (file ^ ": shape") in
    (* a note on the graph and back leaves the text unchanged *)
    let noted = match E.apply catalog forms (E.Set_note { node = [ graph ]; text = "edited" }) with
      | Ok f -> f | Error d -> fail (file ^ ": " ^ Flow.Diagnostic.to_string d) in
    check (canon noted <> canon forms) (file ^ ": note prints");
    (match E.apply catalog noted (E.Set_note { node = [ graph ]; text = "" }) with
     | Ok f -> check (canon f = canon forms) (file ^ ": note round trip")
     | Error d -> fail (file ^ ": " ^ Flow.Diagnostic.to_string d))) files;
  (* bloom: rename a graph binding and back; the comments survive *)
  let bloom = parse (read (Filename.concat cases "bloom.lisp")) in
  let there = E.Rename { node = [ "flower"; "bloom" ]; to_ = "blossom" } in
  match E.apply catalog bloom there with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok renamed ->
      check (canon renamed <> canon bloom) "bloom renamed";
      (match E.apply catalog renamed (E.Rename { node = [ "flower"; "blossom" ]; to_ = "bloom" }) with
       | Ok back -> check (canon back = canon bloom) "bloom rename round trip"
       | Error d -> fail (Flow.Diagnostic.to_string d))

let run () =
  List.iter (fun f -> f ()) [ part1; part2; part3; part4; part5; part6; part7; dialog; part8; part9; part10; part11; part12 ]
