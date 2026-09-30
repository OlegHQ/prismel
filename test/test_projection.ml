(* W4 part A: the graph pane's projection of every fixture (nodes, zones,
   rows, chips), liveness and invariance flags, and the layout. *)
open Flow_sop
module P = Projection
module S = Flow.Syntax
module E = Flow_edit

let fail message = failwith ("test_projection: " ^ message)
let check condition message = if not condition then fail message
let read path = In_channel.with_open_bin path In_channel.input_all
let cases = "../specification/workspace/cases"
let catalog = Editor_document.Contexts.catalog ~version:1 Sop_catalog.Editor.factories |> Result.get_ok
let fixtures = [ "bloom"; "facade"; "garland"; "kit"; "orrery"; "rosette";
                 "sunflower"; "tiles"; "tree"; "tunnel"; "variations"; "wave" ]

let workspace_of text = match S.parse text with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok forms -> (match Flow.Workspace.check catalog forms with
      | Some w, _ -> w
      | None, ds -> fail (String.concat "; " (List.map Flow.Diagnostic.to_string ds)))
let load name = workspace_of (read (Filename.concat cases (name ^ ".lisp")))
let scope w g = P.of_graph catalog w g
let node w g path = match P.find (scope w g) (g :: path) with
  | Some n -> n | None -> fail (String.concat "/" (g :: path) ^ " is not projected")
let zone (n : P.node) = match n.zone with Some z -> z | None -> fail (n.name ^ " is not a zone")
let flat = function Some e -> Flow.Lisp.flat e | None -> ""

(* every node, zone and row of every graph, as (graph, nodes, zones, rows) *)
let rec counts (s : P.scope) =
  List.fold_left (fun (n, z, r) (node : P.node) ->
    let n', z', r' = match node.zone with Some zn -> counts zn.scope | None -> 0, 0, 0 in
    n + 1 + n', z + (if node.zone <> None then 1 else 0) + z', r + List.length node.rows + r')
    (0, 0, 0) s.nodes

let snapshot = [
  "bloom", [ "flower", (9, 1, 35); "scene", (5, 0, 47); "world", (1, 0, 13); "settings", (2, 0, 6);
             "editor", (10, 0, 18); "half", (1, 0, 2); "petal", (1, 0, 7) ];
  "facade", [ "facade", (12, 2, 59) ];
  "garland", [ "garland", (14, 3, 59); "ring", (1, 0, 2) ];
  "kit", [ "kit", (15, 2, 49); "window", (3, 0, 30) ];
  "orrery", [ "orrery", (15, 1, 62) ];
  "rosette", [ "rosette", (4, 0, 29) ];
  "sunflower", [ "sunflower", (8, 1, 24) ];
  "tiles", [ "tiles", (8, 1, 34) ];
  "tree", [ "tree", (8, 1, 67) ];
  "tunnel", [ "rings", (3, 1, 22) ];
  "variations", [ "garden", (5, 0, 54); "scene", (1, 0, 8); "editor", (8, 0, 15) ];
  "wave", [ "wave", (6, 2, 39) ];
]

let snapshots () =
  List.iter (fun (name, expected) ->
    let w = load name in
    let got = List.map (fun (g : Flow.Workspace.graph) -> g.name, counts (scope w g.name)) (w.graphs @ w.defs) in
    check (got = expected) (name ^ ": node, zone and row counts changed"))
    snapshot

let kinds (n : P.node) = List.map (fun (r : P.row) -> r.label, r.kind) n.rows

let rows () =
  let w = load "bloom" in
  (* a zone: rail with the loop variable, captures, and the yield *)
  let ring = node w "flower" [ "ring" ] in
  let z = zone ring in
  check (z.kind = P.For && z.yield_label = "collect" && ring.head = "for") "ring is a for zone";
  check (List.map (fun (r : P.rail_row) -> r.name, r.role) z.rail = [ "i", P.Var; "petals", P.Capture; "seed", P.Capture ])
    "ring rail: the variable, then the names it captures";
  let i = List.hd z.rail in
  check (i.key = Some (E.Bv (1, 1)) && flat i.expr = "(range petals)" && i.ty = Some Flow.Ty.Int)
    "the loop variable edits its collection through Bv";
  check (List.length z.scope.nodes = 5
         && (List.nth z.scope.nodes 4).synthetic && z.scope.result = P.Node [ "flower"; "ring"; "@result" ])
    "the body's result is a synthetic node";
  (* a call: a rest slot with its add row, chips *)
  let bloom = node w "flower" [ "bloom" ] in
  check (kinds bloom = [ "input", P.Rest; "+ input", P.Add ]) "merge is one rest slot and an add row";
  (match bloom.rows with
   | [ a; add ] ->
       check (a.key = E.Pos 0 && a.chip = P.Name "ring" && a.ty = Some Flow.Ty.Geometry) "merge input wire";
       check (add.key = E.Pos 1 && add.chip = P.No_value) "the add row goes one past the last input"
   | _ -> fail "merge rows");
  let tint = node w "flower" [ "ring"; "tint" ] in
  check (List.map (fun (r : P.row) -> r.label) tint.rows = [ "in0"; "group"; "owner"; "color"; "alpha" ])
    "set_color rows: the slot, then the parameters";
  let color = List.find (fun (r : P.row) -> r.label = "color") tint.rows in
  check (color.key = E.Kw "color" && (match color.chip with P.Inline { glyph = "ƒ"; _ } -> true | _ -> false))
    "a nested call is a chip";
  let group = List.find (fun (r : P.row) -> r.label = "group") tint.rows in
  check (group.kind = P.Group_reader && group.chip = P.No_value && group.default = Some "") "group reader row";
  let leaf = node w "flower" [ "ring"; "leaf" ] in
  check (leaf.head = "petal" && List.map (fun (r : P.row) -> r.key) leaf.rows = [ E.Kw "length"; E.Kw "width" ]
         && (List.hd leaf.rows).default = Some "1.0" && (List.hd leaf.rows).ty = Some Flow.Ty.Float)
    "a defn call lists its inputs with their defaults";
  (* graph inputs, and the root scope *)
  let s = scope w "flower" in
  check (List.map (fun (i : P.input) -> i.name, flat i.default) s.inputs = [ "petals", "12"; "seed", "7" ]
         && s.result = P.Link "result") "root inputs and result link";
  (* macros: holes and binders *)
  let r = load "rosette" in
  let outer = node r "rosette" [ "outer" ] in
  check (outer.macro = Some "radial" && kinds outer = [ "i", P.Binder; "n", P.Hole; "body", P.Hole ]) "macro call rows";
  let outer_ = List.hd outer.rows in
  check (outer_.chip = P.Name "k") "the caller supplies the binder's name";
  check ((node r "rosette" [ "soft" ]).bypass && not outer.bypass) "bypass flag";
  (* records: output rows, patterns *)
  let k = load "kit" in
  let window = node k "kit" [ "big" ] in
  check (List.map fst window.outputs = [ "frame"; "pane"; "area" ]) "a values result has output rows";
  let pat = node k "kit" [ "[left mid right]" ] in
  check (List.map fst pat.outputs = [ "left"; "mid"; "right" ] && pat.binds = [ "left"; "mid"; "right" ]) "destructuring outputs";
  let tower = node k "kit" [ "tower" ] in
  let acc = List.hd (zone tower).rail in
  check ((zone tower).kind = P.Fold && acc.role = P.Acc && acc.key = Some (E.Bv (1, 1))
         && (zone tower).yield_label = "next") "fold accumulator row";
  let result = node k "kit" [ "tower"; "@result" ] in
  check (result.head = "record" && List.exists (fun (r : P.row) -> r.kind = P.Add && r.key = E.Field "") result.rows
         && List.exists (fun (r : P.row) -> r.key = E.Field "shape") result.rows) "record rows are fields plus an add row";
  let part = node k "kit" [ "tower"; "part" ] in
  check (part.head = "cond" && List.mem ("else", P.Arg) (kinds part)) "cond rows";
  let style = zone (node k "kit" [ "style" ]) in
  check (style.kind = P.Fn && style.yield_label = "return"
         && (List.hd style.rail).role = P.Param) "a bound fn is a zone with a param rail";
  (* let* scopes are zones too *)
  let f = load "facade" in
  let marked = node f "facade" [ "marked" ] in
  check ((zone marked).kind = P.Let && (zone marked).yield_label = "result"
         && List.map (fun (r : P.rail_row) -> r.name, r.role) (zone marked).rail = [ "glass", P.Capture ])
    "a nested let* is a zone that captures";
  (* a note travels with its binding *)
  let g = load "garland" in
  check ((node g "garland" [ "beads" ]).note = None) "no note";
  (match Flow.Syntax.parse "(workspace w (graph g :context sop (let* [; a note\n a (sop/box)] a)))" with
   | Ok forms ->
       let w = match Flow.Workspace.check catalog forms with Some w, _ -> w | _ -> fail "note" in
       check ((node w "g" [ "a" ]).note = Some "a note") "note carried"
   | Error _ -> fail "parse")

let live_names (s : P.scope) =
  let rec go (s : P.scope) = List.concat_map (fun (n : P.node) ->
    (if n.live then [ n.name ] else []) @ (match n.zone with Some z -> go z.scope | None -> [])) s.nodes in
  go s

let rec invariant_names (s : P.scope) = List.concat_map (fun (n : P.node) ->
  (if n.invariant then [ n.name ] else []) @ (match n.zone with Some z -> invariant_names z.scope | None -> [])) s.nodes

let flags () =
  let w = load "orrery" in
  let s = scope w "orrery" in
  check (live_names s = [ "spin"; "pulse"; "sun"; "glow"; "moons_each"; "a"; "bob"; "moon"; "@result"; "orbit"; "system" ])
    "Orrery: what depends on t is live, base, plinth and the static moon values are not";
  let base = node w "orrery" [ "base" ] and moons = node w "orrery" [ "moons_each" ] in
  check ((not base.live) && moons.live && (zone moons).scope.nodes <> []) "a live zone";
  List.iter (fun name ->
    let w = load name in
    List.iter (fun (g : Flow.Workspace.graph) ->
      if name <> "wave" then check (live_names (scope w g.name) = [])
        (name ^ "/" ^ g.name ^ " has no live node")) (w.graphs @ w.defs)) [ "sunflower"; "tree"; "tiles"; "bloom" ];
  check (live_names (scope (load "wave") "wave") <> []) "Wave is live";
  check (invariant_names (scope (load "sunflower") "sunflower") = [ "turn" ]) "Sunflower: turn is the same each seed";
  check (invariant_names (scope (load "tree") "tree") = [ "up" ]) "Tree: up is the same each level"

(* ---- layout ---- *)

let overlaps (ax, ay, aw, ah) (bx, by, bw, bh) = ax < bx +. bw && bx < ax +. aw && ay < by +. bh && by < ay +. ah
let inside (px, py, pw, ph) (x, y, w, h) = x >= px && y >= py && x +. w <= px +. pw && y +. h <= py +. ph

let rec check_layout name (l : P.layout) =
  let rec pairs = function [] -> [] | x :: r -> List.map (fun y -> x, y) r @ pairs r in
  List.iter (fun ((a : P.placed), (b : P.placed)) ->
    check (not (overlaps (a.x, a.y, a.w, a.h) (b.x, b.y, b.w, b.h)))
      (Printf.sprintf "%s: %s overlaps %s" name (String.concat "/" a.path) (String.concat "/" b.path))) (pairs l.placed);
  List.iter (fun (p : P.placed) ->
    check (inside (0., 0., l.w, l.h) (p.x, p.y, p.w, p.h)) (name ^ ": a node is outside its scope");
    Option.iter (fun (inner : P.layout) ->
      (* the zone's body has room for its whole inner layout, between the rail and the yield *)
      check (P.rail_width +. inner.w <= p.w -. P.yield_width && P.rail_top (match p.item with P.Item n -> n | _ -> fail "item") +. inner.h <= p.h)
        (name ^ ": a zone is smaller than its body");
      check_layout name inner) p.inner) l.placed

let layout () =
  List.iter (fun name ->
    let w = load name in
    List.iter (fun (g : Flow.Workspace.graph) ->
      let s = scope w g.name in
      let l = P.layout s in
      check_layout (name ^ "/" ^ g.name) l;
      check (P.layout s = l) (name ^ "/" ^ g.name ^ ": layout is deterministic");
      (* absolute boxes: every zone child lies inside its zone *)
      let abs = P.place l in
      List.iter (fun (z : P.node) ->
        let zb = List.assoc z.path abs in
        let zn = zone z in
        List.iter (fun (c : P.node) ->
          match List.assoc_opt c.path abs with
          | Some cb -> check (inside zb cb) (name ^ ": " ^ String.concat "/" c.path ^ " leaves its zone")
          | None -> fail ("unplaced " ^ String.concat "/" c.path)) zn.scope.nodes) (P.zones s)) (w.graphs @ w.defs)) fixtures;
  let w = load "sunflower" in
  let s = scope w "sunflower" in
  let l = P.layout s in
  let head = [ "sunflower"; "head" ] in
  (* inputs come first, the return last, and a node sits right of what it reads *)
  let x path = let (x, _, _, _) = List.assoc path (P.place l) in x in
  check (x [ "sunflower"; ":seeds" ] < x [ "sunflower"; "seeds_each" ]
         && x [ "sunflower"; "seeds_each" ] < x head && x head < x [ "sunflower"; "@return" ])
    "columns follow the dependencies";
  (* a position override moves one node; a collapsed zone is a card *)
  let moved = P.layout ~at:(fun p -> if p = head then Some (500., 300.) else None) s in
  let (hx, hy, _, _) = List.assoc head (P.place moved) in
  check (hx = 500. && hy = 300.) "at overrides the position";
  let z = [ "sunflower"; "seeds_each" ] in
  let (_, _, _, open_h) = List.assoc z (P.place l) in
  let collapsed = P.layout ~collapsed:(fun p -> p = z) s in
  let (_, _, cw, ch) = List.assoc z (P.place collapsed) in
  check (cw = P.node_width && ch < open_h && List.length (P.place collapsed) < List.length (P.place l))
    "a collapsed zone is a card without its children";
  (* the study's card geometry, on the 24-point grid *)
  let p = List.find (fun (p : P.placed) -> p.path = head) l.placed in
  check (p.w = P.node_width && p.h = P.head_height +. 2. *. P.row_height +. P.foot_height) "node size"

(* a loop over the points or pieces of geometry says how its elements are ordered *)
let zone_order () =
  let order text = let w = workspace_of text in
    match (scope w "g").nodes with
    | n :: _ -> (match n.zone with Some z -> z.order | None -> fail "not a zone")
    | [] -> fail "no node" in
  check (order "(workspace w (graph g :context sop (let* [z (for [p (sop/point_list (sop/grid))] (sop/box))] (sop/merge z))))" = Some "by index")
    "a loop over points is ordered by index";
  check (order "(workspace w (graph g :context sop (let* [z (for [p (sop/piece_list (sop/grid) :key \"id\")] (sop/box))] (sop/merge z))))" = Some "by id")
    "a loop over pieces keyed by an attribute is ordered by it";
  check ((match (scope (workspace_of "(workspace w (graph g :context sop (let* [pts (sop/point_list (sop/grid)) z (for [p pts] (sop/box))] (sop/merge z))))") "g").nodes with
             | [ _; n; _ ] -> (match n.zone with Some z -> z.order = Some "by index" | None -> false)
             | _ -> false))
    "a loop over a bound point list is ordered by index too";
  check (order "(workspace w (graph g :context sop (let* [z (for [i (range 3)] (sop/box))] (sop/merge z))))" = None)
    "a loop over a range has no order to show"

let run () =
  zone_order ();
  snapshots ();
  rows ();
  flags ();
  layout ();
  print_endline "projection tests passed"
