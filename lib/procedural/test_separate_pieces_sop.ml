open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let pieces = 320 and points_per_piece = 181 in
  let point_count = pieces * points_per_piece in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (pieces + 1) (fun piece ->
        piece * points_per_piece))
      ~primitive_kinds:(Array.make pieces Topology.Open_polyline)
      |> Result.get_ok in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod points_per_piece) *. 0.01))
      ~y:(Array.init point_count (fun point ->
        sin (float_of_int (point mod points_per_piece) *. 0.04)))
      ~z:(Array.make point_count 0.) in
  let piece = Attribute.create_owned ~owner:Attribute.Primitive ~name:"piece"
      (Attribute.Int (Array.init pieces Fun.id)) |> Result.get_ok in
  Geometry.create ~positions ~topology ~attributes:[piece] () |> Result.get_ok

let context ?(frame = 1L) ?(time = 0.) ?(seed = 42L) domains =
  Context.create ~frame ~time ~seed ~domains ~grain:257 () |> get

let cook session context graph =
  match Session.cook session ~context graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph source =
  Sop.snapshot source
  |> Sop.separate_pieces ~label:"space-pieces" ~owner:Attribute.Primitive
       ~translation_attribute:"separation" ~axis:(Vec3.create 1. 2. 3.)
       ~gap:0.02 ~mode:Ops.Separate_pieces_separate ~piece_attribute:"piece"

let equal_geometry left right =
  Packed.Float3.Private.view (Geometry.positions left)
    = Packed.Float3.Private.view (Geometry.positions right)
  && Topology.Private.view (Geometry.topology left)
    = Topology.Private.view (Geometry.topology right)
  && List.equal (fun left right ->
      Attribute.owner left = Attribute.owner right
      && Attribute.name left = Attribute.name right
      && match Attribute.Private.storage left, Attribute.Private.storage right with
         | Attribute.Int left, Attribute.Int right -> left = right
         | Attribute.Float3 left, Attribute.Float3 right ->
             Packed.Float3.Private.view left = Packed.Float3.Private.view right
         | _ -> false)
      (Geometry.attributes left) (Geometry.attributes right)

let () =
  let source = source () in
  let graph_node = graph source in
  let parameters = Node.parameters graph_node in
  check (contains parameters "owner=primitive"
      && contains parameters "piece_attribute=piece"
      && contains parameters "translation_attribute=separation"
      && contains parameters "axis="
      && contains parameters "gap="
      && contains parameters "mode=separate")
    "Separate Pieces SOP cache identity omits controls";
  check (Context.Dependencies.to_list (Node.dependencies graph_node) = [])
    "Separate Pieces SOP unexpectedly depends on context facts";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:220_000_000
      |> get in
  let first = cook session (context 1) graph_node in
  let before = Session.stats session in
  let repeated = cook session (context ~frame:99L ~time:7. ~seed:999L 4)
      graph_node in
  let after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Separate Pieces SOP missed cache across irrelevant context facts";
  Session.close session;
  let fresh domains =
    let session = Session.create ~max_entries:8 ~max_payload_bytes:220_000_000
        |> get in
    let output = cook session (context domains) graph_node in
    Session.close session;
    output in
  let one = fresh 1 and four = fresh 4 in
  check (equal_geometry one four)
    "Separate Pieces SOP one/four-domain geometry differs";
  let one_mesh = Prismel_mesh.to_mesh one |> function
    | Ok value -> value | Error error -> fail (Error.to_string error)
  and four_mesh = Prismel_mesh.to_mesh four |> function
    | Ok value -> value | Error error -> fail (Error.to_string error) in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "Separate Pieces SOP one/four-domain render mesh differs";
  let restored_graph = graph source
      |> Sop.separate_pieces ~owner:Attribute.Primitive
           ~translation_attribute:"separation"
           ~mode:Ops.Separate_pieces_move_back ~piece_attribute:"piece" in
  let session = Session.create ~max_entries:8 ~max_payload_bytes:220_000_000
      |> get in
  let restored = cook session (context 1) restored_graph in
  let restored_positions = Packed.Float3.Private.view (Geometry.positions restored)
  and source_positions = Packed.Float3.Private.view (Geometry.positions source) in
  let close left right = abs_float (left -. right) <= 1e-10 in
  check (Array.for_all2 close restored_positions.x source_positions.x
      && Array.for_all2 close restored_positions.y source_positions.y
      && Array.for_all2 close restored_positions.z source_positions.z)
    "Separate Pieces SOP Move Back did not restore positions";
  let invalid = Sop.snapshot source
      |> Sop.separate_pieces ~piece_attribute:"missing" in
  (match Session.cook session ~context:(context 1) invalid with
   | Error error -> check (error.code = "invalid_separate_pieces")
       "Separate Pieces SOP structured diagnostic"
   | Ok _ -> fail "Separate Pieces SOP accepted a missing piece attribute");
  Session.close session;
  print_endline "Separate Pieces SOP tests passed"
