open Sop
open Test_support

let string_ok = function Ok value -> value | Error message -> fail message

let geometry () =
  let positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:[|-2.5; -1.5; -2.; 1.5; 2.5; 2.|]
      ~y:[|-0.5; -0.5; 0.5; -0.5; -0.5; 0.5|]
      ~z:(Array.make 6 0.) in
  let topology = Rdk.Topology.polygons_owned ~point_count:6
      ~vertex_points:[|0; 1; 2; 3; 4; 5|]
      ~primitive_offsets:[|0; 3; 6|] |> string_ok in
  let geometry = Rdk.Geometry.create ~positions ~topology () |> string_ok in
  let normals = Rdk.Attribute.create_owned ~name:"N"
      ~owner:Rdk.Attribute.Vertex
      (Rdk.Attribute.Float3 (Rdk.Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 6 0.) ~y:(Array.make 6 1.) ~z:(Array.make 6 0.)))
      |> string_ok in
  let geometry = Rdk.Geometry.with_attribute normals geometry |> string_ok in
  let pieces = Rdk.Attribute.create_owned ~name:"class"
      ~owner:Rdk.Attribute.Primitive (Rdk.Attribute.Int [|0; 1|]) |> string_ok in
  Rdk.Geometry.with_attribute pieces geometry |> string_ok

let run () =
  let pieces = Rays_editor.Packed_pieces.of_geometry
      ~piece_attribute:"class" (geometry ()) |> string_ok in
  if Rays_editor.Packed_pieces.piece_count pieces <> 2 then
    fail "Packed_pieces did not preserve two connected pieces";
  let source = Lisp_sop.node {|(sop/box :connectivity "Quads" :normals "None" :size [2.0 2.0 2.0] :consolidate_points true)|} in
  let cutter = Lisp_sop.node {|(sop/grid :width_mode "Auto" :height_mode "Auto" :columns 1 :rows 1 :size 3.0)|} in
  let fractured = Lisp_sop.node ~with_:["source", (source); "cutter", (cutter)] {|(sop/boolean_fracture (sop/ext_source) (sop/ext_cutter))|} in
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(16 * 1024 * 1024) |> string_ok in
  let context = Context.create ~seed:0L () |> string_ok in
  let output = match Session.cook session ~context fractured with
    | Ok output -> output
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  let pieces = Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive
      "piece" (Result.get_ok (Sop.Payload.geometry output.payload)) |> Option.get |> Rdk.Attribute.storage in
  (match pieces with
   | Rdk.Attribute.Int values ->
       let maximum = Array.fold_left Int.max (-1) values in
       if maximum <> 1 then
         fail "one cutting plane did not produce exactly two Boolean cells";
       let counts = Array.make 2 0 in
       Array.iter (fun piece -> counts.(piece) <- counts.(piece) + 1) values;
       if counts.(0) <= 1 || counts.(1) <= 1 then
         fail "Boolean fracture assigned individual polygons as pieces";
       let packed = Rays_editor.Packed_pieces.of_geometry
           ~piece_attribute:"piece" (Result.get_ok (Sop.Payload.geometry output.payload)) |> string_ok in
       if Rays_editor.Packed_pieces.piece_count packed <> 2 then
         fail "Boolean fracture piece attribute did not pack two rigid shards"
   | _ -> fail "Boolean fracture piece attribute is not integer-valued");
  print_endline "sketch support tests passed"
