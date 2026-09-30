(* W8: loops over geometry.  A Garden-like graph (scatter, then a for over its
   points) cooks deterministically at 1 and 3 domains; moving one point recooks
   only its element; pieces, keys and provenance. *)
open Flow_sop
module Edit = Procedural.Edit_graph
module Session = Procedural.Session

let fail message = failwith ("test_workspace_zone: " ^ message)
let check condition message = if not condition then fail message
let factories = Sop_catalog.Editor.factories
let geometry_bytes = Test_workspace_cook.geometry_bytes

let garden ?(result = "(sop/merge bed dots)") ~count () = Printf.sprintf {|
(workspace garden
  (graph garden :context sop [(seed : int 1) (count : int %d)]
    (let* [bed (sop/tube :top_radius 1 :bottom_radius 1 :height 0.04 :columns 12)
           spots (sop/scatter bed :count count :seed seed)
           dots (for [p (sop/point_list spots)]
                  (let* [ball (sop/uv_sphere :radius 0.06 :segments 8 :rings 4)
                         moved (sop/transform ball :translate p)]
                    moved))
           result %s]
      result)))|} count result

let lower source = match Flow.Syntax.parse source with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok forms -> (match Lower.workspace ~factories forms with
      | Ok lowered -> lowered
      | Error d -> fail (Flow.Diagnostic.to_string d))

let context ~domains = Result.get_ok
  (Procedural.Context.create ~domains ~grain:97 ~seed:42L ())
let session ?(entries = 512) () =
  Result.get_ok (Session.create ~max_entries:entries ~max_payload_bytes:(256 * 1024 * 1024))

let cook ?(domains = 1) session graph =
  let root = Option.get (graph : Lower.graph).root in
  let compiled = Result.get_ok (Edit.compile_node graph.network.geometry ~node_id:root) in
  match Session.cook session ~context:(context ~domains) compiled with
  | Ok output -> output.geometry
  | Error error -> fail (Procedural.Diagnostic.error_to_string error)

let prims = Pdk.Geometry.primitive_count

(* the graph with its zero-input node [operation] replaced by a snapshot of its cook whose
   point [index] is lifted by [by] *)
let move_point session (graph : Lower.graph) operation ~index ~by =
  let field = List.find (fun (n : Edit.node_info) -> n.operation = operation)
      (Edit.inspect graph.network.geometry) in
  let base = (Result.get_ok (Session.cook session ~context:(context ~domains:1)
    (Result.get_ok (Edit.compile_node graph.network.geometry ~node_id:field.id)))).geometry in
  let view = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions base) in
  let moved = Result.get_ok (Pdk.Geometry.with_positions
    (Pdk.Packed.Float3.of_owned ~x:(Array.copy view.x)
       ~y:(Array.mapi (fun i v -> if i = index then v +. by else v) view.y)
       ~z:(Array.copy view.z) |> Result.get_ok) base) in
  let replaced = Result.get_ok (Procedural.Node.Private.restore_id field.id
    (Procedural.Sop.snapshot moved)) in
  base, Result.get_ok (Edit.replace_node replaced graph.network.geometry)

let run () =
  let lowered = lower (garden ~count:12 ()) in
  let graph = List.hd lowered.graphs in
  check (Lower.zone_count lowered ["garden"; "dots"] = None) "no count before a cook";
  let one = cook (session ()) graph and three = cook ~domains:3 (session ()) graph in
  check (geometry_bytes one = geometry_bytes three) "zone differs at 1 and 3 domains";
  check (geometry_bytes one = geometry_bytes (cook (session ()) (List.hd (lower (garden ~count:12 ())).graphs)))
    "zone is not deterministic";
  check (Lower.zone_count lowered ["garden"; "dots"] = Some 12) "count after the cook";
  let bed = prims (cook (session ()) (List.hd (lower (garden ~result:"bed" ~count:1 ())).graphs)) in
  let ball = prims (cook (session ()) (List.hd (lower
    "(workspace b (graph b :context sop (sop/uv_sphere :radius 0.06 :segments 8 :rings 4)))").graphs)) in
  check (prims one = bed + 12 * ball) (Printf.sprintf "%d prims, want %d" (prims one) (bed + 12 * ball));
  (* only the template is lowered: the zone node, not 12 copies of its body *)
  let ops = List.map (fun (n : Edit.node_info) -> n.operation) (Edit.inspect graph.network.geometry) in
  check (List.length (List.filter (( = ) "zone") ops) = 1 && not (List.mem "uv_sphere" ops))
    "the template body stays out of the network";
  (* provenance: every tag names an element of the zone, at its index *)
  let attribute = Option.get (Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
    Lower.source_attribute one) in
  let tags = match Pdk.Attribute.storage attribute with
    | Pdk.Attribute.Int values -> values | _ -> fail "tag storage" in
  let elements = Array.to_list tags |> List.sort_uniq compare
    |> List.filter_map (fun tag -> match Lower.origin lowered tag with
        | Some (o : Lower.origin) when o.site = ["garden"; "dots"; "moved"] -> Some o.iter | _ -> None) in
  check (elements = List.init 12 (fun i -> [ i ])) "every element resolves to its iteration";
  check (List.length (Lower.tags lowered ~site:["garden"; "dots"; "moved"] ~iter:[ 3 ]) = 1) "one tag per element";
  (* the 12 elements, and the tag the final merge gave its input (its primitives keep the zone's) *)
  check (List.length (Lower.tags lowered ~site:["garden"; "dots"] ~iter:[]) = 13) "the loop lights every element";
  (* cache hits after moving one point: the collection is a grid whose point 5 moves *)
  let source = {|
(workspace grove
  (graph grove :context sop
    (let* [field (sop/uv_sphere :radius 1 :segments 5 :rings 3)
           trees (for [p (sop/point_list field)]
                   (sop/transform (sop/uv_sphere :radius 0.05 :segments 6 :rings 3) :translate p))]
      (sop/merge field trees))))|} in
  let lowered = lower source in
  let graph = List.hd lowered.graphs in
  let s = session () in
  let first = cook s graph in
  let a = Session.stats s in
  let base, graph' = move_point s graph "uv_sphere" ~index:5 ~by:0.25 in
  let root = Option.get graph.root in
  let compiled = Result.get_ok (Edit.compile_node graph' ~node_id:root) in
  let before = Session.stats s in
  let second = match Session.cook s ~context:(context ~domains:1) compiled with
    | Ok output -> output.geometry | Error e -> fail (Procedural.Diagnostic.error_to_string e) in
  let after = Session.stats s in
  let n = Pdk.Geometry.point_count base in
  check (a.cooks > 0 && n > 4) "the collection has points";
  check (geometry_bytes first <> geometry_bytes second) "moving a point changes the result";
  let misses = after.misses - before.misses and hits = after.hits - before.hits in
  (* the snapshot, the zone, its merge, the moved element's transform, the final merge *)
  Printf.printf "moved one point of %d: %d misses, %d hits\n" n misses hits;
  check (misses <= 5) (Printf.sprintf "%d misses after moving one point" misses);
  check (hits >= n - 1) (Printf.sprintf "only %d hits after moving one point" hits);
  (* pieces: each primitive of two boxes is one element *)
  let pieces = lower {|
(workspace bricks
  (graph bricks :context sop
    (let* [two (sop/merge (sop/box) (sop/transform (sop/box) :translate [3 0 0]))
           lifted (for [q (sop/piece_list two)] (sop/transform q :translate [0 1 0]))]
      (sop/merge lifted))))|} in
  let g = cook (session ()) (List.hd pieces.graphs) in
  check (prims g = 12) (Printf.sprintf "12 pieces in, %d out" (prims g));
  check (Lower.zone_count pieces ["bricks"; "lifted"] = Some 12) "piece count";
  check (geometry_bytes g = geometry_bytes (cook ~domains:3 (session ()) (List.hd pieces.graphs)))
    "pieces differ at 1 and 3 domains";
  (* keys order the elements *)
  let ids = Pdk.Attribute.create_owned ~name:"id" ~owner:Pdk.Attribute.Point
    (Pdk.Attribute.Int (Array.init n (fun i -> n - 1 - i))) |> Result.get_ok in
  let keyed = Result.get_ok (Pdk.Geometry.with_attribute ids base) in
  let ordered = Result.get_ok (Procedural.Zone.elements Points ~key:"id" keyed) in
  check (ordered.(0).key = 0 && ordered.(0).position = Pdk.Packed.Float3.get
    (Pdk.Geometry.positions base) (n - 1)) "elements follow the key attribute";
  let plain = Result.get_ok (Procedural.Zone.elements Points keyed) in
  check (plain.(0).position = Pdk.Packed.Float3.get (Pdk.Geometry.positions base) 0) "index order without a key";
  (* a body that reads t is refused, and one that branches on an element *)
  (match Lower.workspace ~factories (match Flow.Syntax.parse {|
(workspace w (graph g :context sop
  (let* [f (sop/grid)] (sop/merge (for [p (sop/point_list f)] (sop/transform (sop/box) :translate [t 0 0]))))))|} with
     | Ok forms -> forms | Error d -> fail (Flow.Diagnostic.to_string d)) with
   | Error d when d.code = "E_ZONE_LIVE" -> ()
   | Error d -> fail ("wrong error " ^ Flow.Diagnostic.to_string d)
   | Ok _ -> fail "a body that reads t lowered");
  print_endline "workspace zone: ok"

(* [test_main.exe bench_workspace_zone]: a scatter of N points, a for over them with a
   two-node body; cold cook, a recook after one point moves (the other N-1 elements hit),
   and the same work as N hand-written copies of the body (the baseline a zone replaces). *)
let bench () =
  Printf.printf "session capacity 16384 entries, then the editor default of 512\n";
  List.iter (fun capped ->
  let time f =
    let started = Unix.gettimeofday () and words = Gc.minor_words () in
    let value = f () in
    value, (Unix.gettimeofday () -. started) *. 1000., (Gc.minor_words () -. words) /. 1e6 in
  Printf.printf "%8s %10s %10s %8s %10s %10s\n" "N" "cold ms" "moved ms" "misses" "hits" "Mwords";
  List.iter (fun count ->
    let source = Printf.sprintf {|
(workspace bench
  (graph bench :context sop
    (let* [bed (sop/uv_sphere :radius 1 :segments 4 :rings 3)
           spots (sop/scatter bed :count %d :seed 1)
           dots (for [p (sop/point_list spots)]
                  (sop/transform (sop/uv_sphere :radius 0.02 :segments 6 :rings 3) :translate p))]
      (sop/merge bed dots))))|} count in
    let graph = List.hd (lower source).graphs in
    let s = session ~entries:(if capped then 512 else 16384) () in
    let (_, cold, _) = time (fun () -> cook s graph) in
    let _, graph' = move_point s graph "scatter" ~index:0 ~by:0.01 in
    let root = Option.get graph.root in
    let before = Session.stats s in
    let compiled = Result.get_ok (Edit.compile_node graph' ~node_id:root) in
    let (_, moved, words) = time (fun () ->
      Result.get_ok (Session.cook s ~context:(context ~domains:1) compiled)) in
    let after = Session.stats s in
    Printf.printf "%8d %10.2f %10.2f %8d %10d %10.2f\n" count cold moved
      (after.misses - before.misses) (after.hits - before.hits) words) [ 100; 1000; 4000 ]) [ false; true ]
