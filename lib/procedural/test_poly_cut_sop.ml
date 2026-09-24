open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let curves = 320 and points_per_curve = 181 in
  let point_count = curves * points_per_curve in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curves + 1) (fun primitive ->
        primitive * points_per_curve))
      ~primitive_kinds:(Array.make curves Topology.Open_polyline)
      |> Result.get_ok in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod points_per_curve) *. 0.02))
      ~y:(Array.init point_count (fun point ->
        float_of_int (point / points_per_curve) *. 0.03))
      ~z:(Array.make point_count 0.) in
  let signal = Attribute.create_owned ~owner:Attribute.Point ~name:"signal"
      (Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point mod 29) -. 14.5))) |> Result.get_ok
  and piece = Attribute.create_owned ~owner:Attribute.Primitive ~name:"piece"
      (Attribute.Int (Array.init curves Fun.id)) |> Result.get_ok
  and selected = Group.init ~owner:Group.Primitive ~name:"selected_curves"
      curves (fun primitive -> primitive mod 3 <> 0) in
  Geometry.create ~positions ~topology ~attributes:[signal;piece]
      ~groups:[selected] () |> Result.get_ok
  |> Ops.group_edges ~grain:257 ~name:"cuttable" |> function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let context ?(frame = 1L) ?(time = 0.) ?(seed = 42L) domains =
  Context.create ~frame ~time ~seed ~domains ~grain:257 () |> get

let cook session context graph =
  match Session.cook session ~context graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  Sop.snapshot (source ())
  |> Sop.poly_cut ~label:"crossing-cuts" ~group:"selected_curves"
       ~cut_group:"cuttable" ~element:Ops.Poly_cut_edges
       ~strategy:Ops.Poly_cut_cut
       ~detection:(Ops.Poly_cut_crossing {attribute="signal"; value=0.})
       ~keep_closed:false

let equal_geometry left right =
  let equal_storage left right = match left, right with
    | Attribute.Float left, Attribute.Float right -> left = right
    | Attribute.Int left, Attribute.Int right -> left = right
    | _ -> false in
  Packed.Float3.Private.view (Geometry.positions left)
    = Packed.Float3.Private.view (Geometry.positions right)
  && Topology.Private.view (Geometry.topology left)
    = Topology.Private.view (Geometry.topology right)
  && List.equal (fun left right -> Attribute.owner left = Attribute.owner right
      && Attribute.name left = Attribute.name right
      && equal_storage (Attribute.Private.storage left)
           (Attribute.Private.storage right))
      (Geometry.attributes left) (Geometry.attributes right)

let () =
  let graph = graph () in
  let parameters = Node.parameters graph in
  check (contains parameters "group=selected_curves"
      && contains parameters "cut_group=cuttable"
      && contains parameters "element=edges"
      && contains parameters "strategy=cut"
      && contains parameters "crossing:signal"
      && contains parameters "keep_closed=false")
    "PolyCut SOP cache identity omits controls";
  check (Context.Dependencies.to_list (Node.dependencies graph) = [])
    "PolyCut SOP unexpectedly depends on context facts";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:220_000_000
      |> get in
  let first = cook session (context 1) graph in
  let stats_before = Session.stats session in
  let repeated = cook session (context ~frame:99L ~time:7. ~seed:999L 4) graph in
  let stats_after = Session.stats session in
  check (first == repeated && stats_after.hits > stats_before.hits)
    "PolyCut SOP missed cache across irrelevant context facts";
  Session.close session;
  let fresh domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:220_000_000
        |> get in
    let output = cook session (context domains) graph in
    Session.close session;
    output in
  let one = fresh 1 and four = fresh 4 in
  check (equal_geometry one four)
    "PolyCut SOP one/four-domain geometry differs";
  let one_mesh = Prismel_mesh.to_mesh one |> function
    | Ok value -> value | Error error -> fail (Error.to_string error)
  and four_mesh = Prismel_mesh.to_mesh four |> function
    | Ok value -> value | Error error -> fail (Error.to_string error) in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "PolyCut SOP one/four-domain render mesh differs";
  let missing_primitive = Sop.snapshot (source ())
      |> Sop.poly_cut ~group:"missing"
  and missing_edge = Sop.snapshot (source ())
      |> Sop.poly_cut ~element:Ops.Poly_cut_edges ~cut_group:"missing"
  and invalid = Sop.snapshot (source ())
      |> Sop.poly_cut
           ~detection:(Ops.Poly_cut_crossing {attribute="P"; value=0.}) in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:220_000_000
      |> get in
  List.iter (fun graph -> match Session.cook session ~context:(context 1) graph with
    | Error error -> check (error.code = "missing_group")
        "PolyCut SOP missing-group diagnostic"
    | Ok _ -> fail "PolyCut SOP accepted a missing group")
    [missing_primitive; missing_edge];
  (match Session.cook session ~context:(context 1) invalid with
   | Error error -> check (error.code = "invalid_poly_cut")
       "PolyCut SOP structured PDK diagnostic"
   | Ok _ -> fail "PolyCut SOP accepted invalid crossing storage");
  Session.close session;
  print_endline "PolyCut SOP tests passed"
