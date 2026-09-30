(* W5: recorded values, footers, iteration counts, inspector rows and the
   viewport header text. *)
open Flow_sop
module P = Projection
module T = Test_projection
module E = Flow_edit
module Scope = Pxui_graph.Scope

let fail message = failwith ("test_probe: " ^ message)
let check condition message = if not condition then fail message
let recorded ?time ?geometry w = Probe.make ?time ?geometry (Result.get_ok (Flow.Eval.static ~record:true w))
let footer records (n : P.node) ~probes = Probe.footer records n ~probes
let has text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in at 0

let bounds () =
  (* two loops call one function 4,096 times each: 8,192 records at the parameter, 4,096 kept *)
  let w = T.workspace_of "(workspace w (defn f :context value [(x : int)] (+ x 1)) \
    (graph g :context value (let* [a (for [i (range 4096)] (f i)) b (for [j (range 4096)] (f j))] (count a))))" in
  let eval = Result.get_ok (Flow.Eval.static ~record:true w) in
  check (eval.records <> [] && List.for_all (fun (_, l) -> List.length l <= 4096) eval.records)
    "a path recorded more than 4,096 values";
  check (List.exists (fun (_, l) -> List.length l = 4096) eval.records) "the bound was never reached";
  (* geometry is a reference, never geometry; the cook's counts fill it in *)
  let sunflower = T.load "sunflower" in
  let eval = Result.get_ok (Flow.Eval.static ~record:true sunflower) in
  let head = List.assoc [ "sunflower"; "head" ] eval.records in
  check (match head with [ ([], Flow.Eval.Geo _) ] -> true | _ -> false) "geometry records a plan node id only"

let sunflower () =
  let w = T.load "sunflower" in
  let scope = T.scope w "sunflower" in
  let r = recorded w in
  let zone = [ "sunflower"; "seeds_each" ] in
  let node name = T.node w "sunflower" [ "seeds_each"; name ] in
  (* the value at the probe, a sparkline across the loop, ×n *)
  let f = footer r (node "r") ~probes:[ 5 ] in
  check (f.value = "0.139" && f.runs = Some 240 && not f.invariant) ("r footer: " ^ Probe.text f);
  (match f.spark with
   | Some (values, at) -> check (Array.length values = 240 && at = 5) "r sparkline spans the 240 iterations"
   | None -> fail "r has no sparkline");
  check (Probe.text f = "0.139 · ×240") "r footer text";
  (* the invariant one offers to leave the loop and draws no sparkline *)
  let f = footer r (node "turn") ~probes:[ 5 ] in
  check (f.invariant && f.spark = None && f.runs = None && has (Probe.text f) "↑ same each time")
    ("turn footer: " ^ Probe.text f);
  (* outside a zone: the type when nothing was recorded there, the count for geometry *)
  let head = T.node w "sunflower" [ "head" ] in
  let f = footer r head ~probes:[] in
  check (f.value = "geometry" && f.runs = None && not f.invariant) "head: geometry without counts";
  let r' = recorded w ~geometry:(fun _ -> Some { Probe.prims = 1440; groups = [ "a"; "b" ]; data_id = 7 }) in
  check ((footer r' head ~probes:[]).value = "1440 prims · groups a, b") "head: cooked counts";
  check ((footer r' { head with path = [ "nowhere" ] } ~probes:[]).value = "geometry") "an unrecorded node shows its type";
  (* iterations: the inspector list *)
  let its = Probe.iterations r (node "r") ~probes:[ 0 ] in
  check (Array.length its = 240 && its.(0) = "0" && its.(1) = "0.062" && its.(239) <> its.(1)) "iteration list";
  check (Probe.readouts r (node "r") ~probes:[ 5 ] = [ "value at probe", "0.139"; "cook", "cached" ]) "inspector rows";
  check (Probe.readouts r head ~probes:[] = [ "value", "geometry"; "cook", "cached" ]) "inspector rows outside a zone";
  (* counts under the probes *)
  check (Probe.counts r scope ~probe:(fun _ -> 0) = [ zone, 240 ]) "zone count";
  ignore zone

let tree () =
  let w = T.load "tree" in
  let r = recorded w in
  let up = T.node w "tree" [ "crown"; "up" ] in
  let f = footer r up ~probes:[ 2 ] in
  check (f.invariant && f.value = "[0 1 0]") ("up footer: " ^ Probe.text f);
  let a = T.node w "tree" [ "crown"; "a" ] in
  check (not (footer r a ~probes:[ 2 ]).invariant) "a changes with the level";
  (* the fold's accumulator: one value per step *)
  check (Probe.counts r (T.scope w "tree") ~probe:(fun _ -> 0) = [ [ "tree"; "crown" ], 5 ]) "fold steps"

let branches () =
  (* if: how many iterations took each arm *)
  let w = T.load "tiles" in
  let r = recorded w in
  let angle = T.node w "tiles" [ "cells_each"; "angle" ] in
  let f = footer r angle ~probes:[ 3 ] in
  (match f.branch with
   | Some text -> Scanf.sscanf text "then %d · else %d" (fun a b -> check (a + b = 64 && a > 0 && b > 0) "then and else add up to the runs")
   | None -> fail "an if on a name shows then/else");
  check (f.runs = Some 64) "tiles: 64 runs";
  (* filter: kept a of b *)
  let w = T.load "garland" in
  let r = recorded w in
  let big = T.node w "garland" [ "big" ] in
  let f = footer r big ~probes:[] in
  let eval = Result.get_ok (Flow.Eval.static ~record:true w) in
  let length path = match List.assoc path eval.records with
    | [ (_, Flow.Eval.List xs) ] -> Array.length xs | _ -> fail "not a list" in
  check (f.kept = Some (Printf.sprintf "kept %d of %d" (length [ "garland"; "big" ]) (length [ "garland"; "sizes" ]))
         && length [ "garland"; "sizes" ] = 14) ("filter footer: " ^ Probe.text f)

let live () =
  let w = T.load "orrery" in
  let spin = T.node w "orrery" [ "spin" ] and base = T.node w "orrery" [ "base" ] in
  check (spin.live && not base.live) "orrery liveness";
  let at time = footer (recorded ~time w) spin ~probes:[] in
  check ((at 1.).value = "0.8" && (at 2.).value = "1.6" && (at 1.).live) "a live value is forced at the time shown";
  check (has (Probe.text (at 1.)) " · t") "the live tag";
  check (not (footer (recorded ~time:1. w) base ~probes:[]).live) "a cached node carries no tag";
  let bob = T.node w "orrery" [ "moons_each"; "bob" ] in
  (match (footer (recorded ~time:1. w) bob ~probes:[ 3 ]).spark, (footer (recorded ~time:2. w) bob ~probes:[ 3 ]).spark with
   | Some (a, _), Some (b, _) -> check (Array.length a = 24 && a <> b) "a live sparkline moves with t"
   | _ -> fail "bob has no sparkline");
  check (Probe.readouts (recorded ~time:1. w) spin ~probes:[] = [ "value", "0.8"; "cook", "live, recooks every frame" ])
    "live inspector rows";
  (* the viewport header *)
  let lowered = match Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories:Sop_catalog.Editor.factories
      (Result.get_ok (Flow.Syntax.parse (T.read (Filename.concat T.cases "orrery.lisp")))) with
    | Ok l -> l | Error d -> fail (Flow.Diagnostic.to_string d) in
  let live_count, cached = Lower.counts lowered in
  check (live_count > 0 && cached > 0) "orrery has live and cached nodes";
  check (Lower.status lowered ~seconds:0.0013 = Some (Printf.sprintf "t %d live · %d cached · cook 1.3 ms" live_count cached))
    "viewport header text";
  let lowered = Result.get_ok (Lower.workspace ~extra:Editor_document.Contexts.descriptors ~factories:Sop_catalog.Editor.factories
      (Result.get_ok (Flow.Syntax.parse (T.read (Filename.concat T.cases "sunflower.lisp"))))) in
  check (Lower.status lowered ~seconds:0.001 = None) "a static document has no live header"

let nested () =
  (* an inner zone counts per outer iteration, not the whole product *)
  let w = T.workspace_of "(workspace w (graph g :context sop [(n : int 3)] \
    (let* [rows (for [i (range n)] \
                  (let* [cols (for [j (range (+ i 1))] (sop/box))] (sop/merge cols)))] \
       (sop/merge rows))))" in
  let scope = T.scope w "g" in
  let r = recorded w in
  let outer = [ "g"; "rows" ] and inner = [ "g"; "rows"; "cols" ] in
  let counts k = Probe.counts r scope ~probe:(fun p -> if p = outer then k else 0) in
  check (counts 0 = [ outer, 3; inner, 1 ] && counts 1 = [ outer, 3; inner, 2 ] && counts 2 = [ outer, 3; inner, 3 ])
    "nested counts follow the outer probe";
  check (List.length (Array.to_list (Probe.records r (inner @ [ ":j" ]))) = 6) "the whole product is 6 records"

(* the hoist button of an invariant footer is one request *)
let hoist () =
  let w = T.load "sunflower" in
  let view, _ = Test_pxui_graph.scope_view ~probe:(fun _ -> 5) w "sunflower" in
  let view, _ = Test_pxui_graph.scope_step view (Test_pxui_graph.frame ()) in
  let turn = [ "sunflower"; "seeds_each"; "turn" ] in
  let x, y, tw, th = Option.get (Scope.Private.box_of view turn) in
  let z = Scope.zoom view in
  let point = int_of_float (x +. tw -. 30. *. z), int_of_float (y +. th -. 10. *. z) in
  let _, changes = Test_pxui_graph.scope_click view point in
  check (List.mem (Scope.Syntax_edit (E.Hoist { node = turn })) changes) "the footer's hoist button did not emit Hoist";
  (* a node that varies has none *)
  let r = [ "sunflower"; "seeds_each"; "r" ] in
  let x, y, tw, th = Option.get (Scope.Private.box_of view r) in
  let _, changes = Test_pxui_graph.scope_click view (int_of_float (x +. tw -. 30. *. z), int_of_float (y +. th -. 10. *. z)) in
  check (not (List.exists (function Scope.Syntax_edit (E.Hoist _) -> true | _ -> false) changes)) "r offered a hoist"

(* a selection that an edit removed does not survive the next layout *)
let selection () =
  let w = T.load "sunflower" in
  let view, scope = Test_pxui_graph.scope_view w "sunflower" in
  let turn = [ "sunflower"; "seeds_each"; "turn" ] in
  let view = Scope.select [ turn; [ "sunflower"; "gone" ] ] view in
  let view = Scope.with_scope ~key:"sunflower" scope view in
  check (Scope.selected view = [ turn ]) "the selection kept a path that no longer exists"

(* W8: a loop over geometry has one template record; the count comes from the cook *)
let geometry_zone () =
  let w = T.workspace_of "(workspace w (graph g :context sop (let* [f (sop/grid) \
    d (for [p (sop/point_list f)] (let* [b (sop/box) m (sop/transform b :translate p)] m)) r (sop/merge f d)] r)))" in
  let scope = T.scope w "g" in
  let zone = [ "g"; "d" ] in
  let dynamic path = if path = zone then Some 100 else None in
  let eval = Result.get_ok (Flow.Eval.static ~record:true w) in
  check (Probe.counts (Probe.make eval) scope ~probe:(fun _ -> 0) = [ zone, 1 ]) "template count before a cook";
  let r = Probe.make ~dynamic eval in
  check (Probe.counts r scope ~probe:(fun _ -> 0) = [ zone, 100 ]) "the cook's element count";
  let m = T.node w "g" [ "d"; "m" ] in
  check ((footer r m ~probes:[ 41 ]).value <> "not run here") "every element reads the template record";
  check ((footer (Probe.make eval) m ~probes:[ 41 ]).value = "not run here") "without a count only iteration 0 ran"

let run () =
  geometry_zone (); bounds (); sunflower (); tree (); branches (); live (); nested (); hoist (); selection ();
  print_endline "probe tests passed"
