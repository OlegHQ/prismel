open Prismel
open Pdk

let fail message = raise (Failure message)
let get_ok = function Ok value -> value | Error _ -> fail "unexpected error"

let equal_positions left right =
  let left = Packed.Float3.Private.view (Geometry.positions left)
  and right = Packed.Float3.Private.view (Geometry.positions right) in
  left.x = right.x && left.y = right.y && left.z = right.z

let near_array expected actual =
  Array.length expected = Array.length actual
  && Array.for_all2 (fun expected actual -> abs_float (expected -. actual) <= 1e-12)
       expected actual

let int_array_values ~owner ~name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int_array values -> Packed.Int_array.Private.view values
       | _ -> fail ("unexpected non-integer-array storage for " ^ name))
  | None -> fail ("missing integer-array attribute " ^ name)

let float_array_values ~owner ~name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float_array values -> Packed.Float_array.Private.view values
       | _ -> fail ("unexpected non-float-array storage for " ^ name))
  | None -> fail ("missing float-array attribute " ^ name)

let () =
  let pattern source = Attribute_pattern.compile source |> get_ok in
  let reference_glob glob name =
    let glob_length = String.length glob and name_length = String.length name in
    let matches = Array.make_matrix (glob_length + 1) (name_length + 1) false in
    matches.(glob_length).(name_length) <- true;
    for glob_index = glob_length - 1 downto 0 do
      for name_index = name_length downto 0 do
        matches.(glob_index).(name_index) <- match glob.[glob_index] with
          | '*' -> matches.(glob_index + 1).(name_index)
              || (name_index < name_length
                  && matches.(glob_index).(name_index + 1))
          | '?' -> name_index < name_length
              && matches.(glob_index + 1).(name_index + 1)
          | literal -> name_index < name_length && literal = name.[name_index]
              && matches.(glob_index + 1).(name_index + 1)
      done
    done;
    matches.(0).(0) in
  let words alphabet max_length =
    let values = ref [""] and frontier = ref [""] in
    for _ = 1 to max_length do
      frontier := List.concat_map (fun prefix ->
        List.map (fun character -> prefix ^ String.make 1 character) alphabet)
        !frontier;
      values := List.rev_append !frontier !values
    done;
    !values in
  let expect_pattern source included excluded =
    let pattern = pattern source in
    List.iter (fun name -> if not (Attribute_pattern.matches pattern name) then
      fail (Printf.sprintf "attribute pattern %S did not include %S" source name))
      included;
    List.iter (fun name -> if Attribute_pattern.matches pattern name then
      fail (Printf.sprintf "attribute pattern %S did not exclude %S" source name))
      excluded in
  expect_pattern "" ["Cd"; "N"; "anything"] [];
  expect_pattern "Cd pscale" ["Cd"; "pscale"] ["N"; "Cdx"];
  expect_pattern "* ^tmp* ^N Cd" ["Cd"; "width"] ["N"; "tmp1"];
  expect_pattern "^tmp* ^N N" ["Cd"; "N"] ["tmp_cache"];
  expect_pattern "foo? value[0-2] kind[!0-9]"
    ["foo1"; "value0"; "value2"; "kindx"]
    ["foo"; "foooo"; "value3"; "kind7"];
  expect_pattern "literal\\* has\\ space \\^caret"
    ["literal*"; "has space"; "^caret"] ["literalX"; "has"];
  List.iter (fun invalid -> match Attribute_pattern.compile invalid with
    | Error _ -> ()
    | Ok _ -> fail (Printf.sprintf "accepted malformed attribute pattern %S" invalid))
    ["^"; "bad\\"; "[abc"; "[]"; "[z-a]"];
  let exhaustive_names = words ['a'; 'b'] 5
  and exhaustive_globs = List.filter (fun value -> value <> "")
      (words ['a'; 'b'; '*'; '?'] 5) in
  List.iter (fun glob ->
    let compiled = pattern glob in
    let rewrite = Attribute_pattern.compile_rewrite ~pattern:glob
        ~replacement:glob |> get_ok in
    List.iter (fun name ->
      let expected = reference_glob glob name
      and actual = Attribute_pattern.matches compiled name in
      if expected <> actual then fail (Printf.sprintf
        "attribute pattern/reference disagreement for %S and %S" glob name);
      let rewritten = Attribute_pattern.rewrite rewrite name in
      if rewritten <> (if expected then Some name else None) then
        fail (Printf.sprintf
          "attribute rewrite/reference disagreement for %S and %S" glob name))
      exhaustive_names)
    exhaustive_globs;
  let expect_rewrite source replacement name expected =
    let rewrite = Attribute_pattern.compile_rewrite ~pattern:source ~replacement
        |> get_ok in
    if Attribute_pattern.rewrite rewrite name <> expected then fail
        (Printf.sprintf "attribute rewrite %S -> %S failed for %S"
          source replacement name) in
  expect_rewrite "instance*" "my*instance" "instancepoint"
    (Some "mypointinstance");
  expect_rewrite "*_alpha_*" "*_beta_*" "lamp_alpha_matt"
    (Some "lamp_beta_matt");
  expect_rewrite "*_???" "old_???_*" "lamp_esr"
    (Some "old_esr_lamp");
  expect_rewrite "kind[ab]" "class?" "kinda" (Some "classa");
  expect_rewrite "literal\\**" "escaped_*" "literal*tail"
    (Some "escaped_tail");
  expect_rewrite "instance*" "my*instance" "other" None;
  List.iter (fun (source, replacement) ->
    match Attribute_pattern.compile_rewrite ~pattern:source ~replacement with
    | Error _ -> ()
    | Ok _ -> fail (Printf.sprintf "accepted invalid rewrite %S -> %S"
        source replacement))
    [("a*", "plain"); ("a b", "c d"); ("^a*", "b*"); ("a*", "")];
  let rewrite_set source replacement name expected =
    let rules = Attribute_pattern.compile_rewrite_set ~pattern:source
        ~replacement |> get_ok in
    let actual = Attribute_pattern.rewrite_set rules name in
    if actual <> expected then
      fail (Printf.sprintf
        "attribute rewrite set %S -> %S failed for %S: expected %s, got %s"
        source replacement name
        (Option.value ~default:"none" expected)
        (Option.value ~default:"none" actual)) in
  rewrite_set "foo* bar? ^bar_tmp" "out* short_?" "foo_tail"
    (Some "out_tail");
  rewrite_set "foo* bar? ^bar_tmp" "out* short_?" "bar7"
    (Some "short_7");
  rewrite_set "* foo*" "all_* exact*" "foo_tail" (Some "exact_tail");
  List.iter (fun (source, replacement) ->
    match Attribute_pattern.compile_rewrite_set ~pattern:source ~replacement with
    | Error _ -> ()
    | Ok _ -> fail (Printf.sprintf "accepted invalid rewrite set %S -> %S"
        source replacement))
    [("foo* bar*", "only_*"); ("^tmp*", "renamed_*");
     ("foo* ^tmp*", "one_* two_*")];
  let generated_line domains = Parallel.run ~domains (fun () ->
    Ops.line ~grain:257 ~points:100_001
      ~origin:(Vec3.create 1. 2. 3.)
      ~direction:(Vec3.create max_float max_float 0.) ~length:(sqrt 2.) ()
    |> get_ok) in
  let line_one = generated_line 1 and line_many = generated_line 4 in
  let line_positions = Packed.Float3.Private.view (Geometry.positions line_one)
  and line_many_positions = Packed.Float3.Private.view
      (Geometry.positions line_many) in
  if Geometry.point_count line_one <> 100_001
      || Geometry.vertex_count line_one <> 100_001
      || Geometry.primitive_count line_one <> 1
      || Topology.primitive_kind (Geometry.topology line_one) 0
           <> Topology.Open_polyline
      || line_positions.x.(0) <> 1. || line_positions.y.(0) <> 2.
      || abs_float (line_positions.x.(100_000) -. 2.) > 1e-12
      || abs_float (line_positions.y.(100_000) -. 3.) > 1e-12
      || line_positions.x <> line_many_positions.x
      || line_positions.y <> line_many_positions.y
      || line_positions.z <> line_many_positions.z then
    fail "Line packed generation/domain exactness";
  let free_line = Ops.line ~kind:Ops.Line_points ~points:3
      ~origin:(Vec3.create (-1.) 0. 0.) ~direction:Vec3.unit_x ~length:2. ()
      |> get_ok in
  let free_positions = Packed.Float3.Private.view
      (Geometry.positions free_line) in
  if Geometry.primitive_count free_line <> 0
      || free_positions.x <> [|-1.; 0.; 1.|] then
    fail "Line free-point mode";
  (match Ops.line ~origin:Vec3.zero ~direction:Vec3.zero ~length:1. () with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "Line accepted a zero direction");
  (match Ops.line ~points:1 ~origin:Vec3.zero ~direction:Vec3.unit_x
      ~length:1. () with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "Line accepted one point in curve mode");
  (match Ops.line ~origin:(Vec3.create max_float 0. 0.)
      ~direction:Vec3.unit_x ~length:max_float () with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "Line accepted a non-finite endpoint");
  let cancelled_line = Cancel.create () in
  Cancel.cancel cancelled_line;
  (match Ops.line ~cancel:cancelled_line ~points:10_000 ~origin:Vec3.zero
      ~direction:Vec3.unit_x ~length:1. () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Line ignored cancellation");
  let builder = Packed.Float3.Builder.create 4 in
  Packed.Float3.Builder.set builder 0 0. 0. 0.;
  Packed.Float3.Builder.set builder 1 1. 0. 0.;
  Packed.Float3.Builder.set builder 2 1. 1. 0.;
  Packed.Float3.Builder.set builder 3 0. 1. 0.;
  let positions = Packed.Float3.Builder.freeze builder in
  let topology_builder = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_polygon topology_builder [|0; 1; 2; 3|];
  let topology = Topology.Builder.freeze topology_builder in
  if Topology.vertex_count topology <> 4 || Topology.primitive_size topology 0 <> 4
  then fail "polygon CSR cardinality";
  let selected = Group.init ~owner:Group.Point ~name:"even" 4 (fun i -> i land 1 = 0) in
  let all = Group.init ~owner:Group.Point ~name:"all" 4 (fun _ -> true) in
  let odd = Group.difference all selected |> get_ok in
  if Group.cardinality odd <> 2 || Group.mem 0 odd || not (Group.mem 1 odd) then
    fail "packed group difference";
  let geometry = Geometry.create ~positions ~topology ~groups:[selected] () |> get_ok in
  if Group.cardinality selected <> 2 then fail "packed group cardinality";
  let existing_sequence = Attribute.create_owned ~name:"sequence"
      ~owner:Attribute.Point (Attribute.Int [|99; 99; 99; 99|]) |> get_ok in
  let sequence_source = Geometry.with_attribute existing_sequence geometry |> get_ok in
  let enumerated = Attribute_ops.enumerate ~grain:1 ~selection:selected
      ~start:10 ~step:2 ~owner:Attribute.Point ~name:"sequence"
      sequence_source |> get_ok in
  let sequence = Geometry.find_attribute ~owner:Attribute.Point "sequence" enumerated
      |> Option.get |> Attribute.get (Attribute.key ~name:"sequence"
        ~owner:Attribute.Point Attribute.int) |> Option.get in
  if sequence <> [|10; 99; 12; 99|] then
    fail "restricted integer enumeration/preserved values";
  let enumerated_text = Attribute_ops.enumerate ~grain:1 ~start:(-3) ~step:2
      ~storage:(Attribute_ops.Text { prefix = "v" }) ~owner:Attribute.Vertex
      ~name:"label" geometry |> get_ok in
  let labels = Geometry.find_attribute ~owner:Attribute.Vertex "label" enumerated_text
      |> Option.get |> Attribute.get (Attribute.key ~name:"label"
        ~owner:Attribute.Vertex Attribute.text) |> Option.get in
  if labels <> [|"v-3"; "v-1"; "v1"; "v3"|] then
    fail "text enumeration sequence";
  (match Attribute_ops.enumerate ~selection:selected ~owner:Attribute.Vertex
      ~name:"bad" geometry with
   | Error error when Error.code error = "invalid_enumeration" -> ()
   | _ -> fail "enumerate accepted a mismatched group owner");
  (match Attribute_ops.enumerate ~start:max_int ~step:1 ~owner:Attribute.Point
      ~name:"overflow" geometry with
   | Error error when Error.code error = "invalid_enumeration" -> ()
   | _ -> fail "enumerate accepted an overflowing integer sequence");
  let one = Parallel.run ~domains:1 (fun () ->
    Kernel.map_points (fun output index x y z ->
      Kernel.Writer.set output index (x +. float_of_int index) (y *. 2.) (z -. 1.)) geometry) in
  let many = Parallel.run ~domains:4 (fun () ->
    Kernel.map_points ~grain:1 (fun output index x y z ->
      Kernel.Writer.set output index (x +. float_of_int index) (y *. 2.) (z -. 1.)) geometry) in
  if not (equal_positions one many) then fail "one/multi-domain point output differs";
  if Topology.data_id (Geometry.topology one) <> Topology.data_id topology then
    fail "point kernel invalidated unchanged topology";
  if Packed.Float3.data_id (Geometry.positions one) = Packed.Float3.data_id positions then
    fail "point kernel did not invalidate position data";
  if Geometry.find_group ~owner:Group.Point "even" one = None then
    fail "point kernel dropped group";
  let quad_mesh = Prismel_mesh.to_mesh geometry |> get_ok in
  if Mesh.index_count quad_mesh <> 6 then fail "quad bridge triangulation";
  let extruded = Ops.poly_extrude ~distance:2. geometry |> get_ok in
  if Geometry.point_count extruded <> 8
     || Geometry.primitive_count extruded <> 6
     || Geometry.vertex_count extruded <> 24
  then fail "poly extrude cardinality";
  if Mesh.index_count (Prismel_mesh.to_mesh extruded |> get_ok) <> 36
  then fail "poly extrude bridge";
  (match Geometry.find_group ~owner:Group.Point "even" extruded with
   | Some group when Group.cardinality group = 4 -> ()
   | _ -> fail "poly extrude point group remap");
  let reserved_p = Attribute.create_owned ~name:"P" ~owner:Attribute.Point
      (Attribute.Float3 positions) |> get_ok in
  (match Geometry.create ~positions ~topology ~attributes:[reserved_p] () with
   | Error _ -> () | Ok _ -> fail "duplicate canonical P was accepted");
  (match Topology.polygons_owned ~point_count:2 ~vertex_points:[|0; 1|]
           ~primitive_offsets:[|0; 2|] with
   | Error _ -> () | Ok _ -> fail "undersized polygon was accepted");
  let triangle_builder = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_triangle triangle_builder 0 1 2;
  Topology.Builder.add_triangle triangle_builder 0 2 3;
  let triangle_geometry = Geometry.create ~positions
      ~topology:(Topology.Builder.freeze triangle_builder) () |> get_ok in
  let point_ids = Attribute.create_owned ~name:"point_id" ~owner:Attribute.Point
      (Attribute.Int [|0; 1; 2; 3|]) |> get_ok in
  let sortable_points = Geometry.with_attribute point_ids geometry |> get_ok in
  let sorted_points = Ops.sort ~grain:1 ~selection:selected ~descending:true
      ~owner:Ops.Points ~key:Ops.X sortable_points |> get_ok in
  let sorted_positions = Packed.Float3.Private.view (Geometry.positions sorted_points)
  and sorted_topology = Topology.Private.view (Geometry.topology sorted_points) in
  let sorted_ids = Geometry.find_attribute ~owner:Attribute.Point "point_id"
      sorted_points |> Option.get |> Attribute.get (Attribute.key ~name:"point_id"
        ~owner:Attribute.Point Attribute.int) |> Option.get in
  if sorted_positions.x <> [|1.; 1.; 0.; 0.|]
     || sorted_topology.vertex_points <> [|2; 1; 0; 3|]
     || sorted_ids <> [|2; 1; 0; 3|] then
    fail "restricted stable point sort/remap";
  let stable_points = Ops.sort ~grain:1 ~owner:Ops.Points ~key:Ops.X
      sortable_points |> get_ok in
  let stable_ids = Geometry.find_attribute ~owner:Attribute.Point "point_id"
      stable_points |> Option.get |> Attribute.get (Attribute.key ~name:"point_id"
        ~owner:Attribute.Point Attribute.int) |> Option.get in
  if stable_ids <> [|0; 3; 1; 2|] then fail "point sort stability";
  let shifted_points = Ops.sort ~owner:Ops.Points ~key:(Ops.Shift 1)
      sortable_points |> get_ok in
  let shifted_ids = Geometry.find_attribute ~owner:Attribute.Point "point_id"
      shifted_points |> Option.get |> Attribute.get (Attribute.key ~name:"point_id"
        ~owner:Attribute.Point Attribute.int) |> Option.get in
  if shifted_ids <> [|3; 0; 1; 2|] then fail "point sort cyclic shift";
  (match Ops.sort ~owner:Ops.Points
      ~key:(Ops.Attribute_component { name = "missing"; component = 0 })
      sortable_points with
   | Error error when Error.code error = "invalid_sort" -> ()
   | _ -> fail "sort accepted a missing key attribute");
  (match Ops.sort ~selection:selected ~owner:Ops.Primitives ~key:Ops.X
      triangle_geometry with
   | Error error when Error.code error = "invalid_sort" -> ()
   | _ -> fail "sort accepted a mismatched selection owner");
  let vertex_ids = Attribute.create_owned ~name:"vertex_id"
      ~owner:Attribute.Vertex (Attribute.Int [|0; 1; 2; 3; 4; 5|]) |> get_ok
  and primitive_ids = Attribute.create_owned ~name:"primitive_id"
      ~owner:Attribute.Primitive (Attribute.Int [|10; 20|]) |> get_ok in
  let sortable_primitives = triangle_geometry
      |> Geometry.with_attribute vertex_ids |> get_ok
      |> Geometry.with_attribute primitive_ids |> get_ok in
  let sorted_primitives = Ops.sort ~grain:1 ~owner:Ops.Primitives
      ~key:Ops.Reverse sortable_primitives |> get_ok in
  let sorted_primitive_topology = Topology.Private.view
      (Geometry.topology sorted_primitives) in
  let sorted_vertex_ids = Geometry.find_attribute ~owner:Attribute.Vertex
      "vertex_id" sorted_primitives |> Option.get
      |> Attribute.get (Attribute.key ~name:"vertex_id"
        ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and sorted_primitive_ids = Geometry.find_attribute ~owner:Attribute.Primitive
      "primitive_id" sorted_primitives |> Option.get
      |> Attribute.get (Attribute.key ~name:"primitive_id"
        ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if sorted_primitive_topology.vertex_points <> [|0; 2; 3; 0; 1; 2|]
     || sorted_vertex_ids <> [|3; 4; 5; 0; 1; 2|]
     || sorted_primitive_ids <> [|20; 10|] then
    fail "primitive reverse sort/vertex payload remap";
  let duplicated = Ops.duplicate ~grain:1 ~copies:2
      ~transform:(Mat4.translation (Vec3.create 2. 0. 0.)) sortable_points
      |> get_ok in
  let duplicated_positions = Packed.Float3.Private.view
      (Geometry.positions duplicated) in
  let duplicated_ids = Geometry.find_attribute ~owner:Attribute.Point "point_id"
      duplicated |> Option.get |> Attribute.get (Attribute.key ~name:"point_id"
        ~owner:Attribute.Point Attribute.int) |> Option.get in
  if Geometry.point_count duplicated <> 12
     || Geometry.vertex_count duplicated <> 12
     || Geometry.primitive_count duplicated <> 3
     || duplicated_positions.x.(0) <> 0. || duplicated_positions.x.(4) <> 2.
     || duplicated_positions.x.(8) <> 4.
     || duplicated_ids <> [|0;1;2;3; 0;1;2;3; 0;1;2;3|] then
    fail "cumulative duplicate cardinality/transform/attributes";
  (match Geometry.find_group ~owner:Group.Point "even" duplicated with
   | Some group when Group.cardinality group = 6 -> ()
   | _ -> fail "duplicate group replication");
  let duplicate_once = Ops.duplicate ~copies:0 sortable_points |> get_ok in
  if Geometry.data_id duplicate_once <> Geometry.data_id sortable_points then
    fail "zero-copy duplicate was not identity";
  (match Ops.duplicate ~copies:(-1) sortable_points with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "duplicate accepted a negative copy count");
  let topology_index = Topology_index.create (Geometry.topology triangle_geometry) in
  let topology_index_cached = Topology_index.create
      (Geometry.topology triangle_geometry)
  and topology_index_cold = Topology_index.create_uncached
      (Geometry.topology triangle_geometry) in
  if topology_index_cached != topology_index
     || topology_index_cold == topology_index
     || Topology_index.edge_count topology_index_cold <> 5
     || Topology_index.edge_count topology_index <> 5
     || Topology_index.boundary_edge_count topology_index <> 4
     || Topology_index.non_manifold_edge_count topology_index <> 0
     || Topology_index.point_incidence_count topology_index 0 <> 2
     || Topology_index.opposite_vertex topology_index 2 <> 3
     || Topology_index.opposite_vertex topology_index 3 <> 2
  then fail "packed reverse topology/half-edge incidence";
  let point_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float [|1.; 2.; 3.; 4.|]) |> get_ok in
  let weighted_quad = Geometry.with_attribute point_weight geometry |> get_ok in
  let promoted domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote ~grain:1 ~source:Attribute.Point
        ~destination:Attribute.Primitive ~name:"weight" weighted_quad |> get_ok) in
  let promoted_one = promoted 1 and promoted_many = promoted 4 in
  let promoted_values value = Geometry.find_attribute
      ~owner:Attribute.Primitive "weight" value |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Primitive
          Attribute.float) |> Option.get in
  if promoted_values promoted_one <> [|2.5|]
     || promoted_values promoted_one <> promoted_values promoted_many
     || Geometry.find_attribute ~owner:Attribute.Point "weight" promoted_one <> None
  then fail "point-to-primitive attribute promotion";
  let primitive_weight = Attribute.create_owned ~name:"piece_weight"
      ~owner:Attribute.Primitive (Attribute.Float [|10.; 20.|]) |> get_ok in
  let weighted_triangles = Geometry.with_attribute primitive_weight
      triangle_geometry |> get_ok in
  let point_weights = Attribute_ops.promote ~grain:1
      ~source:Attribute.Primitive ~destination:Attribute.Point
      ~name:"piece_weight" weighted_triangles |> get_ok in
  let point_weights = Geometry.find_attribute ~owner:Attribute.Point
      "piece_weight" point_weights |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece_weight" ~owner:Attribute.Point
          Attribute.float) |> Option.get in
  if point_weights <> [|15.; 10.; 15.; 20.|] then
    fail "primitive-to-point unique-incidence promotion";
  let reduction_values = Attribute.create_owned ~name:"sample"
      ~owner:Attribute.Point (Attribute.Float [|9.; 2.; 9.; 2.|]) |> get_ok
  and reduction_ids = Attribute.create_owned ~name:"sample_id"
      ~owner:Attribute.Point (Attribute.Int [|9; 2; 9; 2|]) |> get_ok
  and reduction_labels = Attribute.create_owned ~name:"sample_label"
      ~owner:Attribute.Point (Attribute.Text [|"z"; "a"; "z"; "a"|]) |> get_ok in
  let reductions = geometry
      |> Geometry.with_attribute reduction_values |> get_ok
      |> Geometry.with_attribute reduction_ids |> get_ok
      |> Geometry.with_attribute reduction_labels |> get_ok in
  let owner_point = Attribute.create_owned ~name:"owner_point"
      ~owner:Attribute.Point (Attribute.Int [|10; 11; 12; 13|]) |> get_ok
  and owner_vertex = Attribute.create_owned ~name:"owner_vertex"
      ~owner:Attribute.Vertex (Attribute.Int [|20; 21; 22; 23; 24; 25|]) |> get_ok
  and owner_primitive = Attribute.create_owned ~name:"owner_primitive"
      ~owner:Attribute.Primitive (Attribute.Int [|30; 31|]) |> get_ok
  and owner_detail = Attribute.create_owned ~name:"owner_detail"
      ~owner:Attribute.Detail (Attribute.Int [|40|]) |> get_ok in
  let owner_source = triangle_geometry
      |> Geometry.with_attribute owner_point |> get_ok
      |> Geometry.with_attribute owner_vertex |> get_ok
      |> Geometry.with_attribute owner_primitive |> get_ok
      |> Geometry.with_attribute owner_detail |> get_ok in
  let expect_owner_indices source destination name expected =
    let promoted = Attribute_ops.promote ~method_:Attribute_ops.First
        ~index_attribute:"source_index" ~source ~destination ~name owner_source
        |> get_ok in
    let indices = Geometry.find_attribute ~owner:destination "source_index"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"source_index" ~owner:destination Attribute.int) |> Option.get in
    if indices <> expected then fail (Printf.sprintf
        "promotion source-index ownership mapping %s" name) in
  expect_owner_indices Attribute.Point Attribute.Vertex "owner_point"
    [|0; 1; 2; 0; 2; 3|];
  expect_owner_indices Attribute.Primitive Attribute.Vertex "owner_primitive"
    [|0; 0; 0; 1; 1; 1|];
  expect_owner_indices Attribute.Vertex Attribute.Primitive "owner_vertex" [|0; 3|];
  expect_owner_indices Attribute.Point Attribute.Primitive "owner_point" [|0; 0|];
  expect_owner_indices Attribute.Vertex Attribute.Point "owner_vertex" [|0; 1; 2; 5|];
  expect_owner_indices Attribute.Primitive Attribute.Point "owner_primitive"
    [|0; 0; 0; 1|];
  expect_owner_indices Attribute.Detail Attribute.Point "owner_detail" [|0; 0; 0; 0|];
  expect_owner_indices Attribute.Point Attribute.Detail "owner_point" [|0|];
  let promoted_float method_ = Attribute_ops.promote ~method_ ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Detail ~name:"sample"
      reductions |> get_ok |> Geometry.find_attribute ~owner:Attribute.Detail "sample"
      |> Option.get |> Attribute.get (Attribute.key ~name:"sample"
        ~owner:Attribute.Detail Attribute.float) |> Option.get
  and promoted_int method_ = Attribute_ops.promote ~method_ ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Detail ~name:"sample_id"
      reductions |> get_ok |> Geometry.find_attribute ~owner:Attribute.Detail "sample_id"
      |> Option.get |> Attribute.get (Attribute.key ~name:"sample_id"
        ~owner:Attribute.Detail Attribute.int) |> Option.get
  and promoted_text method_ = Attribute_ops.promote ~method_ ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Detail ~name:"sample_label"
      reductions |> get_ok |> Geometry.find_attribute ~owner:Attribute.Detail
        "sample_label" |> Option.get |> Attribute.get
        (Attribute.key ~name:"sample_label" ~owner:Attribute.Detail Attribute.text)
      |> Option.get in
  if promoted_float Attribute_ops.Mode <> [|2.|]
     || promoted_float Attribute_ops.Median <> [|9.|]
     || promoted_int Attribute_ops.Mode <> [|2|]
     || promoted_int Attribute_ops.Median <> [|9|]
     || promoted_text Attribute_ops.Mode <> [|"a"|]
     || promoted_text Attribute_ops.Median <> [|"z"|] then
    fail "attribute promote deterministic mode/upper median";
  if promoted_text Attribute_ops.Average <> [|"z"|]
      || promoted_text Attribute_ops.Sum <> [|"zaza"|]
      || promoted_text Attribute_ops.Minimum <> [|"z"|]
      || promoted_text Attribute_ops.Maximum <> [|"z"|]
      || promoted_text Attribute_ops.Sum_squares <> [|"z"|]
      || promoted_text Attribute_ops.Root_mean_square <> [|"z"|] then
    fail "attribute promote Houdini string/index reduction policy";
  List.iter (fun method_ ->
    let promoted = Attribute_ops.promote ~method_ ~delete_source:false
        ~index_attribute:"text_source" ~into:"indexed_text"
        ~source:Attribute.Point ~destination:Attribute.Detail
        ~name:"sample_label" reductions |> get_ok in
    let value = Geometry.find_attribute ~owner:Attribute.Detail "indexed_text"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"indexed_text" ~owner:Attribute.Detail Attribute.text)
        |> Option.get
    and index = Geometry.find_attribute ~owner:Attribute.Detail "text_source"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"text_source" ~owner:Attribute.Detail Attribute.int)
        |> Option.get in
    if value <> [|"z"|] || index <> [|0|] then
      fail "string numeric fallback source index")
    [Attribute_ops.Minimum; Attribute_ops.Maximum];
  let promote_array domains method_ name = Parallel.run ~domains (fun () ->
    Attribute_ops.promote ~grain:1 ~method_ ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Detail ~name reductions
    |> get_ok) in
  let float_all_one = promote_array 1 Attribute_ops.Array_all "sample"
  and float_all_many = promote_array 4 Attribute_ops.Array_all "sample"
  and float_unique_one = promote_array 1 Attribute_ops.Unique_values "sample"
  and float_unique_many = promote_array 4 Attribute_ops.Unique_values "sample"
  and int_all_one = promote_array 1 Attribute_ops.Array_all "sample_id"
  and int_all_many = promote_array 4 Attribute_ops.Array_all "sample_id"
  and int_unique_one = promote_array 1 Attribute_ops.Unique_values "sample_id"
  and int_unique_many = promote_array 4 Attribute_ops.Unique_values "sample_id" in
  let float_all = float_array_values ~owner:Attribute.Detail ~name:"sample"
      float_all_one
  and float_all_parallel = float_array_values ~owner:Attribute.Detail
      ~name:"sample" float_all_many
  and float_unique = float_array_values ~owner:Attribute.Detail ~name:"sample"
      float_unique_one
  and float_unique_parallel = float_array_values ~owner:Attribute.Detail
      ~name:"sample" float_unique_many
  and int_all = int_array_values ~owner:Attribute.Detail ~name:"sample_id"
      int_all_one
  and int_all_parallel = int_array_values ~owner:Attribute.Detail
      ~name:"sample_id" int_all_many
  and int_unique = int_array_values ~owner:Attribute.Detail ~name:"sample_id"
      int_unique_one
  and int_unique_parallel = int_array_values ~owner:Attribute.Detail
      ~name:"sample_id" int_unique_many in
  if float_all.offsets <> [|0; 4|] || float_all.values <> [|9.; 2.; 9.; 2.|]
      || float_unique.offsets <> [|0; 2|]
      || float_unique.values <> [|2.; 9.|]
      || int_all.offsets <> [|0; 4|] || int_all.values <> [|9; 2; 9; 2|]
      || int_unique.offsets <> [|0; 2|] || int_unique.values <> [|2; 9|]
      || float_all <> float_all_parallel
      || float_unique <> float_unique_parallel
      || int_all <> int_all_parallel || int_unique <> int_unique_parallel then
    fail "packed all/unique promotion values/domain exactness";
  let indexed_float method_ expected_value expected_index =
    let promoted = Attribute_ops.promote ~method_ ~delete_source:false
        ~index_attribute:"sample_source" ~into:"indexed_sample"
        ~source:Attribute.Point ~destination:Attribute.Detail ~name:"sample"
        reductions |> get_ok in
    let value = Geometry.find_attribute ~owner:Attribute.Detail "indexed_sample"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"indexed_sample" ~owner:Attribute.Detail Attribute.float)
        |> Option.get
    and index = Geometry.find_attribute ~owner:Attribute.Detail "sample_source"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"sample_source" ~owner:Attribute.Detail Attribute.int)
        |> Option.get in
    if value <> [|expected_value|] || index <> [|expected_index|] then
      fail "scalar float promotion source index" in
  indexed_float Attribute_ops.First 9. 0;
  indexed_float Attribute_ops.Last 2. 3;
  indexed_float Attribute_ops.Minimum 2. 1;
  indexed_float Attribute_ops.Maximum 9. 0;
  indexed_float Attribute_ops.Mode 2. 1;
  let special_values = Attribute.create_owned ~name:"special"
      ~owner:Attribute.Point (Attribute.Float [|1.; nan; 0.; -0.|]) |> get_ok in
  let special_source = Geometry.with_attribute special_values geometry |> get_ok in
  List.iter (fun method_ ->
    let promoted = Attribute_ops.promote ~method_ ~index_attribute:"special_source"
        ~source:Attribute.Point ~destination:Attribute.Detail ~name:"special"
        special_source |> get_ok in
    let value = Geometry.find_attribute ~owner:Attribute.Detail "special" promoted
        |> Option.get |> Attribute.get (Attribute.key ~name:"special"
          ~owner:Attribute.Detail Attribute.float) |> Option.get
    and index = Geometry.find_attribute ~owner:Attribute.Detail "special_source"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"special_source" ~owner:Attribute.Detail Attribute.int)
        |> Option.get in
    if not (Float.is_nan value.(0)) || index <> [|1|] then
      fail "indexed float extremum changed NaN propagation")
    [Attribute_ops.Minimum; Attribute_ops.Maximum];
  let unique_special = Attribute.create_owned ~name:"unique_special"
      ~owner:Attribute.Point (Attribute.Float [|nan; nan; 0.; -0.|]) |> get_ok in
  let unique_special_source = Geometry.with_attribute unique_special geometry
      |> get_ok in
  let unique_special domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote ~grain:1 ~method_:Attribute_ops.Unique_values
        ~source:Attribute.Point ~destination:Attribute.Detail
        ~name:"unique_special" unique_special_source |> get_ok
      |> float_array_values ~owner:Attribute.Detail ~name:"unique_special") in
  let unique_special_one = unique_special 1
  and unique_special_many = unique_special 4 in
  let exact_special = unique_special_one.offsets = unique_special_many.offsets
      && Array.length unique_special_one.values
         = Array.length unique_special_many.values
      && Array.for_all2 (fun left right ->
           Int64.bits_of_float left = Int64.bits_of_float right)
           unique_special_one.values unique_special_many.values in
  if not exact_special || unique_special_one.offsets <> [|0; 2|]
      || not (Array.exists Float.is_nan unique_special_one.values)
      || not (Array.exists (fun value -> value = 0.) unique_special_one.values)
  then fail "unique float total-comparison equivalence/domain exactness";
  let zero_values = Attribute.create_owned ~name:"signed_zero"
      ~owner:Attribute.Point (Attribute.Float [|0.; -0.|]) |> get_ok in
  let zero_source = Geometry.with_attribute zero_values
      (Ops.points [|(0., 0., 0.); (1., 0., 0.)|]) |> get_ok in
  let signed_zero method_ expected_bits expected_index =
    let promoted = Attribute_ops.promote ~method_ ~index_attribute:"zero_source"
        ~source:Attribute.Point ~destination:Attribute.Detail
        ~name:"signed_zero" zero_source |> get_ok in
    let value = Geometry.find_attribute ~owner:Attribute.Detail "signed_zero"
        promoted |> Option.get |> Attribute.get (Attribute.key ~name:"signed_zero"
          ~owner:Attribute.Detail Attribute.float) |> Option.get
    and index = Geometry.find_attribute ~owner:Attribute.Detail "zero_source"
        promoted |> Option.get |> Attribute.get (Attribute.key ~name:"zero_source"
          ~owner:Attribute.Detail Attribute.int) |> Option.get in
    if Int64.bits_of_float value.(0) <> expected_bits
        || index <> [|expected_index|] then
      fail "indexed float extremum changed signed-zero semantics" in
  signed_zero Attribute_ops.Minimum Int64.min_int 1;
  signed_zero Attribute_ops.Maximum 0L 0;
  let indexed_scalar name method_ expected_index =
    let promoted = Attribute_ops.promote ~method_ ~delete_source:false
        ~index_attribute:"source_index" ~into:("indexed_" ^ name)
        ~source:Attribute.Point ~destination:Attribute.Detail ~name reductions
        |> get_ok in
    let index = Geometry.find_attribute ~owner:Attribute.Detail "source_index"
        promoted |> Option.get |> Attribute.get (Attribute.key
          ~name:"source_index" ~owner:Attribute.Detail Attribute.int)
        |> Option.get in
    if index <> [|expected_index|]
       || Geometry.find_attribute ~owner:Attribute.Detail ("indexed_" ^ name)
            promoted = None then
      fail "integer/text promotion source index" in
  indexed_scalar "sample_id" Attribute_ops.Mode 1;
  indexed_scalar "sample_label" Attribute_ops.Mode 1;
  let promoted_pattern domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote_pattern ~grain:1 ~method_:Attribute_ops.First
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Detail ~pattern:"sample* ^sample_label"
        reductions |> get_ok) in
  let pattern_one = promoted_pattern 1 and pattern_many = promoted_pattern 4 in
  let pattern_sample geometry = Geometry.find_attribute ~owner:Attribute.Detail
      "sample" geometry |> Option.get |> Attribute.get (Attribute.key
        ~name:"sample" ~owner:Attribute.Detail Attribute.float) |> Option.get
  and pattern_id geometry = Geometry.find_attribute ~owner:Attribute.Detail
      "sample_id" geometry |> Option.get |> Attribute.get (Attribute.key
        ~name:"sample_id" ~owner:Attribute.Detail Attribute.int) |> Option.get in
  if pattern_sample pattern_one <> [|9.|] || pattern_id pattern_one <> [|9|]
     || Geometry.find_attribute ~owner:Attribute.Detail "sample_label"
          pattern_one <> None
     || pattern_sample pattern_one <> pattern_sample pattern_many
     || pattern_id pattern_one <> pattern_id pattern_many then
    fail "pattern attribute promotion/order/domain determinism";
  let array_pattern domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote_pattern ~grain:1
        ~method_:Attribute_ops.Unique_values ~delete_source:false
        ~source:Attribute.Point ~destination:Attribute.Detail
        ~pattern:"sample sample_id" reductions |> get_ok) in
  let array_pattern_one = array_pattern 1 and array_pattern_many = array_pattern 4 in
  let array_pattern_float geometry = float_array_values ~owner:Attribute.Detail
      ~name:"sample" geometry
  and array_pattern_int geometry = int_array_values ~owner:Attribute.Detail
      ~name:"sample_id" geometry in
  if array_pattern_float array_pattern_one
      <> array_pattern_float array_pattern_many
      || array_pattern_int array_pattern_one <> array_pattern_int array_pattern_many
      || (array_pattern_float array_pattern_one).values <> [|2.; 9.|]
      || (array_pattern_int array_pattern_one).values <> [|2; 9|] then
    fail "pattern unique-array promotion/domain exactness";
  let unmatched_pattern = Attribute_ops.promote_pattern
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~pattern:"missing*" reductions |> get_ok in
  if Geometry.data_id unmatched_pattern <> Geometry.data_id reductions then
    fail "unmatched promotion pattern was not an identity";
  (match Attribute_ops.promote_pattern ~source:Attribute.Point
      ~destination:Attribute.Detail ~pattern:"[bad" reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "pattern promotion accepted a malformed glob");
  let renamed_pattern = Attribute_ops.promote_pattern ~grain:1
      ~method_:Attribute_ops.First ~source:Attribute.Point
      ~destination:Attribute.Detail ~pattern:"sample*"
      ~into_pattern:"promoted*" ~index_pattern:"source*" reductions |> get_ok in
  let renamed_sample = Geometry.find_attribute ~owner:Attribute.Detail
      "promoted" renamed_pattern |> Option.get |> Attribute.get
      (Attribute.key ~name:"promoted" ~owner:Attribute.Detail Attribute.float)
      |> Option.get
  and renamed_id = Geometry.find_attribute ~owner:Attribute.Detail
      "promoted_id" renamed_pattern |> Option.get |> Attribute.get
      (Attribute.key ~name:"promoted_id" ~owner:Attribute.Detail Attribute.int)
      |> Option.get
  and renamed_label = Geometry.find_attribute ~owner:Attribute.Detail
      "promoted_label" renamed_pattern |> Option.get |> Attribute.get
      (Attribute.key ~name:"promoted_label" ~owner:Attribute.Detail Attribute.text)
      |> Option.get
  and renamed_index name = Geometry.find_attribute ~owner:Attribute.Detail name
      renamed_pattern |> Option.get |> Attribute.get
      (Attribute.key ~name ~owner:Attribute.Detail Attribute.int) |> Option.get in
  if renamed_sample <> [|9.|] || renamed_id <> [|9|]
      || renamed_label <> [|"z"|]
      || renamed_index "source" <> [|0|]
      || renamed_index "source_id" <> [|0|]
      || renamed_index "source_label" <> [|0|]
      || Geometry.find_attribute ~owner:Attribute.Point "sample"
           renamed_pattern <> None
      || Geometry.find_attribute ~owner:Attribute.Point "sample_id"
           renamed_pattern <> None
      || Geometry.find_attribute ~owner:Attribute.Point "sample_label"
           renamed_pattern <> None then
    fail "pattern promotion capture rename/delete semantics";
  let multi_renamed = Attribute_ops.promote_pattern ~grain:1
      ~method_:Attribute_ops.First ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~pattern:"sample sample_* ^sample_label"
      ~into_pattern:"value reduced_*"
      ~index_pattern:"value_source reduced_source_*" reductions |> get_ok in
  let detail_float name = Geometry.find_attribute ~owner:Attribute.Detail name
      multi_renamed |> Option.get |> Attribute.get (Attribute.key ~name
        ~owner:Attribute.Detail Attribute.float) |> Option.get
  and detail_int name = Geometry.find_attribute ~owner:Attribute.Detail name
      multi_renamed |> Option.get |> Attribute.get (Attribute.key ~name
        ~owner:Attribute.Detail Attribute.int) |> Option.get in
  if detail_float "value" <> [|9.|]
      || detail_int "reduced_id" <> [|9|]
      || detail_int "value_source" <> [|0|]
      || detail_int "reduced_source_id" <> [|0|]
      || Geometry.find_attribute ~owner:Attribute.Detail "reduced_label"
           multi_renamed <> None then
    fail "multi-term promotion destination/index rewrite";
  let overlap_source = Pdk.Ops.points
      [|(0., 0., 0.); (1., 0., 0.); (2., 0., 0.)|] in
  let overlap_a = Attribute.create_owned ~name:"a" ~owner:Attribute.Point
      (Attribute.Int [|1; 2; 3|]) |> get_ok
  and overlap_copy = Attribute.create_owned ~name:"copy_a"
      ~owner:Attribute.Point (Attribute.Int [|4; 5; 6|]) |> get_ok
  and overlap_piece = Attribute.create_owned ~name:"piece"
      ~owner:Attribute.Point (Attribute.Int [|0; 1; 2|]) |> get_ok in
  let overlap_source = overlap_source
      |> Geometry.with_attribute overlap_a |> get_ok
      |> Geometry.with_attribute overlap_copy |> get_ok
      |> Geometry.with_attribute overlap_piece |> get_ok in
  let overlap_promoted = Attribute_ops.promote_pattern ~method_:Attribute_ops.First
      ~piece_attribute:"piece" ~source:Attribute.Point
      ~destination:Attribute.Point ~pattern:"[ac]*"
      ~into_pattern:"copy_?*" overlap_source |> get_ok in
  let overlap_result name = Geometry.find_attribute ~owner:Attribute.Point name
      overlap_promoted |> Option.get |> Attribute.get
      (Attribute.key ~name ~owner:Attribute.Point Attribute.int) |> Option.get in
  if Geometry.find_attribute ~owner:Attribute.Point "a" overlap_promoted <> None
      || overlap_result "copy_a" <> [|1; 2; 3|]
      || overlap_result "copy_copy_a" <> [|4; 5; 6|] then
    fail "pattern promotion overlapping simultaneous rename/delete";
  (match Attribute_ops.promote_pattern ~source:Attribute.Point
      ~destination:Attribute.Point ~pattern:"sample*" ~into_pattern:"P*"
      reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "pattern promotion accepted a canonical P rewrite");
  (match Attribute_ops.promote ~method_:Attribute_ops.Average
      ~index_attribute:"source_index" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"sample" reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "average promotion accepted a source index output");
  (match Attribute_ops.promote ~method_:Attribute_ops.First
      ~into:"collision" ~index_attribute:"collision" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"sample" reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "promotion accepted colliding value/index names");
  let tuple_values = Packed.Float2.of_owned ~x:[|1.; 2.; 3.; 4.|]
      ~y:[|4.; 3.; 2.; 1.|] |> get_ok in
  let tuple_attribute = Attribute.create_owned ~name:"tuple_value"
      ~owner:Attribute.Point (Attribute.Float2 tuple_values) |> get_ok in
  let tuple_source = Geometry.with_attribute tuple_attribute reductions |> get_ok in
  let tuple_indexed = Attribute_ops.promote ~method_:Attribute_ops.Maximum
      ~index_attribute:"tuple_source" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"tuple_value" tuple_source |> get_ok in
  let tuple_source_indices = int_array_values ~owner:Attribute.Detail
      ~name:"tuple_source" tuple_indexed in
  if tuple_source_indices.offsets <> [|0;2|]
      || tuple_source_indices.values <> [|3;0|] then
    fail "tuple promotion component source indices";
  let empty_source = Ops.points [||] in
  let empty_value = Attribute.create_owned ~name:"empty_value"
      ~owner:Attribute.Point (Attribute.Float [||]) |> get_ok in
  let empty_source = Geometry.with_attribute empty_value empty_source |> get_ok in
  let empty_promoted = Attribute_ops.promote ~method_:Attribute_ops.First
      ~index_attribute:"empty_source" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"empty_value" empty_source |> get_ok in
  let empty_index = Geometry.find_attribute ~owner:Attribute.Detail
      "empty_source" empty_promoted |> Option.get |> Attribute.get
      (Attribute.key ~name:"empty_source" ~owner:Attribute.Detail Attribute.int)
      |> Option.get in
  if empty_index <> [|-1|] then fail "empty promotion source index sentinel";
  let empty_array = Attribute_ops.promote ~method_:Attribute_ops.Array_all
      ~source:Attribute.Point ~destination:Attribute.Detail ~name:"empty_value"
      empty_source |> get_ok
      |> float_array_values ~owner:Attribute.Detail ~name:"empty_value" in
  if empty_array.offsets <> [|0; 0|] || empty_array.values <> [||] then
    fail "empty array promotion row";
  (match Attribute_ops.promote ~method_:Attribute_ops.Array_all
      ~index_attribute:"source_index" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"sample" reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "array promotion accepted an index attribute");
  (match Attribute_ops.promote ~method_:Attribute_ops.Unique_values
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~name:"tuple_value" tuple_source with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "array promotion flattened a wider tuple ambiguously");
  (match Attribute_ops.promote ~method_:Attribute_ops.Array_all
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~name:"sample_label" reductions with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "array promotion invented text-array storage");
  let source_array = Packed.Int_array.create_owned ~offsets:[|0; 1; 2; 3; 4|]
      ~values:[|1; 2; 3; 4|] |> get_ok in
  let source_array = Attribute.create_owned ~name:"source_array"
      ~owner:Attribute.Point (Attribute.Int_array source_array) |> get_ok in
  let source_array_geometry = Geometry.with_attribute source_array reductions
      |> get_ok in
  (match Attribute_ops.promote ~method_:Attribute_ops.Array_all
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~name:"source_array" source_array_geometry with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "array promotion nested existing arrays without a policy");
  let piece = Attribute.create_owned ~name:"piece"
      ~owner:Attribute.Primitive (Attribute.Int [|7; 7|]) |> get_ok in
  let piece_source = triangle_geometry
      |> Geometry.with_attribute reduction_values |> get_ok
      |> Geometry.with_attribute piece |> get_ok in
  let piece_promoted = Attribute_ops.promote ~grain:1
      ~method_:Attribute_ops.First ~delete_source:false ~piece_attribute:"piece"
      ~source:Attribute.Point ~destination:Attribute.Primitive ~name:"sample"
      piece_source |> get_ok in
  let piece_values = Geometry.find_attribute ~owner:Attribute.Primitive "sample"
      piece_promoted |> Option.get |> Attribute.get (Attribute.key ~name:"sample"
        ~owner:Attribute.Primitive Attribute.float) |> Option.get in
  if piece_values <> [|9.; 9.|] then
    fail "piece promotion did not deduplicate/order contributing sources";
  let piece_arrays = Attribute_ops.promote ~grain:1
      ~method_:Attribute_ops.Array_all ~delete_source:false
      ~piece_attribute:"piece" ~into:"piece_samples" ~source:Attribute.Point
      ~destination:Attribute.Primitive ~name:"sample" piece_source |> get_ok in
  let piece_arrays = float_array_values ~owner:Attribute.Primitive
      ~name:"piece_samples" piece_arrays in
  if piece_arrays.offsets <> [|0; 4; 8|]
      || piece_arrays.values <> [|9.; 2.; 9.; 2.; 9.; 2.; 9.; 2.|] then
    fail "piece array promotion did not remap complete ordered rows";
  let piece_indexed = Attribute_ops.promote ~grain:1
      ~method_:Attribute_ops.Mode ~delete_source:false ~piece_attribute:"piece"
      ~index_attribute:"sample_source" ~source:Attribute.Point
      ~destination:Attribute.Primitive ~name:"sample" piece_source |> get_ok in
  let piece_modes = Geometry.find_attribute ~owner:Attribute.Primitive "sample"
      piece_indexed |> Option.get |> Attribute.get (Attribute.key ~name:"sample"
        ~owner:Attribute.Primitive Attribute.float) |> Option.get
  and piece_indices = Geometry.find_attribute ~owner:Attribute.Primitive
      "sample_source" piece_indexed |> Option.get |> Attribute.get
      (Attribute.key ~name:"sample_source" ~owner:Attribute.Primitive Attribute.int)
      |> Option.get in
  if piece_modes <> [|2.; 2.|] || piece_indices <> [|1; 1|] then
    fail "piece promotion source index/tie semantics";
  let piece_averaged = Attribute_ops.promote ~grain:1
      ~method_:Attribute_ops.Average ~delete_source:false ~piece_attribute:"piece"
      ~source:Attribute.Point ~destination:Attribute.Primitive ~name:"sample"
      piece_source |> get_ok in
  let piece_averages = Geometry.find_attribute ~owner:Attribute.Primitive "sample"
      piece_averaged |> Option.get |> Attribute.get (Attribute.key ~name:"sample"
        ~owner:Attribute.Primitive Attribute.float) |> Option.get in
  if piece_averages <> [|5.5; 5.5|] then
    fail "piece promotion counted shared source elements more than once";
  let primitive_arrays = Attribute_ops.promote ~grain:1
      ~method_:Attribute_ops.Array_all ~delete_source:false
      ~source:Attribute.Primitive ~destination:Attribute.Point
      ~name:"piece_weight" weighted_triangles |> get_ok in
  let primitive_arrays = float_array_values ~owner:Attribute.Point
      ~name:"piece_weight" primitive_arrays in
  if primitive_arrays.offsets <> [|0; 2; 3; 5; 6|]
      || primitive_arrays.values <> [|10.; 20.; 10.; 10.; 20.; 20.|] then
    fail "primitive-to-point array promotion incidence order";
  let point_piece = Attribute.create_owned ~name:"point_piece"
      ~owner:Attribute.Point (Attribute.Text [|"a"; "a"; "b"; "b"|]) |> get_ok in
  let point_piece_source = reductions |> Geometry.with_attribute point_piece |> get_ok in
  let same_owner_piece = Attribute_ops.promote ~method_:Attribute_ops.Average
      ~delete_source:false ~piece_attribute:"point_piece" ~into:"piece_mean"
      ~source:Attribute.Point ~destination:Attribute.Point ~name:"sample"
      point_piece_source |> get_ok in
  let piece_means = Geometry.find_attribute ~owner:Attribute.Point "piece_mean"
      same_owner_piece |> Option.get |> Attribute.get (Attribute.key
        ~name:"piece_mean" ~owner:Attribute.Point Attribute.float) |> Option.get in
  if piece_means <> [|5.5; 5.5; 5.5; 5.5|] then
    fail "text-partition same-owner piece promotion";
  let tuple = Packed.Float2.of_owned ~x:[|1.; 4.; 3.; 2.|]
      ~y:[|10.; 1.; 8.; 7.|] |> get_ok in
  let tuple = Attribute.create_owned ~name:"tuple" ~owner:Attribute.Point
      (Attribute.Float2 tuple) |> get_ok in
  let tuple_source = Geometry.with_attribute tuple point_piece_source |> get_ok in
  let tuple_median = Attribute_ops.promote ~method_:Attribute_ops.Median
      ~delete_source:false ~piece_attribute:"point_piece" ~into:"tuple_median"
      ~source:Attribute.Point ~destination:Attribute.Point ~name:"tuple"
      tuple_source |> get_ok in
  let tuple_median = Geometry.find_attribute ~owner:Attribute.Point "tuple_median"
      tuple_median |> Option.get |> Attribute.get (Attribute.key
        ~name:"tuple_median" ~owner:Attribute.Point Attribute.float2) |> Option.get
      |> Packed.Float2.Private.view in
  if tuple_median.x <> [|4.; 4.; 3.; 3.|]
     || tuple_median.y <> [|10.; 10.; 8.; 8.|] then
    fail "piece tuple promotion was not component-wise upper median";
  let tuple_indexed domains = Parallel.run ~domains (fun () ->
    Attribute_ops.promote ~grain:1 ~method_:Attribute_ops.Maximum
      ~delete_source:false ~index_attribute:"tuple_sources"
      ~into:"tuple_maximum" ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"tuple" tuple_source |> get_ok) in
  let tuple_index_one = tuple_indexed 1 and tuple_index_many = tuple_indexed 4 in
  let tuple_maximum geometry = Geometry.find_attribute ~owner:Attribute.Detail
      "tuple_maximum" geometry |> Option.get |> Attribute.get (Attribute.key
        ~name:"tuple_maximum" ~owner:Attribute.Detail Attribute.float2)
      |> Option.get |> Packed.Float2.Private.view
  and tuple_sources geometry = int_array_values ~owner:Attribute.Detail
      ~name:"tuple_sources" geometry in
  let maximum = tuple_maximum tuple_index_one
  and sources = tuple_sources tuple_index_one
  and parallel_sources = tuple_sources tuple_index_many in
  if maximum.x <> [|4.|] || maximum.y <> [|10.|]
      || sources.offsets <> [|0;2|] || sources.values <> [|1;0|]
      || sources <> parallel_sources then
    fail "component-wise tuple source-index output/domain exactness";
  let bad_piece = Attribute.create_owned ~name:"bad_piece"
      ~owner:Attribute.Primitive (Attribute.Float [|0.; 0.|]) |> get_ok in
  let bad_piece_source = Geometry.with_attribute bad_piece piece_source |> get_ok in
  (match Attribute_ops.promote ~piece_attribute:"missing"
      ~source:Attribute.Point ~destination:Attribute.Primitive ~name:"sample"
      piece_source with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "attribute promote accepted a missing piece attribute");
  (match Attribute_ops.promote ~piece_attribute:"bad_piece"
      ~source:Attribute.Point ~destination:Attribute.Primitive ~name:"sample"
      bad_piece_source with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "attribute promote accepted a numeric piece attribute");
  let dense_count = 40_000 and dense_piece_size = 40 in
  let dense = Ops.points (Array.init dense_count (fun point ->
      float_of_int point, 0., 0.)) in
  let dense_values = Attribute.create_owned ~name:"dense_value"
      ~owner:Attribute.Point (Attribute.Int
        (Array.init dense_count (fun point -> (point * 17) mod 101))) |> get_ok
  and dense_pieces = Attribute.create_owned ~name:"dense_piece"
      ~owner:Attribute.Point (Attribute.Int
        (Array.init dense_count (fun point -> point / dense_piece_size))) |> get_ok in
  let dense = dense |> Geometry.with_attribute dense_values |> get_ok
      |> Geometry.with_attribute dense_pieces |> get_ok in
  let dense_promoted domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote ~grain:7 ~method_:Attribute_ops.Mode
        ~piece_attribute:"dense_piece" ~into:"piece_mode" ~delete_source:false
        ~source:Attribute.Point ~destination:Attribute.Point ~name:"dense_value"
        dense |> get_ok) in
  let dense_one = dense_promoted 1 and dense_many = dense_promoted 4 in
  let dense_result geometry = Geometry.find_attribute ~owner:Attribute.Point
      "piece_mode" geometry |> Option.get |> Attribute.get (Attribute.key
        ~name:"piece_mode" ~owner:Attribute.Point Attribute.int) |> Option.get in
  if dense_result dense_one <> dense_result dense_many
     || (dense_result dense_one).(0) <> 0 then
    fail "piece mode differs between one and four domains";
  let dense_unique domains = Parallel.run ~domains (fun () ->
      Attribute_ops.promote ~grain:257 ~method_:Attribute_ops.Unique_values
        ~piece_attribute:"dense_piece" ~into:"piece_unique"
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Point ~name:"dense_value" dense |> get_ok) in
  let dense_unique_one = dense_unique 1 |> int_array_values
      ~owner:Attribute.Point ~name:"piece_unique"
  and dense_unique_many = dense_unique 4 |> int_array_values
      ~owner:Attribute.Point ~name:"piece_unique" in
  if dense_unique_one <> dense_unique_many
      || Array.length dense_unique_one.offsets <> dense_count + 1
      || Array.length dense_unique_one.values <> dense_count * dense_piece_size
      || dense_unique_one.offsets.(dense_count) <> dense_count * dense_piece_size
  then fail "piece unique-array scale/domain exactness";
  let cancelled_promote = Cancel.create () in
  Cancel.cancel cancelled_promote;
  (match Attribute_ops.promote ~cancel:cancelled_promote
      ~method_:Attribute_ops.Median ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"dense_value" dense with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "median promotion ignored cancellation");
  (match Attribute_ops.promote_pattern ~cancel:cancelled_promote
      ~method_:Attribute_ops.Median ~source:Attribute.Point
      ~destination:Attribute.Detail ~pattern:"dense_*" dense with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "pattern promotion ignored cancellation");
  (match Attribute_ops.promote_pattern ~cancel:cancelled_promote
      ~method_:Attribute_ops.Maximum ~source:Attribute.Point
      ~destination:Attribute.Detail ~pattern:"dense_*"
      ~index_pattern:"source_*" dense with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "indexed pattern promotion ignored cancellation");
  (match Attribute_ops.promote ~cancel:cancelled_promote
      ~method_:Attribute_ops.Unique_values ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"dense_value" dense with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "unique-array promotion ignored cancellation");
  (match Attribute_ops.promote ~grain:0 ~source:Attribute.Point
      ~destination:Attribute.Detail ~name:"dense_value" dense with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "attribute promotion did not structure an invalid grain error");
  let detail = Attribute.create_owned ~name:"gain" ~owner:Attribute.Detail
      (Attribute.Float [|7.|]) |> get_ok in
  let detailed = Geometry.with_attribute detail triangle_geometry |> get_ok in
  let expanded_detail = Attribute_ops.promote ~source:Attribute.Detail
      ~destination:Attribute.Vertex ~name:"gain" detailed |> get_ok in
  (match Geometry.find_attribute ~owner:Attribute.Vertex "gain" expanded_detail with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Float values when values = Array.make 6 7. -> ()
        | _ -> fail "detail-to-vertex attribute promotion")
   | None -> fail "detail promotion missing output");
  let integer = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|1; 2; 3; 4|]) |> get_ok in
  let integer_geometry = Geometry.with_attribute integer geometry |> get_ok in
  (match Attribute_ops.promote ~method_:Attribute_ops.Sum
      ~source:Attribute.Point ~destination:Attribute.Detail ~name:"id"
      integer_geometry with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "unsupported integer promotion did not return a structured error");
  let transfer_source = Ops.points [|(0., 0., 0.); (2., 0., 0.)|] in
  let transfer_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float [|0.; 10.|]) |> get_ok
  and transfer_id = Attribute.create_owned ~name:"id"
      ~owner:Attribute.Point (Attribute.Int [|5; 9|]) |> get_ok in
  let transfer_source = transfer_source
      |> Geometry.with_attribute transfer_weight |> get_ok
      |> Geometry.with_attribute transfer_id |> get_ok in
  let transfer_target = Ops.points
      [|(0., 0., 0.); (1., 0., 0.); (10., 0., 0.)|] in
  let existing_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float [|100.; 100.; 100.|]) |> get_ok in
  let transfer_target = Geometry.with_attribute existing_weight transfer_target
      |> get_ok in
  let transferred domains = Parallel.run ~domains (fun () ->
      Attribute_ops.transfer_points ~grain:1 ~max_distance:3.
        ~mode:(Attribute_ops.Inverse_distance { neighbors = 2; power = 1. })
        ~source:transfer_source ~target:transfer_target () |> get_ok) in
  let transfer_one = transferred 1 and transfer_many = transferred 4 in
  let transferred_weight geometry = Geometry.find_attribute
      ~owner:Attribute.Point "weight" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
          Attribute.float) |> Option.get
  and transferred_id geometry = Geometry.find_attribute
      ~owner:Attribute.Point "id" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"id" ~owner:Attribute.Point
          Attribute.int) |> Option.get in
  if transferred_weight transfer_one <> [|0.; 5.; 100.|]
     || transferred_id transfer_one <> [|5; 5; 0|]
     || transferred_weight transfer_one <> transferred_weight transfer_many
     || transferred_id transfer_one <> transferred_id transfer_many
  then fail "weighted attribute transfer/unmatched/domain determinism";
  let nearest_tie = Attribute_ops.transfer_points ~grain:1 ~names:["id"]
      ~max_distance:1. ~source:transfer_source
      ~target:(Ops.points [|(1., 0., 0.)|]) () |> get_ok in
  if transferred_id nearest_tie <> [|5|] then
    fail "attribute transfer deterministic equal-distance tie";
  let pattern_transfer = Attribute_ops.transfer_points ~grain:1
      ~pattern:"* ^id" ~source:transfer_source
      ~target:(Ops.points [|(0., 0., 0.)|]) () |> get_ok in
  if transferred_weight pattern_transfer <> [|0.|]
     || Geometry.find_attribute ~owner:Attribute.Point "id" pattern_transfer
        <> None then
    fail "point transfer attribute include/exclude pattern";
  (match Attribute_ops.transfer_points ~names:["weight"] ~pattern:"*"
      ~source:transfer_source ~target:transfer_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "point transfer accepted both exact names and a pattern");
  (match Attribute_ops.transfer_points ~pattern:"bad["
      ~source:transfer_source ~target:transfer_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "point transfer accepted a malformed pattern");
  let source_second = Group.init ~owner:Group.Point ~name:"source_second" 2
      (fun point -> point = 1)
  and target_outer = Group.init ~owner:Group.Point ~name:"target_outer" 3
      (fun point -> point <> 1) in
  let restricted_points = Attribute_ops.transfer_points ~grain:1
      ~max_distance:3. ~source_points:source_second ~target_points:target_outer
      ~source:transfer_source ~target:transfer_target () |> function
      | Ok value -> value
      | Error error -> fail (Error.to_string error) in
  if transferred_weight restricted_points <> [|10.; 100.; 100.|]
     || transferred_id restricted_points <> [|9; 0; 0|] then
    fail "point attribute transfer source/target group restriction";
  let restricted_defaults = Attribute_ops.transfer_points ~grain:1
      ~names:["weight"] ~max_distance:0.1
      ~unmatched:Attribute_ops.Default_value ~source_points:source_second
      ~target_points:target_outer ~source:transfer_source
      ~target:transfer_target () |> get_ok in
  if transferred_weight restricted_defaults <> [|0.; 100.; 0.|] then
    fail "point transfer default miss modified unselected target elements";
  let primitive_weight = Attribute.create_owned ~name:"primitive_weight"
      ~owner:Attribute.Primitive (Attribute.Float [|10.; 20.|]) |> get_ok
  and primitive_id = Attribute.create_owned ~name:"primitive_id"
      ~owner:Attribute.Primitive (Attribute.Int [|4; 8|]) |> get_ok in
  let primitive_source = triangle_geometry
      |> Geometry.with_attribute primitive_weight |> get_ok
      |> Geometry.with_attribute primitive_id |> get_ok in
  let primitive_target_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.5|] ~y:[|0.; 0.; 1.5|] ~z:[|0.; 0.; 0.|] in
  let primitive_target_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle primitive_target_topology 0 1 2;
  let primitive_target_geometry = Geometry.create
      ~positions:primitive_target_positions
      ~topology:(Topology.Builder.freeze primitive_target_topology) () |> get_ok in
  let primitive_transferred domains = Parallel.run ~domains (fun () ->
      Attribute_ops.transfer_primitives ~grain:1
        ~mode:(Attribute_ops.Inverse_distance { neighbors = 2; power = 1. })
        ~source:primitive_source ~target:primitive_target_geometry () |> get_ok) in
  let primitive_one = primitive_transferred 1
  and primitive_many = primitive_transferred 4 in
  let transferred_primitive_float geometry = Geometry.find_attribute
      ~owner:Attribute.Primitive "primitive_weight" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"primitive_weight"
          ~owner:Attribute.Primitive Attribute.float) |> Option.get
  and transferred_primitive_int geometry = Geometry.find_attribute
      ~owner:Attribute.Primitive "primitive_id" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"primitive_id"
          ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if not (near_array [|15.|] (transferred_primitive_float primitive_one))
     || transferred_primitive_float primitive_one
        <> transferred_primitive_float primitive_many
     || transferred_primitive_int primitive_one
        <> transferred_primitive_int primitive_many then
    fail (Printf.sprintf
      "primitive-barycenter transfer/tie/domain determinism: weight=%g id=%d"
      (transferred_primitive_float primitive_one).(0)
      (transferred_primitive_int primitive_one).(0));
  let coincident_topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_triangle coincident_topology 0 1 2;
  Topology.Builder.add_triangle coincident_topology 0 1 2;
  let coincident_source = Geometry.create ~positions
      ~topology:(Topology.Builder.freeze coincident_topology)
      ~attributes:[primitive_id] () |> get_ok in
  let coincident_target_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 1.|] ~y:[|0.; 0.; 1.|] ~z:[|0.; 0.; 0.|] in
  let coincident_target_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle coincident_target_topology 0 1 2;
  let coincident_target = Geometry.create ~positions:coincident_target_positions
      ~topology:(Topology.Builder.freeze coincident_target_topology) () |> get_ok in
  let coincident_transfer = Attribute_ops.transfer_primitives ~names:["primitive_id"]
      ~source:coincident_source ~target:coincident_target () |> get_ok in
  if transferred_primitive_int coincident_transfer <> [|4|] then
    fail "primitive transfer deterministic coincident-barycenter tie";
  let second_primitive = Group.init ~owner:Group.Primitive
      ~name:"second_primitive" 2 (fun primitive -> primitive = 1) in
  let restricted_primitive = Attribute_ops.transfer_primitives ~grain:1
      ~pattern:"primitive_* ^primitive_id" ~source_primitives:second_primitive
      ~source:primitive_source
      ~target:primitive_target_geometry () |> get_ok in
  if transferred_primitive_float restricted_primitive <> [|20.|]
     || Geometry.find_attribute ~owner:Attribute.Primitive "primitive_id"
          restricted_primitive <> None then
    fail "primitive attribute transfer source group restriction";
  (match Attribute_ops.transfer_primitives ~source_primitives:source_second
      ~source:primitive_source ~target:primitive_target_geometry () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "primitive transfer accepted a point-owned source group");
  let source_detail = Attribute.create_owned ~name:"asset"
      ~owner:Attribute.Detail (Attribute.Text [|"oak"|]) |> get_ok in
  let detail_source = Geometry.with_attribute source_detail primitive_source
      |> get_ok in
  let detail_target = Attribute_ops.transfer_detail ~source:detail_source
      ~target:primitive_target_geometry () |> get_ok in
  (match Geometry.find_attribute ~owner:Attribute.Detail "asset" detail_target with
   | Some attribute when Attribute.storage_id attribute
       = Attribute.storage_id source_detail ->
       (match Attribute.storage attribute with
        | Attribute.Text [|"oak"|] -> ()
        | _ -> fail "detail transfer payload")
   | _ -> fail "detail transfer did not structurally share source payload");
  let detail_p = Attribute.create_owned ~name:"P" ~owner:Attribute.Detail
      (Attribute.Int [|23|]) |> get_ok in
  let detail_p_source = Geometry.with_attribute detail_p detail_source |> get_ok in
  let detail_pattern_target = Attribute_ops.transfer_detail ~pattern:"^P"
      ~source:detail_p_source ~target:primitive_target_geometry () |> get_ok in
  if Geometry.find_attribute ~owner:Attribute.Detail "asset"
       detail_pattern_target = None
     || Geometry.find_attribute ~owner:Attribute.Detail "P"
          detail_pattern_target <> None then
    fail "detail transfer leading-exclusion pattern";
  (match Attribute_ops.transfer_detail ~names:["P"] ~source:detail_p_source
      ~target:primitive_target_geometry () with
   | Ok geometry ->
       (match Geometry.find_attribute ~owner:Attribute.Detail "P" geometry with
        | Some attribute ->
            (match Attribute.storage attribute with
             | Attribute.Int [|23|] -> ()
             | _ -> fail "detail-owned P transfer payload")
        | None -> fail "detail-owned P transfer missing")
   | Error _ -> fail "detail-owned ordinary P was rejected");
  let selected_spatial = Spatial_index.create ~points:source_second
      (Geometry.positions transfer_source) |> get_ok in
  (match Spatial_index.nearest selected_spatial ~x:0. ~y:0. ~z:0. with
   | Ok (Some (1, distance)) when distance = 2. -> ()
   | _ -> fail "spatial index source point restriction/original ID");
  let spatial = Spatial_index.create (Geometry.positions transfer_source) |> get_ok in
  (match Spatial_index.nearest spatial ~x:1. ~y:0. ~z:0. with
   | Ok (Some (0, distance)) when distance = 1. -> ()
   | _ -> fail "spatial index nearest tie/query");
  let indexed_points = Array.init 257 (fun point ->
      let value = float_of_int point in
      (sin (value *. 0.73) *. 7., cos (value *. 1.17) *. 5.,
       sin (value *. 0.19) *. 3.)) in
  let indexed_geometry = Ops.points indexed_points in
  let indexed = Spatial_index.create (Geometry.positions indexed_geometry) |> get_ok in
  (match Spatial_index.create ~grain:0 (Geometry.positions indexed_geometry) with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "spatial index accepted a non-positive parallel grain");
  for query = 0 to 127 do
    let value = float_of_int query in
    let qx = sin (value *. 0.31) *. 6.
    and qy = cos (value *. 0.43) *. 4.
    and qz = sin (value *. 0.61) *. 2. in
    let expected = ref 0 and expected_distance = ref Float.infinity in
    Array.iteri (fun point (x, y, z) ->
      let dx = x -. qx and dy = y -. qy and dz = z -. qz in
      let distance = (dx *. dx) +. (dy *. dy) +. (dz *. dz) in
      if distance < !expected_distance
         || (distance = !expected_distance && point < !expected) then begin
        expected := point; expected_distance := distance
      end) indexed_points;
    match Spatial_index.nearest indexed ~x:qx ~y:qy ~z:qz with
    | Ok (Some (actual, _)) when actual = !expected -> ()
    | _ -> fail "spatial index disagrees with brute-force nearest"
  done;
  let surface_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 2.; 0.|] ~y:[|0.; 0.; 2.|] ~z:[|0.; 0.; 0.|] in
  let surface_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle surface_topology 0 1 2;
  let surface_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float [|0.; 2.; 4.|]) |> get_ok
  and surface_vertex = Attribute.create_owned ~name:"corner_value"
      ~owner:Attribute.Vertex (Attribute.Float [|10.; 20.; 30.|]) |> get_ok
  and surface_piece = Attribute.create_owned ~name:"piece"
      ~owner:Attribute.Primitive (Attribute.Int [|7|]) |> get_ok in
  let surface_source = Geometry.create ~positions:surface_positions
      ~topology:(Topology.Builder.freeze surface_topology)
      ~attributes:[surface_weight; surface_vertex; surface_piece] () |> get_ok in
  let vertex_owned_transfer domains = Parallel.run ~domains (fun () ->
      Attribute_ops.transfer_vertices ~grain:1 ~pattern:"corner*"
        ~source:surface_source ~target:triangle_geometry () |> get_ok) in
  let vertex_owned_one = vertex_owned_transfer 1
  and vertex_owned_many = vertex_owned_transfer 4 in
  let transferred_corner geometry = Geometry.find_attribute
      ~owner:Attribute.Vertex "corner_value" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner_value"
          ~owner:Attribute.Vertex Attribute.float) |> Option.get in
  if not (near_array [|10.; 15.; 25.; 10.; 25.; 20.|]
      (transferred_corner vertex_owned_one))
     || transferred_corner vertex_owned_one
        <> transferred_corner vertex_owned_many then
    fail "vertex closest-surface transfer/domain determinism";
  let surface_index = Surface_index.create surface_source |> get_ok in
  (match Surface_index.closest surface_index ~x:0.5 ~y:0.5 ~z:1. with
   | Ok (Some hit) ->
       let a, b, c = hit.barycentric in
       if hit.primitive <> 0 || abs_float (hit.distance -. 1.) > 1e-12
          || abs_float (a -. 0.5) > 1e-12 || abs_float (b -. 0.25) > 1e-12
          || abs_float (c -. 0.25) > 1e-12 then
         fail "surface index closest/barycentric query"
   | _ -> fail "surface index missed a triangle");
  let no_surface_vertices = Group.init ~owner:Group.Vertex ~name:"none" 3
      (fun _ -> false) in
  let empty_surface = Surface_index.create ~vertices:no_surface_vertices
      surface_source |> get_ok in
  if Surface_index.triangle_count empty_surface <> 0
      || Surface_index.node_count empty_surface <> 0 then
    fail "surface index empty vertex restriction cardinality";
  (match Surface_index.closest empty_surface ~x:0.5 ~y:0.5 ~z:1. with
   | Ok None -> ()
   | _ -> fail "empty surface index query did not miss");
  let one_surface_vertex = Group.init ~owner:Group.Vertex ~name:"one" 3
      (fun vertex -> vertex = 0) in
  let any_corner_surface = Surface_index.create ~vertices:one_surface_vertex
      ~vertex_selection:Surface_index.Any_triangle_vertex surface_source
      |> get_ok in
  if Surface_index.triangle_count any_corner_surface <> 1 then
    fail "surface index any-corner vertex restriction";
  let all_corner_surface = Surface_index.create ~vertices:one_surface_vertex
      ~vertex_selection:Surface_index.All_triangle_vertices surface_source
      |> get_ok in
  if Surface_index.triangle_count all_corner_surface <> 0 then
    fail "surface index all-corners vertex restriction";
  let surface_target = Ops.points [|(0.5,0.5,1.); (10.,10.,0.)|] in
  let initial_surface_weight = Attribute.create_owned ~name:"sampled_weight"
      ~owner:Attribute.Point (Attribute.Float [|99.; 99.|]) |> get_ok
  and initial_corner = Attribute.create_owned ~name:"sampled_corner"
      ~owner:Attribute.Point (Attribute.Float [|88.; 88.|]) |> get_ok
  and initial_piece = Attribute.create_owned ~name:"sampled_piece"
      ~owner:Attribute.Point (Attribute.Int [|6; 6|]) |> get_ok
  and initial_distance = Attribute.create_owned ~name:"surface_distance"
      ~owner:Attribute.Point (Attribute.Float [|77.; 77.|]) |> get_ok in
  let surface_target = surface_target
      |> Geometry.with_attribute initial_surface_weight |> get_ok
      |> Geometry.with_attribute initial_corner |> get_ok
      |> Geometry.with_attribute initial_piece |> get_ok
      |> Geometry.with_attribute initial_distance |> get_ok in
  let surface_specs = [
    Attribute_ops.surface_attribute ~into:"sampled_weight"
      ~owner:Attribute.Point "weight";
    Attribute_ops.surface_attribute ~into:"sampled_corner"
      ~owner:Attribute.Vertex "corner_value";
    Attribute_ops.surface_attribute ~into:"sampled_piece"
      ~owner:Attribute.Primitive "piece";
  ] in
  let surface_transfer domains = Parallel.run ~domains (fun () ->
      Attribute_ops.transfer_surface ~grain:1 ~max_distance:2.
        ~distance_attribute:"surface_distance" ~attributes:surface_specs
        ~source:surface_source ~target:surface_target () |> get_ok) in
  let surface_one = surface_transfer 1 and surface_many = surface_transfer 4 in
  let surface_float name geometry = Geometry.find_attribute
      ~owner:Attribute.Point name geometry |> Option.get
      |> Attribute.get (Attribute.key ~name ~owner:Attribute.Point Attribute.float)
      |> Option.get
  and surface_int name geometry = Geometry.find_attribute
      ~owner:Attribute.Point name geometry |> Option.get
      |> Attribute.get (Attribute.key ~name ~owner:Attribute.Point Attribute.int)
      |> Option.get in
  if surface_float "sampled_weight" surface_one <> [|1.5; 99.|]
     || surface_float "sampled_corner" surface_one <> [|17.5; 88.|]
     || surface_int "sampled_piece" surface_one <> [|7; 6|]
     || surface_float "surface_distance" surface_one <> [|1.; 77.|]
     || surface_float "sampled_weight" surface_one
        <> surface_float "sampled_weight" surface_many
     || surface_float "sampled_corner" surface_one
        <> surface_float "sampled_corner" surface_many
     || surface_int "sampled_piece" surface_one
        <> surface_int "sampled_piece" surface_many
  then fail "surface attribute transfer payload/unmatched/domain determinism";
  let vertex_spec = Attribute_ops.surface_attribute ~into:"vertex_weight"
      ~owner:Attribute.Point "weight" in
  let vertex_transfer domains = Parallel.run ~domains (fun () ->
      Attribute_ops.transfer_surface ~grain:1 ~target_owner:Attribute.Vertex
        ~attributes:[vertex_spec] ~source:surface_source
        ~target:triangle_geometry () |> get_ok) in
  let vertex_one = vertex_transfer 1 and vertex_many = vertex_transfer 4 in
  let vertex_weight geometry = Geometry.find_attribute ~owner:Attribute.Vertex
      "vertex_weight" geometry |> Option.get |> Attribute.get (Attribute.key
        ~name:"vertex_weight" ~owner:Attribute.Vertex Attribute.float) |> Option.get in
  if not (near_array [|0.; 1.; 3.; 0.; 3.; 2.|] (vertex_weight vertex_one))
     || vertex_weight vertex_one <> vertex_weight vertex_many then
    fail "surface transfer destination vertex ownership/domain determinism";
  let primitive_initial = Attribute.create_owned ~name:"sampled_weight"
      ~owner:Attribute.Primitive (Attribute.Float [|99.; 99.|]) |> get_ok in
  let primitive_target = Geometry.with_attribute primitive_initial
      triangle_geometry |> get_ok in
  let target_primitive = Group.init ~owner:Group.Primitive ~name:"target_primitive"
      2 (fun primitive -> primitive = 1) in
  let primitive_transfer = Attribute_ops.transfer_surface ~grain:1
      ~target_owner:Attribute.Primitive ~target_elements:target_primitive
      ~attributes:[
        Attribute_ops.surface_attribute ~into:"sampled_weight"
          ~owner:Attribute.Point "weight";
        Attribute_ops.surface_attribute ~into:"sampled_piece"
          ~owner:Attribute.Primitive "piece";
      ] ~source:surface_source ~target:primitive_target () |> get_ok in
  let primitive_float name geometry = Geometry.find_attribute
      ~owner:Attribute.Primitive name geometry |> Option.get
      |> Attribute.get (Attribute.key ~name ~owner:Attribute.Primitive Attribute.float)
      |> Option.get
  and primitive_int name geometry = Geometry.find_attribute
      ~owner:Attribute.Primitive name geometry |> Option.get
      |> Attribute.get (Attribute.key ~name ~owner:Attribute.Primitive Attribute.int)
      |> Option.get in
  if not (near_array [|99.; 5. /. 3.|]
      (primitive_float "sampled_weight" primitive_transfer))
     || primitive_int "sampled_piece" primitive_transfer <> [|0; 7|] then
    fail "surface transfer destination primitive barycenter/group semantics";
  (match Attribute_ops.transfer_surface ~target_owner:Attribute.Vertex
      ~target_elements:target_primitive ~attributes:[vertex_spec]
      ~source:surface_source ~target:triangle_geometry () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "surface transfer accepted mismatched destination group ownership");
  (match Attribute_ops.transfer_surface ~target_owner:Attribute.Detail
      ~attributes:[vertex_spec] ~source:surface_source ~target:triangle_geometry () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "surface transfer accepted spatial detail destination ownership");
  (match Attribute_ops.transfer_surface
      ~attributes:[Attribute_ops.surface_attribute ~into:"P"
        ~owner:Attribute.Vertex "corner_value"]
      ~source:surface_source ~target:surface_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "surface transfer accepted canonical target P as ordinary data");
  let falloff_target = Ops.points [|(0.5,0.5,0.5); (0.5,0.5,1.5);
      (0.5,0.5,3.); (0.5,0.5,4.)|] in
  let falloff_initial = Attribute.create_owned ~name:"sampled_weight"
      ~owner:Attribute.Point (Attribute.Float [|10.; 10.; 10.; 10.|]) |> get_ok in
  let falloff_target = Geometry.with_attribute falloff_initial falloff_target |> get_ok in
  let falloff_result = Attribute_ops.transfer_surface ~max_distance:1.
      ~blend_width:2. ~falloff:Attribute_ops.Linear
      ~attributes:[List.hd surface_specs] ~source:surface_source
      ~target:falloff_target () |> get_ok in
  if surface_float "sampled_weight" falloff_result
      <> [|1.5; 3.625; 10.; 10.|] then
    fail "surface transfer linear threshold/blend falloff";
  (match Attribute_ops.transfer_surface ~blend_width:1.
      ~attributes:[List.hd surface_specs] ~source:surface_source
      ~target:falloff_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "surface transfer accepted blend width without distance threshold");
  let duplicate_surface_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle duplicate_surface_topology 0 1 2;
  Topology.Builder.add_triangle duplicate_surface_topology 0 1 2;
  let duplicate_surface = Geometry.create ~positions:surface_positions
      ~topology:(Topology.Builder.freeze duplicate_surface_topology) () |> get_ok
      |> Surface_index.create |> get_ok in
  (match Surface_index.closest duplicate_surface ~x:0.5 ~y:0.5 ~z:1. with
   | Ok (Some hit) when hit.primitive = 0 -> ()
   | _ -> fail "surface index equal-distance primitive tie");
  let selected_second = Group.init ~owner:Group.Primitive ~name:"second" 2
      (fun primitive -> primitive = 1) in
  let duplicate_geometry = Geometry.create ~positions:surface_positions
      ~topology:(Topology.Builder.freeze (let builder =
        Topology.Builder.create ~point_count:3 () in
        Topology.Builder.add_triangle builder 0 1 2;
        Topology.Builder.add_triangle builder 0 1 2; builder)) () |> get_ok in
  let selected_surface = Surface_index.create ~primitives:selected_second
      duplicate_geometry |> get_ok in
  (match Surface_index.closest selected_surface ~x:0.5 ~y:0.5 ~z:1. with
   | Ok (Some hit) when hit.primitive = 1 -> ()
   | _ -> fail "surface index primitive restriction/original ID");
  let restricted_piece = Attribute.create_owned ~name:"piece"
      ~owner:Attribute.Primitive (Attribute.Int [|7; 9|]) |> get_ok in
  let restricted_source = Geometry.with_attribute restricted_piece
      duplicate_geometry |> get_ok
  and restricted_target = Ops.points [|(0.5,0.5,1.); (0.5,0.5,1.)|] in
  let restricted_initial = Attribute.create_owned ~name:"piece"
      ~owner:Attribute.Point (Attribute.Int [|4; 4|]) |> get_ok in
  let restricted_target = Geometry.with_attribute restricted_initial
      restricted_target |> get_ok in
  let target_second = Group.init ~owner:Group.Point ~name:"second_target" 2
      (fun point -> point = 1) in
  let restricted_result = Attribute_ops.transfer_surface
      ~unmatched:Attribute_ops.Default_value
      ~source_primitives:selected_second ~target_points:target_second
      ~attributes:[Attribute_ops.surface_attribute
        ~owner:Attribute.Primitive "piece"]
      ~source:restricted_source ~target:restricted_target () |> get_ok in
  if surface_int "piece" restricted_result <> [|4; 9|] then
    fail "surface transfer source/target group restriction";
  let degenerate_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.|] ~y:[|0.; 0.; 0.|] ~z:[|0.; 0.; 0.|] in
  let degenerate_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle degenerate_topology 0 1 2;
  let degenerate_surface = Geometry.create ~positions:degenerate_positions
      ~topology:(Topology.Builder.freeze degenerate_topology) () |> get_ok in
  (match Surface_index.create degenerate_surface with
   | Error error when Error.code error = "invalid_surface" -> ()
   | _ -> fail "surface index accepted a degenerate triangle");
  let tiny = 1e-100 in
  let tiny_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; tiny; 0.|] ~y:[|0.; 0.; tiny|] ~z:[|0.; 0.; 0.|] in
  let tiny_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle tiny_topology 0 1 2;
  let tiny_surface = Geometry.create ~positions:tiny_positions
      ~topology:(Topology.Builder.freeze tiny_topology) () |> get_ok in
  let tiny_index = Surface_index.create tiny_surface |> get_ok in
  if Surface_index.triangle_count tiny_index <> 1 then
    fail "surface index rejected an exact non-collinear subnormal-area triangle";
  let surface_cancel = Cancel.create () in
  Cancel.cancel surface_cancel;
  (match Surface_index.create ~cancel:surface_cancel surface_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled surface index construction returned the wrong result");
  (match Attribute_ops.transfer_surface ~cancel:surface_cancel
      ~attributes:surface_specs ~source:surface_source ~target:surface_target () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled surface transfer published geometry or wrong error");
  let nonfinite_surface_target = Ops.points [|(Float.nan, 0., 0.)|] in
  (match Attribute_ops.transfer_surface ~attributes:surface_specs
      ~source:surface_source ~target:nonfinite_surface_target () with
   | Error error when Error.code error = "invalid_position" -> ()
   | _ -> fail "surface transfer accepted a non-finite target point");
  let quad_surface_weight = Attribute.create_owned ~name:"quad_weight"
      ~owner:Attribute.Point (Attribute.Float [|0.; 1.; 2.; 3.|]) |> get_ok
  and quad_surface_corner = Attribute.create_owned ~name:"quad_corner"
      ~owner:Attribute.Vertex (Attribute.Float [|10.; 20.; 30.; 40.|]) |> get_ok in
  let quad_surface = geometry
      |> Geometry.with_attribute quad_surface_weight |> get_ok
      |> Geometry.with_attribute quad_surface_corner |> get_ok in
  let quad_index = Surface_index.create quad_surface |> get_ok in
  if Surface_index.triangle_count quad_index <> 2 then
    fail "surface index did not triangulate a quad exactly";
  (match Surface_index.closest quad_index ~x:0.2 ~y:0.7 ~z:1. with
   | Ok (Some hit) when hit.primitive = 0
       && abs_float (hit.distance -. 1.) <= 1e-12 -> ()
   | _ -> fail "surface index missed a general polygon");
  let quad_target = Ops.points [|(0.2, 0.7, 1.); (0.8, 0.7, 1.)|] in
  let quad_transfer = Attribute_ops.transfer_surface ~grain:1
      ~attributes:[
        Attribute_ops.surface_attribute ~owner:Attribute.Point "quad_weight";
        Attribute_ops.surface_attribute ~owner:Attribute.Vertex "quad_corner";
      ] ~source:quad_surface ~target:quad_target () |> get_ok in
  let quad_weight = surface_float "quad_weight" quad_transfer
  and quad_corner = surface_float "quad_corner" quad_transfer in
  if not (near_array [|2.3; 1.9|] quad_weight)
     || not (near_array [|33.; 29.|] quad_corner) then
    fail "general-polygon point/vertex surface interpolation";
  let concave_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 2.; 2.; 1.; 0.|] ~y:[|0.; 0.; 2.; 1.; 2.|]
      ~z:(Array.make 5 0.) in
  let concave_topology = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_polygon concave_topology [|0; 1; 2; 3; 4|];
  let concave_geometry = Geometry.create ~positions:concave_positions
      ~topology:(Topology.Builder.freeze concave_topology) () |> get_ok in
  let concave_index = Surface_index.create concave_geometry |> get_ok in
  if Surface_index.triangle_count concave_index <> 3 then
    fail "surface index concave polygon triangle cardinality";
  (match Surface_index.closest concave_index ~x:0.4 ~y:1.4 ~z:0.75 with
   | Ok (Some hit) when hit.primitive = 0
       && abs_float (hit.distance -. 0.75) <= 1e-12 -> ()
   | _ -> fail "surface index missed a concave polygon interior");
  let bow_tie_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 2.; 0.; 2.|] ~y:[|0.; 2.; 2.; 0.|]
      ~z:(Array.make 4 0.) in
  let bow_tie_topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_polygon bow_tie_topology [|0; 1; 2; 3|];
  let bow_tie = Geometry.create ~positions:bow_tie_positions
      ~topology:(Topology.Builder.freeze bow_tie_topology) () |> get_ok in
  (match Surface_index.create bow_tie with
   | Error error when Error.code error = "invalid_surface" -> ()
   | _ -> fail "surface index accepted a self-intersecting polygon");
  let bad_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|Float.nan|] ~y:[|0.|] ~z:[|0.|] in
  (match Spatial_index.create bad_positions with
   | Error error when Error.code error = "invalid_position" -> ()
   | _ -> fail "spatial index accepted a non-finite point");
  let conflicting_id = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Float (Array.make 3 0.)) |> get_ok in
  let conflicting_target = Geometry.with_attribute conflicting_id
      transfer_target |> get_ok in
  (match Attribute_ops.transfer_points ~names:["id"] ~source:transfer_source
      ~target:conflicting_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "attribute transfer accepted incompatible target storage");
  (match Attribute_ops.transfer_points
      ~mode:(Attribute_ops.Inverse_distance { neighbors = 0; power = 1. })
      ~source:transfer_source ~target:transfer_target () with
   | Error error when Error.code error = "invalid_transfer" -> ()
   | _ -> fail "attribute transfer accepted invalid neighbor count");
  let fuse_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 1.; 0.; 0.000_000_5|]
      ~y:[|0.; 0.; 1.; 1.; 0.|] ~z:(Array.make 5 0.) in
  let fuse_topology = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_triangle fuse_topology 0 1 2;
  Topology.Builder.add_triangle fuse_topology 4 2 3;
  let weights = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float [|2.; 4.; 6.; 8.; 10.|]) |> get_ok in
  let seam = Group.init ~owner:Group.Point ~name:"seam" 5
      (fun point -> point = 4) in
  let fuse_source = Geometry.create ~positions:fuse_positions
      ~topology:(Topology.Builder.freeze fuse_topology)
      ~attributes:[weights] ~groups:[seam] () |> get_ok in
  let fused domains = Parallel.run ~domains (fun () ->
      Ops.fuse ~grain:1 ~tolerance:1e-6 ~position:Ops.Average_position
        ~attributes:Ops.Average_numeric fuse_source |> get_ok) in
  let fused_one = fused 1 and fused_many = fused 4 in
  let fused_topology_one = Topology.Private.view (Geometry.topology fused_one)
  and fused_topology_many = Topology.Private.view (Geometry.topology fused_many) in
  if Geometry.point_count fused_one <> 4
     || not (equal_positions fused_one fused_many)
     || fused_topology_one.vertex_points <> fused_topology_many.vertex_points
     || fused_topology_one.vertex_points <> [|0; 1; 2; 0; 2; 3|]
  then fail "fuse cardinality/topology/domain determinism";
  let fused_x, _, _ = Packed.Float3.get (Geometry.positions fused_one) 0 in
  if abs_float (fused_x -. 0.000_000_25) > 1e-15 then
    fail "fuse average position";
  (match Geometry.find_attribute ~owner:Attribute.Point "weight" fused_one with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Float values when values.(0) = 6. -> ()
        | _ -> fail "fuse numeric attribute reduction")
   | None -> fail "fuse dropped point attribute");
  (match Geometry.find_group ~owner:Group.Point "seam" fused_one with
   | Some group when Group.mem 0 group && Group.cardinality group = 1 -> ()
   | _ -> fail "fuse point-group union");
  let directed = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make 4 1.) ~y:(Array.make 4 0.) ~z:(Array.make 4 0.) in
  let direction_attribute = Attribute.create_key_owned
      (Attribute.normal ~owner:Attribute.Point) directed |> get_ok in
  let mirror_source = Geometry.with_attribute direction_attribute
      triangle_geometry |> get_ok in
  let mirrored domains = Parallel.run ~domains (fun () ->
      Ops.mirror ~grain:1 ~origin:Vec3.zero ~normal:Vec3.unit_x mirror_source
      |> get_ok) in
  let mirrored_one = mirrored 1 and mirrored_many = mirrored 4 in
  let mirror_topology_one = Topology.Private.view (Geometry.topology mirrored_one)
  and mirror_topology_many = Topology.Private.view (Geometry.topology mirrored_many) in
  if Geometry.point_count mirrored_one <> 8
     || Geometry.primitive_count mirrored_one <> 4
     || not (equal_positions mirrored_one mirrored_many)
     || mirror_topology_one.vertex_points <> mirror_topology_many.vertex_points
     || Array.sub mirror_topology_one.vertex_points 6 6 <> [|6; 5; 4; 7; 6; 4|]
  then fail "mirror winding/cardinality/domain determinism";
  let mirror_normals = Geometry.find_attribute ~owner:Attribute.Point "N" mirrored_one
      |> Option.get |> Attribute.get (Attribute.normal ~owner:Attribute.Point)
      |> Option.get in
  let original_nx, _, _ = Packed.Float3.get mirror_normals 0
  and reflected_nx, _, _ = Packed.Float3.get mirror_normals 4 in
  if original_nx <> 1. || reflected_nx <> -1. then fail "mirror normal reflection";
  let shared_box = Ops.box ~size:(Vec3.create 2. 2. 2.) () |> get_ok
      |> Ops.fuse ~tolerance:0. ~attributes:Ops.Average_numeric |> get_ok in
  let shared_positions = Packed.Float3.Private.view (Geometry.positions shared_box) in
  let clip_weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float (Array.copy shared_positions.x)) |> get_ok in
  let clip_source = Geometry.with_attribute clip_weight shared_box |> get_ok in
  let clipped domains = Parallel.run ~domains (fun () ->
      Ops.clip ~grain:1 ~keep:Ops.Above ~fill:true ~cap_group:"cap"
        ~clipped_group:"cut" ~origin:Vec3.zero ~normal:Vec3.unit_x
        clip_source |> get_ok) in
  let clipped_one = clipped 1 and clipped_many = clipped 4 in
  let clipped_bounds = Analysis.bounds clipped_one |> Option.get
  and clipped_topology = Topology.Private.view (Geometry.topology clipped_one)
  and clipped_topology_many = Topology.Private.view (Geometry.topology clipped_many) in
  if abs_float clipped_bounds.min.x > 1e-12
     || abs_float (clipped_bounds.max.x -. 1.) > 1e-12
     || not (equal_positions clipped_one clipped_many)
     || clipped_topology.vertex_points <> clipped_topology_many.vertex_points
     || clipped_topology.primitive_offsets <> clipped_topology_many.primitive_offsets
  then fail "filled plane clip bounds/topology/domain determinism";
  let cap = Geometry.find_group ~owner:Group.Primitive "cap" clipped_one
      |> Option.get in
  if Group.cardinality cap <> 1 then fail "clip cap primitive group";
  let cap_primitive = ref (-1) in
  Group.iter (fun primitive -> cap_primitive := primitive) cap;
  let first_cap, last_cap = Topology.primitive_vertex_range
      (Geometry.topology clipped_one) !cap_primitive in
  if last_cap - first_cap < 4 then fail "clip cap loop cardinality";
  let clipped_normals = Geometry.find_attribute ~owner:Attribute.Vertex "N"
      clipped_one |> Option.get
      |> Attribute.get (Attribute.normal ~owner:Attribute.Vertex) |> Option.get in
  for vertex = first_cap to last_cap - 1 do
    let x, y, z = Packed.Float3.get clipped_normals vertex in
    if abs_float (x +. 1.) > 1e-12 || abs_float y > 1e-12
       || abs_float z > 1e-12 then fail "clip cap hard normal"
  done;
  let clipped_index = Topology_index.create (Geometry.topology clipped_one) in
  if Topology_index.boundary_edge_count clipped_index <> 0 then
    fail "filled clip is not topologically watertight";
  let clipped_weights geometry = Geometry.find_attribute ~owner:Attribute.Point
      "weight" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
          Attribute.float) |> Option.get in
  if clipped_weights clipped_one <> clipped_weights clipped_many then
    fail "clip interpolated attribute domain determinism";
  for vertex = first_cap to last_cap - 1 do
    let point = Topology.point_of_vertex (Geometry.topology clipped_one) vertex in
    if abs_float (clipped_weights clipped_one).(point) > 1e-12 then
      fail "clip point attribute interpolation"
  done;
  let split = Ops.clip ~keep:Ops.All ~split_connectivity:true
      ~above_group:"above" ~below_group:"below" ~origin:Vec3.zero
      ~normal:Vec3.unit_x clip_source |> get_ok in
  let split_topology = Geometry.topology split
  and above = Geometry.find_group ~owner:Group.Primitive "above" split |> Option.get
  and below = Geometry.find_group ~owner:Group.Primitive "below" split |> Option.get in
  let above_plane = Hashtbl.create 16 in
  Group.iter (fun primitive ->
    let first, last = Topology.primitive_vertex_range split_topology primitive in
    for vertex = first to last - 1 do
      let point = Topology.point_of_vertex split_topology vertex in
      let x, _, _ = Packed.Float3.get (Geometry.positions split) point in
      if abs_float x < 1e-12 then Hashtbl.replace above_plane point ()
    done) above;
  Group.iter (fun primitive ->
    let first, last = Topology.primitive_vertex_range split_topology primitive in
    for vertex = first to last - 1 do
      let point = Topology.point_of_vertex split_topology vertex in
      let x, _, _ = Packed.Float3.get (Geometry.positions split) point in
      if abs_float x < 1e-12 && Hashtbl.mem above_plane point then
        fail "clip split connectivity shared a plane point"
    done) below;
  let clipped_curve = Ops.polyline [|(-1.,0.,0.); (0.,1.,0.); (1.,0.,0.)|]
      |> get_ok |> Ops.clip ~keep:Ops.Above ~origin:Vec3.zero
           ~normal:Vec3.unit_x |> get_ok in
  if Geometry.primitive_count clipped_curve <> 1
     || Geometry.point_count clipped_curve <> 2
     || Topology.primitive_kind (Geometry.topology clipped_curve) 0
        <> Topology.Open_polyline then fail "open-polyline plane clip";
  let point_cloud = Ops.points
      [|(-1.,0.,0.); (0.000_01,0.,0.); (1.,0.,0.)|] in
  let point_ids = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|10; 20; 30|]) |> get_ok in
  let point_cloud = Geometry.with_attribute point_ids point_cloud |> get_ok in
  let clipped_points = Ops.clip ~snapping_tolerance:0.001
      ~origin:Vec3.zero ~normal:Vec3.unit_x point_cloud |> get_ok in
  let clipped_point_ids = Geometry.find_attribute ~owner:Attribute.Point "id"
      clipped_points |> Option.get
      |> Attribute.get (Attribute.key ~name:"id" ~owner:Attribute.Point
          Attribute.int) |> Option.get in
  let first_x, _, _ = Packed.Float3.get (Geometry.positions clipped_points) 0 in
  if Geometry.point_count clipped_points <> 2 || first_x <> 0.
     || clipped_point_ids <> [|20; 30|] then
    fail "point-cloud clip/filter/snapping/attribute remap";
  let vertex_clip_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|-1.; 1.; 1.|] ~y:[|0.; 0.; 1.|] ~z:[|0.; 0.; 0.|] in
  let vertex_clip_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle vertex_clip_topology 0 1 2;
  let vertex_u = Attribute.create_owned ~name:"u" ~owner:Attribute.Vertex
      (Attribute.Float [|0.; 2.; 4.|]) |> get_ok in
  let vertex_clip_source = Geometry.create ~positions:vertex_clip_positions
      ~topology:(Topology.Builder.freeze vertex_clip_topology)
      ~attributes:[vertex_u] () |> get_ok in
  let vertex_clipped = Ops.clip ~origin:Vec3.zero ~normal:Vec3.unit_x
      vertex_clip_source |> get_ok in
  let vertex_u = Geometry.find_attribute ~owner:Attribute.Vertex "u"
      vertex_clipped |> Option.get
      |> Attribute.get (Attribute.key ~name:"u" ~owner:Attribute.Vertex
          Attribute.float) |> Option.get in
  let plane_values = ref [] in
  for vertex = 0 to Geometry.vertex_count vertex_clipped - 1 do
    let point = Topology.point_of_vertex (Geometry.topology vertex_clipped) vertex in
    let x, _, _ = Packed.Float3.get (Geometry.positions vertex_clipped) point in
    if abs_float x < 1e-12 then plane_values := vertex_u.(vertex) :: !plane_values
  done;
  if List.sort Float.compare !plane_values <> [1.; 2.] then
    fail "clip vertex attribute interpolation";
  let closed_curve = Ops.circle ~segments:16 ~radius:1. () |> get_ok
      |> Ops.clip ~origin:Vec3.zero ~normal:Vec3.unit_x |> get_ok in
  if Geometry.primitive_count closed_curve <> 1
     || Topology.primitive_kind (Geometry.topology closed_curve) 0
        <> Topology.Open_polyline then
    fail "closed-polyline plane clip did not emit an open retained arc";
  let concave = Ops.polyline ~closed:true
      [|(-2.,-2.,0.); (2.,-2.,0.); (2.,2.,0.); (1.,2.,0.);
        (1.,-1.,0.); (-1.,-1.,0.); (-1.,2.,0.); (-2.,2.,0.)|]
      |> get_ok in
  let concave_topology = Topology.Private.view (Geometry.topology concave) in
  let concave_polygon = Topology.Private.create_validated_owned
      ~point_count:(Geometry.point_count concave)
      ~vertex_points:(Array.copy concave_topology.vertex_points)
      ~primitive_offsets:(Array.copy concave_topology.primitive_offsets)
      ~primitive_kinds:(Bytes.make 1 '\000') in
  let concave = Geometry.create ~positions:(Geometry.positions concave)
      ~topology:concave_polygon () |> get_ok in
  let concave_clipped = Ops.clip ~origin:Vec3.zero ~normal:Vec3.unit_y
      concave |> get_ok in
  if Geometry.primitive_count concave_clipped <> 2
     || Geometry.vertex_count concave_clipped <> 8 then
    fail "clip did not reconstruct disconnected concave half-plane fragments";
  (match Ops.clip ~split_connectivity:true ~origin:Vec3.zero
      ~normal:Vec3.unit_x clip_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "clip accepted split connectivity outside keep-all mode");
  (match Ops.clip ~cap_group:"same" ~above_group:"same" ~origin:Vec3.zero
      ~normal:Vec3.unit_x clip_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "clip accepted duplicate output group names");
  let huge_normal_clip = Ops.clip ~origin:Vec3.zero
      ~normal:(Vec3.create 1e300 0. 0.) clip_source |> get_ok
  and unit_normal_clip = Ops.clip ~origin:Vec3.zero ~normal:Vec3.unit_x
      clip_source |> get_ok in
  if not (equal_positions huge_normal_clip unit_normal_clip) then
    fail "clip normal normalization overflow";
  (match Ops.clip ~origin:Vec3.zero ~normal:Vec3.zero clip_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "clip accepted a zero plane normal");
  (match Ops.clip ~fill:true ~origin:(Vec3.create 0.5 0. 0.) ~normal:Vec3.unit_x
      triangle_geometry with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "clip filled an open polygon boundary");
  let uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 1.; 1.; 0.|] ~y:[|0.; 0.; 1.; 1.|] |> get_ok)) |> get_ok
  and material = Attribute.create_owned ~name:"material"
      ~owner:Attribute.Primitive (Attribute.Int [|7|]) |> get_ok
  and stale_normal = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 4 0.) ~y:(Array.make 4 0.) ~z:(Array.make 4 1.)))
      |> get_ok
  and all_corners = Group.init ~owner:Group.Vertex ~name:"all_corners" 4
      (fun _ -> true)
  and selected_face = Group.init ~owner:Group.Primitive ~name:"selected_face" 1
      (fun _ -> true) in
  let subdivision_source = geometry
      |> Geometry.with_attribute uv |> get_ok
      |> Geometry.with_attribute material |> get_ok
      |> Geometry.with_attribute stale_normal |> get_ok
      |> Geometry.with_group all_corners |> get_ok
      |> Geometry.with_group selected_face |> get_ok in
  let catmull domains = Parallel.run ~domains (fun () ->
      Ops.subdivide ~grain:1 ~scheme:Ops.Catmull_clark subdivision_source
      |> get_ok) in
  let catmull_one = catmull 1 and catmull_many = catmull 4 in
  let catmull_topology = Topology.Private.view (Geometry.topology catmull_one)
  and catmull_topology_many = Topology.Private.view
      (Geometry.topology catmull_many) in
  if Geometry.point_count catmull_one <> 9
     || Geometry.primitive_count catmull_one <> 4
     || Geometry.vertex_count catmull_one <> 16
     || catmull_topology.vertex_points <> catmull_topology_many.vertex_points
     || not (equal_positions catmull_one catmull_many)
  then fail "Catmull-Clark cardinality/domain determinism";
  let c0x, c0y, c0z = Packed.Float3.get (Geometry.positions catmull_one) 0
  and center_x, center_y, center_z = Packed.Float3.get
      (Geometry.positions catmull_one) 8 in
  if abs_float (c0x -. 0.125) > 1e-12
     || abs_float (c0y -. 0.125) > 1e-12 || abs_float c0z > 1e-12
     || abs_float (center_x -. 0.5) > 1e-12
     || abs_float (center_y -. 0.5) > 1e-12 || abs_float center_z > 1e-12
  then fail "Catmull-Clark boundary/face stencils";
  if Array.exists (fun primitive ->
      Topology.primitive_size (Geometry.topology catmull_one) primitive <> 4)
      (Array.init 4 Fun.id) then fail "Catmull-Clark did not emit quads";
  (match Geometry.find_attribute ~owner:Attribute.Point "N" catmull_one with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            if not (Array.for_all (( = ) 0.) values.x
                && Array.for_all (( = ) 0.) values.y
                && Array.for_all (( = ) 1.) values.z) then
              fail "subdivision point-normal stencil"
        | _ -> fail "subdivision changed point-normal storage")
   | None -> fail "subdivision dropped interpolated point normals");
  let catmull_uv geometry = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      geometry |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  let uv_one = catmull_uv catmull_one and uv_many = catmull_uv catmull_many in
  if uv_one.x <> uv_many.x || uv_one.y <> uv_many.y
     || Array.sub uv_one.x 0 4 <> [|0.; 0.5; 0.5; 0.|]
     || Array.sub uv_one.y 0 4 <> [|0.; 0.; 0.5; 0.5|]
  then fail "Catmull-Clark face-varying UV refinement";
  (match Geometry.find_attribute ~owner:Attribute.Primitive "material" catmull_one with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Int values when values = [|7; 7; 7; 7|] -> ()
        | _ -> fail "subdivision primitive attribute propagation")
   | None -> fail "subdivision dropped primitive attribute");
  (match Geometry.find_group ~owner:Group.Point "even" catmull_one with
   | Some group when Group.cardinality group = 2 -> ()
   | _ -> fail "subdivision point group propagation");
  (match Geometry.find_group ~owner:Group.Vertex "all_corners" catmull_one with
   | Some group when Group.cardinality group = 16 -> ()
   | _ -> fail "subdivision vertex group propagation");
  (match Geometry.find_group ~owner:Group.Primitive "selected_face" catmull_one with
   | Some group when Group.cardinality group = 4 -> ()
   | _ -> fail "subdivision primitive group propagation");
  let bilinear = Ops.subdivide ~scheme:Ops.Bilinear ~iterations:2
      subdivision_source |> get_ok in
  if Geometry.point_count bilinear <> 25
     || Geometry.primitive_count bilinear <> 16
     || Geometry.vertex_count bilinear <> 64 then
    fail "bilinear subdivision iteration cardinality";
  for point = 0 to 3 do
    if Packed.Float3.get (Geometry.positions bilinear) point
       <> Packed.Float3.get positions point then
      fail "bilinear subdivision moved a control point"
  done;
  let loop_one = Ops.subdivide ~scheme:Ops.Loop triangle_geometry |> get_ok in
  if Geometry.point_count loop_one <> 9
     || Geometry.primitive_count loop_one <> 8
     || Geometry.vertex_count loop_one <> 24
     || not (Topology.all_triangles (Geometry.topology loop_one)) then
    fail "Loop subdivision cardinality/topology";
  let tetra_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.|] ~y:[|0.; 0.; 1.; 0.|]
      ~z:[|0.; 0.; 0.; 1.|] in
  let tetra_topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_triangle tetra_topology 0 2 1;
  Topology.Builder.add_triangle tetra_topology 0 1 3;
  Topology.Builder.add_triangle tetra_topology 1 2 3;
  Topology.Builder.add_triangle tetra_topology 2 0 3;
  let tetra_topology = Topology.Builder.freeze tetra_topology in
  let tetra_index = Topology_index.create tetra_topology in
  let sharp_edge = Topology_index.find_edge tetra_index ~a:0 ~b:1
      |> Option.get in
  let crease_values = Array.init (Topology.vertex_count tetra_topology)
      (fun vertex ->
        if Topology_index.edge_of_vertex tetra_index vertex = sharp_edge
        then 2. else 0.) in
  let creaseweight = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex (Attribute.Float crease_values) |> get_ok
  and cornerweight = Attribute.create_owned ~name:"cornerweight"
      ~owner:Attribute.Point (Attribute.Float [|0.; 0.; 1.; 0.|]) |> get_ok in
  let creased_source = Geometry.create ~positions:tetra_positions
      ~topology:tetra_topology ~attributes:[creaseweight; cornerweight] ()
      |> get_ok in
  let creased = Ops.subdivide creased_source |> get_ok in
  let ex, ey, ez = Packed.Float3.get (Geometry.positions creased)
      (4 + sharp_edge) in
  if abs_float (ex -. 0.5) > 1e-12 || abs_float ey > 1e-12
     || abs_float ez > 1e-12 then
    fail "semi-sharp subdivision did not preserve the sharp edge midpoint";
  if Packed.Float3.get (Geometry.positions creased) 2 <> (0., 1., 0.) then
    fail "subdivision cornerweight did not preserve the control point";
  (match Geometry.find_attribute ~owner:Attribute.Vertex "creaseweight" creased with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Float values when Array.exists ((=) 1.) values -> ()
        | _ -> fail "subdivision did not decay/output creaseweight")
   | None -> fail "subdivision dropped resulting creaseweight");
  let negative_crease = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.make (Topology.vertex_count tetra_topology) (-1.)))
      |> get_ok in
  let negative_crease = Geometry.create ~positions:tetra_positions
      ~topology:tetra_topology ~attributes:[negative_crease] () |> get_ok in
  (match Ops.subdivide negative_crease with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "subdivision accepted a negative creaseweight");
  (match Ops.subdivide ~scheme:Ops.Loop geometry with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "Loop subdivision accepted a non-triangle polygon");
  let nonmanifold_topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_triangle nonmanifold_topology 0 1 2;
  Topology.Builder.add_triangle nonmanifold_topology 1 0 3;
  Topology.Builder.add_triangle nonmanifold_topology 0 1 3;
  let nonmanifold = Geometry.create ~positions
      ~topology:(Topology.Builder.freeze nonmanifold_topology) () |> get_ok in
  (match Ops.subdivide nonmanifold with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "subdivision accepted a non-manifold edge");
  let bowtie_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.; -1.; 0.; 0.|]
      ~y:[|0.; 0.; 1.; 0.; 0.; -1.; 0.|]
      ~z:[|0.; 0.; 0.; 1.; 0.; 0.; -1.|] in
  let bowtie_topology = Topology.Builder.create ~point_count:7 () in
  List.iter (fun (a, b, c) -> Topology.Builder.add_triangle bowtie_topology a b c)
    [(0,2,1); (0,1,3); (1,2,3); (2,0,3);
     (0,4,5); (0,6,4); (4,6,5); (5,6,0)];
  let bowtie = Geometry.create ~positions:bowtie_positions
      ~topology:(Topology.Builder.freeze bowtie_topology) () |> get_ok in
  (match Ops.subdivide bowtie with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "subdivision accepted disconnected vertex fans");
  let subdivision_cancel = Cancel.create () in
  Cancel.cancel subdivision_cancel;
  (match Ops.subdivide ~cancel:subdivision_cancel subdivision_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled subdivision published geometry or wrong error");
  let point_ids = Attribute.create_owned ~name:"point_id" ~owner:Attribute.Point
      (Attribute.Int [|10; 20; 30; 40|]) |> get_ok in
  let delete_source = Geometry.with_attribute point_ids subdivision_source
      |> get_ok in
  let remove_point = Group.init ~owner:Group.Point ~name:"remove_point" 4
      (fun point -> point = 1) in
  let remove_nothing = Group.init ~owner:Group.Point ~name:"remove_nothing" 4
      (fun _ -> false) in
  if Ops.delete remove_nothing delete_source |> get_ok != delete_source then
    fail "no-op deletion did not preserve geometry identity";
  let healed_points domains = Parallel.run ~domains (fun () ->
      Ops.delete ~grain:1 ~policy:Ops.Heal_primitives remove_point delete_source
      |> get_ok) in
  let healed_one = healed_points 1 and healed_many = healed_points 4 in
  let healed_topology = Topology.Private.view (Geometry.topology healed_one)
  and healed_topology_many = Topology.Private.view
      (Geometry.topology healed_many) in
  if Geometry.point_count healed_one <> 3
     || Geometry.primitive_count healed_one <> 1
     || Geometry.vertex_count healed_one <> 3
     || healed_topology.vertex_points <> [|0; 1; 2|]
     || healed_topology.vertex_points <> healed_topology_many.vertex_points
     || not (equal_positions healed_one healed_many) then
    fail "point delete/heal cardinality/domain determinism";
  (match Geometry.find_attribute ~owner:Attribute.Point "point_id" healed_one with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Int values when values = [|10; 30; 40|] -> ()
        | _ -> fail "point delete attribute remap")
   | None -> fail "point delete dropped point attribute");
  if Geometry.find_attribute ~owner:Attribute.Point "N" healed_one <> None then
    fail "point healing retained stale normals";
  (match Geometry.find_group ~owner:Group.Point "even" healed_one with
   | Some group when Group.cardinality group = 2
       && Group.mem 0 group && Group.mem 1 group -> ()
   | _ -> fail "point delete group remap");
  let destroyed = Ops.delete remove_point delete_source |> get_ok in
  if Geometry.point_count destroyed <> 3
     || Geometry.primitive_count destroyed <> 0 then
    fail "point delete destroy-touched policy";
  let kept_only = Ops.delete ~selected:false ~policy:Ops.Heal_primitives
      selected delete_source |> get_ok in
  if Geometry.point_count kept_only <> 2
     || Geometry.primitive_count kept_only <> 0 then
    fail "point delete non-selected inversion";
  let remove_vertex = Group.init ~owner:Group.Vertex ~name:"remove_vertex" 4
      (fun vertex -> vertex = 1) in
  let healed_vertex = Ops.delete ~policy:Ops.Heal_primitives remove_vertex
      delete_source |> get_ok in
  if Geometry.point_count healed_vertex <> 4
     || Geometry.vertex_count healed_vertex <> 3
     || (Topology.Private.view (Geometry.topology healed_vertex)).vertex_points
        <> [|0; 2; 3|] then
    fail "vertex delete/heal topology";
  (match Geometry.find_attribute ~owner:Attribute.Vertex "uv" healed_vertex with
   | Some attribute ->
       let values = Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
           attribute |> Option.get |> Packed.Float2.Private.view in
       if values.x <> [|0.; 1.; 0.|] || values.y <> [|0.; 1.; 1.|] then
         fail "vertex delete attribute remap"
   | None -> fail "vertex delete dropped vertex attribute");
  let destroyed_vertex = Ops.delete remove_vertex delete_source |> get_ok in
  if Geometry.primitive_count destroyed_vertex <> 0
     || Geometry.point_count destroyed_vertex <> 4 then
    fail "vertex delete destroy-touched policy";
  let remove_first_primitive = Group.init ~owner:Group.Primitive
      ~name:"remove_first" 2 (fun primitive -> primitive = 0) in
  let primitive_deleted = Ops.delete remove_first_primitive weighted_triangles
      |> get_ok in
  if Packed.Float3.data_id (Geometry.positions primitive_deleted)
       <> Packed.Float3.data_id (Geometry.positions weighted_triangles) then
    fail "primitive deletion copied unchanged point storage";
  let compacted_vertex = Ops.delete ~compact_points:true remove_vertex
      delete_source |> get_ok in
  if Geometry.point_count compacted_vertex <> 0 then
    fail "vertex deletion compact-points policy";
  let open_curve = Ops.polyline
      [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,0.)|] |> get_ok in
  let curve_vertex = Group.init ~owner:Group.Vertex ~name:"middle" 4
      (fun vertex -> vertex = 1) in
  let healed_curve = Ops.delete ~policy:Ops.Heal_primitives curve_vertex open_curve
      |> get_ok in
  if Geometry.vertex_count healed_curve <> 3
     || Topology.primitive_kind (Geometry.topology healed_curve) 0
        <> Topology.Open_polyline then
    fail "open-curve vertex healing";
  let wrong_delete_group = Group.init ~owner:Group.Point ~name:"wrong" 3
      (fun _ -> false) in
  (match Ops.delete wrong_delete_group delete_source with
   | Error error when Error.code error = "invalid_selection" -> ()
   | _ -> fail "delete accepted a mismatched selection length");
  let delete_cancel = Cancel.create () in
  Cancel.cancel delete_cancel;
  (match Ops.delete ~cancel:delete_cancel remove_point delete_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled delete published geometry or wrong error");
  let mesh = Prismel_mesh.to_mesh triangle_geometry |> get_ok in
  if Mesh.vertex_count mesh <> 4 || Mesh.index_count mesh <> 6 then
    fail "mesh bridge cardinality";
  let source_positions = Packed.Float3.Private.view positions
  and source_topology = Topology.Private.view (Geometry.topology triangle_geometry)
  and mesh_view = Mesh.Private.packed_view mesh in
  if source_positions.x != mesh_view.vertices.x
     || source_positions.y != mesh_view.vertices.y
     || source_positions.z != mesh_view.vertices.z
     || source_topology.vertex_points != mesh_view.indices then
    fail "mesh bridge copied packed render buffers";
  let roundtrip = Prismel_mesh.of_mesh mesh |> get_ok in
  if not (equal_positions triangle_geometry roundtrip) then fail "mesh bridge positions";
  let colored = Ops.color_by_height ~low:Color.red ~high:Color.blue
      triangle_geometry |> get_ok in
  let color_before = Geometry.find_attribute ~owner:Attribute.Point "Cd" colored
      |> Option.get in
  let renamed = Geometry.rename_attribute ~owner:Attribute.Point
      ~from:"Cd" ~into:"display_color" colored |> get_ok in
  let color_after = Geometry.find_attribute ~owner:Attribute.Point "display_color"
      renamed |> Option.get in
  if Attribute.data_id color_before = Attribute.data_id color_after
     || Attribute.storage_id color_before <> Attribute.storage_id color_after
  then fail "attribute rename storage sharing";
  let colored_mesh = Prismel_mesh.to_mesh colored |> get_ok in
  if not (Mesh.has_colors colored_mesh) then fail "mesh bridge dropped point Cd";
  let vertex_colors =
    let values = Packed.Float4.of_owned
        ~x:[|1.; 0.; 0.; 0.; 1.; 1.|]
        ~y:[|0.; 1.; 0.; 0.; 1.; 0.|]
        ~z:[|0.; 0.; 1.; 1.; 0.; 1.|]
        ~w:(Array.make 6 1.) |> get_ok in
    Attribute.create_key_owned (Attribute.color ~owner:Attribute.Vertex) values
    |> get_ok in
  let seamed = Geometry.with_attribute vertex_colors triangle_geometry |> get_ok in
  let seamed_mesh = Prismel_mesh.to_mesh seamed |> get_ok in
  if Mesh.vertex_count seamed_mesh <> 6 || Mesh.index_count seamed_mesh <> 6
  then fail "vertex attribute seam was not expanded";
  let diagonal = 1. /. sqrt 2. in
  let vertex_normals = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make 6 diagonal) ~y:(Array.make 6 diagonal) ~z:(Array.make 6 0.) in
  let vertex_normal = Attribute.create_key_owned
      (Attribute.normal ~owner:Attribute.Vertex) vertex_normals |> get_ok in
  let with_vertex_normals = Geometry.with_attribute vertex_normal triangle_geometry |> get_ok in
  let scaled = Ops.transform (Mat4.scaling (Vec3.create 2. 1. 1.))
      with_vertex_normals in
  let scaled_n = Geometry.find_attribute ~owner:Attribute.Vertex "N" scaled
      |> Option.get |> Attribute.get (Attribute.normal ~owner:Attribute.Vertex)
      |> Option.get in
  let nx, ny, _ = Packed.Float3.get scaled_n 0 in
  if abs_float (nx -. 0.4472135955) > 1e-9
     || abs_float (ny -. 0.8944271910) > 1e-9
  then fail "vertex normal inverse-transpose";
  let grid = Ops.grid ~columns:8 ~rows:4 ~size:2. () |> get_ok in
  if Geometry.point_count grid <> 45 || Geometry.primitive_count grid <> 64
  then fail "grid cardinality";
  let box = Ops.box ~size:(Vec3.create 2. 4. 6.) () |> get_ok in
  if Geometry.point_count box <> 24 || Geometry.primitive_count box <> 12
  then fail "box cardinality";
  let sphere = Ops.uv_sphere ~segments:12 ~rings:6 ~radius:2. () |> get_ok in
  if Geometry.point_count sphere <> 62 || Geometry.primitive_count sphere <> 120
  then fail "UV sphere cardinality";
  if Mesh.index_count (Prismel_mesh.to_mesh sphere |> get_ok) <> 360
  then fail "UV sphere bridge";
  let circle = Ops.circle ~segments:18 ~radius:2. () |> get_ok in
  let circle_mesh = Prismel_mesh.to_mesh circle |> get_ok in
  if Mesh.mode circle_mesh <> Mesh.Lines || Mesh.index_count circle_mesh <> 36
  then fail "closed curve bridge";
  let bent = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (1.,3.,0.)|] |> get_ok in
  let distance_attribute = Attribute.create_owned ~name:"distance"
      ~owner:Attribute.Point (Attribute.Float [|0.; 1.; 4.|]) |> get_ok in
  let bent = Geometry.with_attribute distance_attribute bent |> get_ok in
  (match Attribute.storage distance_attribute with
   | Attribute.Float values -> values.(0) <- 99.
   | _ -> assert false);
  let distance_key = Attribute.key ~name:"distance" ~owner:Attribute.Point
      Attribute.float in
  let borrowed_copy = Attribute.get distance_key distance_attribute |> Option.get in
  borrowed_copy.(1) <- 99.;
  (match Attribute.storage distance_attribute with
   | Attribute.Float values when values = [|0.; 1.; 4.|] -> ()
   | _ -> fail "public attribute access leaked mutable storage");
  let resampled = Ops.resample_curves ~segments:4 bent |> get_ok in
  if Geometry.point_count resampled <> 5
     || Topology.primitive_kind (Geometry.topology resampled) 0
        <> Topology.Open_polyline
  then fail "curve resample cardinality/kind";
  let resampled_positions = Geometry.positions resampled in
  let x2, y2, _ = Packed.Float3.get resampled_positions 2
  and _, y4, _ = Packed.Float3.get resampled_positions 4 in
  if x2 <> 1. || y2 <> 1. || y4 <> 3. then fail "curve arc-length resample";
  (match Geometry.find_attribute ~owner:Attribute.Point "distance" resampled with
   | Some attribute ->
       (match Attribute.storage attribute with
        | Attribute.Float values when values = [|0.; 1.; 2.; 3.; 4.|] -> ()
        | _ -> fail "curve attribute interpolation")
   | None -> fail "curve resample dropped point attribute");
  let swept = Ops.sweep_circle ~sides:8 ~radius:0.2 resampled |> get_ok in
  if Geometry.point_count swept <> 40 || Geometry.primitive_count swept <> 32
     || Geometry.vertex_count swept <> 128
  then fail "circle sweep cardinality";
  if Geometry.find_attribute ~owner:Attribute.Point "N" swept = None
     || Geometry.find_attribute ~owner:Attribute.Vertex "uv" swept = None
     || Geometry.find_attribute ~owner:Attribute.Point "distance" swept = None
  then fail "circle sweep attributes";
  if Mesh.index_count (Prismel_mesh.to_mesh swept |> get_ok) <> 192
  then fail "circle sweep bridge";
  let planar_projection = Ops.Planar {
      origin = Vec3.create 0.5 0.5 0.;
      u_axis = Vec3.unit_x;
      v_axis = Vec3.unit_y;
    } in
  let projected_quad = Ops.uv_project ~grain:1 planar_projection geometry
      |> get_ok in
  let projected_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      projected_quad |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  if projected_uv.x <> [|0.; 1.; 1.; 0.|]
     || projected_uv.y <> [|0.; 0.; 1.; 1.|]
  then fail "planar UV projection coordinates";
  if Geometry.payload_bytes projected_quad - Geometry.payload_bytes geometry
     <> Geometry.vertex_count geometry * 16
  then fail "UV projection payload is not exact per-corner float2 storage";
  if Geometry.positions projected_quad != Geometry.positions geometry
     || Geometry.topology projected_quad != Geometry.topology geometry
  then fail "UV projection copied unchanged geometry payload";
  let skewed_quad = Ops.uv_project
      (Ops.Planar { origin = Vec3.zero; u_axis = Vec3.unit_x;
        v_axis = Vec3.create 0.5 1. 0. }) geometry |> get_ok in
  let skewed_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      skewed_quad |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  let nearly_array left right =
    Array.length left = Array.length right
    && Array.for_all2 (fun left right -> abs_float (left -. right) < 1e-12)
         left right in
  if not (nearly_array skewed_uv.x [|0.5; 1.5; 1.; 0.|])
     || not (nearly_array skewed_uv.y [|0.5; 0.5; 1.5; 1.5|])
  then fail "skewed planar UV frame solve";
  let existing_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.make 6 0.25) ~y:(Array.make 6 0.25) |> get_ok)) |> get_ok in
  let restricted_source = Geometry.with_attribute existing_uv triangle_geometry
      |> get_ok in
  let first_face = Group.init ~owner:Group.Primitive ~name:"first_face" 2
      (fun primitive -> primitive = 0) in
  let restricted = Ops.uv_project ~grain:1 ~primitives:first_face
      planar_projection restricted_source |> get_ok in
  let restricted_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      restricted |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  if restricted_uv.x <> [|0.; 1.; 1.; 0.25; 0.25; 0.25|]
     || restricted_uv.y <> [|0.; 0.; 1.; 0.25; 0.25; 0.25|]
  then fail "primitive-restricted UV projection did not preserve other corners";
  let selected_uv = Group.init ~owner:Group.Vertex ~name:"selected_uv" 6
      (fun vertex -> vertex = 0 || vertex = 2) in
  let transformed_uv = Ops.uv_transform ~grain:1 ~owner:Attribute.Vertex
      ~selection:selected_uv ~pivot:Vec2.zero ~scale:(Vec2.create 2. 2.)
      ~translate:(Vec2.create 0.1 (-0.2)) restricted |> get_ok in
  let transformed_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      transformed_uv |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  if transformed_uv.x <> [|0.1; 1.; 2.1; 0.25; 0.25; 0.25|]
     || transformed_uv.y <> [|-0.2; 0.; 1.8; 0.25; 0.25; 0.25|]
  then fail "restricted UV transform";
  let point_uv = Attribute.create_owned ~name:"point_uv"
      ~owner:Attribute.Point
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 1.; 1.; 0.|] ~y:[|0.; 0.; 1.; 1.|] |> get_ok)) |> get_ok in
  let point_uv_source = Geometry.with_attribute point_uv geometry |> get_ok in
  let point_uv_output = Ops.uv_transform ~name:"point_uv"
      ~owner:Attribute.Point ~selection:selected
      ~scale:(Vec2.create 0.5 0.5) ~pivot:Vec2.zero point_uv_source |> get_ok in
  let point_uv_values = Geometry.find_attribute ~owner:Attribute.Point "point_uv"
      point_uv_output |> Option.get
      |> Attribute.get (Attribute.key ~name:"point_uv" ~owner:Attribute.Point
           Attribute.float2)
      |> Option.get |> Packed.Float2.Private.view in
  if point_uv_values.x <> [|0.; 1.; 0.5; 0.|]
     || point_uv_values.y <> [|0.; 0.; 0.5; 1.|]
  then fail "point-owned restricted UV transform";
  let angle = 0.1 in
  let cylinder_curve = Ops.polyline ~closed:true [|
      (cos (-.angle), 0.5, sin (-.angle));
      (cos (-.angle), -0.5, sin (-.angle));
      (cos angle, -0.5, sin angle);
      (cos angle, 0.5, sin angle);
    |] |> get_ok in
  let cylindrical = Ops.uv_project ~grain:1
      (Ops.Cylindrical { origin = Vec3.zero; axis = Vec3.unit_y;
        seam = Vec3.unit_x; height = 1. }) cylinder_curve |> get_ok in
  let cylindrical_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      cylindrical |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  let cylinder_min = Array.fold_left min infinity cylindrical_uv.x
  and cylinder_max = Array.fold_left max neg_infinity cylindrical_uv.x in
  if cylinder_max -. cylinder_min > 0.04
     || cylindrical_uv.y <> [|1.; 0.; 0.; 1.|]
  then fail "cylindrical UV seam/height projection";
  let huge_frame = Ops.uv_project
      (Ops.Cylindrical { origin = Vec3.zero;
        axis = Vec3.create 0. max_float 0.;
        seam = Vec3.create max_float 0. 0.; height = 1. })
      cylinder_curve |> get_ok in
  let huge_frame_uv = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      huge_frame |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  if Array.exists (fun value -> not (Float.is_finite value)) huge_frame_uv.x
     || Array.exists (fun value -> not (Float.is_finite value)) huge_frame_uv.y
  then fail "UV projection did not normalize an extreme finite frame safely";
  let sphere_uv = Ops.uv_sphere ~segments:48 ~rings:24 ~radius:1. () |> get_ok
      |> Ops.uv_project ~grain:31
           (Ops.Spherical { origin = Vec3.zero; axis = Vec3.unit_y;
             seam = Vec3.unit_x }) |> get_ok in
  let sphere_values = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      sphere_uv |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view
  and sphere_topology = Topology.Private.view (Geometry.topology sphere_uv) in
  for primitive = 0 to Geometry.primitive_count sphere_uv - 1 do
    let first = sphere_topology.primitive_offsets.(primitive)
    and last = sphere_topology.primitive_offsets.(primitive + 1) in
    let minimum = ref infinity and maximum = ref neg_infinity in
    for vertex = first to last - 1 do
      minimum := min !minimum sphere_values.x.(vertex);
      maximum := max !maximum sphere_values.x.(vertex);
      if not (Float.is_finite sphere_values.x.(vertex)
          && Float.is_finite sphere_values.y.(vertex))
         || sphere_values.y.(vertex) < 0. || sphere_values.y.(vertex) > 1.
      then fail "spherical UV produced an invalid coordinate"
    done;
    if !maximum -. !minimum > 0.500000000001 then
      fail "spherical UV primitive crosses the wrap seam"
  done;
  (match Ops.uv_project
      (Ops.Planar { origin = Vec3.zero; u_axis = Vec3.unit_x;
        v_axis = Vec3.unit_x }) geometry with
   | Error error when Error.code error = "invalid_projection" -> ()
   | _ -> fail "UV Project accepted parallel planar axes");
  (match Ops.uv_project ~primitives:selected planar_projection geometry with
   | Error error when Error.code error = "invalid_projection" -> ()
   | _ -> fail "UV Project accepted a point-owned primitive selection");
  let wrong_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float (Array.make 4 0.)) |> get_ok in
  let wrong_uv_geometry = Geometry.with_attribute wrong_uv geometry |> get_ok in
  (match Ops.uv_project planar_projection wrong_uv_geometry with
   | Error error when Error.code error = "invalid_projection" -> ()
   | _ -> fail "UV Project accepted a non-float2 existing UV attribute");
  let invalid_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|nan; 1.; 1.; 0.|] ~y:[|0.; 0.; 1.; 1.|]
      ~z:[|0.; 0.; 0.; 0.|] in
  let invalid_geometry = Geometry.create ~positions:invalid_positions ~topology ()
      |> get_ok in
  (match Ops.uv_project planar_projection invalid_geometry with
   | Error error when Error.code error = "invalid_projection" -> ()
   | _ -> fail "UV Project accepted a non-finite point position");
  let cancelled_uv = Cancel.create () in
  Cancel.cancel cancelled_uv;
  (match Ops.uv_project ~cancel:cancelled_uv planar_projection geometry with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "UV Project ignored cancellation");
  let hard_seams domains = Parallel.run ~domains (fun () ->
    Ops.uv_auto_seam ~grain:1 ~angle:(Float.pi /. 4.)
      ~include_boundaries:false ~island_attribute:"uv_island" shared_box
    |> get_ok) in
  let hard_seams_one = hard_seams 1 and hard_seams_many = hard_seams 4 in
  let seam_group geometry = Geometry.find_group ~owner:Group.Vertex
      "uv_seams" geometry |> Option.get in
  let edge_seam_group geometry = Geometry.find_edge_group "uv_seams" geometry
      |> Option.get in
  let island_values geometry = Geometry.find_attribute
      ~owner:Attribute.Primitive "uv_island" geometry |> Option.get
      |> Attribute.get (Attribute.key ~name:"uv_island"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  let hard_one_group = seam_group hard_seams_one
  and hard_many_group = seam_group hard_seams_many
  and hard_one_edges = edge_seam_group hard_seams_one
  and hard_many_edges = edge_seam_group hard_seams_many in
  if Group.cardinality hard_one_group <> 24
     || Group.cardinality hard_many_group <> 24
     || Edge_group.cardinality hard_one_edges <> 12
     || Edge_group.cardinality hard_many_edges <> 12
     || island_values hard_seams_one <> island_values hard_seams_many
     || List.length (List.sort_uniq Int.compare
          (Array.to_list (island_values hard_seams_one))) <> 6
  then fail "UV Auto Seam cube classification/islands/domain determinism";
  for vertex = 0 to Group.length hard_one_group - 1 do
    if Group.mem vertex hard_one_group <> Group.mem vertex hard_many_group then
      fail "UV Auto Seam group differs by domain count"
  done;
  for edge = 0 to Edge_group.length hard_one_edges - 1 do
    if Edge_group.mem edge hard_one_edges <> Edge_group.mem edge hard_many_edges then
      fail "UV Auto Seam native edge group differs by domain count"
  done;
  if Geometry.positions hard_seams_one != Geometry.positions shared_box
     || Geometry.topology hard_seams_one != Geometry.topology shared_box
  then fail "UV Auto Seam copied unchanged geometry payload";
  let sharp_edges domains = Parallel.run ~domains (fun () ->
    Ops.group_edges ~grain:1 ~name:"sharp" ~incidence:Ops.Manifold_edge
      ~min_angle:(Float.pi /. 4.) shared_box |> get_ok) in
  let sharp_one = sharp_edges 1 and sharp_many = sharp_edges 4 in
  let sharp_group geometry = Geometry.find_edge_group "sharp" geometry
      |> Option.get in
  let sharp_one_group = sharp_group sharp_one
  and sharp_many_group = sharp_group sharp_many in
  if Edge_group.cardinality sharp_one_group <> 12
     || Edge_group.cardinality sharp_many_group <> 12 then
    fail "Edge Group sharp cube cardinality";
  for edge = 0 to Edge_group.length sharp_one_group - 1 do
    if Edge_group.mem edge sharp_one_group <> Edge_group.mem edge sharp_many_group
    then fail "Edge Group differs by domain count"
  done;
  let boundary_edges = Ops.group_edges ~name:"boundary"
      ~incidence:Ops.Boundary_edge triangle_geometry |> get_ok
      |> Geometry.find_edge_group "boundary" |> Option.get in
  if Edge_group.cardinality boundary_edges <> 4 then
    fail "Edge Group boundary incidence";
  let unit_edges = Ops.group_edges ~name:"unit" ~min_length:1. ~max_length:1.
      triangle_geometry |> get_ok |> Geometry.find_edge_group "unit"
      |> Option.get in
  if Edge_group.cardinality unit_edges <> 4 then
    fail "Edge Group inclusive length range";
  let selected_edges = Ops.group_edges ~name:"selected_edges"
      ~primitives:first_face triangle_geometry |> get_ok
      |> Geometry.find_edge_group "selected_edges" |> Option.get in
  if Edge_group.cardinality selected_edges <> 3 then
    fail "Edge Group primitive selection";
  (match Geometry.with_edge_group sharp_one_group triangle_geometry with
   | Error _ -> ()
   | Ok _ -> fail "Geometry accepted an edge group from another topology");
  let quad_edges = Ops.group_edges ~name:"quad_edges" geometry |> get_ok in
  let triangulated_edges = Ops.triangulate quad_edges |> get_ok in
  let triangulated_edge_group = Geometry.find_edge_group "quad_edges"
      triangulated_edges |> Option.get in
  if Edge_group.cardinality triangulated_edge_group <> 4
     || Edge_group.length triangulated_edge_group <> 5 then
    fail "triangulate did not preserve original edges/exclude its diagonal";
  let reversed_edges = Ops.reverse quad_edges |> get_ok
      |> Geometry.find_edge_group "quad_edges" |> Option.get in
  if Edge_group.cardinality reversed_edges <> 4 then
    fail "reverse did not remap native edge membership";
  let quad_edge_group = Geometry.find_edge_group "quad_edges" quad_edges
      |> Option.get
  and quad_edge_index = Topology_index.create (Geometry.topology quad_edges) in
  let reversed_topology = Ops.reverse quad_edges |> get_ok |> Geometry.topology in
  (match Edge_group.replicate_exact_copies
      ~source_topology:(Geometry.topology quad_edges)
      ~source_index:quad_edge_index ~target_topology:reversed_topology
      ~copies:1 quad_edge_group with
   | Error _ -> ()
   | Ok _ -> fail "exact-copy edge replication accepted reordered topology");
  let mirrored_edge_geometry = Ops.mirror ~origin:Vec3.zero ~normal:Vec3.unit_x
      quad_edges |> get_ok in
  let mirrored_edge_group = Geometry.find_edge_group "quad_edges"
      mirrored_edge_geometry |> Option.get in
  if Edge_group.cardinality mirrored_edge_group <> 8
     || Edge_group.length mirrored_edge_group <> 8 then
    fail "mirror did not replicate native edge membership";
  let duplicated_edge_geometry = Ops.duplicate ~copies:2 quad_edges |> get_ok in
  let duplicated_edge_group = Geometry.find_edge_group "quad_edges"
      duplicated_edge_geometry |> Option.get in
  if Edge_group.cardinality duplicated_edge_group <> 12
     || Edge_group.length duplicated_edge_group <> 12 then
    fail "duplicate did not replicate native edge membership";
  let merged_edge_geometry = Ops.merge [quad_edges; quad_edges] |> get_ok in
  let merged_edge_group = Geometry.find_edge_group "quad_edges"
      merged_edge_geometry |> Option.get in
  if Edge_group.cardinality merged_edge_group <> 8
     || Edge_group.length merged_edge_group <> 8 then
    fail "merge did not concatenate native edge membership";
  let copied_edge_geometry = Ops.copy_to_points ~source:quad_edges
      ~targets:(Ops.points [|(0., 0., 0.); (3., 0., 0.)|]) () |> get_ok in
  let copied_edge_group = Geometry.find_edge_group "quad_edges"
      copied_edge_geometry |> Option.get in
  if Edge_group.cardinality copied_edge_group <> 8
     || Edge_group.length copied_edge_group <> 8 then
    fail "copy-to-points did not replicate native edge membership";
  let hard_box_edges = Ops.box ~size:(Vec3.create 2. 2. 2.) () |> get_ok
      |> Ops.group_edges ~name:"all_box_edges" |> get_ok in
  let fused_edge_geometry = Ops.fuse ~tolerance:0.
      ~attributes:Ops.Average_numeric hard_box_edges |> get_ok in
  let fused_edge_group = Geometry.find_edge_group "all_box_edges"
      fused_edge_geometry |> Option.get in
  if Edge_group.cardinality fused_edge_group <> 18
     || Edge_group.length fused_edge_group <> 18 then
    fail "fuse did not union collapsed native edge membership";
  let subdivided_edge_geometry = Ops.subdivide ~scheme:Ops.Catmull_clark
      ~iterations:2 quad_edges |> get_ok in
  let subdivided_edge_group = Geometry.find_edge_group "quad_edges"
      subdivided_edge_geometry |> Option.get in
  if Edge_group.cardinality subdivided_edge_group <> 16 then
    fail "subdivision did not propagate selected source-edge children";
  let clipped_edge_geometry = Ops.clip ~keep:Ops.Above
      ~origin:(Vec3.create 0.5 0. 0.) ~normal:Vec3.unit_x quad_edges |> get_ok in
  let clipped_edge_group = Geometry.find_edge_group "quad_edges"
      clipped_edge_geometry |> Option.get in
  if Edge_group.cardinality clipped_edge_group <> 3
     || Edge_group.length clipped_edge_group <> 4 then
    fail "clip did not preserve source fragments/exclude its cut edge";
  let extruded_edge_geometry = Ops.poly_extrude ~distance:1. quad_edges
      |> get_ok in
  let extruded_edge_group = Geometry.find_edge_group "quad_edges"
      extruded_edge_geometry |> Option.get in
  if Edge_group.cardinality extruded_edge_group <> 8
     || Edge_group.length extruded_edge_group <> 12 then
    fail "poly extrude did not propagate bottom/top source edges";
  let sorted_edge_geometry = Ops.sort ~owner:Ops.Points ~key:Ops.X quad_edges
      |> get_ok in
  let sorted_edge_group = Geometry.find_edge_group "quad_edges"
      sorted_edge_geometry |> Option.get in
  if Edge_group.cardinality sorted_edge_group <> 4 then
    fail "point sort did not remap native edge membership";
  let triangle_edges = Ops.group_edges ~name:"triangle_edges" triangle_geometry
      |> get_ok in
  let sorted_primitives = Ops.sort ~descending:true ~owner:Ops.Primitives
      ~key:Ops.Reverse triangle_edges |> get_ok in
  if Edge_group.cardinality (Geometry.find_edge_group "triangle_edges"
      sorted_primitives |> Option.get) <> 5 then
    fail "primitive sort did not remap native edge membership";
  let remove_first_edge_face = Group.init ~owner:Group.Primitive
      ~name:"remove_first_edge_face" 2 (fun primitive -> primitive = 0) in
  let deleted_edge_geometry = Ops.delete remove_first_edge_face triangle_edges
      |> get_ok in
  let deleted_edge_group = Geometry.find_edge_group "triangle_edges"
      deleted_edge_geometry |> Option.get in
  if Edge_group.cardinality deleted_edge_group <> 3
     || Edge_group.length deleted_edge_group <> 3 then
    fail "primitive deletion did not remap surviving native edges";
  let partition = Attribute.create_owned ~name:"partition"
      ~owner:Attribute.Primitive (Attribute.Int [|0; 1|]) |> get_ok in
  let partition_source = Geometry.with_attribute partition triangle_geometry
      |> get_ok in
  let partitioned = Ops.uv_auto_seam ~grain:1 ~angle:Float.pi
      ~include_boundaries:false ~partition_attribute:"partition"
      ~island_attribute:"piece" partition_source |> get_ok in
  let partition_seams = seam_group partitioned in
  let pieces = Geometry.find_attribute ~owner:Attribute.Primitive "piece"
      partitioned |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if Group.cardinality partition_seams <> 2
     || Edge_group.cardinality (edge_seam_group partitioned) <> 1
     || pieces <> [|0; 1|] then
    fail "UV Auto Seam partition cut/stable island IDs";
  let continuous_uv = Attribute.create_owned ~name:"existing_uv"
      ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 1.; 1.; 0.; 1.; 0.|]
        ~y:[|0.; 0.; 1.; 0.; 1.; 1.|] |> get_ok)) |> get_ok in
  let continuous_source = Geometry.with_attribute continuous_uv triangle_geometry
      |> get_ok in
  let continuous = Ops.uv_auto_seam ~angle:Float.pi
      ~include_boundaries:false ~existing_uv:"existing_uv" continuous_source
      |> get_ok in
  if Group.cardinality (seam_group continuous) <> 0
     || Edge_group.cardinality (edge_seam_group continuous) <> 0 then
    fail "UV Auto Seam cut a continuous shared edge";
  let discontinuous_uv = Attribute.create_owned ~name:"existing_uv"
      ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 1.; 1.; 0.25; 1.; 0.|]
        ~y:[|0.; 0.; 1.; 0.; 1.; 1.|] |> get_ok)) |> get_ok in
  let discontinuous_source = Geometry.with_attribute discontinuous_uv
      triangle_geometry |> get_ok in
  let discontinuous = Ops.uv_auto_seam ~angle:Float.pi
      ~include_boundaries:false ~existing_uv:"existing_uv" discontinuous_source
      |> get_ok in
  if Group.cardinality (seam_group discontinuous) <> 2
     || Edge_group.cardinality (edge_seam_group discontinuous) <> 1 then
    fail "UV Auto Seam missed an existing-UV discontinuity";
  let nonmanifold_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.; 0.|] ~y:[|0.; 0.; 1.; 0.; -1.|]
      ~z:[|0.; 0.; 0.; 1.; 0.|] in
  let nonmanifold_builder = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_triangle nonmanifold_builder 0 1 2;
  Topology.Builder.add_triangle nonmanifold_builder 1 0 3;
  Topology.Builder.add_triangle nonmanifold_builder 0 1 4;
  let nonmanifold = Geometry.create ~positions:nonmanifold_positions
      ~topology:(Topology.Builder.freeze nonmanifold_builder) () |> get_ok in
  let nonmanifold = Ops.uv_auto_seam ~angle:Float.pi
      ~include_boundaries:false ~include_non_manifold:true nonmanifold |> get_ok in
  if Group.cardinality (seam_group nonmanifold) <> 3
     || Edge_group.cardinality (edge_seam_group nonmanifold) <> 1 then
    fail "UV Auto Seam non-manifold incidence policy";
  let nonmanifold_edges = Ops.group_edges ~name:"nonmanifold"
      ~incidence:Ops.Non_manifold_edge nonmanifold |> get_ok
      |> Geometry.find_edge_group "nonmanifold" |> Option.get in
  if Edge_group.cardinality nonmanifold_edges <> 1 then
    fail "Edge Group non-manifold incidence";
  let strip_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.; 0.; 1.; 2.|]
      ~y:[|0.; 0.; 0.; 1.; 1.; 1.|] ~z:(Array.make 6 0.) in
  let strip_builder = Topology.Builder.create ~point_count:6 () in
  Topology.Builder.add_polygon strip_builder [|0; 1; 4; 3|];
  Topology.Builder.add_polygon strip_builder [|1; 2; 5; 4|];
  let strip_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 1.; 1.; 0.; 1.; 2.; 2.; 1.|]
        ~y:[|0.; 0.; 1.; 1.; 0.; 0.; 1.; 1.|] |> get_ok)) |> get_ok in
  let strip = Geometry.create ~positions:strip_positions
      ~topology:(Topology.Builder.freeze strip_builder) ~attributes:[strip_uv] ()
      |> get_ok in
  let unitized domains seams = Parallel.run ~domains (fun () ->
    Ops.uv_unitize ~grain:1 ?seams ~uniform:false Ops.Islands strip |> get_ok) in
  let island_unitized_one = unitized 1 None
  and island_unitized_many = unitized 4 None in
  let uv_values geometry = Geometry.find_attribute ~owner:Attribute.Vertex "uv"
      geometry |> Option.get
      |> Attribute.get (Attribute.tex_coord ~owner:Attribute.Vertex)
      |> Option.get |> Packed.Float2.Private.view in
  let island_one_uv = uv_values island_unitized_one
  and island_many_uv = uv_values island_unitized_many in
  if island_one_uv.x <> [|0.; 0.5; 0.5; 0.; 0.5; 1.; 1.; 0.5|]
     || island_one_uv.y <> [|0.; 0.; 1.; 1.; 0.; 0.; 1.; 1.|]
     || island_one_uv.x <> island_many_uv.x
     || island_one_uv.y <> island_many_uv.y
  then fail "UV Unitize island fit/domain determinism";
  let forced_seams = Group.init ~owner:Group.Vertex ~name:"forced" 8
      (fun vertex -> vertex = 1 || vertex = 7) in
  let split_unitized = unitized 4 (Some forced_seams) |> uv_values in
  if split_unitized.x <> [|0.; 1.; 1.; 0.; 0.; 1.; 1.; 0.|]
     || split_unitized.y <> [|0.; 0.; 1.; 1.; 0.; 0.; 1.; 1.|]
  then fail "UV Unitize forced island seam";
  let strip_index = Topology_index.create (Geometry.topology strip) in
  let shared_strip_edge = Topology_index.find_edge strip_index ~a:1 ~b:4
      |> Option.get in
  let native_forced = Edge_group.init ~topology:(Geometry.topology strip)
      ~index:strip_index ~name:"forced_native"
      (fun edge -> edge = shared_strip_edge) in
  let native_split = Ops.uv_unitize ~grain:1 ~edge_seams:native_forced
      ~uniform:false Ops.Islands strip |> get_ok |> uv_values in
  if native_split.x <> split_unitized.x || native_split.y <> split_unitized.y then
    fail "UV Unitize native edge seam differs from compatibility corners";
  (match Ops.uv_unitize ~edge_seams:hard_one_edges Ops.Islands strip with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Unitize accepted an edge group from another topology");
  let face_unitized = Ops.uv_unitize ~uniform:false Ops.Per_face strip
      |> get_ok |> uv_values in
  if face_unitized.x <> split_unitized.x
     || face_unitized.y <> split_unitized.y
  then fail "UV Unitize per-face mode";
  let uniform_unitized = Ops.uv_unitize ~uniform:true Ops.Islands strip
      |> get_ok |> uv_values in
  if uniform_unitized.x <> [|0.; 0.5; 0.5; 0.; 0.5; 1.; 1.; 0.5|]
     || uniform_unitized.y <> [|0.25; 0.25; 0.75; 0.75; 0.25; 0.25; 0.75; 0.75|]
  then fail "UV Unitize uniform aspect preservation";
  let flatten_source = Ops.grid ~columns:2 ~rows:2 ~size:2. () |> get_ok in
  let flattened domains = Parallel.run ~domains (fun () ->
    Ops.uv_flatten ~grain:1 ~iterations:500 ~tolerance:1e-12 flatten_source
    |> get_ok) in
  let flattened_one = flattened 1 and flattened_many = flattened 4 in
  let flat_one_uv = uv_values flattened_one
  and flat_many_uv = uv_values flattened_many in
  if flat_one_uv.x <> flat_many_uv.x || flat_one_uv.y <> flat_many_uv.y then
    fail "UV Flatten differs by domain count";
  Array.iteri (fun corner u ->
    let v = flat_one_uv.y.(corner) in
    if not (Float.is_finite u && Float.is_finite v)
        || u < 0. || u > 1. || v < 0. || v > 1. then
      fail "UV Flatten escaped its packed unit area") flat_one_uv.x;
  let flat_topology = Topology.Private.view (Geometry.topology flattened_one) in
  let winding = ref 0. in
  for primitive = 0 to Geometry.primitive_count flattened_one - 1 do
    let first = flat_topology.primitive_offsets.(primitive) in
    let area = (flat_one_uv.x.(first + 1) -. flat_one_uv.x.(first))
          *. (flat_one_uv.y.(first + 2) -. flat_one_uv.y.(first))
        -. (flat_one_uv.y.(first + 1) -. flat_one_uv.y.(first))
          *. (flat_one_uv.x.(first + 2) -. flat_one_uv.x.(first)) in
    if abs_float area <= 1e-12 then fail "UV Flatten collapsed a triangle";
    if !winding = 0. then winding := area
    else if area *. !winding <= 0. then fail "UV Flatten flipped a triangle"
  done;
  let relaxed domains = Parallel.run ~domains (fun () ->
    Ops.uv_relax ~grain:1 ~iterations:100 ~tolerance:1e-12 flattened_one
    |> get_ok) in
  let relaxed_one = relaxed 1 |> uv_values
  and relaxed_many = relaxed 4 |> uv_values in
  if relaxed_one.x <> relaxed_many.x || relaxed_one.y <> relaxed_many.y then
    fail "UV Relax differs by domain count";
  for corner = 0 to Geometry.vertex_count flattened_one - 1 do
    let point = flat_topology.vertex_points.(corner) in
    if point <> 4 && (relaxed_one.x.(corner) <> flat_one_uv.x.(corner)
        || relaxed_one.y.(corner) <> flat_one_uv.y.(corner)) then
      fail "UV Relax moved an island boundary"
  done;
  let seam_cut_box = Ops.uv_auto_seam ~angle:0.1 shared_box |> get_ok in
  let box_seams = Geometry.find_edge_group "uv_seams" seam_cut_box
      |> Option.get in
  let flattened_box = Ops.uv_flatten ~edge_seams:box_seams seam_cut_box
      |> get_ok |> uv_values in
  if Array.exists (fun value -> not (Float.is_finite value)) flattened_box.x
      || Array.exists (fun value -> not (Float.is_finite value)) flattened_box.y
  then fail "UV Flatten seam-cut box produced non-finite coordinates";
  (match Ops.uv_flatten shared_box with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Flatten accepted a closed island without seams");
  (match Ops.uv_flatten geometry with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Flatten accepted non-triangle polygons");
  (match Ops.uv_flatten ~iterations:1 ~tolerance:1e-15
      (Ops.grid ~columns:20 ~rows:20 ~size:2. () |> get_ok) with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Flatten published a non-converged solve");
  (match Ops.uv_flatten ~edge_seams:hard_one_edges flatten_source with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Flatten accepted seams from another topology");
  let discontinuous_u = Array.copy flat_one_uv.x
  and discontinuous_v = Array.copy flat_one_uv.y in
  let center_corner = ref (-1) and repeated_center_corner = ref (-1) in
  Array.iteri (fun corner point -> if point = 4 then
    if !center_corner < 0 then center_corner := corner
    else if !repeated_center_corner < 0 then repeated_center_corner := corner)
    flat_topology.vertex_points;
  discontinuous_u.(!repeated_center_corner) <-
    discontinuous_u.(!repeated_center_corner) +. 0.25;
  let discontinuous_attribute = Attribute.create_owned ~name:"uv"
      ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned ~x:discontinuous_u
        ~y:discontinuous_v |> get_ok)) |> get_ok in
  let discontinuous_flattened = Geometry.with_attribute discontinuous_attribute
      flattened_one |> get_ok in
  (match Ops.uv_relax discontinuous_flattened with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Relax accepted an undeclared UV discontinuity");
  let cancelled_flatten = Cancel.create () in
  Cancel.cancel cancelled_flatten;
  (match Ops.uv_flatten ~cancel:cancelled_flatten flatten_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "UV Flatten ignored cancellation");
  let cancelled_unitize = Cancel.create () in
  Cancel.cancel cancelled_unitize;
  (match Ops.uv_auto_seam ~cancel:cancelled_unitize shared_box with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "UV Auto Seam ignored cancellation");
  (match Ops.uv_unitize ~cancel:cancelled_unitize Ops.Islands strip with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "UV Unitize ignored cancellation");
  (match Ops.group_edges ~cancel:cancelled_unitize strip with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Edge Group ignored cancellation");
  (match Ops.group_edges ~min_angle:0. cylinder_curve with
   | Error error when Error.code error = "invalid_edge_group" -> ()
   | _ -> fail "Edge Group accepted an angle filter on curves");
  let swept_edge_geometry = cylinder_curve
      |> Ops.group_edges ~name:"centerline_edges" |> get_ok
      |> Ops.sweep_circle ~sides:8 ~radius:0.1 |> get_ok in
  let swept_edge_group = Geometry.find_edge_group "centerline_edges"
      swept_edge_geometry |> Option.get in
  if Edge_group.cardinality swept_edge_group <> 32
     || Edge_group.length swept_edge_group <> 64 then
    fail "sweep did not propagate selected centerline edges longitudinally";
  let scaled_spine = Ops.polyline [|(0.,0.,0.); (2.,0.,0.); (4.,0.,0.)|]
      |> get_ok in
  let wire_scale = Attribute.create_owned ~name:"wire_scale"
      ~owner:Attribute.Point (Attribute.Float [|1.; 2.; 0.5|]) |> get_ok in
  let scaled_spine = Geometry.with_attribute wire_scale scaled_spine |> get_ok in
  let scaled_wire = Ops.sweep_circle ~grain:1 ~sides:8
      ~scale_attribute:"wire_scale" ~radius:0.25 scaled_spine |> get_ok in
  let scaled_positions = Packed.Float3.Private.view
      (Geometry.positions scaled_wire) in
  let ring_radius point =
    let output = point * 8 in
    let dx = scaled_positions.x.(output) -. (float_of_int point *. 2.)
    and dy = scaled_positions.y.(output)
    and dz = scaled_positions.z.(output) in
    sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
  if abs_float (ring_radius 0 -. 0.25) > 1e-12
      || abs_float (ring_radius 1 -. 0.5) > 1e-12
      || abs_float (ring_radius 2 -. 0.125) > 1e-12 then
    fail "sweep point scale attribute";
  let capped_wire = Ops.sweep_circle ~grain:1 ~sides:8
      ~scale_attribute:"wire_scale" ~caps:true ~cap_group:"caps"
      ~radius:0.25 scaled_spine |> get_ok in
  let capped_topology = Geometry.topology capped_wire in
  let capped_points = Packed.Float3.Private.view (Geometry.positions capped_wire) in
  let cap_normal_x primitive =
    let first, _ = Topology.primitive_vertex_range capped_topology primitive in
    let point local = Topology.point_of_vertex capped_topology (first + local) in
    let a = point 0 and b = point 1 and c = point 2 in
    let aby = capped_points.y.(b) -. capped_points.y.(a)
    and abz = capped_points.z.(b) -. capped_points.z.(a)
    and acy = capped_points.y.(c) -. capped_points.y.(a)
    and acz = capped_points.z.(c) -. capped_points.z.(a) in
    (aby *. acz) -. (abz *. acy) in
  let cap_group = Geometry.find_group ~owner:Group.Primitive "caps" capped_wire
      |> Option.get in
  if Geometry.point_count capped_wire <> 24
      || Geometry.primitive_count capped_wire <> 18
      || Geometry.vertex_count capped_wire <> 80
      || Topology.primitive_size capped_topology 16 <> 8
      || Topology.primitive_size capped_topology 17 <> 8
      || cap_normal_x 16 >= 0. || cap_normal_x 17 <= 0.
      || Group.cardinality cap_group <> 2
      || Geometry.find_attribute ~owner:Attribute.Vertex "N" capped_wire = None
      then fail "sweep cap topology/winding/group/hard normals";
  (match Ops.sweep_circle ~cap_group:"caps" ~radius:0.1 scaled_spine with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "sweep accepted a cap group without caps");
  (match Ops.sweep_circle ~scale_attribute:"missing" ~radius:0.1 scaled_spine with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "sweep accepted a missing scale attribute");
  let invalid_wire_scale = Attribute.create_owned ~name:"wire_scale"
      ~owner:Attribute.Point (Attribute.Float [|1.; -1.; 1.|]) |> get_ok in
  let invalid_scaled_spine = Geometry.with_attribute invalid_wire_scale
      scaled_spine |> get_ok in
  (match Ops.sweep_circle ~scale_attribute:"wire_scale" ~radius:0.1
      invalid_scaled_spine with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "sweep accepted a negative point scale");
  let resampled_closed = cylinder_curve
      |> Ops.group_edges ~name:"curve_edges" |> get_ok
      |> Ops.resample_curves ~segments:8 |> get_ok in
  let resampled_closed_group = Geometry.find_edge_group "curve_edges"
      resampled_closed |> Option.get in
  if Edge_group.cardinality resampled_closed_group <> 8
     || Edge_group.length resampled_closed_group <> 8 then
    fail "closed resample did not propagate selected edge intervals";
  let open_curve = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.);
      (3.,0.,0.)|] |> get_ok in
  let open_index = Topology_index.create (Geometry.topology open_curve) in
  let middle_edge = Topology_index.find_edge open_index ~a:1 ~b:2 |> Option.get in
  let middle_group = Edge_group.init ~topology:(Geometry.topology open_curve)
      ~index:open_index ~name:"middle_edge" (fun edge -> edge = middle_edge) in
  let resampled_partial = Geometry.with_edge_group middle_group open_curve |> get_ok
      |> Ops.resample_curves ~segments:6 |> get_ok in
  let resampled_partial_group = Geometry.find_edge_group "middle_edge"
      resampled_partial |> Option.get in
  if Edge_group.cardinality resampled_partial_group <> 2
     || Edge_group.length resampled_partial_group <> 6 then
    fail "resample partial edge-interval propagation";
  let line_point_id = Attribute.create_owned ~name:"line_point_id"
      ~owner:Attribute.Point (Attribute.Int [|10; 11; 12; 13|]) |> get_ok
  and line_corner_id = Attribute.create_owned ~name:"line_corner_id"
      ~owner:Attribute.Vertex (Attribute.Int [|0; 1; 2; 3; 4; 5|]) |> get_ok
  and line_face_id = Attribute.create_owned ~name:"line_face_id"
      ~owner:Attribute.Primitive (Attribute.Int [|20; 21|]) |> get_ok
  and line_detail_id = Attribute.create_owned ~name:"line_detail_id"
      ~owner:Attribute.Detail (Attribute.Int [|30|]) |> get_ok
  and line_points = Group.init ~owner:Group.Point ~name:"line_points" 4
      (fun point -> point land 1 = 0)
  and line_corners = Group.init ~owner:Group.Vertex ~name:"line_corners" 6
      (fun vertex -> vertex = 0)
  and line_faces = Group.init ~owner:Group.Primitive ~name:"line_faces" 2
      (fun primitive -> primitive = 1) in
  let line_source = Geometry.create ~positions
      ~topology:(Geometry.topology triangle_geometry)
      ~attributes:[line_point_id; line_corner_id; line_face_id; line_detail_id]
      ~groups:[line_points; line_corners; line_faces] () |> get_ok
      |> Ops.group_edges ~name:"all_source_edges" |> get_ok in
  let line_index = Topology_index.create (Geometry.topology line_source) in
  let diagonal = Topology_index.find_edge line_index ~a:0 ~b:2 |> Option.get
  and top = Topology_index.find_edge line_index ~a:2 ~b:3 |> Option.get in
  let selected_lines = Edge_group.init ~topology:(Geometry.topology line_source)
      ~index:line_index ~name:"selected_lines"
      (fun edge -> edge = diagonal || edge = top) in
  let line_source = Geometry.with_edge_group selected_lines line_source |> get_ok in
  let converted domains = Parallel.run ~domains (fun () ->
    Ops.convert_line ~grain:1 ~length_attribute:"length" line_source |> get_ok) in
  let converted_one = converted 1 and converted_many = converted 4 in
  let converted_topology = Topology.Private.view (Geometry.topology converted_one)
  and converted_many_topology = Topology.Private.view
      (Geometry.topology converted_many) in
  let line_lengths = Geometry.find_attribute ~owner:Attribute.Primitive "length"
      converted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"length"
           ~owner:Attribute.Primitive Attribute.float) |> Option.get in
  if converted_topology.vertex_points <> [|0;1; 0;2; 0;3; 1;2; 2;3|]
      || converted_topology.vertex_points <> converted_many_topology.vertex_points
      || Geometry.primitive_count converted_one <> 5
      || not (near_array [|1.; sqrt 2.; 1.; 1.; 1.|] line_lengths)
      || Geometry.positions converted_one != Geometry.positions line_source then
    fail "Convert Line ordering/cardinality/length/domain behavior";
  if Geometry.find_attribute ~owner:Attribute.Point "line_point_id" converted_one
       = None
      || Geometry.find_attribute ~owner:Attribute.Detail "line_detail_id"
           converted_one = None
      || Geometry.find_attribute ~owner:Attribute.Vertex "line_corner_id"
           converted_one <> None
      || Geometry.find_attribute ~owner:Attribute.Primitive "line_face_id"
           converted_one <> None
      || Geometry.find_group ~owner:Group.Point "line_points" converted_one = None
      || Geometry.find_group ~owner:Group.Vertex "line_corners" converted_one
           <> None
      || Geometry.find_group ~owner:Group.Primitive "line_faces" converted_one
           <> None then
    fail "Convert Line payload ownership policy";
  let selected_output = Geometry.find_edge_group "selected_lines" converted_one
      |> Option.get in
  if Edge_group.length selected_output <> 5
      || Edge_group.cardinality selected_output <> 2
      || not (Edge_group.mem 1 selected_output)
      || not (Edge_group.mem 4 selected_output) then
    fail "Convert Line native edge provenance";
  let selected_compact = Ops.convert_line ~grain:1 ~edges:selected_lines
      ~remove_unused_points:true ~length_attribute:"edge_length" line_source
      |> get_ok in
  let selected_topology = Topology.Private.view
      (Geometry.topology selected_compact) in
  let selected_ids = Geometry.find_attribute ~owner:Attribute.Point
      "line_point_id" selected_compact |> Option.get
      |> Attribute.get (Attribute.key ~name:"line_point_id"
           ~owner:Attribute.Point Attribute.int) |> Option.get in
  if Geometry.point_count selected_compact <> 3
      || Geometry.primitive_count selected_compact <> 2
      || selected_topology.vertex_points <> [|0;1; 1;2|]
      || selected_ids <> [|10;12;13|] then
    fail "Convert Line edge restriction/stable compaction";
  let connected_selected domains = Parallel.run ~domains (fun () ->
    Ops.convert_line ~grain:1 ~edges:selected_lines ~connect_path:true
      ~maximum_distance:0. ~remove_unused_points:true
      ~length_attribute:"path_length" line_source |> get_ok) in
  let connected_one = connected_selected 1
  and connected_many = connected_selected 4 in
  let connected_topology = Topology.Private.view
      (Geometry.topology connected_one)
  and connected_many_topology = Topology.Private.view
      (Geometry.topology connected_many) in
  let path_lengths = Geometry.find_attribute ~owner:Attribute.Primitive
      "path_length" connected_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"path_length"
           ~owner:Attribute.Primitive Attribute.float) |> Option.get in
  if connected_topology.vertex_points <> connected_many_topology.vertex_points
      || connected_topology.primitive_offsets
           <> connected_many_topology.primitive_offsets
      || not (Bytes.equal connected_topology.primitive_kinds
           connected_many_topology.primitive_kinds)
      || Geometry.point_count connected_one <> 3
      || Geometry.primitive_count connected_one <> 1
      || connected_topology.vertex_points <> [|0;1;2|]
      || not (near_array [|1. +. sqrt 2.|] path_lengths)
      || Geometry.find_attribute ~owner:Attribute.Point "line_point_id"
           connected_one = None
      || Geometry.find_attribute ~owner:Attribute.Detail "line_detail_id"
           connected_one = None
      || Geometry.find_attribute ~owner:Attribute.Vertex "line_corner_id"
           connected_one <> None
      || Geometry.find_attribute ~owner:Attribute.Primitive "line_face_id"
           connected_one <> None
      || Geometry.find_group ~owner:Group.Point "line_points" connected_one = None
      || Geometry.find_group ~owner:Group.Vertex "line_corners" connected_one
           <> None
      || Geometry.find_group ~owner:Group.Primitive "line_faces" connected_one
           <> None then
    fail "Convert Line connected-path topology/length/payload/domain behavior";
  let connected_edges = Geometry.find_edge_group "selected_lines" connected_one
      |> Option.get in
  if Edge_group.length connected_edges <> 2
      || Edge_group.cardinality connected_edges <> 2 then
    fail "Convert Line connected-path native edge provenance";
  let loop = Ops.circle ~segments:8 ~radius:1. () |> get_ok in
  let open_loop = Ops.convert_line ~connect_path:true ~maximum_distance:0. loop
      |> get_ok
  and closed_loop = Ops.convert_line ~connect_path:true ~maximum_distance:0.
      ~make_isolated_loops_closed:true loop |> get_ok in
  if Geometry.primitive_count open_loop <> 1
      || Geometry.vertex_count open_loop <> 9
      || Topology.primitive_kind (Geometry.topology open_loop) 0
           <> Topology.Open_polyline
      || Geometry.primitive_count closed_loop <> 1
      || Geometry.vertex_count closed_loop <> 8
      || Topology.primitive_kind (Geometry.topology closed_loop) 0
           <> Topology.Polygon then
    fail "Convert Line isolated-loop path mode";
  let empty_lines = Edge_group.init ~topology:(Geometry.topology line_source)
      ~index:line_index ~name:"empty_lines" (fun _ -> false) in
  let empty_output = Ops.convert_line ~edges:empty_lines ~connect_path:true
      line_source |> get_ok
  and empty_compact = Ops.convert_line ~edges:empty_lines ~connect_path:true
      ~remove_unused_points:true line_source |> get_ok in
  if Geometry.point_count empty_output <> 4
      || Geometry.primitive_count empty_output <> 0
      || Geometry.point_count empty_compact <> 0
      || Geometry.primitive_count empty_compact <> 0 then
    fail "Convert Line empty path selection/compaction";
  (match Ops.convert_line ~edges:middle_group line_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line accepted an edge group from another topology");
  let overflowing_line = Ops.polyline
      [|(-.max_float,0.,0.); (max_float,0.,0.)|] |> get_ok in
  (match Ops.convert_line ~length_attribute:"length" overflowing_line with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line published a non-finite length attribute");
  (match Ops.convert_line ~connect_path:true ~maximum_distance:Float.nan
      line_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line path mode accepted a non-finite distance");
  (match Ops.convert_line ~connect_path:true ~maximum_distance:(-1.) line_source
      with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line path mode accepted a negative distance");
  (match Ops.convert_line ~connect_path:true ~length_attribute:" " line_source
      with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line path mode accepted an empty length name");
  let overflowing_path = Ops.polyline
      [|(0.,0.,0.); (max_float,0.,0.); (0.,1.,0.)|] |> get_ok in
  (match Ops.convert_line ~connect_path:true ~maximum_distance:0.
      ~length_attribute:"length" overflowing_path with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Convert Line published a non-finite accumulated path length");
  let cancelled_convert_path = Cancel.create () in
  Cancel.cancel cancelled_convert_path;
  (match Ops.convert_line ~cancel:cancelled_convert_path ~connect_path:true
      line_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled Convert Line path mode published geometry");
  let carve_source = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (3.,0.,0.);
      (6.,0.,0.)|] |> get_ok in
  let carve_weight = Attribute.create_owned ~name:"curve_weight"
      ~owner:Attribute.Point (Attribute.Float [|0.; 10.; 30.; 60.|]) |> get_ok
  and carve_vertex_id = Attribute.create_owned ~name:"corner_id"
      ~owner:Attribute.Vertex (Attribute.Int [|0; 1; 2; 3|]) |> get_ok in
  let carve_source = carve_source |> Geometry.with_attribute carve_weight |> get_ok
      |> Geometry.with_attribute carve_vertex_id |> get_ok in
  let carve_index = Topology_index.create (Geometry.topology carve_source) in
  let selected_middle_edge = Topology_index.find_edge carve_index ~a:1 ~b:2
      |> Option.get in
  let carve_edges = Edge_group.init ~topology:(Geometry.topology carve_source)
      ~index:carve_index ~name:"middle" (fun edge -> edge = selected_middle_edge) in
  let carve_source = Geometry.with_edge_group carve_edges carve_source |> get_ok in
  let carved domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~first:0.2 ~last:0.6 carve_source |> get_ok) in
  let carved_one = carved 1 and carved_many = carved 4 in
  let carved_positions = Packed.Float3.Private.view (Geometry.positions carved_one)
  and carved_many_positions = Packed.Float3.Private.view
      (Geometry.positions carved_many) in
  let carved_weights = Geometry.find_attribute ~owner:Attribute.Point
      "curve_weight" carved_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"curve_weight"
           ~owner:Attribute.Point Attribute.float) |> Option.get
  and carved_corner_ids = Geometry.find_attribute ~owner:Attribute.Vertex
      "corner_id" carved_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner_id"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get in
  if not (near_array [|1.2; 3.; 3.6|] carved_positions.x)
      || carved_positions.x <> carved_many_positions.x
      || carved_positions.y <> carved_many_positions.y
      || carved_positions.z <> carved_many_positions.z
      || not (near_array [|12.; 30.; 36.|] carved_weights)
      || carved_corner_ids <> [|1; 2; 2|]
      || Topology.primitive_kind (Geometry.topology carved_one) 0
         <> Topology.Open_polyline then
    fail (Printf.sprintf
      "Curve Carve relative-arc interpolation/domain determinism: x=%s weight=%s ids=%s"
      (String.concat "," (Array.to_list (Array.map string_of_float carved_positions.x)))
      (String.concat "," (Array.to_list (Array.map string_of_float carved_weights)))
      (String.concat "," (Array.to_list (Array.map string_of_int carved_corner_ids))));
  let carved_edge_group = Geometry.find_edge_group "middle" carved_one
      |> Option.get in
  if Edge_group.length carved_edge_group <> 2
      || Edge_group.cardinality carved_edge_group <> 1 then
    fail "Curve Carve native edge-interval propagation";
  let parameter_carved = Ops.carve_curves ~relative_arc_length:false
      ~first:0.25 ~last:0.75 carve_source |> get_ok in
  let parameter_positions = Packed.Float3.Private.view
      (Geometry.positions parameter_carved) in
  if not (near_array [|0.75; 1.; 3.; 3.75|] parameter_positions.x) then
    fail "Curve Carve uniform-edge parameterization";
  let breakpoint_carved domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~relative_arc_length:false ~first:0.2 ~last:0.8
      ~only_at_breakpoints:true carve_source |> get_ok) in
  let breakpoint_one = breakpoint_carved 1
  and breakpoint_many = breakpoint_carved 4 in
  let breakpoint_positions = Packed.Float3.Private.view
      (Geometry.positions breakpoint_one) in
  let breakpoint_weights = Geometry.find_attribute ~owner:Attribute.Point
      "curve_weight" breakpoint_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"curve_weight"
           ~owner:Attribute.Point Attribute.float) |> Option.get
  and breakpoint_corners = Geometry.find_attribute ~owner:Attribute.Vertex
      "corner_id" breakpoint_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner_id"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get in
  if Geometry.point_count breakpoint_one <> 2
      || Geometry.vertex_count breakpoint_one <> 2
      || not (near_array [|1.;3.|] breakpoint_positions.x)
      || breakpoint_weights <> [|10.;30.|]
      || breakpoint_corners <> [|1;2|]
      || not (equal_positions breakpoint_one breakpoint_many)
      || (Topology.Private.view (Geometry.topology breakpoint_one)).vertex_points
           <> (Topology.Private.view
                 (Geometry.topology breakpoint_many)).vertex_points
      || Edge_group.cardinality (Geometry.find_edge_group "middle" breakpoint_one
           |> Option.get) <> 1 then
    fail "Curve Carve vertex-breakpoint inside/payload/edge/domain behavior";
  let breakpoint_segments domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~relative_arc_length:false ~first:0. ~last:1.
      ~only_at_breakpoints:true ~cut_at_all_internal_breakpoints:true
      carve_source |> get_ok) in
  let segments_one = breakpoint_segments 1
  and segments_many = breakpoint_segments 4 in
  let segment_topology = Topology.Private.view (Geometry.topology segments_one)
  and segment_positions = Packed.Float3.Private.view
      (Geometry.positions segments_one) in
  if Geometry.primitive_count segments_one <> 3
      || Geometry.vertex_count segments_one <> 6
      || segment_topology.primitive_offsets <> [|0;2;4;6|]
      || not (near_array [|0.;1.; 1.;3.; 3.;6.|] segment_positions.x)
      || not (equal_positions segments_one segments_many)
      || Edge_group.cardinality (Geometry.find_edge_group "middle" segments_one
           |> Option.get) <> 1 then
    fail "Curve Carve cut-at-all polygon breakpoints/domain behavior";
  let breakpoint_extract = Ops.carve_curves ~relative_arc_length:false
      ~first:0.1 ~last:1. ~only_at_breakpoints:true ~extract_points:true
      ~divisions:99 carve_source |> get_ok
  and all_breakpoint_extract = Ops.carve_curves ~relative_arc_length:false
      ~first:0.1 ~last:1. ~only_at_breakpoints:true
      ~cut_at_all_internal_breakpoints:true ~extract_points:true ~divisions:99
      carve_source |> get_ok in
  let breakpoint_extract_positions = Packed.Float3.Private.view
      (Geometry.positions breakpoint_extract)
  and all_breakpoint_extract_positions = Packed.Float3.Private.view
      (Geometry.positions all_breakpoint_extract) in
  if Geometry.primitive_count breakpoint_extract <> 0
      || not (near_array [|1.;6.|] breakpoint_extract_positions.x)
      || not (near_array [|1.;3.;6.|] all_breakpoint_extract_positions.x) then
    fail "Curve Carve breakpoint extraction outer/all behavior";
  let breakpoint_outside = Ops.carve_curves ~relative_arc_length:false
      ~first:0.2 ~last:0.8 ~only_at_breakpoints:true
      ~keep:Ops.Keep_outside carve_source |> get_ok in
  let breakpoint_outside_positions = Packed.Float3.Private.view
      (Geometry.positions breakpoint_outside) in
  if Geometry.primitive_count breakpoint_outside <> 2
      || not (near_array [|0.;1.; 3.;6.|] breakpoint_outside_positions.x)
      || Edge_group.cardinality (Geometry.find_edge_group "middle"
           breakpoint_outside |> Option.get) <> 0 then
    fail "Curve Carve breakpoint outside pieces";
  let empty_breakpoint_inside = Ops.carve_curves ~relative_arc_length:false
      ~first:0.34 ~last:0.6 ~only_at_breakpoints:true carve_source |> get_ok
  and empty_breakpoint_outside = Ops.carve_curves ~relative_arc_length:false
      ~first:0.34 ~last:0.6 ~only_at_breakpoints:true
      ~keep:Ops.Keep_outside carve_source |> get_ok in
  if Geometry.point_count empty_breakpoint_inside <> 0
      || Geometry.primitive_count empty_breakpoint_inside <> 0
      || not (equal_positions empty_breakpoint_outside carve_source)
      || (Topology.Private.view (Geometry.topology empty_breakpoint_outside)).vertex_points
           <> (Topology.Private.view (Geometry.topology carve_source)).vertex_points then
    fail "Curve Carve empty breakpoint interval behavior";
  let arc_breakpoints = Ops.carve_curves ~first:0.1 ~last:0.9
      ~only_at_breakpoints:true carve_source |> get_ok in
  if not (near_array [|1.;3.|]
      (Packed.Float3.Private.view (Geometry.positions arc_breakpoints)).x) then
    fail "Curve Carve relative-arc breakpoint interval";
  let mixed_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;3.; 0.;1.;0.; 5.;6.;5.5|]
      ~y:[|0.;0.;0.;0.; 2.;2.;3.; 2.;2.;3.|] ~z:(Array.make 10 0.) in
  let mixed_topology = Topology.create_owned ~point_count:10
      ~vertex_points:[|0;1;2;3; 4;5;6; 7;8;9|]
      ~primitive_offsets:[|0;4;7;10|]
      ~primitive_kinds:[|Topology.Open_polyline; Topology.Polygon;
        Topology.Closed_polyline|] |> get_ok in
  let mixed_point_id = Attribute.create_owned ~name:"mixed_point"
      ~owner:Attribute.Point (Attribute.Int (Array.init 10 Fun.id)) |> get_ok
  and mixed_vertex_id = Attribute.create_owned ~name:"mixed_vertex"
      ~owner:Attribute.Vertex (Attribute.Int (Array.init 10 Fun.id)) |> get_ok
  and mixed_primitive_id = Attribute.create_owned ~name:"mixed_primitive"
      ~owner:Attribute.Primitive (Attribute.Int [|10;20;30|]) |> get_ok
  and mixed_first_u = Attribute.create_owned ~name:"first_u"
      ~owner:Attribute.Primitive (Attribute.Float [|0.25;Float.nan;Float.nan|])
      |> get_ok
  and mixed_second_u = Attribute.create_owned ~name:"second_u"
      ~owner:Attribute.Primitive (Attribute.Float [|0.5;Float.nan;Float.nan|])
      |> get_ok
  and mixed_even = Group.init ~owner:Group.Point ~name:"mixed_even" 10
      (fun point -> point land 1 = 0)
  and carve_first = Group.init ~owner:Group.Primitive ~name:"carve_first" 3
      (fun primitive -> primitive = 0) in
  let mixed = Geometry.create ~positions:mixed_positions ~topology:mixed_topology
      ~attributes:[mixed_point_id; mixed_vertex_id; mixed_primitive_id;
        mixed_first_u; mixed_second_u]
      ~groups:[mixed_even; carve_first] () |> get_ok
      |> Ops.group_edges ~name:"mixed_edges" |> get_ok in
  let mixed_carved domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~primitives:carve_first
      ~relative_arc_length:false ~first:0.25 ~last:0.75 mixed |> get_ok) in
  let mixed_one = mixed_carved 1 and mixed_many = mixed_carved 4 in
  let mixed_view = Topology.Private.view (Geometry.topology mixed_one)
  and mixed_many_view = Topology.Private.view (Geometry.topology mixed_many)
  and mixed_result_positions = Packed.Float3.Private.view
      (Geometry.positions mixed_one) in
  let mixed_result_points = Geometry.find_attribute ~owner:Attribute.Point
      "mixed_point" mixed_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_point"
           ~owner:Attribute.Point Attribute.int) |> Option.get
  and mixed_result_vertices = Geometry.find_attribute ~owner:Attribute.Vertex
      "mixed_vertex" mixed_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_vertex"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and mixed_result_primitives = Geometry.find_attribute
      ~owner:Attribute.Primitive "mixed_primitive" mixed_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_primitive"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if Geometry.point_count mixed_one <> 14
      || Geometry.vertex_count mixed_one <> 10
      || mixed_view.vertex_points <> [|10;11;12;13; 4;5;6; 7;8;9|]
      || mixed_view.vertex_points <> mixed_many_view.vertex_points
      || not (near_array [|0.75;1.;2.;2.25|]
           (Array.sub mixed_result_positions.x 10 4))
      || Array.sub mixed_result_points 0 10 <> Array.init 10 Fun.id
      || Array.sub mixed_result_points 10 4 <> [|1;1;2;2|]
      || mixed_result_vertices <> [|1;1;2;2; 4;5;6; 7;8;9|]
      || mixed_result_primitives <> [|10;20;30|]
      || Topology.primitive_kind (Geometry.topology mixed_one) 1
           <> Topology.Polygon
      || Topology.primitive_kind (Geometry.topology mixed_one) 2
           <> Topology.Closed_polyline then
    fail "Curve Carve mixed selection/topology/payload/domain behavior";
  let mixed_edges = Geometry.find_edge_group "mixed_edges" mixed_one
      |> Option.get
  and mixed_even_output = Geometry.find_group ~owner:Group.Point "mixed_even"
      mixed_one |> Option.get in
  if Edge_group.length mixed_edges <> 9
      || Edge_group.cardinality mixed_edges <> 9
      || Group.length mixed_even_output <> 14
      || Group.cardinality mixed_even_output <> 7 then
    fail "Curve Carve mixed selection group/native-edge ancestry";
  let attributed_carve domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~primitives:carve_first
      ~relative_arc_length:false ~first:0. ~last:1.
      ~first_attribute:"first_u" ~last_attribute:"second_u" mixed |> get_ok) in
  let attributed_one = attributed_carve 1
  and attributed_many = attributed_carve 4 in
  let attributed_topology = Topology.Private.view
      (Geometry.topology attributed_one)
  and attributed_many_topology = Topology.Private.view
      (Geometry.topology attributed_many)
  and attributed_positions = Packed.Float3.Private.view
      (Geometry.positions attributed_one) in
  if Geometry.point_count attributed_one <> 13
      || Geometry.vertex_count attributed_one <> 9
      || attributed_topology.primitive_offsets <> [|0;3;6;9|]
      || attributed_topology.vertex_points <> [|10;11;12; 4;5;6; 7;8;9|]
      || attributed_topology.vertex_points
           <> attributed_many_topology.vertex_points
      || not (equal_positions attributed_one attributed_many)
      || not (near_array [|0.75;1.;1.5|]
           (Array.sub attributed_positions.x 10 3)) then
    fail "Curve Carve primitive parameter replace/domain behavior";
  let scaled_carve = Ops.carve_curves ~primitives:carve_first
      ~relative_arc_length:false ~first:0.5 ~last:1.
      ~first_attribute:"first_u" ~last_attribute:"second_u"
      ~attribute_mode:Ops.Attribute_scale mixed |> get_ok in
  let scaled_positions = Packed.Float3.Private.view
      (Geometry.positions scaled_carve) in
  if Geometry.point_count scaled_carve <> 13
      || not (near_array [|0.375;1.;1.5|]
           (Array.sub scaled_positions.x 10 3))
      || (Topology.Private.view (Geometry.topology scaled_carve)).vertex_points
           <> [|10;11;12; 4;5;6; 7;8;9|] then
    fail "Curve Carve primitive parameter scale behavior";
  let attributed_extract domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~primitives:carve_first
      ~relative_arc_length:false ~first_attribute:"first_u"
      ~last_attribute:"second_u" ~extract_points:true ~divisions:2 mixed
      |> get_ok) in
  let attributed_extract_one = attributed_extract 1
  and attributed_extract_many = attributed_extract 4 in
  let attributed_extract_positions = Packed.Float3.Private.view
      (Geometry.positions attributed_extract_one) in
  if Geometry.point_count attributed_extract_one <> 12
      || Geometry.vertex_count attributed_extract_one <> 6
      || Geometry.primitive_count attributed_extract_one <> 2
      || not (near_array [|0.75;1.5|]
           (Array.sub attributed_extract_positions.x 10 2))
      || not (equal_positions attributed_extract_one attributed_extract_many)
      || (Topology.Private.view (Geometry.topology attributed_extract_one)).vertex_points
           <> (Topology.Private.view
                 (Geometry.topology attributed_extract_many)).vertex_points then
    fail "Curve Carve primitive parameter extraction/domain behavior";
  let attributed_pieces = Ops.carve_curves ~primitives:carve_first
      ~relative_arc_length:false ~first_attribute:"first_u"
      ~last_attribute:"second_u" ~keep:Ops.Keep_inside_and_outside mixed
      |> get_ok in
  let attributed_piece_topology = Topology.Private.view
      (Geometry.topology attributed_pieces) in
  if Geometry.primitive_count attributed_pieces <> 5
      || Geometry.vertex_count attributed_pieces <> 14
      || attributed_piece_topology.primitive_offsets <> [|0;2;5;8;11;14|]
  then fail "Curve Carve primitive parameters on all cut pieces";
  (match Ops.carve_curves ~primitives:carve_first
      ~first_attribute:"missing" mixed with
   | Error error when Error.code error = "invalid_geometry"
       && String.length (Error.message error) > 0 -> ()
   | _ -> fail "Curve Carve accepted a missing primitive parameter attribute");
  (match Ops.carve_curves ~primitives:carve_first
      ~first_attribute:"mixed_primitive" mixed with
   | Error error when Error.code error = "invalid_geometry"
       && String.length (Error.message error) > 0 -> ()
   | _ -> fail "Curve Carve accepted a non-float primitive parameter attribute");
  (match Ops.carve_curves ~primitives:carve_first
      ~first_attribute:"mixed_point" mixed with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted a point parameter attribute");
  let carve_closed = Group.init ~owner:Group.Primitive ~name:"carve_closed" 3
      (fun primitive -> primitive = 2) in
  (match Ops.carve_curves ~primitives:carve_closed
      ~first_attribute:"first_u" ~last_attribute:"second_u" mixed with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted a selected non-finite parameter");
  let attributed_breakpoint = Ops.carve_curves ~primitives:carve_first
      ~relative_arc_length:false ~first_attribute:"first_u"
      ~last_attribute:"second_u" ~only_at_breakpoints:true
      ~extract_points:true mixed |> get_ok in
  if not (near_array [|1.|]
      (Array.sub (Packed.Float3.Private.view
        (Geometry.positions attributed_breakpoint)).x 10 1)) then
    fail "Curve Carve primitive attributes with breakpoint extraction";
  let mixed_breakpoint_segments = Ops.carve_curves ~grain:1
      ~primitives:carve_first ~relative_arc_length:false ~first:0. ~last:1.
      ~only_at_breakpoints:true ~cut_at_all_internal_breakpoints:true mixed
      |> get_ok in
  let mixed_breakpoint_ids = Geometry.find_attribute
      ~owner:Attribute.Primitive "mixed_primitive" mixed_breakpoint_segments
      |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_primitive"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get
  and mixed_breakpoint_group = Geometry.find_group ~owner:Group.Primitive
      "carve_first" mixed_breakpoint_segments |> Option.get in
  if Geometry.primitive_count mixed_breakpoint_segments <> 5
      || Geometry.vertex_count mixed_breakpoint_segments <> 12
      || mixed_breakpoint_ids <> [|10;10;10;20;30|]
      || Group.cardinality mixed_breakpoint_group <> 3
      || Topology.primitive_kind (Geometry.topology mixed_breakpoint_segments) 3
           <> Topology.Polygon
      || Edge_group.cardinality (Geometry.find_edge_group "mixed_edges"
           mixed_breakpoint_segments |> Option.get) <> 9 then
    fail "Curve Carve mixed cut-at-all breakpoint payload/group/edge behavior";
  let carve_none = Group.init ~owner:Group.Primitive ~name:"carve_none" 3
      (fun _ -> false) in
  if (Ops.carve_curves ~primitives:carve_none ~first:0.2 ~last:0.8 mixed
      |> get_ok) != mixed then
    fail "Curve Carve empty selection did not preserve identity";
  let carve_polygon = Group.init ~owner:Group.Primitive ~name:"carve_polygon" 3
      (fun primitive -> primitive = 1) in
  (match Ops.carve_curves ~primitives:carve_polygon ~first:0.2 ~last:0.8 mixed with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted a selected polygon");
  (match Ops.carve_curves ~primitives:mixed_even ~first:0.2 ~last:0.8 mixed with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted a point selection");
  let short_primitive_group = Group.init ~owner:Group.Primitive ~name:"short" 2
      (fun _ -> true) in
  (match Ops.carve_curves ~primitives:short_primitive_group ~first:0.2 ~last:0.8
      mixed with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted a mismatched primitive selection");
  (match Ops.carve_curves ~grain:0 ~first:0.2 ~last:0.8 carve_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted zero grain");
  let extreme_carve = Ops.polyline
      [|(-5e307,0.,0.); (5e307,0.,0.)|] |> get_ok
      |> Ops.carve_curves ~first:0.25 ~last:0.75 |> get_ok in
  let extreme_positions = Packed.Float3.Private.view
      (Geometry.positions extreme_carve) in
  if not (near_array [|(-2.5e307);2.5e307|] extreme_positions.x) then
    fail "Curve Carve did not preserve a representable extreme interpolation";
  let overflowing_carve = Ops.polyline
      [|(-.max_float,0.,0.); (max_float,0.,0.)|] |> get_ok in
  (match Ops.carve_curves ~first:0.25 ~last:0.75 overflowing_carve with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted an unrepresentable segment length");
  let extracted domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~primitives:carve_first
      ~relative_arc_length:false ~first:0.25 ~last:0.75
      ~extract_points:true ~divisions:3 mixed |> get_ok) in
  let extracted_one = extracted 1 and extracted_many = extracted 4 in
  let extracted_topology = Topology.Private.view
      (Geometry.topology extracted_one)
  and extracted_many_topology = Topology.Private.view
      (Geometry.topology extracted_many)
  and extracted_positions = Packed.Float3.Private.view
      (Geometry.positions extracted_one) in
  let extracted_point_ids = Geometry.find_attribute ~owner:Attribute.Point
      "mixed_point" extracted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_point"
           ~owner:Attribute.Point Attribute.int) |> Option.get
  and extracted_vertex_ids = Geometry.find_attribute ~owner:Attribute.Vertex
      "mixed_vertex" extracted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_vertex"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and extracted_primitive_ids = Geometry.find_attribute
      ~owner:Attribute.Primitive "mixed_primitive" extracted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_primitive"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if Geometry.point_count extracted_one <> 13
      || Geometry.vertex_count extracted_one <> 6
      || Geometry.primitive_count extracted_one <> 2
      || extracted_topology.vertex_points <> [|4;5;6;7;8;9|]
      || extracted_topology.vertex_points <> extracted_many_topology.vertex_points
      || not (near_array [|0.75;1.5;2.25|]
           (Array.sub extracted_positions.x 10 3))
      || Array.sub extracted_point_ids 10 3 <> [|1;2;2|]
      || extracted_vertex_ids <> [|4;5;6;7;8;9|]
      || extracted_primitive_ids <> [|20;30|]
      || Topology.primitive_kind (Geometry.topology extracted_one) 0
           <> Topology.Polygon
      || Topology.primitive_kind (Geometry.topology extracted_one) 1
           <> Topology.Closed_polyline then
    fail "Curve Carve point extraction topology/payload/domain behavior";
  let extracted_edges = Geometry.find_edge_group "mixed_edges" extracted_one
      |> Option.get in
  if Edge_group.length extracted_edges <> 6
      || Edge_group.cardinality extracted_edges <> 6 then
    fail "Curve Carve point extraction unselected edge ancestry";
  let extracted_kept = Ops.carve_curves ~primitives:carve_first
      ~relative_arc_length:false ~first:0.25 ~last:0.75
      ~extract_points:true ~divisions:3 ~keep_original:true mixed |> get_ok in
  if Geometry.point_count extracted_kept <> 13
      || Geometry.primitive_count extracted_kept <> 3
      || Geometry.vertex_count extracted_kept <> 10
      || Edge_group.cardinality (Geometry.find_edge_group "mixed_edges"
           extracted_kept |> Option.get) <> 9 then
    fail "Curve Carve point extraction keep-original behavior";
  let extracted_only = Ops.carve_curves ~relative_arc_length:false
      ~first:0. ~last:1. ~extract_points:true ~divisions:4 carve_source
      |> get_ok in
  if Geometry.point_count extracted_only <> 4
      || Geometry.vertex_count extracted_only <> 0
      || Geometry.primitive_count extracted_only <> 0
      || Attribute.length (Geometry.find_attribute ~owner:Attribute.Vertex
           "corner_id" extracted_only |> Option.get) <> 0
      || Edge_group.length (Geometry.find_edge_group "middle" extracted_only
           |> Option.get) <> 0 then
    fail "Curve Carve extraction-only empty topology/payload";
  let repeated_extract = Ops.carve_curves ~relative_arc_length:false
      ~first:0.5 ~last:0.5
      ~extract_points:true ~divisions:2 carve_source |> get_ok in
  let repeated_positions = Packed.Float3.Private.view
      (Geometry.positions repeated_extract) in
  if not (near_array [|2.;2.|] repeated_positions.x) then
    fail "Curve Carve repeated single-parameter extraction";
  (match Ops.carve_curves ~extract_points:true ~divisions:0 carve_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve extraction accepted zero divisions");
  let outside = Ops.carve_curves ~relative_arc_length:false ~first:0.25
      ~last:0.75 ~keep:Ops.Keep_outside carve_source |> get_ok in
  let outside_topology = Topology.Private.view (Geometry.topology outside)
  and outside_positions = Packed.Float3.Private.view (Geometry.positions outside) in
  if Geometry.primitive_count outside <> 2
      || outside_topology.primitive_offsets <> [|0;2;4|]
      || not (near_array [|0.;0.75;3.75;6.|] outside_positions.x) then
    fail "Curve Carve keep-outside open pieces";
  let all_pieces domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~relative_arc_length:false ~first:0.25 ~last:0.75
      ~keep:Ops.Keep_inside_and_outside carve_source |> get_ok) in
  let pieces_one = all_pieces 1 and pieces_many = all_pieces 4 in
  let pieces_topology = Topology.Private.view (Geometry.topology pieces_one)
  and pieces_many_topology = Topology.Private.view (Geometry.topology pieces_many)
  and pieces_positions = Packed.Float3.Private.view (Geometry.positions pieces_one) in
  if Geometry.primitive_count pieces_one <> 3
      || pieces_topology.primitive_offsets <> [|0;2;6;8|]
      || pieces_topology.vertex_points <> pieces_many_topology.vertex_points
      || not (near_array [|0.;0.75; 0.75;1.;3.;3.75; 3.75;6.|]
           pieces_positions.x)
      || Edge_group.length (Geometry.find_edge_group "middle" pieces_one
           |> Option.get) <> 5
      || Edge_group.cardinality (Geometry.find_edge_group "middle" pieces_one
           |> Option.get) <> 1 then
    fail "Curve Carve keep-inside-and-outside topology/edge/domain behavior";
  let divided_inside domains = Parallel.run ~domains (fun () ->
    Ops.carve_curves ~grain:1 ~relative_arc_length:false ~first:0.25 ~last:0.75
      ~divisions:3 carve_source |> get_ok) in
  let divided_one = divided_inside 1 and divided_many = divided_inside 4 in
  let divided_topology = Topology.Private.view (Geometry.topology divided_one)
  and divided_many_topology = Topology.Private.view
      (Geometry.topology divided_many)
  and divided_positions = Packed.Float3.Private.view
      (Geometry.positions divided_one) in
  let divided_weights = Geometry.find_attribute ~owner:Attribute.Point
      "curve_weight" divided_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"curve_weight"
           ~owner:Attribute.Point Attribute.float) |> Option.get
  and divided_corners = Geometry.find_attribute ~owner:Attribute.Vertex
      "corner_id" divided_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner_id"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and divided_weights_many = Geometry.find_attribute ~owner:Attribute.Point
      "curve_weight" divided_many |> Option.get
      |> Attribute.get (Attribute.key ~name:"curve_weight"
           ~owner:Attribute.Point Attribute.float) |> Option.get
  and divided_corners_many = Geometry.find_attribute ~owner:Attribute.Vertex
      "corner_id" divided_many |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner_id"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get in
  let divided_edges = Geometry.find_edge_group "middle" divided_one
      |> Option.get
  and divided_edges_many = Geometry.find_edge_group "middle" divided_many
      |> Option.get in
  let divided_edge_members_equal = ref
      (Edge_group.length divided_edges = Edge_group.length divided_edges_many) in
  for edge = 0 to Edge_group.length divided_edges - 1 do
    if Edge_group.mem edge divided_edges <> Edge_group.mem edge divided_edges_many
    then divided_edge_members_equal := false
  done;
  if Geometry.point_count divided_one <> 8
      || Geometry.vertex_count divided_one <> 8
      || Geometry.primitive_count divided_one <> 3
      || divided_topology.primitive_offsets <> [|0;3;5;8|]
      || divided_topology.vertex_points <> Array.init 8 Fun.id
      || divided_topology.vertex_points <> divided_many_topology.vertex_points
      || divided_topology.primitive_offsets
           <> divided_many_topology.primitive_offsets
      || not (near_array [|0.75;1.;1.5; 1.5;2.5; 2.5;3.;3.75|]
           divided_positions.x)
      || not (near_array [|7.5;10.;15.; 15.;25.; 25.;30.;37.5|]
           divided_weights)
      || divided_corners <> [|1;1;1; 1;2; 2;2;2|]
      || divided_weights <> divided_weights_many
      || divided_corners <> divided_corners_many
      || not (equal_positions divided_one divided_many)
      || not !divided_edge_members_equal
      || Edge_group.cardinality divided_edges <> 3 then
    fail "Curve Carve divided cut topology/payload/edge/domain behavior";
  let divided_all = Ops.carve_curves ~relative_arc_length:false ~first:0.25
      ~last:0.75 ~divisions:3 ~keep:Ops.Keep_inside_and_outside carve_source
      |> get_ok in
  if Geometry.primitive_count divided_all <> 5
      || (Topology.Private.view (Geometry.topology divided_all)).primitive_offsets
           <> [|0;2;5;7;10;12|]
      || not (near_array
           [|0.;0.75; 0.75;1.;1.5; 1.5;2.5; 2.5;3.;3.75; 3.75;6.|]
           (Packed.Float3.Private.view (Geometry.positions divided_all)).x) then
    fail "Curve Carve divided inside-and-outside ordering";
  (match Ops.carve_curves ~divisions:0 carve_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve cut accepted zero divisions");
  let closed_cut_source = Ops.polyline ~closed:true [|(0.,0.,0.); (1.,0.,0.);
      (1.,1.,0.); (0.,1.,0.)|] |> get_ok
      |> Ops.group_edges ~name:"closed_cut_edges" |> get_ok in
  let closed_outside = Ops.carve_curves ~relative_arc_length:false ~first:0.25
      ~last:0.75 ~keep:Ops.Keep_outside closed_cut_source |> get_ok in
  let closed_outside_topology = Topology.Private.view
      (Geometry.topology closed_outside) in
  if Geometry.primitive_count closed_outside <> 1
      || closed_outside_topology.vertex_points <> [|0;1;2|]
      || Geometry.vertex_count closed_outside <> 3
      || Edge_group.cardinality (Geometry.find_edge_group "closed_cut_edges"
           closed_outside |> Option.get) <> 2 then
    fail "Curve Carve closed complement seam path";
  let closed_all = Ops.carve_curves ~relative_arc_length:false ~first:0.25
      ~last:0.75 ~keep:Ops.Keep_inside_and_outside closed_cut_source |> get_ok in
  if Geometry.primitive_count closed_all <> 2
      || Geometry.vertex_count closed_all <> 6
      || Edge_group.cardinality (Geometry.find_edge_group "closed_cut_edges"
           closed_all |> Option.get) <> 4 then
    fail "Curve Carve closed inside/complement pieces";
  let closed_breakpoint_outside = Ops.carve_curves
      ~relative_arc_length:false ~first:0.2 ~last:0.8
      ~only_at_breakpoints:true ~keep:Ops.Keep_outside closed_cut_source
      |> get_ok in
  let closed_breakpoint_topology = Topology.Private.view
      (Geometry.topology closed_breakpoint_outside) in
  if Geometry.primitive_count closed_breakpoint_outside <> 1
      || closed_breakpoint_topology.vertex_points <> [|0;1;2|]
      || Edge_group.cardinality (Geometry.find_edge_group "closed_cut_edges"
           closed_breakpoint_outside |> Option.get) <> 2 then
    fail "Curve Carve closed breakpoint seam complement";
  let closed_breakpoint_edges = Ops.carve_curves
      ~relative_arc_length:false ~first:0.2 ~last:0.8
      ~only_at_breakpoints:true ~cut_at_all_internal_breakpoints:true
      ~keep:Ops.Keep_outside closed_cut_source |> get_ok in
  if Geometry.primitive_count closed_breakpoint_edges <> 2
      || Geometry.vertex_count closed_breakpoint_edges <> 4
      || Edge_group.cardinality (Geometry.find_edge_group "closed_cut_edges"
           closed_breakpoint_edges |> Option.get) <> 2 then
    fail "Curve Carve closed cut-at-all breakpoint complement";
  let mixed_outside = Ops.carve_curves ~primitives:carve_first
      ~relative_arc_length:false ~first:0.25 ~last:0.75
      ~keep:Ops.Keep_outside mixed |> get_ok in
  let mixed_outside_ids = Geometry.find_attribute ~owner:Attribute.Primitive
      "mixed_primitive" mixed_outside |> Option.get
      |> Attribute.get (Attribute.key ~name:"mixed_primitive"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  let mixed_outside_group = Geometry.find_group ~owner:Group.Primitive
      "carve_first" mixed_outside |> Option.get
  and mixed_outside_edges = Geometry.find_edge_group "mixed_edges" mixed_outside
      |> Option.get in
  if Geometry.point_count mixed_outside <> 14
      || Geometry.primitive_count mixed_outside <> 4
      || mixed_outside_ids <> [|10;10;20;30|]
      || Group.cardinality mixed_outside_group <> 2
      || Topology.primitive_kind (Geometry.topology mixed_outside) 2
           <> Topology.Polygon
      || Topology.primitive_kind (Geometry.topology mixed_outside) 3
           <> Topology.Closed_polyline
      || Edge_group.length mixed_outside_edges <> 8
      || Edge_group.cardinality mixed_outside_edges <> 8 then
    fail "Curve Carve mixed outside payload/group/edge ancestry";
  let closed_ends_source = Ops.polyline ~closed:true [|(0.,0.,0.); (1.,0.,0.);
      (1.,1.,0.); (0.,1.,0.)|] |> get_ok
      |> Ops.group_edges ~name:"closed_edges" |> get_ok in
  let opened domains = Parallel.run ~domains (fun () ->
    Ops.curve_ends ~grain:1 Ops.Open_curve closed_ends_source |> get_ok) in
  let opened_one = opened 1 and opened_many = opened 4 in
  let opened_group geometry = Geometry.find_edge_group "closed_edges" geometry
      |> Option.get in
  if Topology.primitive_kind (Geometry.topology opened_one) 0
      <> Topology.Open_polyline
      || Geometry.vertex_count opened_one <> 4
      || Edge_group.cardinality (opened_group opened_one) <> 3
      || Edge_group.cardinality (opened_group opened_many) <> 3 then
    fail "Curve Ends open/native-edge/domain behavior";
  let unrolled = Ops.curve_ends Ops.Unroll_curve closed_ends_source |> get_ok in
  let unrolled_topology = Topology.Private.view (Geometry.topology unrolled) in
  if Topology.primitive_kind (Geometry.topology unrolled) 0
      <> Topology.Open_polyline
      || unrolled_topology.vertex_points <> [|0; 1; 2; 3; 0|]
      || Edge_group.cardinality (opened_group unrolled) <> 4 then
    fail "Curve Ends unroll/remap";
  let open_ends_source = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.)|]
      |> get_ok |> Ops.group_edges ~name:"open_edges" |> get_ok in
  let closed_ends = Ops.curve_ends Ops.Close_curve open_ends_source |> get_ok in
  let closed_group = Geometry.find_edge_group "open_edges" closed_ends
      |> Option.get in
  if Topology.primitive_kind (Geometry.topology closed_ends) 0
      <> Topology.Closed_polyline || Edge_group.length closed_group <> 3
      || Edge_group.cardinality closed_group <> 2 then
    fail "Curve Ends close selected a generated closing edge";
  let join_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.; 3.; 4.; 10.; 11.|]
      ~y:(Array.make 7 0.) ~z:(Array.make 7 0.) in
  let join_topology = Topology.Builder.create ~point_count:7 () in
  Topology.Builder.add_open_polyline join_topology [|0; 1; 2|];
  Topology.Builder.add_open_polyline join_topology [|4; 3; 2|];
  Topology.Builder.add_open_polyline join_topology [|5; 6|];
  let join_corner_id = Attribute.create_owned ~name:"join_corner"
      ~owner:Attribute.Vertex (Attribute.Int (Array.init 8 Fun.id)) |> get_ok
  and join_piece = Attribute.create_owned ~name:"join_piece"
      ~owner:Attribute.Primitive (Attribute.Int [|10; 20; 30|]) |> get_ok
  and join_tagged = Group.init ~owner:Group.Primitive ~name:"tagged" 3
      (fun primitive -> primitive = 1) in
  let join_source = Geometry.create ~positions:join_positions
      ~topology:(Topology.Builder.freeze join_topology)
      ~attributes:[join_corner_id; join_piece] ~groups:[join_tagged] () |> get_ok
      |> Ops.group_edges ~name:"join_edges" |> get_ok in
  let joined domains = Parallel.run ~domains (fun () ->
    Ops.join_curves ~grain:1 join_source |> get_ok) in
  let joined_one = joined 1 and joined_many = joined 4 in
  let joined_topology = Topology.Private.view (Geometry.topology joined_one)
  and joined_many_topology = Topology.Private.view (Geometry.topology joined_many) in
  let joined_corner_ids = Geometry.find_attribute ~owner:Attribute.Vertex
      "join_corner" joined_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"join_corner"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and joined_pieces = Geometry.find_attribute ~owner:Attribute.Primitive
      "join_piece" joined_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"join_piece"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if Geometry.primitive_count joined_one <> 1
      || joined_topology.vertex_points <> [|0; 1; 2; 3; 4; 5; 6|]
      || joined_topology.vertex_points <> joined_many_topology.vertex_points
      || joined_corner_ids <> [|0; 1; 2; 4; 3; 6; 7|]
      || joined_pieces <> [|10|] then
    fail "Curve Join order/orientation/weld/payload/domain behavior";
  (match Geometry.find_group ~owner:Group.Primitive "tagged" joined_one with
   | Some group when Group.cardinality group = 1 -> ()
   | _ -> fail "Curve Join primitive-group union policy");
  let joined_edges = Geometry.find_edge_group "join_edges" joined_one
      |> Option.get in
  if Edge_group.length joined_edges <> 6
      || Edge_group.cardinality joined_edges <> 5 then
    fail "Curve Join original/generated native edge policy";
  let connected_only = Ops.join_curves ~only_connected:true join_source |> get_ok in
  if Geometry.primitive_count connected_only <> 2
      || Geometry.vertex_count connected_only <> 7 then
    fail "Curve Join only-connected chain partition";
  let closest_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.; 10.;11.; 3.;2.; 12.;11.|]
      ~y:(Array.make 8 0.) ~z:(Array.make 8 0.) in
  let closest_topology = Topology.Builder.create ~point_count:8 () in
  Topology.Builder.add_open_polyline closest_topology [|0;1|];
  Topology.Builder.add_open_polyline closest_topology [|2;3|];
  Topology.Builder.add_open_polyline closest_topology [|4;5|];
  Topology.Builder.add_open_polyline closest_topology [|6;7|];
  let closest_corner = Attribute.create_owned ~name:"closest_corner"
      ~owner:Attribute.Vertex (Attribute.Int (Array.init 8 Fun.id)) |> get_ok
  and closest_piece = Attribute.create_owned ~name:"closest_piece"
      ~owner:Attribute.Primitive (Attribute.Int [|10;20;30;40|]) |> get_ok in
  let closest_source = Geometry.create ~positions:closest_positions
      ~topology:(Topology.Builder.freeze closest_topology)
      ~attributes:[closest_corner; closest_piece] () |> get_ok
      |> Ops.group_edges ~name:"closest_edges" |> get_ok in
  let globally_joined domains = Parallel.run ~domains (fun () ->
      Ops.join_curves ~grain:1 ~connect_closest_ends:true closest_source
      |> get_ok) in
  let globally_joined_one = globally_joined 1
  and globally_joined_many = globally_joined 4 in
  let globally_joined_topology = Topology.Private.view
      (Geometry.topology globally_joined_one)
  and globally_joined_many_topology = Topology.Private.view
      (Geometry.topology globally_joined_many) in
  let globally_joined_corners = Geometry.find_attribute
      ~owner:Attribute.Vertex "closest_corner" globally_joined_one
      |> Option.get |> Attribute.get (Attribute.key ~name:"closest_corner"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and globally_joined_pieces = Geometry.find_attribute
      ~owner:Attribute.Primitive "closest_piece" globally_joined_one
      |> Option.get |> Attribute.get (Attribute.key ~name:"closest_piece"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if globally_joined_topology.vertex_points <> [|0;1;5;4;2;3;6|]
      || globally_joined_topology.vertex_points
         <> globally_joined_many_topology.vertex_points
      || globally_joined_corners <> [|0;1;5;4;2;3;6|]
      || globally_joined_pieces <> [|10|]
      || Edge_group.cardinality (Geometry.find_edge_group "closest_edges"
           globally_joined_one |> Option.get) <> 4 then
    fail "Curve Join global closest-end ordering/payload/edge/domain behavior";
  let closest_components = Ops.join_curves ~connect_closest_ends:true
      ~only_connected:true ~tolerance:0. closest_source |> get_ok in
  if Geometry.primitive_count closest_components <> 3
      || Geometry.vertex_count closest_components <> 7 then
    fail "Curve Join global closest-end connected-component partition";
  let closest_subgroups = Ops.join_curves ~connect_closest_ends:true
      ~group_size:2 closest_source |> get_ok in
  let closest_subgroup_topology = Topology.Private.view
      (Geometry.topology closest_subgroups) in
  if Geometry.primitive_count closest_subgroups <> 2
      || closest_subgroup_topology.primitive_offsets <> [|0;4;7|]
      || closest_subgroup_topology.vertex_points <> [|0;1;5;4;2;3;6|] then
    fail "Curve Join global closest-end fixed subgroup policy";
  let authored_order = Group.ordered ~owner:Group.Primitive
      ~name:"authored_order" ~length:4 [|2;0;3|] |> get_ok in
  let authored_join = Ops.join_curves ~primitives:authored_order
      ~orient_closest:false closest_source |> get_ok in
  let authored_topology = Topology.Private.view
      (Geometry.topology authored_join) in
  if authored_topology.primitive_offsets <> [|0;2;8|]
      || authored_topology.vertex_points <> [|2;3;4;5;0;1;6;7|] then
    fail "Curve Join ignored ordered primitive-group traversal";
  let picked_ends = [|
      { Ops.primitive = 2; end_ = Ops.Join_curve_start };
      { Ops.primitive = 0; end_ = Ops.Join_curve_start };
      { Ops.primitive = 3; end_ = Ops.Join_curve_end };
    |] in
  let picked_join domains = Parallel.run ~domains (fun () ->
    Ops.join_curves ~grain:1 ~picked_ends closest_source |> get_ok) in
  let picked_one = picked_join 1 and picked_many = picked_join 4 in
  let picked_topology = Topology.Private.view (Geometry.topology picked_one)
  and picked_many_topology = Topology.Private.view
      (Geometry.topology picked_many) in
  let picked_corners = Geometry.find_attribute ~owner:Attribute.Vertex
      "closest_corner" picked_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"closest_corner"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get
  and picked_pieces = Geometry.find_attribute ~owner:Attribute.Primitive
      "closest_piece" picked_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"closest_piece"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if picked_topology.primitive_offsets <> [|0;2;8|]
      || picked_topology.vertex_points <> [|2;3;5;4;0;1;7;6|]
      || picked_topology.vertex_points <> picked_many_topology.vertex_points
      || picked_corners <> [|2;3;5;4;0;1;7;6|]
      || picked_pieces <> [|20;30|]
      || Edge_group.cardinality (Geometry.find_edge_group "closest_edges"
           picked_one |> Option.get) <> 4 then
    fail "Curve Join picked-end order/orientation/payload/edge/domain behavior";
  let picked_subgroups = Ops.join_curves ~picked_ends ~group_size:2
      closest_source |> get_ok in
  let picked_subgroup_topology = Topology.Private.view
      (Geometry.topology picked_subgroups) in
  if picked_subgroup_topology.primitive_offsets <> [|0;2;6;8|]
      || picked_subgroup_topology.vertex_points <> [|2;3;5;4;0;1;6;7|] then
    fail "Curve Join picked subgroup-root outgoing-end behavior";
  if (Ops.join_curves ~picked_ends:[||] closest_source |> get_ok) != closest_source
  then fail "Curve Join rebuilt an empty picked-end selection";
  (match Ops.join_curves ~primitives:authored_order ~picked_ends closest_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted primitive selection with picked ends");
  (match Ops.join_curves ~picked_ends ~connect_closest_ends:true closest_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted picked ends with closest-end ordering");
  (match Ops.join_curves ~picked_ends:[|
      { Ops.primitive = 1; end_ = Ops.Join_curve_start };
      { Ops.primitive = 1; end_ = Ops.Join_curve_end }|] closest_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted a duplicate picked primitive");
  (match Ops.join_curves ~picked_ends:[|
      { Ops.primitive = 4; end_ = Ops.Join_curve_start }|] closest_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted an out-of-bounds picked primitive");
  let ordered_subgroups = Ops.join_curves ~group_size:2 closest_source |> get_ok in
  let ordered_subgroup_topology = Topology.Private.view
      (Geometry.topology ordered_subgroups) in
  if ordered_subgroup_topology.primitive_offsets <> [|0;4;8|]
      || ordered_subgroup_topology.vertex_points <> [|0;1;2;3;5;4;7;6|] then
    fail "Curve Join input-order subgroup root/continuation orientation";
  let retained_join = Ops.join_curves ~keep_originals:true join_source |> get_ok in
  let retained_topology = Topology.Private.view (Geometry.topology retained_join)
  and retained_pieces = Geometry.find_attribute ~owner:Attribute.Primitive
      "join_piece" retained_join |> Option.get
      |> Attribute.get (Attribute.key ~name:"join_piece"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get
  and retained_corners = Geometry.find_attribute ~owner:Attribute.Vertex
      "join_corner" retained_join |> Option.get
      |> Attribute.get (Attribute.key ~name:"join_corner"
           ~owner:Attribute.Vertex Attribute.int) |> Option.get in
  if Geometry.point_count retained_join <> 7
      || Geometry.primitive_count retained_join <> 4
      || retained_topology.primitive_offsets <> [|0;3;6;8;15|]
      || retained_topology.vertex_points
         <> [|0;1;2; 4;3;2; 5;6; 0;1;2;3;4;5;6|]
      || retained_pieces <> [|10;20;30;10|]
      || retained_corners <> [|0;1;2;3;4;5;6;7; 0;1;2;4;3;6;7|] then
    fail "Curve Join Keep Primitives topology/payload ancestry";
  (match Geometry.find_group ~owner:Group.Primitive "tagged" retained_join with
   | Some group when Group.cardinality group = 2
       && Group.mem 1 group && Group.mem 3 group -> ()
   | _ -> fail "Curve Join Keep Primitives group union ancestry");
  let retained_edges = Geometry.find_edge_group "join_edges" retained_join
      |> Option.get in
  if Edge_group.length retained_edges <> 6
      || Edge_group.cardinality retained_edges <> 5 then
    fail "Curve Join Keep Primitives native-edge ancestry";
  (match Ops.join_curves ~group_size:0 join_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted a non-positive subgroup size");
  let random_curve_count = 257 and random_point_count = 514 in
  let random_x = Array.make random_point_count 0.
  and random_y = Array.make random_point_count 0.
  and random_z = Array.make random_point_count 0. in
  for primitive = 0 to random_curve_count - 1 do
    let base = float_of_int primitive *. 1e-4 in
    let x = float_of_int ((primitive * 97) mod 257) +. base
    and y = float_of_int ((primitive * 53) mod 251) +. (base *. 0.7)
    and z = float_of_int ((primitive * 29) mod 241) +. (base *. 0.3) in
    random_x.(primitive * 2) <- x;
    random_y.(primitive * 2) <- y;
    random_z.(primitive * 2) <- z;
    random_x.((primitive * 2) + 1) <- x +. 0.013;
    random_y.((primitive * 2) + 1) <- y -. 0.017;
    random_z.((primitive * 2) + 1) <- z +. 0.019
  done;
  let random_topology = Topology.create_owned ~point_count:random_point_count
      ~vertex_points:(Array.init random_point_count Fun.id)
      ~primitive_offsets:(Array.init (random_curve_count + 1)
        (fun primitive -> primitive * 2))
      ~primitive_kinds:(Array.make random_curve_count Topology.Open_polyline)
      |> get_ok in
  let random_source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:random_x ~y:random_y ~z:random_z)
      ~topology:random_topology () |> get_ok in
  let random_result = Ops.join_curves ~grain:7 ~connect_closest_ends:true
      random_source |> get_ok in
  let expected_points = Array.make random_point_count 0
  and used = Bytes.make random_curve_count '\000' in
  expected_points.(0) <- 0;
  expected_points.(1) <- 1;
  Bytes.set used 0 '\001';
  let current = ref 1 in
  for order = 1 to random_curve_count - 1 do
    let best = ref (-1) and best_distance = ref infinity in
    for endpoint = 0 to random_point_count - 1 do
      if Bytes.get used (endpoint lsr 1) = '\000' then begin
        let distance =
          let dx = random_x.(!current) -. random_x.(endpoint)
          and dy = random_y.(!current) -. random_y.(endpoint)
          and dz = random_z.(!current) -. random_z.(endpoint) in
          let scale = max (abs_float dx) (max (abs_float dy) (abs_float dz)) in
          if scale = 0. then 0.
          else
            let x = dx /. scale and y = dy /. scale and z = dz /. scale in
            scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
        if distance < !best_distance
            || distance = !best_distance && (!best < 0 || endpoint < !best)
        then begin best := endpoint; best_distance := distance end
      end
    done;
    let primitive = !best lsr 1 and reverse = !best land 1 = 1 in
    Bytes.set used primitive '\001';
    let output = order * 2 in
    expected_points.(output) <- (primitive * 2) + if reverse then 1 else 0;
    expected_points.(output + 1) <- (primitive * 2) + if reverse then 0 else 1;
    current := expected_points.(output + 1)
  done;
  if (Topology.Private.view (Geometry.topology random_result)).vertex_points
      <> expected_points then
    fail "Curve Join endpoint k-d tree disagrees with brute-force greedy order";
  let wrapped_join = Ops.join_curves ~wrap:true join_source |> get_ok in
  let wrapped_edges = Geometry.find_edge_group "join_edges" wrapped_join
      |> Option.get in
  if Topology.primitive_kind (Geometry.topology wrapped_join) 0
      <> Topology.Closed_polyline || Edge_group.length wrapped_edges <> 7
      || Edge_group.cardinality wrapped_edges <> 5 then
    fail "Curve Join wrap/generated edge policy";
  (match Ops.join_curves triangle_geometry with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted polygon geometry");
  (match Ops.join_curves ~tolerance:nan join_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Join accepted a non-finite tolerance");
  let extreme_join = Ops.merge [
      Ops.polyline [|(-.max_float,0.,0.); (-.max_float,1.,0.)|] |> get_ok;
      Ops.polyline [|(max_float,0.,0.); (max_float,1.,0.)|] |> get_ok;
    ] |> get_ok |> Ops.join_curves |> get_ok in
  if Geometry.vertex_count extreme_join <> 4 then
    fail "Curve Join mishandled overflowing finite endpoint distance";
  let extreme_global = Ops.merge [
      Ops.polyline [|(-.max_float,0.,0.); (-.max_float,1.,0.)|] |> get_ok;
      Ops.polyline [|(max_float,0.,0.); (max_float,1.,0.)|] |> get_ok;
    ] |> get_ok |> Ops.join_curves ~connect_closest_ends:true |> get_ok in
  if Geometry.vertex_count extreme_global <> 4 then
    fail "global closest Curve Join mishandled overflowing finite distance";
  let invalid_join_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;Float.nan;3.|] ~y:(Array.make 4 0.) ~z:(Array.make 4 0.) in
  let invalid_join_topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:(Array.make 2 Topology.Open_polyline) |> get_ok in
  let invalid_join = Geometry.create ~positions:invalid_join_positions
      ~topology:invalid_join_topology () |> get_ok in
  (match Ops.join_curves ~connect_closest_ends:true invalid_join with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "global closest Curve Join accepted a non-finite endpoint");
  (match Ops.carve_curves ~first:0.5 ~last:0.5 carve_source with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve accepted an empty interval");
  let point_only_carve = Ops.points [|(2.,3.,4.)|] in
  if (Ops.carve_curves ~first:0.2 point_only_carve |> get_ok) != point_only_carve
  then fail "Curve Carve rebuilt point-only geometry";
  (match Ops.carve_curves ~last:0.9 triangle_geometry with
   | Ok _ -> fail "Curve Carve accepted polygon geometry"
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Carve polygon diagnostic code");
  (match Ops.curve_ends Ops.Open_curve geometry with
   | Error error when Error.code error = "invalid_geometry" -> ()
   | _ -> fail "Curve Ends accepted polygon geometry");
  let cancelled_curve = Cancel.create () in
  Cancel.cancel cancelled_curve;
  (match Ops.carve_curves ~cancel:cancelled_curve ~first:0.1 carve_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Curve Carve ignored cancellation");
  (match Ops.join_curves ~cancel:cancelled_curve join_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Curve Join ignored cancellation");
  (match Ops.convert_line ~cancel:cancelled_curve line_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Convert Line ignored cancellation");
  (match Ops.uv_unitize Ops.Islands geometry with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Unitize accepted missing UVs");
  (match Ops.uv_auto_seam ~primitives:selected shared_box with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "UV Auto Seam accepted a point-owned primitive selection");
  (match Ops.uv_unitize ~seams:selected Ops.Islands strip with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Unitize accepted a point-owned seam group");
  (match Ops.uv_auto_seam ~existing_uv:"uv" wrong_uv_geometry with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "UV Auto Seam accepted non-float2 existing UVs");
  (match Ops.uv_auto_seam cylinder_curve with
   | Error error when Error.code error = "invalid_topology" -> ()
   | _ -> fail "UV Auto Seam accepted a polygon curve");
  (match Ops.uv_unitize Ops.Islands cylindrical with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Unitize accepted a polygon curve");
  let extreme_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|-.max_float; max_float; max_float; -.max_float|]
        ~y:[|0.; 0.; 1.; 1.|] |> get_ok)) |> get_ok in
  let extreme_uv_geometry = Geometry.with_attribute extreme_uv geometry |> get_ok in
  (match Ops.uv_unitize Ops.Per_face extreme_uv_geometry with
   | Error error when Error.code error = "invalid_uv" -> ()
   | _ -> fail "UV Unitize accepted an overflowing finite UV extent");
  (match Analysis.bounds box with
   | None -> fail "box bounds missing"
   | Some bounds ->
       if bounds.min.Vec3.x <> -1. || bounds.max.x <> 1.
          || bounds.size.y <> 4. || bounds.size.z <> 6.
       then fail "box bounds");
  let box_area = Analysis.surface_area box |> get_ok in
  if abs_float (box_area -. 88.) > 1e-12 then fail "box surface area";
  let polygon_geometry points =
    let count = Array.length points in
    let x = Array.make count 0. and y = Array.make count 0.
    and z = Array.make count 0. in
    Array.iteri (fun index (px, py, pz) ->
      x.(index) <- px; y.(index) <- py; z.(index) <- pz) points;
    let topology = Topology.Builder.create ~point_count:count () in
    Topology.Builder.add_polygon topology (Array.init count Fun.id);
    Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology:(Topology.Builder.freeze topology) () |> get_ok in
  let concave = polygon_geometry
      [|(0.,0.,0.); (3.,0.,0.); (3.,3.,0.); (2.,3.,0.);
        (2.,1.,0.); (1.,1.,0.); (1.,3.,0.); (0.,3.,0.)|] in
  let concave_area = Analysis.surface_area ~grain:2 concave |> get_ok
  and concave_perimeter = Analysis.perimeter ~grain:2 concave |> get_ok in
  if abs_float (concave_area -. 7.) > 1e-12
      || abs_float (concave_perimeter -. 16.) > 1e-12 then
    fail "concave polygon area/perimeter";
  let bow_tie = polygon_geometry
      [|(0.,0.,0.); (1.,1.,0.); (0.,1.,0.); (1.,0.,0.)|] in
  (match Analysis.primitive_area bow_tie with
   | Error _ -> ()
   | Ok _ -> fail "measure accepted a self-intersecting polygon");
  let open_curve = Ops.polyline
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.)|] |> get_ok
  and closed_curve = Ops.polyline ~closed:true
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.)|] |> get_ok in
  let open_length = Analysis.perimeter open_curve |> get_ok
  and closed_length = Analysis.perimeter closed_curve |> get_ok in
  if abs_float (open_length -. 2.) > 1e-12
      || abs_float (closed_length -. (2. +. sqrt 2.)) > 1e-12 then
    fail "open/closed curve length";
  (match Analysis.surface_area open_curve with
   | Error _ -> ()
   | Ok _ -> fail "area measurement accepted an open curve");
  let box_volume = Analysis.signed_volume ~grain:3 box |> get_ok in
  let reversed_box = Ops.reverse box |> get_ok in
  let reversed_volume = Analysis.signed_volume ~grain:3 reversed_box |> get_ok in
  if abs_float (abs_float box_volume -. 48.) > 1e-12
      || abs_float (box_volume +. reversed_volume) > 1e-12 then
    fail "closed box signed volume/winding";
  let first_triangle = Group.init ~owner:Group.Primitive ~name:"first_triangle"
      2 (fun primitive -> primitive = 0) in
  let old_measure = Attribute.create_owned ~name:"measured"
      ~owner:Attribute.Primitive (Attribute.Float [|99.; 88.|]) |> get_ok in
  let restricted_source = Geometry.with_attribute old_measure triangle_geometry
      |> get_ok in
  let restricted_measure = Analysis.with_measure ~grain:1
      ~primitives:first_triangle ~name:"measured" ~total_name:"measured_total"
      Analysis.Area restricted_source |> get_ok in
  let restricted_values = Geometry.find_attribute ~owner:Attribute.Primitive
      "measured" restricted_measure |> Option.get |> Attribute.get
      (Attribute.key ~name:"measured" ~owner:Attribute.Primitive Attribute.float)
      |> Option.get
  and restricted_total = Geometry.find_attribute ~owner:Attribute.Detail
      "measured_total" restricted_measure |> Option.get |> Attribute.get
      (Attribute.key ~name:"measured_total" ~owner:Attribute.Detail Attribute.float)
      |> Option.get in
  if restricted_values <> [|0.5; 88.|] || restricted_total <> [|0.5|] then
    fail "restricted measure preservation/detail total";
  let throughout = Analysis.with_measure ~grain:1
      ~accumulation:Analysis.Throughout ~name:"surface_total"
      ~total_name:"surface_total_detail" Analysis.Area triangle_geometry
      |> get_ok in
  let throughout_values = Geometry.find_attribute ~owner:Attribute.Primitive
      "surface_total" throughout |> Option.get |> Attribute.get
      (Attribute.key ~name:"surface_total" ~owner:Attribute.Primitive Attribute.float)
      |> Option.get in
  if throughout_values <> [|1.; 1.|] then
    fail "throughout area accumulation";
  (match Analysis.with_measure ~primitives:selected Analysis.Area triangle_geometry with
   | Error error when Error.code error = "invalid_measure" -> ()
   | _ -> fail "measure accepted a point-owned primitive selection");
  let cancelled_measure = Cancel.create () in
  Cancel.cancel cancelled_measure;
  (match Analysis.with_measure ~cancel:cancelled_measure Analysis.Area grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "measure ignored cancellation");
  (match Analysis.with_measure ~grain:0 Analysis.Area grid with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "measure accepted non-positive grain");
  let disconnected = Ops.merge [box; Ops.transform
      (Mat4.translation (Vec3.create 10. 0. 0.)) box] |> get_ok in
  let classes, class_count = Analysis.connectivity disconnected in
  if class_count <> 12 || Array.length classes <> 24
  then fail "primitive connectivity";
  let merged = Ops.merge [grid; grid] |> get_ok in
  if Geometry.point_count merged <> 90 || Geometry.primitive_count merged <> 128
  then fail "merge cardinality";
  let degenerate_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.|] ~y:[|0.; 0.; 0.|] ~z:[|0.; 0.; 0.|] in
  let degenerate_topology = Topology.Builder.create ~point_count:3 () in
  Topology.Builder.add_triangle degenerate_topology 0 1 2;
  let degenerate = Geometry.create ~positions:degenerate_positions
      ~topology:(Topology.Builder.freeze degenerate_topology) () |> get_ok in
  let cleaned = Ops.clean degenerate |> get_ok in
  if Geometry.primitive_count cleaned <> 0 || Geometry.point_count cleaned <> 3
  then fail "clean degenerate primitive/point identity";
  let cleaned_compact = Ops.clean ~remove_unused_points:true degenerate |> get_ok in
  if Geometry.primitive_count cleaned_compact <> 0
     || Geometry.point_count cleaned_compact <> 0 then
    fail "clean remove-unused-points policy";
  let compact_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 2.; 3.; 4.|] ~y:(Array.make 5 0.) ~z:(Array.make 5 0.) in
  let compact_topology = Topology.Builder.create ~point_count:5 () in
  Topology.Builder.add_triangle compact_topology 0 2 4;
  let compact_ids = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int [|10; 11; 12; 13; 14|]) |> get_ok
  and compact_group = Group.init ~owner:Group.Point ~name:"marked" 5
      (fun point -> point = 2 || point = 3) in
  let compact_source = Geometry.create ~positions:compact_positions
      ~topology:(Topology.Builder.freeze compact_topology)
      ~attributes:[compact_ids] ~groups:[compact_group] () |> get_ok
      |> Ops.group_edges ~name:"compact_edges" |> get_ok in
  let compacted domains = Parallel.run ~domains (fun () ->
      Ops.compact_points ~grain:1 compact_source |> get_ok) in
  let compact_one = compacted 1 and compact_many = compacted 4 in
  let compact_view = Topology.Private.view (Geometry.topology compact_one) in
  let compact_id_values = Geometry.find_attribute ~owner:Attribute.Point "id"
      compact_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"id" ~owner:Attribute.Point
          Attribute.int) |> Option.get in
  if Geometry.point_count compact_one <> 3
     || compact_view.vertex_points <> [|0; 1; 2|]
     || compact_id_values <> [|10; 12; 14|]
     || not (equal_positions compact_one compact_many)
  then fail "compact points cardinality/remap/domain determinism";
  (match Geometry.find_group ~owner:Group.Point "marked" compact_one with
   | Some group when Group.cardinality group = 1 && Group.mem 1 group -> ()
   | _ -> fail "compact points group remap");
  (match Geometry.find_edge_group "compact_edges" compact_one,
      Geometry.find_edge_group "compact_edges" compact_many with
   | Some one, Some many when Edge_group.cardinality one = 3
       && Edge_group.length one = 3 && Edge_group.length many = 3 ->
       for edge = 0 to 2 do
         if Edge_group.mem edge one <> Edge_group.mem edge many then
           fail "compact points native edge group differs by domain count"
       done
   | _ -> fail "compact points native edge-group remap");
  let bounded = Ops.bounding_box ~padding:(Vec3.create 0.1 0.1 0.1)
      triangle_geometry |> get_ok in
  (match Analysis.bounds bounded with
   | Some bounds when abs_float (bounds.min.x +. 0.1) < 1e-12
       && abs_float (bounds.max.y -. 1.1) < 1e-12
       && abs_float (bounds.size.z -. 0.2) < 1e-12 -> ()
   | _ -> fail "bounding box bounds/padding");
  let match_source = Ops.box ~size:(Vec3.create 1. 2. 4.) () |> get_ok
  and match_target = Ops.box ~size:(Vec3.create 4. 6. 8.) () |> get_ok
      |> Ops.transform (Mat4.translation (Vec3.create (-3.) 5. 2.)) in
  let matched domains = Parallel.run ~domains (fun () ->
      Ops.match_size ~grain:1 ~fit:Ops.Stretch ~target:match_target match_source
      |> get_ok) in
  let matched_one = matched 1 and matched_many = matched 4 in
  let matched_bounds = Analysis.bounds matched_one |> Option.get
  and target_bounds = Analysis.bounds match_target |> Option.get in
  if not (equal_positions matched_one matched_many)
     || abs_float (matched_bounds.min.x -. target_bounds.min.x) > 1e-12
     || abs_float (matched_bounds.max.y -. target_bounds.max.y) > 1e-12
     || abs_float (matched_bounds.max.z -. target_bounds.max.z) > 1e-12
  then fail "match size bounds/domain determinism";
  let axis_source = Ops.points [|(1., 0., 0.); (2., 0., 0.)|] in
  let aligned = Ops.match_axis ~grain:1 ~from:Vec3.unit_x ~into:Vec3.unit_y
      axis_source |> get_ok in
  let aligned_positions = Packed.Float3.Private.view (Geometry.positions aligned) in
  if abs_float aligned_positions.x.(0) > 1e-12
     || abs_float (aligned_positions.y.(0) -. 1.) > 1e-12 then
    fail "match axis quarter turn";
  let opposed = Ops.match_axis ~from:Vec3.unit_x ~into:(Vec3.neg Vec3.unit_x)
      axis_source |> get_ok in
  let opposed_positions = Packed.Float3.Private.view (Geometry.positions opposed) in
  if abs_float (opposed_positions.x.(1) +. 2.) > 1e-12 then
    fail "match axis deterministic half turn";
  (match Ops.match_axis ~from:Vec3.zero ~into:Vec3.unit_y axis_source with
   | Error error when Error.code error = "invalid_axis" -> ()
   | _ -> fail "match axis accepted a zero vector");
  let float_values name geometry =
    match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values
         | _ -> fail ("unexpected storage for " ^ name))
    | None -> fail ("missing point attribute " ^ name) in
  let blur_curve values =
    let geometry = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (3.,0.,0.)|]
        |> get_ok in
    let attribute = Attribute.create_owned ~name:"value" ~owner:Attribute.Point
        (Attribute.Float values) |> get_ok in
    Geometry.with_attribute attribute geometry |> get_ok in
  let uniform_blur = Attribute_ops.blur_points ~iterations:1
      ~mode:(Attribute_ops.Laplacian 1.) ~pattern:"value"
      (blur_curve [|0.; 10.; 0.|]) |> get_ok in
  if float_values "value" uniform_blur <> [|10.; 0.; 10.|] then
    fail "uniform Attribute Blur";
  let edge_blur = Attribute_ops.blur_points ~iterations:1
      ~method_:Attribute_ops.Edge_length ~mode:(Attribute_ops.Laplacian 1.)
      ~pattern:"value" (blur_curve [|0.; 0.; 12.|]) |> get_ok in
  if abs_float ((float_values "value" edge_blur).(1) -. 4.) > 1e-12 then
    fail "edge-length Attribute Blur";
  let controls = blur_curve [|0.; 10.; 0.|] in
  let weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float [|1.; 0.5; 1.|]) |> get_ok
  and alpha = Attribute.create_owned ~name:"alpha" ~owner:Attribute.Point
      (Attribute.Float [|1.; 1.; 0.|]) |> get_ok in
  let controls = controls |> Geometry.with_attribute weight |> get_ok
      |> Geometry.with_attribute alpha |> get_ok in
  let center = Group.init ~owner:Group.Point ~name:"center" 3
      (fun point -> point = 1) in
  let controlled = Attribute_ops.blur_points ~selection:center
      ~weight_attribute:"weight" ~alpha_attribute:"alpha"
      ~mode:(Attribute_ops.Laplacian 1.) ~pattern:"value" controls |> get_ok in
  if float_values "value" controlled <> [|0.; 5.; 0.|] then
    fail "selected weighted/alpha Attribute Blur";
  let blended = Attribute_ops.blur_points ~original_blend:1. ~blurred_blend:1.
      ~mode:(Attribute_ops.Laplacian 1.) ~pattern:"value"
      (blur_curve [|0.; 10.; 0.|]) |> get_ok in
  if float_values "value" blended <> [|10.; 10.; 10.|] then
    fail "Attribute Blur output blending";
  let custom = Attribute_ops.blur_points ~iterations:2
      ~mode:(Attribute_ops.Custom_steps { odd = 1.; even = 0. })
      ~pattern:"value" (blur_curve [|0.; 10.; 0.|]) |> get_ok in
  if float_values "value" custom <> [|10.; 0.; 10.|] then
    fail "Attribute Blur custom odd/even steps";
  let tuple_source = blur_curve [|0.; 10.; 0.|] in
  let uv = Attribute.create_owned ~name:"f_uv" ~owner:Attribute.Point
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:[|0.; 10.; 0.|] ~y:[|2.; 4.; 2.|] |> get_ok)) |> get_ok
  and color = Attribute.create_owned ~name:"f_color" ~owner:Attribute.Point
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:[|0.; 1.; 0.|] ~y:[|0.; 2.; 0.|]
        ~z:[|0.; 3.; 0.|] ~w:[|1.; 1.; 1.|] |> get_ok)) |> get_ok in
  let tuple_source = tuple_source |> Geometry.with_attribute uv |> get_ok
      |> Geometry.with_attribute color |> get_ok in
  let tuple_blur = Attribute_ops.blur_points
      ~mode:(Attribute_ops.Laplacian 1.) ~pattern:"f_*" tuple_source |> get_ok in
  (match Geometry.find_attribute ~owner:Attribute.Point "f_uv" tuple_blur,
      Geometry.find_attribute ~owner:Attribute.Point "f_color" tuple_blur with
   | Some uv, Some color ->
       let uv = match Attribute.Private.storage uv with
         | Attribute.Float2 values -> Packed.Float2.Private.view values
         | _ -> fail "Attribute Blur float2 storage"
       and color = match Attribute.Private.storage color with
         | Attribute.Float4 values -> Packed.Float4.Private.view values
         | _ -> fail "Attribute Blur float4 storage" in
       if uv.x <> [|10.; 0.; 10.|] || uv.y <> [|4.; 2.; 4.|]
           || color.z <> [|3.; 0.; 3.|] || color.w <> [|1.; 1.; 1.|]
       then fail "Attribute Blur tuple planes"
   | _ -> fail "Attribute Blur dropped tuple attributes");
  let pinned = Attribute_ops.blur_points ~pin_borders:true
      ~mode:(Attribute_ops.Laplacian 1.) ~pattern:"value"
      (blur_curve [|0.; 10.; 0.|]) |> get_ok in
  if float_values "value" pinned <> [|0.; 10.; 0.|] then
    fail "Attribute Blur border pins";
  let smoothed_grid = Attribute_ops.blur_points ~iterations:1
      ~mode:(Attribute_ops.Laplacian 0.25) ~pattern:"P" grid |> get_ok in
  if Geometry.find_attribute ~owner:Attribute.Point "N" smoothed_grid <> None
      || Geometry.find_attribute ~owner:Attribute.Vertex "N" smoothed_grid <> None
  then fail "position Attribute Blur retained stale normals";
  (match Attribute_ops.blur_points ~iterations:(-1) ~pattern:"P" grid with
   | Error error when Error.code error = "invalid_blur" -> ()
   | _ -> fail "Attribute Blur accepted negative iterations");
  (match Attribute_ops.blur_points ~weight_attribute:"missing" ~pattern:"P" grid with
   | Error error when Error.code error = "invalid_blur" -> ()
   | _ -> fail "Attribute Blur accepted a missing weight attribute");
  (match Attribute_ops.blur_points ~pattern:"value"
      (blur_curve [|Float.nan; 1.; 2.|]) with
   | Error error when Error.code error = "invalid_blur" -> ()
   | _ -> fail "Attribute Blur accepted non-finite source data");
  let extreme_curve = Ops.polyline
      [|(max_float,0.,0.); (-.max_float,0.,0.)|] |> get_ok in
  let extreme_value = Attribute.create_owned ~name:"value"
      ~owner:Attribute.Point (Attribute.Float [|0.; 1.|]) |> get_ok in
  let extreme_curve = Geometry.with_attribute extreme_value extreme_curve |> get_ok in
  (match Attribute_ops.blur_points ~method_:Attribute_ops.Edge_length
      ~pattern:"value" extreme_curve with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "Attribute Blur accepted a non-finite edge metric");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.grid ~cancel:cancelled ~columns:256 ~rows:256 ~size:2. () with
   | Error error when Error.code error = "cancelled" -> ()
   | Error error -> fail ("unexpected cancellation code: " ^ Error.code error)
   | Ok _ -> fail "cancelled PDK operation published geometry");
  (match Ops.fuse ~cancel:cancelled ~tolerance:0. grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled fuse published geometry or wrong error");
  (match Ops.mirror ~cancel:cancelled ~origin:Vec3.zero ~normal:Vec3.unit_x grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled mirror published geometry or wrong error");
  (match Ops.clip ~cancel:cancelled ~origin:Vec3.zero ~normal:Vec3.unit_x grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled clip published geometry or wrong error");
  (match Attribute_ops.promote ~cancel:cancelled ~source:Attribute.Point
      ~destination:Attribute.Primitive ~name:"N" grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled attribute promotion published geometry or wrong error");
  (match Attribute_ops.transfer_points ~cancel:cancelled
      ~source:transfer_source ~target:transfer_target () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled attribute transfer published geometry or wrong error");
  (match Attribute_ops.blur_points ~cancel:cancelled ~pattern:"P" grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled Attribute Blur published geometry or wrong error");
  (match Ops.compact_points ~cancel:cancelled compact_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled point compaction published geometry or wrong error");
  (match Ops.bounding_box ~cancel:cancelled compact_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled bounding box published geometry or wrong error");
  (match Ops.match_size ~cancel:cancelled ~target:match_target match_source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled match size published geometry or wrong error");
  (match Ops.sort ~cancel:cancelled ~owner:Ops.Points ~key:Ops.X grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled sort published geometry or wrong error");
  (match Ops.duplicate ~cancel:cancelled ~copies:4 grid with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled duplicate published geometry or wrong error");
  (match Ops.copy_to_points ~cancel:cancelled ~source:grid
      ~targets:(Ops.points [|(0.,0.,0.)|]) () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled Copy to Points published geometry or wrong error");
  (match Prismel_mesh.to_mesh ~cancel:cancelled grid with
   | Error error when Error.code error = "cancelled" -> ()
   | Error error -> fail ("unexpected mesh cancellation code: " ^ Error.code error)
   | Ok _ -> fail "cancelled mesh conversion published a mesh");
  let target_positions = Ops.points [|(10., 0., 0.); (0., 20., 0.)|] in
  let target_scale = Attribute.create_owned ~name:"scale" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|2.; 1.|] ~y:[|1.; 3.|] ~z:[|1.; 1.|])) |> get_ok in
  let half_turn = sqrt 0.5 in
  let target_orient = Attribute.create_owned ~name:"orient" ~owner:Attribute.Point
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:[|0.; 0.|] ~y:[|0.; 0.|] ~z:[|half_turn; 0.|]
        ~w:[|half_turn; 1.|] |> get_ok)) |> get_ok in
  let targets = target_positions |> Geometry.with_attribute target_scale |> get_ok
      |> Geometry.with_attribute target_orient |> get_ok in
  let prototype = Ops.points [|(1., 0., 0.); (0., 1., 0.)|] in
  let copied domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~source:prototype ~targets () |> get_ok) in
  let copied_one = copied 1 and copied_many = copied 4 in
  if not (equal_positions copied_one copied_many)
     || Geometry.point_count copied_one <> 4
  then fail "copy-to-points domain determinism/cardinality";
  let copied_positions = Geometry.positions copied_one in
  let x0, y0, _ = Packed.Float3.get copied_positions 0
  and x1, y1, _ = Packed.Float3.get copied_positions 1
  and x2, y2, _ = Packed.Float3.get copied_positions 2
  and x3, y3, _ = Packed.Float3.get copied_positions 3 in
  if abs_float (x0 -. 10.) > 1e-12 || abs_float (y0 -. 2.) > 1e-12
     || abs_float (x1 -. 9.) > 1e-12 || abs_float y1 > 1e-12
     || abs_float (x2 -. 1.) > 1e-12 || abs_float (y2 -. 20.) > 1e-12
     || abs_float x3 > 1e-12 || abs_float (y3 -. 23.) > 1e-12
  then fail "copy-to-points scale/orient/translate";
  let axis_prototype = Ops.points
      [|(1.,0.,0.); (0.,1.,0.); (0.,0.,1.)|] in
  let alignment_targets = Ops.points [|(0.,0.,0.); (10.,0.,0.)|] in
  let target_n = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|1.;0.|] ~y:[|0.;1.|] ~z:[|0.;0.|])) |> get_ok
  and target_up = Attribute.create_owned ~name:"up" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|0.;0.|] ~y:[|0.;0.|] ~z:[|1.;0.|])) |> get_ok in
  let alignment_targets = alignment_targets
      |> Geometry.with_attribute target_n |> get_ok
      |> Geometry.with_attribute target_up |> get_ok in
  let aligned domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~source:axis_prototype
      ~targets:alignment_targets () |> get_ok) in
  let aligned_one = aligned 1 and aligned_many = aligned 4 in
  let aligned_positions = Packed.Float3.Private.view
      (Geometry.positions aligned_one) in
  if not (equal_positions aligned_one aligned_many)
      || not (near_array [|0.;0.;1.; 11.;10.;10.|] aligned_positions.x)
      || not (near_array [|1.;0.;0.; 0.;0.;1.|] aligned_positions.y)
      || not (near_array [|0.;1.;0.; 0.;-1.;0.|] aligned_positions.z) then
    fail "copy-to-points N/up and shortest-arc alignment/domain behavior";
  let priority_n = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|0.;0.|] ~y:[|1.;1.|] ~z:[|0.;0.|])) |> get_ok in
  let orient_priority_targets = targets |> Geometry.with_attribute priority_n
      |> get_ok in
  let orient_priority = Ops.copy_to_points ~source:prototype
      ~targets:orient_priority_targets () |> get_ok in
  if not (equal_positions orient_priority copied_one) then
    fail "copy-to-points orient did not override N";
  let velocity = Attribute.create_owned ~name:"v" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|0.|] ~y:[|1.|] ~z:[|0.|])) |> get_ok
  and velocity_up = Attribute.create_owned ~name:"up" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|0.|] ~y:[|0.|] ~z:[|1.|])) |> get_ok in
  let velocity_target = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute velocity |> get_ok
      |> Geometry.with_attribute velocity_up |> get_ok in
  let velocity_copy = Ops.copy_to_points ~source:axis_prototype
      ~targets:velocity_target () |> get_ok in
  let velocity_positions = Packed.Float3.Private.view
      (Geometry.positions velocity_copy) in
  if not (near_array [|-1.;0.;0.|] velocity_positions.x)
      || not (near_array [|0.;0.;1.|] velocity_positions.y)
      || not (near_array [|0.;1.;0.|] velocity_positions.z) then
    fail "copy-to-points velocity/up fallback alignment";
  let quarter_turn = sqrt 0.5 in
  let target_rot = Attribute.create_owned ~name:"rot" ~owner:Attribute.Point
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:[|0.|] ~y:[|0.|] ~z:[|quarter_turn|] ~w:[|quarter_turn|]
        |> get_ok)) |> get_ok
  and target_trans = Attribute.create_owned ~name:"trans" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|3.|] ~y:[|0.|] ~z:[|0.|])) |> get_ok
  and target_pivot = Attribute.create_owned ~name:"pivot" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|1.|] ~y:[|0.|] ~z:[|0.|])) |> get_ok
  and target_pscale = Attribute.create_owned ~name:"pscale" ~owner:Attribute.Point
      (Attribute.Float [|2.|]) |> get_ok in
  let stacked_target = Ops.points [|(10.,0.,0.)|]
      |> Geometry.with_attribute target_rot |> get_ok
      |> Geometry.with_attribute target_trans |> get_ok
      |> Geometry.with_attribute target_pivot |> get_ok
      |> Geometry.with_attribute target_pscale |> get_ok in
  let pivot_normal = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|1.;1.|] ~y:[|0.;0.|] ~z:[|0.;0.|])) |> get_ok in
  let pivot_source = Ops.points [|(1.,0.,0.); (2.,0.,0.)|]
      |> Geometry.with_attribute pivot_normal |> get_ok in
  let stacked domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~source:pivot_source ~targets:stacked_target ()
      |> get_ok) in
  let stacked_one = stacked 1 and stacked_many = stacked 4 in
  let stacked_positions = Packed.Float3.Private.view
      (Geometry.positions stacked_one)
  and stacked_normals = Geometry.find_attribute ~owner:Attribute.Point "N"
      stacked_one |> Option.get
      |> Attribute.get (Attribute.normal ~owner:Attribute.Point) |> Option.get
      |> Packed.Float3.Private.view
  and stacked_normals_many = Geometry.find_attribute ~owner:Attribute.Point "N"
      stacked_many |> Option.get
      |> Attribute.get (Attribute.normal ~owner:Attribute.Point) |> Option.get
      |> Packed.Float3.Private.view in
  if not (equal_positions stacked_one stacked_many)
      || not (near_array [|13.;13.|] stacked_positions.x)
      || not (near_array [|0.;2.|] stacked_positions.y)
      || not (near_array [|0.;0.|] stacked_positions.z)
      || not (near_array [|0.;0.|] stacked_normals.x)
      || not (near_array [|1.;1.|] stacked_normals.y)
      || not (near_array [|0.;0.|] stacked_normals.z)
      || stacked_normals.x <> stacked_normals_many.x
      || stacked_normals.y <> stacked_normals_many.y
      || stacked_normals.z <> stacked_normals_many.z then
    fail "copy-to-points pivot/scale/post-rotation/translation stack";
  let packed_transform values = Pdk.Packed.Float_array.create_owned
      ~offsets:[|0; Array.length values|] ~values |> get_ok in
  let target_transform = Attribute.create_owned ~name:"transform"
      ~owner:Attribute.Point (Attribute.Float_array (packed_transform
        [|2.;0.;0.;5.; 0.;3.;0.;6.; 0.;0.;4.;7.; 0.;0.;0.;1.|]))
      |> get_ok in
  let matrix_target = stacked_target |> Geometry.with_attribute target_transform
      |> get_ok in
  let matrix_copied domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~source:pivot_source ~targets:matrix_target ()
      |> get_ok) in
  let matrix_one = matrix_copied 1 and matrix_many = matrix_copied 4 in
  let matrix_positions = Packed.Float3.Private.view (Geometry.positions matrix_one)
  and matrix_normals = Geometry.find_attribute ~owner:Attribute.Point "N"
      matrix_one |> Option.get
      |> Attribute.get (Attribute.normal ~owner:Attribute.Point) |> Option.get
      |> Packed.Float3.Private.view
  and matrix_normals_many = Geometry.find_attribute ~owner:Attribute.Point "N"
      matrix_many |> Option.get
      |> Attribute.get (Attribute.normal ~owner:Attribute.Point) |> Option.get
      |> Packed.Float3.Private.view in
  if not (equal_positions matrix_one matrix_many)
      || not (near_array [|18.;20.|] matrix_positions.x)
      || not (near_array [|6.;6.|] matrix_positions.y)
      || not (near_array [|7.;7.|] matrix_positions.z)
      || not (near_array [|1.;1.|] matrix_normals.x)
      || not (near_array [|0.;0.|] matrix_normals.y)
      || not (near_array [|0.;0.|] matrix_normals.z)
      || matrix_normals.x <> matrix_normals_many.x
      || matrix_normals.y <> matrix_normals_many.y
      || matrix_normals.z <> matrix_normals_many.z then
    fail "copy-to-points affine transform override/normal/domain behavior";
  let singular_transform = Attribute.create_owned ~name:"transform"
      ~owner:Attribute.Point (Attribute.Float_array (packed_transform
        [|1.;0.;0.; 0.;1.;0.; 0.;0.;0.|])) |> get_ok in
  let singular_target = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute singular_transform |> get_ok in
  let singular_copy = Ops.copy_to_points ~source:pivot_source
      ~targets:singular_target () |> get_ok in
  if Geometry.find_attribute ~owner:Attribute.Point "N" singular_copy <> None
  then fail "copy-to-points singular transform retained invalid normals";
  let malformed_transform = Attribute.create_owned ~name:"transform"
      ~owner:Attribute.Point (Attribute.Float_array (packed_transform
        [|1.;0.;0.;0.; 0.;1.;0.;0.; 0.;0.;1.;0.; 0.;0.;1.;1.|]))
      |> get_ok in
  let malformed_target = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute malformed_transform |> get_ok in
  (match Ops.copy_to_points ~source:prototype ~targets:malformed_target () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted a projective transform matrix");
  let restricted_source = Ops.merge [
      Ops.polyline [|(0.,0.,0.); (1.,0.,0.)|] |> get_ok;
      Ops.polyline [|(10.,0.,0.); (12.,0.,0.)|] |> get_ok]
      |> get_ok in
  let restricted_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float [|0.;1.;10.;12.|]) |> get_ok
  and restricted_id = Attribute.create_owned ~name:"piece_id"
      ~owner:Attribute.Primitive (Attribute.Int [|100;200|]) |> get_ok
  and restricted_detail = Attribute.create_owned ~name:"detail_id"
      ~owner:Attribute.Detail (Attribute.Int [|77|]) |> get_ok in
  let restricted_source = restricted_source
      |> Geometry.with_attribute restricted_weight |> get_ok
      |> Geometry.with_attribute restricted_id |> get_ok
      |> Geometry.with_attribute restricted_detail |> get_ok
      |> Ops.group_edges ~name:"source_edges" |> get_ok in
  let source_second = Group.ordered ~owner:Group.Primitive ~name:"source_second"
      ~length:2 [|1|] |> get_ok in
  let restricted_source = Geometry.with_group source_second restricted_source
      |> get_ok in
  let restricted_targets = Ops.points
      [|(0.,0.,0.); (0.,10.,0.); (0.,20.,0.)|] in
  let restricted_scale = Attribute.create_owned ~name:"pscale"
      ~owner:Attribute.Point (Attribute.Float [|1.;9.;2.|]) |> get_ok in
  let restricted_targets = Geometry.with_attribute restricted_scale
      restricted_targets |> get_ok in
  let target_outer = Group.ordered ~owner:Group.Point ~name:"target_outer"
      ~length:3 [|2;0|] |> get_ok in
  let restricted domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~source_primitives:source_second
      ~target_points:target_outer ~source:restricted_source
      ~targets:restricted_targets () |> get_ok) in
  let restricted_one = restricted 1 and restricted_many = restricted 4 in
  let restricted_positions = Packed.Float3.Private.view
      (Geometry.positions restricted_one)
  and restricted_topology = Topology.Private.view
      (Geometry.topology restricted_one)
  and restricted_many_topology = Topology.Private.view
      (Geometry.topology restricted_many) in
  let restricted_weights = Geometry.find_attribute ~owner:Attribute.Point
      "weight" restricted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and restricted_weights_many = Geometry.find_attribute ~owner:Attribute.Point
      "weight" restricted_many |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and restricted_ids = Geometry.find_attribute ~owner:Attribute.Primitive
      "piece_id" restricted_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece_id" ~owner:Attribute.Primitive
           Attribute.int) |> Option.get in
  let restricted_group = Geometry.find_group ~owner:Group.Primitive
      "source_second" restricted_one |> Option.get
  and restricted_edges = Geometry.find_edge_group "source_edges" restricted_one
      |> Option.get
  and restricted_edges_many = Geometry.find_edge_group "source_edges"
      restricted_many |> Option.get in
  if Geometry.point_count restricted_one <> 4
      || Geometry.vertex_count restricted_one <> 4
      || Geometry.primitive_count restricted_one <> 2
      || not (near_array [|10.;12.;20.;24.|] restricted_positions.x)
      || not (near_array [|0.;0.;20.;20.|] restricted_positions.y)
      || restricted_topology.vertex_points <> [|0;1;2;3|]
      || restricted_topology.vertex_points <> restricted_many_topology.vertex_points
      || restricted_topology.primitive_offsets <> [|0;2;4|]
      || restricted_weights <> [|10.;12.;10.;12.|]
      || restricted_weights <> restricted_weights_many
      || restricted_ids <> [|200;200|]
      || Group.cardinality restricted_group <> 2
      || not (Group.is_ordered restricted_group)
      || Group.ordered_elements restricted_group <> Some [|0;1|]
      || Edge_group.length restricted_edges <> 2
      || Edge_group.cardinality restricted_edges <> 2
      || Edge_group.cardinality restricted_edges_many <> 2
      || not (equal_positions restricted_one restricted_many) then
    fail "copy-to-points source/target restriction payload/group/domain behavior";
  let empty_targets = Group.init ~owner:Group.Point ~name:"none" 3
      (fun _ -> false) in
  let restricted_empty = Ops.copy_to_points ~source_primitives:source_second
      ~target_points:empty_targets ~source:restricted_source
      ~targets:restricted_targets () |> get_ok in
  if Geometry.point_count restricted_empty <> 0
      || Geometry.primitive_count restricted_empty <> 0
      || Geometry.find_attribute ~owner:Attribute.Detail "detail_id"
           restricted_empty = None then
    fail "copy-to-points empty target restriction/detail preservation";
  let piece_targets = Ops.points
      [|(0.,0.,0.); (0.,10.,0.); (0.,20.,0.); (0.,30.,0.)|]
    |> Geometry.with_attribute (Attribute.create_owned ~name:"piece_id"
         ~owner:Attribute.Point (Attribute.Int [|200;100;999;200|]) |> get_ok)
    |> get_ok
    |> Geometry.with_attribute (Attribute.create_owned ~name:"pscale"
         ~owner:Attribute.Point (Attribute.Float [|1.;2.;3.;1.|]) |> get_ok)
    |> get_ok
    |> Geometry.with_attribute (Attribute.create_owned ~name:"piece_profile"
         ~owner:Attribute.Point (Attribute.Float_array
           (Packed.Float_array.create_owned ~offsets:[|0;2;3;6;8|]
             ~values:[|0.;1.;2.;3.;4.;5.;6.;7.|] |> get_ok)) |> get_ok)
    |> get_ok in
  let piece_rules = Ops.[{
      copy_target_pattern = "piece_profile";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_copy;
    }] in
  let piece_copy domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~piece_attribute:"piece_id"
      ~target_attributes:piece_rules ~source:restricted_source
      ~targets:piece_targets () |> get_ok) in
  let piece_one = piece_copy 1 and piece_many = piece_copy 4 in
  let piece_positions = Packed.Float3.Private.view
      (Geometry.positions piece_one)
  and piece_topology = Topology.Private.view (Geometry.topology piece_one)
  and piece_many_topology = Topology.Private.view (Geometry.topology piece_many) in
  let piece_weights = Geometry.find_attribute ~owner:Attribute.Point "weight"
      piece_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and piece_ids = Geometry.find_attribute ~owner:Attribute.Primitive "piece_id"
      piece_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece_id"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get
  and piece_group = Geometry.find_group ~owner:Group.Primitive "source_second"
      piece_one |> Option.get
  and piece_edges = Geometry.find_edge_group "source_edges" piece_one
      |> Option.get
  and piece_edges_many = Geometry.find_edge_group "source_edges" piece_many
      |> Option.get in
  let piece_profile = float_array_values ~owner:Attribute.Primitive
      ~name:"piece_profile" piece_one
  and piece_profile_many = float_array_values ~owner:Attribute.Primitive
      ~name:"piece_profile" piece_many in
  if Geometry.point_count piece_one <> 6
      || Geometry.vertex_count piece_one <> 6
      || Geometry.primitive_count piece_one <> 3
      || not (near_array [|10.;12.;0.;2.;10.;12.|] piece_positions.x)
      || not (near_array [|0.;0.;10.;10.;30.;30.|] piece_positions.y)
      || piece_topology.vertex_points <> [|0;1;2;3;4;5|]
      || piece_topology.primitive_offsets <> [|0;2;4;6|]
      || piece_topology.vertex_points <> piece_many_topology.vertex_points
      || piece_topology.primitive_offsets <> piece_many_topology.primitive_offsets
      || piece_weights <> [|10.;12.;0.;1.;10.;12.|]
      || piece_ids <> [|200;100;200|]
      || piece_profile.offsets <> [|0;2;3;5|]
      || piece_profile.values <> [|0.;1.;2.;6.;7.|]
      || piece_profile.offsets <> piece_profile_many.offsets
      || piece_profile.values <> piece_profile_many.values
      || Group.ordered_elements piece_group <> Some [|0;2|]
      || Edge_group.cardinality piece_edges <> 3
      || Edge_group.cardinality piece_edges_many <> 3
      || Geometry.find_attribute ~owner:Attribute.Detail "detail_id" piece_one
           = None
      || not (equal_positions piece_one piece_many) then
    fail "copy-to-points primitive piece matching/order/payload/group/domain behavior";
  let text_source = restricted_source
      |> Geometry.with_attribute (Attribute.create_owned ~name:"name"
           ~owner:Attribute.Primitive (Attribute.Text [|"stem";"cap"|])
           |> get_ok) |> get_ok in
  let text_targets = Ops.points [|(0.,0.,0.); (0.,10.,0.); (0.,20.,0.)|]
      |> Geometry.with_attribute (Attribute.create_owned ~name:"name"
           ~owner:Attribute.Point (Attribute.Text [|"cap";"missing";"stem"|])
           |> get_ok) |> get_ok in
  let text_piece = Ops.copy_to_points ~piece_attribute:"name"
      ~source:text_source ~targets:text_targets () |> get_ok in
  let text_piece_ids = Geometry.find_attribute ~owner:Attribute.Primitive
      "piece_id" text_piece |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece_id"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if text_piece_ids <> [|200;100|] then
    fail "copy-to-points text piece matching/unmatched behavior";
  let point_piece_source = Ops.polyline [|(0.,0.,0.); (1.,0.,0.)|]
      |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned ~name:"point_piece"
           ~owner:Attribute.Point (Attribute.Text [|"left";"right"|])
           |> get_ok) |> get_ok in
  let point_piece_targets = Ops.points [|(0.,0.,0.); (0.,5.,0.)|]
      |> Geometry.with_attribute (Attribute.create_owned ~name:"point_piece"
           ~owner:Attribute.Point (Attribute.Text [|"right";"left"|])
           |> get_ok) |> get_ok in
  let point_piece = Ops.copy_to_points ~piece_attribute:"point_piece"
      ~source:point_piece_source ~targets:point_piece_targets () |> get_ok in
  let point_piece_positions = Packed.Float3.Private.view
      (Geometry.positions point_piece) in
  if Geometry.point_count point_piece <> 2
      || Geometry.vertex_count point_piece <> 0
      || Geometry.primitive_count point_piece <> 0
      || not (near_array [|1.;0.|] point_piece_positions.x)
      || not (near_array [|0.;5.|] point_piece_positions.y) then
    fail "copy-to-points point piece mixed-primitive/free-point behavior";
  let fallback_targets = Ops.points [|(0.,0.,0.); (0.,5.,0.); (0.,10.,0.)|]
      |> Geometry.with_attribute (Attribute.create_owned ~name:"which"
           ~owner:Attribute.Point (Attribute.Int [|1;7;0|]) |> get_ok)
      |> get_ok in
  let fallback_piece = Ops.copy_to_points ~piece_attribute:"which"
      ~source:restricted_source ~targets:fallback_targets () |> get_ok in
  let fallback_ids = Geometry.find_attribute ~owner:Attribute.Primitive
      "piece_id" fallback_piece |> Option.get
      |> Attribute.get (Attribute.key ~name:"piece_id"
           ~owner:Attribute.Primitive Attribute.int) |> Option.get in
  if fallback_ids <> [|200;100|] then
    fail "copy-to-points primitive-number piece fallback";
  let invalid_piece_targets = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute (Attribute.create_owned ~name:"bad_piece"
           ~owner:Attribute.Point (Attribute.Float [|1.|]) |> get_ok)
      |> get_ok in
  (match Ops.copy_to_points ~piece_attribute:"bad_piece"
      ~source:restricted_source ~targets:invalid_piece_targets () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted a non-discrete piece attribute");
  let cancelled_piece = Cancel.create () in
  Cancel.cancel cancelled_piece;
  (match Ops.copy_to_points ~cancel:cancelled_piece
      ~piece_attribute:"piece_id" ~source:restricted_source
      ~targets:piece_targets () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "copy-to-points piece planning ignored cancellation");
  let wrong_source_owner = Group.init ~owner:Group.Point ~name:"wrong" 4
      (fun _ -> true)
  and wrong_target_owner = Group.init ~owner:Group.Primitive ~name:"wrong" 0
      (fun _ -> false) in
  (match Ops.copy_to_points ~source_primitives:wrong_source_owner
      ~source:restricted_source ~targets:restricted_targets () with
   | Error error when Error.code error = "invalid_selection" -> ()
   | _ -> fail "copy-to-points accepted a point-owned source selection");
  (match Ops.copy_to_points ~target_points:wrong_target_owner
      ~source:restricted_source ~targets:restricted_targets () with
   | Error error when Error.code error = "invalid_selection" -> ()
   | _ -> fail "copy-to-points accepted a primitive-owned target selection");
  let transfer_source = Ops.polyline [|(0.,0.,0.); (1.,0.,0.)|] |> get_ok in
  let source_weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float [|10.;20.|]) |> get_ok
  and source_corner = Attribute.create_owned ~name:"corner" ~owner:Attribute.Vertex
      (Attribute.Int [|1;2|]) |> get_ok
  and source_density = Attribute.create_owned ~name:"density"
      ~owner:Attribute.Primitive (Attribute.Float [|2.|]) |> get_ok
  and source_profile = Attribute.create_owned ~name:"profile"
      ~owner:Attribute.Point (Attribute.Float_array
        (Packed.Float_array.create_owned ~offsets:[|0;2;4|]
          ~values:[|10.;20.;30.;40.|] |> get_ok)) |> get_ok
  and source_disabled = Attribute.create_owned ~name:"disabled"
      ~owner:Attribute.Point (Attribute.Int [|7;8|]) |> get_ok in
  let transfer_source = transfer_source
      |> Geometry.with_attribute source_weight |> get_ok
      |> Geometry.with_attribute source_corner |> get_ok
      |> Geometry.with_attribute source_density |> get_ok
      |> Geometry.with_attribute source_profile |> get_ok
      |> Geometry.with_attribute source_disabled |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point ~name:"union_mask" 2
           (fun point -> point = 0)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Vertex
           ~name:"intersect_mask" 2 (fun vertex -> vertex = 0)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Primitive
           ~name:"subtract_mask" 1 (fun _ -> true)) |> get_ok in
  let transfer_targets = Ops.points [|(0.,0.,0.); (0.,10.,0.)|] in
  let target_weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float [|3.;4.|]) |> get_ok
  and target_corner = Attribute.create_owned ~name:"corner" ~owner:Attribute.Point
      (Attribute.Int [|100;200|]) |> get_ok
  and target_density = Attribute.create_owned ~name:"density" ~owner:Attribute.Point
      (Attribute.Float [|5.;7.|]) |> get_ok
  and target_label = Attribute.create_owned ~name:"label" ~owner:Attribute.Point
      (Attribute.Text [|"first";"second"|]) |> get_ok
  and target_gain = Attribute.create_owned ~name:"gain" ~owner:Attribute.Point
      (Attribute.Float [|2.;3.|]) |> get_ok
  and target_profile = Attribute.create_owned ~name:"profile"
      ~owner:Attribute.Point (Attribute.Float_array
        (Packed.Float_array.create_owned ~offsets:[|0;2;4|]
          ~values:[|1.;2.;3.;4.|] |> get_ok)) |> get_ok
  and target_disabled = Attribute.create_owned ~name:"disabled"
      ~owner:Attribute.Point (Attribute.Int [|100;200|]) |> get_ok in
  let transfer_targets = transfer_targets
      |> Geometry.with_attribute target_weight |> get_ok
      |> Geometry.with_attribute target_corner |> get_ok
      |> Geometry.with_attribute target_density |> get_ok
      |> Geometry.with_attribute target_label |> get_ok
      |> Geometry.with_attribute target_gain |> get_ok
      |> Geometry.with_attribute target_profile |> get_ok
      |> Geometry.with_attribute target_disabled |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point ~name:"union_mask" 2
           (fun point -> point = 1)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point
           ~name:"intersect_mask" 2 (fun point -> point = 1)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point
           ~name:"subtract_mask" 2 (fun point -> point = 1)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point ~name:"copy_mask" 2
           (fun point -> point = 1)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point
           ~name:"missing_multiply" 2 (fun point -> point = 1)) |> get_ok
      |> Geometry.with_group (Group.init ~owner:Group.Point
           ~name:"missing_subtract" 2 (fun point -> point = 1)) |> get_ok in
  let transfer_rules = Ops.[
    { copy_target_pattern = "weight"; copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_multiply };
    { copy_target_pattern = "weight"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "corner"; copy_target_owner = Copy_target_vertices;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "density";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_subtract };
    { copy_target_pattern = "label"; copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_copy };
    { copy_target_pattern = "gain"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_subtract };
    { copy_target_pattern = "profile"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "disabled";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_copy };
    { copy_target_pattern = "disabled"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_nothing };
    { copy_target_pattern = "union_mask"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "intersect_mask";
      copy_target_owner = Copy_target_vertices;
      copy_target_operation = Copy_target_multiply };
    { copy_target_pattern = "subtract_mask";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_subtract };
    { copy_target_pattern = "copy_mask";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_copy };
    { copy_target_pattern = "missing_multiply";
      copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_multiply };
    { copy_target_pattern = "missing_subtract";
      copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_subtract };
  ] in
  let transferred domains = Parallel.run ~domains (fun () ->
    Ops.copy_to_points ~grain:1 ~target_attributes:transfer_rules
      ~source:transfer_source ~targets:transfer_targets () |> get_ok) in
  let transferred_one = transferred 1 and transferred_many = transferred 4 in
  let transferred_weight = Geometry.find_attribute ~owner:Attribute.Point "weight"
      transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and transferred_weight_many = Geometry.find_attribute ~owner:Attribute.Point
      "weight" transferred_many |> Option.get
      |> Attribute.get (Attribute.key ~name:"weight" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and transferred_corner = Geometry.find_attribute ~owner:Attribute.Vertex
      "corner" transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"corner" ~owner:Attribute.Vertex
           Attribute.int) |> Option.get
  and transferred_density = Geometry.find_attribute ~owner:Attribute.Primitive
      "density" transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"density" ~owner:Attribute.Primitive
           Attribute.float) |> Option.get
  and transferred_label = Geometry.find_attribute ~owner:Attribute.Primitive
      "label" transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"label" ~owner:Attribute.Primitive
           Attribute.text) |> Option.get
  and transferred_gain = Geometry.find_attribute ~owner:Attribute.Point "gain"
      transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"gain" ~owner:Attribute.Point
           Attribute.float) |> Option.get
  and transferred_disabled = Geometry.find_attribute ~owner:Attribute.Point
      "disabled" transferred_one |> Option.get
      |> Attribute.get (Attribute.key ~name:"disabled" ~owner:Attribute.Point
           Attribute.int) |> Option.get in
  let transferred_profile = float_array_values ~owner:Attribute.Point
      ~name:"profile" transferred_one
  and transferred_profile_many = float_array_values ~owner:Attribute.Point
      ~name:"profile" transferred_many in
  let group_members owner name geometry =
    let group = Geometry.find_group ~owner name geometry |> Option.get in
    Array.init (Group.length group) (fun element -> Group.mem element group) in
  if transferred_weight <> [|13.;23.;14.;24.|]
      || transferred_weight <> transferred_weight_many
      || Geometry.find_attribute ~owner:Attribute.Primitive "weight"
           transferred_one <> None
      || transferred_corner <> [|101;102;201;202|]
      || transferred_density <> [|-3.;-5.|]
      || transferred_label <> [|"first";"second"|]
      || transferred_gain <> [|-2.;-2.;-3.;-3.|]
      || transferred_disabled <> [|7;8;7;8|]
      || Geometry.find_attribute ~owner:Attribute.Primitive "disabled"
           transferred_one <> None
      || transferred_profile.offsets <> [|0;2;4;6;8|]
      || transferred_profile.values
           <> [|11.;22.;31.;42.;13.;24.;33.;44.|]
      || transferred_profile.offsets <> transferred_profile_many.offsets
      || transferred_profile.values <> transferred_profile_many.values
      || group_members Group.Point "union_mask" transferred_one
           <> [|true;false;true;true|]
      || group_members Group.Vertex "intersect_mask" transferred_one
           <> [|false;false;true;false|]
      || group_members Group.Primitive "subtract_mask" transferred_one
           <> [|true;false|]
      || group_members Group.Primitive "copy_mask" transferred_one
           <> [|false;true|]
      || group_members Group.Point "missing_multiply" transferred_one
           <> [|false;false;true;true|]
      || group_members Group.Point "missing_subtract" transferred_one
           <> [|false;false;false;false|]
      || List.exists (fun (owner, name) ->
           group_members owner name transferred_one
             <> group_members owner name transferred_many)
           [Group.Point, "union_mask"; Group.Vertex, "intersect_mask";
            Group.Primitive, "subtract_mask"; Group.Primitive, "copy_mask";
            Group.Point, "missing_multiply";
            Group.Point, "missing_subtract"]
      || not (equal_positions transferred_one transferred_many) then
    fail "copy-to-points ordered target attribute transfer/domain behavior";
  let incompatible_source = Geometry.with_attribute
      (Attribute.create_owned ~name:"corner" ~owner:Attribute.Point
        (Attribute.Text [|"a";"b"|]) |> get_ok) transfer_source |> get_ok in
  let incompatible_rule = Ops.{ copy_target_pattern = "corner";
      copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add } in
  (match Ops.copy_to_points ~target_attributes:[incompatible_rule]
      ~source:incompatible_source ~targets:transfer_targets () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted incompatible target arithmetic storage");
  let malformed_rule = Ops.{ copy_target_pattern = "[unterminated";
      copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_copy } in
  (match Ops.copy_to_points ~target_attributes:[malformed_rule]
      ~source:transfer_source ~targets:transfer_targets () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted malformed target attribute pattern");
  let mismatched_profile = Attribute.create_owned ~name:"profile"
      ~owner:Attribute.Point (Attribute.Float_array
        (Packed.Float_array.create_owned ~offsets:[|0;1;2|]
          ~values:[|1.;2.|] |> get_ok)) |> get_ok in
  let mismatched_targets = Geometry.with_attribute mismatched_profile
      transfer_targets |> get_ok in
  let mismatched_rule = Ops.{ copy_target_pattern = "profile";
      copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add } in
  (match Ops.copy_to_points ~target_attributes:[mismatched_rule]
      ~source:transfer_source ~targets:mismatched_targets () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted mismatched target ragged row widths");
  let nonfinite_n = Attribute.create_owned ~name:"N" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|Float.nan|] ~y:[|0.|] ~z:[|1.|])) |> get_ok in
  let invalid_alignment = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute nonfinite_n |> get_ok in
  (match Ops.copy_to_points ~source:prototype ~targets:invalid_alignment () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted a non-finite target N");
  let invalid_rot = Attribute.create_owned ~name:"rot" ~owner:Attribute.Point
      (Attribute.Int [|1|]) |> get_ok in
  let invalid_rot_target = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute invalid_rot |> get_ok in
  (match Ops.copy_to_points ~source:prototype ~targets:invalid_rot_target () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted a non-quaternion target rot");
  let nonfinite_trans = Attribute.create_owned ~name:"trans"
      ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:[|Float.infinity|] ~y:[|0.|] ~z:[|0.|])) |> get_ok in
  let invalid_trans_target = Ops.points [|(0.,0.,0.)|]
      |> Geometry.with_attribute nonfinite_trans |> get_ok in
  (match Ops.copy_to_points ~source:prototype ~targets:invalid_trans_target () with
   | Error error when Error.code error = "invalid_attribute" -> ()
   | _ -> fail "copy-to-points accepted a non-finite target translation");
  let scatter_source = Ops.color_by_height ~low:Color.red ~high:Color.blue sphere
      |> get_ok in
  let scatter domains = Parallel.run ~domains (fun () ->
    Ops.scatter_surface ~grain:97 ~count:10_000 ~seed:123 scatter_source |> get_ok) in
  let scatter_one = scatter 1 and scatter_many = scatter 4 in
  if not (equal_positions scatter_one scatter_many)
     || Geometry.point_count scatter_one <> 10_000
  then fail "surface scatter domain determinism/cardinality";
  if Geometry.find_attribute ~owner:Attribute.Point "N" scatter_one = None
     || Geometry.find_attribute ~owner:Attribute.Point "Cd" scatter_one = None
     || Geometry.find_attribute ~owner:Attribute.Point "id" scatter_one = None
  then fail "surface scatter attributes";
  (* Scale regression: exact packed cardinality and deterministic output at a
     workload large enough to catch accidental list-backed implementations. *)
  let count = 1_000_000 in
  let generated domains = Parallel.run ~domains (fun () ->
    Kernel.generate_points ~grain:16_384 count (fun output index ->
      let value = float_of_int index in
      Kernel.Writer.set output index value (value *. 0.5) (-.value))) in
  let large_one = generated 1 and large_many = generated 4 in
  if Geometry.point_count large_one <> count || not (equal_positions large_one large_many)
  then fail "million-point deterministic scale regression";
  if Geometry.payload_bytes large_one <> (count * 24) + (Sys.word_size / 8) then
    fail "million-point payload estimate";
  let generated_ranges domains = Parallel.run ~domains (fun () ->
    Kernel.generate_point_ranges ~grain:16_384 count
      (fun ~first ~last ~x ~y ~z ->
        for index = first to last - 1 do
          let value = float_of_int index in
          x.(index) <- value; y.(index) <- value *. 0.5; z.(index) <- -.value
        done)) in
  if not (equal_positions (generated_ranges 1) (generated_ranges 4)) then
    fail "million-point deterministic range kernel";
  let displaced domains = Parallel.run ~domains (fun () ->
    Ops.noise_displace ~grain:16_384 ~amplitude:2. ~frequency:0.01 ~seed:71
      large_one |> get_ok) in
  if not (equal_positions (displaced 1) (displaced 4)) then
    fail "noise displacement differs by domain count";
  print_endline "pdk tests passed"
