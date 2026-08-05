open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let attribute_storage_equal left right =
  match Attribute.Private.storage left, Attribute.Private.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Text left, Attribute.Text right -> left = right
  | Attribute.Float2 left, Attribute.Float2 right ->
      let left = Packed.Float2.Private.view left
      and right = Packed.Float2.Private.view right in
      left.x = right.x && left.y = right.y
  | Attribute.Float3 left, Attribute.Float3 right ->
      let left = Packed.Float3.Private.view left
      and right = Packed.Float3.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
  | Attribute.Float4 left, Attribute.Float4 right ->
      let left = Packed.Float4.Private.view left
      and right = Packed.Float4.Private.view right in
      left.x = right.x && left.y = right.y && left.z = right.z
      && left.w = right.w
  | _ -> false

let geometry_equal left right =
  let lp = Packed.Float3.Private.view (Geometry.positions left)
  and rp = Packed.Float3.Private.view (Geometry.positions right)
  and lt = Topology.Private.view (Geometry.topology left)
  and rt = Topology.Private.view (Geometry.topology right) in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal (fun left right ->
      Attribute.owner left = Attribute.owner right
      && String.equal (Attribute.name left) (Attribute.name right)
      && attribute_storage_equal left right)
      (Geometry.attributes left) (Geometry.attributes right)
  && List.equal (fun left right ->
      Group.owner left = Group.owner right
      && String.equal (Group.name left) (Group.name right)
      && Group.length left = Group.length right
      && Group.ordered_elements left = Group.ordered_elements right
      && let equal = ref true in
         for index = 0 to Group.length left - 1 do
           if Group.mem index left <> Group.mem index right then equal := false
         done;
         !equal) (Geometry.groups left) (Geometry.groups right)
  && List.equal (fun left right ->
      String.equal (Edge_group.name left) (Edge_group.name right)
      && Edge_group.length left = Edge_group.length right
      && let equal = ref true in
         for edge = 0 to Edge_group.length left - 1 do
           if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
         done;
         !equal) (Geometry.edge_groups left) (Geometry.edge_groups right)

let add_attribute attribute geometry =
  Geometry.with_attribute attribute geometry |> get_ok

let enriched_grid () =
  let geometry = Ops.grid ~columns:1 ~rows:1 ~size:2. () |> get_pdk in
  let point_id = Attribute.create_owned ~name:"point_id" ~owner:Attribute.Point
      (Attribute.Int [|0; 1; 2; 3|]) |> get_ok
  and vertex_value = Attribute.create_owned ~name:"vertex_value"
      ~owner:Attribute.Vertex
      (Attribute.Float [|0.; 1.; 2.; 3.; 4.; 5.|]) |> get_ok
  and primitive_id = Attribute.create_owned ~name:"primitive_id"
      ~owner:Attribute.Primitive (Attribute.Int [|10; 20|]) |> get_ok
  and detail = Attribute.create_owned ~name:"label" ~owner:Attribute.Detail
      (Attribute.Text [|"grid"|]) |> get_ok in
  let point_group = Group.init ~owner:Group.Point ~name:"corner" 4
      (fun point -> point = 0)
  and primitive_group = Group.init ~owner:Group.Primitive ~name:"first_face" 2
      (fun primitive -> primitive = 0) in
  geometry |> add_attribute point_id |> add_attribute vertex_value
  |> add_attribute primitive_id |> add_attribute detail
  |> Geometry.with_group point_group |> get_ok
  |> Geometry.with_group primitive_group |> get_ok
  |> Ops.group_edges ~name:"source_edges" |> get_pdk

let group_cardinality owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> Group.cardinality group
  | None -> fail ("missing group " ^ name)

let edge_cardinality name geometry =
  match Geometry.find_edge_group name geometry with
  | Some group -> Edge_group.cardinality group
  | None -> fail ("missing edge group " ^ name)

let int_attribute owner name geometry =
  Geometry.find_attribute ~owner name geometry |> Option.get
  |> Attribute.get (Attribute.key ~name ~owner Attribute.int) |> Option.get

let () =
  let source = enriched_grid () in
  let connected = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components
      ~front_group:"front" ~back_group:"back" ~side_group:"side"
      ~front_boundary_group:"front_boundary"
      ~back_boundary_group:"back_boundary"
      ~distance:1. source |> get_pdk in
  check (Geometry.point_count connected = 8
      && Geometry.vertex_count connected = 28
      && Geometry.primitive_count connected = 8)
    "connected Poly Extrude cardinality";
  check (group_cardinality Group.Primitive "front" connected = 2
      && group_cardinality Group.Primitive "back" connected = 2
      && group_cardinality Group.Primitive "side" connected = 4)
    "connected Poly Extrude output groups";
  check (edge_cardinality "front_boundary" connected = 4
      && edge_cardinality "back_boundary" connected = 4)
    "connected Poly Extrude boundary groups";
  check (edge_cardinality "source_edges" connected = 10)
    "connected Poly Extrude source edge propagation";
  check (group_cardinality Group.Point "corner" connected = 2
      && group_cardinality Group.Primitive "first_face" connected = 4)
    "connected Poly Extrude ordinary group ancestry";
  let point_ids = int_attribute Attribute.Point "point_id" connected
  and primitive_ids = int_attribute Attribute.Primitive "primitive_id" connected in
  check (Array.length point_ids = 8 && Array.length primitive_ids = 8
      && Array.for_all (fun value -> value = 10 || value = 20) primitive_ids)
    "connected Poly Extrude attribute ancestry";
  let positions = Packed.Float3.Private.view (Geometry.positions connected) in
  for point = 4 to 7 do
    check (abs_float (abs_float positions.y.(point) -. 1.) <= 1e-12)
      "connected Poly Extrude distance"
  done;
  check (Geometry.find_attribute ~owner:Attribute.Detail "label" connected <> None)
    "connected Poly Extrude dropped detail attribute";

  let divided = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~divisions:3
      ~front_group:"surface" ~side_group:"surface"
      ~front_boundary_group:"rim" ~back_boundary_group:"rim"
      ~distance:1. source |> get_pdk in
  check (Geometry.point_count divided = 16
      && Geometry.vertex_count divided = 60
      && Geometry.primitive_count divided = 16)
    "divided connected Poly Extrude cardinality";
  check (group_cardinality Group.Primitive "surface" divided = 14
      && edge_cardinality "rim" divided = 8)
    "Poly Extrude same-name output-group union";
  check (group_cardinality Group.Point "corner" divided = 4)
    "divided Poly Extrude point-group replication";
  let divided_positions = Packed.Float3.Private.view
      (Geometry.positions divided) in
  for association = 0 to 3 do
    let first = 4 + (association * 3) in
    check (abs_float (abs_float divided_positions.y.(first) -. (1. /. 3.))
        <= 1e-12
        && abs_float (abs_float divided_positions.y.(first + 1) -. (2. /. 3.))
           <= 1e-12
        && abs_float (abs_float divided_positions.y.(first + 2) -. 1.)
           <= 1e-12)
      "Poly Extrude division spacing"
  done;

  let one_face = Group.init ~owner:Group.Primitive ~name:"selected" 2
      (fun primitive -> primitive = 0) in
  let selected_source = Geometry.with_group one_face source |> get_ok in
  let selected = Ops.poly_extrude ~primitives:one_face
      ~divide:Ops.Extrude_connected_components ~front_group:"selected_front"
      ~distance:0.5 selected_source |> get_pdk in
  check (Geometry.point_count selected = 7
      && Geometry.vertex_count selected = 21
      && Geometry.primitive_count selected = 6
      && group_cardinality Group.Primitive "selected_front" selected = 1)
    "selected connected Poly Extrude cardinality";

  let without_back = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~output_back:false
      ~distance:1. source |> get_pdk
  and without_front = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~output_front:false
      ~distance:1. source |> get_pdk
  and without_sides = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~output_side:false
      ~distance:1. source |> get_pdk
  and only_back = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~output_front:false
      ~output_side:false ~back_group:"only_back" ~distance:1. source |> get_pdk
  and no_outputs = Ops.poly_extrude
      ~divide:Ops.Extrude_connected_components ~output_front:false
      ~output_back:false ~output_side:false ~distance:1. source |> get_pdk in
  check (Geometry.primitive_count without_back = 6
      && Geometry.primitive_count without_front = 6
      && Geometry.primitive_count without_sides = 4
      && Geometry.primitive_count only_back = 2
      && group_cardinality Group.Primitive "only_back" only_back = 2
      && Geometry.primitive_count no_outputs = 0)
    "Poly Extrude output geometry switches";

  let source_index = Topology_index.create (Geometry.topology source) in
  let internal_edge = ref (-1) in
  for edge = 0 to Topology_index.edge_count source_index - 1 do
    if Topology_index.edge_incidence_count source_index edge = 2 then
      internal_edge := edge
  done;
  check (!internal_edge >= 0) "split fixture missing internal edge";
  let split_builder = Edge_group.Builder.create ~topology:(Geometry.topology source)
      ~index:source_index ~name:"split" in
  Edge_group.Builder.set split_builder !internal_edge true;
  let split_group = Edge_group.Builder.freeze split_builder in
  let split_source = Geometry.with_edge_group split_group source |> get_ok in
  let split = Ops.poly_extrude ~split_edges:split_group
      ~divide:Ops.Extrude_connected_components ~distance:1. split_source
      |> get_pdk in
  check (Geometry.point_count split = 10
      && Geometry.vertex_count split = 36
      && Geometry.primitive_count split = 10)
    "split-edge Poly Extrude component separation";

  let mixed_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|-1.; 1.; -1.; 1.; 3.; 4.|] ~y:[|0.; 0.; 0.; 0.; 0.; 0.|]
      ~z:[|-1.; -1.; 1.; 1.; 0.; 0.|] in
  let mixed_topology = Topology.create_owned ~point_count:6
      ~vertex_points:[|0; 1; 3; 0; 3; 2; 4; 5|]
      ~primitive_offsets:[|0; 3; 6; 8|]
      ~primitive_kinds:[|Topology.Polygon; Topology.Polygon;
        Topology.Open_polyline|] |> get_ok in
  let mixed = Geometry.create ~positions:mixed_positions ~topology:mixed_topology ()
      |> get_ok in
  let polygon_selection = Group.init ~owner:Group.Primitive ~name:"polygons"
      (Geometry.primitive_count mixed) (fun primitive -> primitive < 2) in
  let mixed = Geometry.with_group polygon_selection mixed |> get_ok in
  let mixed_output = Ops.poly_extrude ~primitives:polygon_selection
      ~divide:Ops.Extrude_connected_components ~distance:1. mixed |> get_pdk in
  check (Geometry.primitive_count mixed_output = 9
      && Array.exists (fun primitive ->
        Topology.primitive_kind (Geometry.topology mixed_output) primitive
          = Topology.Open_polyline)
        (Array.init (Geometry.primitive_count mixed_output) Fun.id))
    "Poly Extrude did not preserve an unselected curve";
  let curve_selection = Group.init ~owner:Group.Primitive ~name:"curve"
      (Geometry.primitive_count mixed) (fun primitive -> primitive = 2) in
  (match Ops.poly_extrude ~primitives:curve_selection
      ~divide:Ops.Extrude_connected_components ~distance:1. mixed with
   | Error error -> check (Error.code error = "invalid_geometry")
       "selected-curve Poly Extrude diagnostic"
   | Ok _ -> fail "Poly Extrude accepted a selected curve");

  let non_manifold_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 0.; 0.; 0.|] ~y:[|0.; 0.; 1.; -1.; 0.|]
      ~z:[|0.; 0.; 0.; 0.; 1.|] in
  let non_manifold_topology = Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2; 1;0;3; 0;1;4|]
      ~primitive_offsets:[|0;3;6;9|] |> get_ok in
  let non_manifold = Geometry.create ~positions:non_manifold_positions
      ~topology:non_manifold_topology () |> get_ok in
  (match Ops.poly_extrude ~divide:Ops.Extrude_connected_components
      ~distance:1. non_manifold with
   | Error error -> check (Error.code error = "invalid_geometry")
       "non-manifold Poly Extrude diagnostic"
   | Ok _ -> fail "connected Poly Extrude accepted a non-manifold edge");

  let wrong_owner = Group.init ~owner:Group.Point ~name:"wrong" 4
      (fun _ -> true) in
  (match Ops.poly_extrude ~primitives:wrong_owner
      ~divide:Ops.Extrude_connected_components ~distance:1. source with
   | Error error -> check (Error.code error = "invalid_geometry")
       "Poly Extrude wrong-owner diagnostic"
   | Ok _ -> fail "Poly Extrude accepted a point selection");
  (match Ops.poly_extrude ~divide:Ops.Extrude_connected_components
      ~divisions:0 ~distance:1. source with
   | Error error -> check (Error.code error = "invalid_geometry")
       "Poly Extrude divisions diagnostic"
   | Ok _ -> fail "Poly Extrude accepted zero divisions");
  (match Ops.poly_extrude ~divide:Ops.Extrude_connected_components
      ~front_group:"" ~distance:1. source with
   | Error error -> check (Error.code error = "invalid_geometry")
       "Poly Extrude output-name diagnostic"
   | Ok _ -> fail "Poly Extrude accepted an empty output name");
  (match Ops.poly_extrude ~divide:Ops.Extrude_individual
      ~split_edges:split_group ~distance:1. split_source with
   | Error error -> check (Error.code error = "invalid_geometry")
       "Poly Extrude split-mode diagnostic"
   | Ok _ -> fail "individual Poly Extrude accepted split edges");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.poly_extrude ~cancel:cancelled
      ~divide:Ops.Extrude_connected_components ~distance:1. source with
   | Error error -> check (Error.code error = "cancelled")
       "Poly Extrude cancellation diagnostic"
   | Ok _ -> fail "cancelled Poly Extrude published geometry");

  let dense = Ops.grid ~columns:320 ~rows:240 ~size:20. () |> get_pdk in
  let dense = dense
      |> Geometry.with_attribute (Attribute.create_owned ~name:"id"
           ~owner:Attribute.Point
           (Attribute.Int (Array.init (Geometry.point_count dense) Fun.id))
           |> get_ok) |> get_ok
      |> Ops.group_edges ~name:"dense_edges" |> get_pdk in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.poly_extrude ~grain:257
        ~divide:Ops.Extrude_connected_components ~divisions:4
        ~front_group:"front" ~side_group:"side"
        ~front_boundary_group:"front_boundary"
        ~back_boundary_group:"back_boundary" ~distance:0.75 dense |> get_pdk) in
  let one = run 1 and many = run 4 in
  check (geometry_equal one many)
    "connected Poly Extrude differs across domain counts";
  check (Geometry.point_count one = (321 * 241 * 5)
      && group_cardinality Group.Primitive "front" one = 320 * 240 * 2
      && group_cardinality Group.Primitive "side" one = (320 + 240) * 2 * 4)
    "connected Poly Extrude scale cardinality";
  print_endline "poly extrude tests passed"
