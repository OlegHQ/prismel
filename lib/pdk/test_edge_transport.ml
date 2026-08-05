open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function Ok value -> value | Error error -> fail (Error.to_string error)

let geometry_owned positions edges values =
  let positions = Array.of_list positions and edge_count = Array.length edges in
  let point_count = Array.length positions in
  let x = Array.map (fun (x,_,_) -> x) positions
  and y = Array.map (fun (_,y,_) -> y) positions
  and z = Array.map (fun (_,_,z) -> z) positions in
  let vertex_points = Array.make (edge_count * 2) 0 in
  Array.iteri (fun edge (a,b) ->
    vertex_points.(edge * 2) <- a; vertex_points.(edge * 2 + 1) <- b) edges;
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (edge_count + 1) (fun edge -> edge * 2))
      ~primitive_kinds:(Array.make edge_count Topology.Open_polyline) |> get_ok in
  let attributes = match values with
    | None -> []
    | Some values -> [Attribute.create_owned ~owner:Attribute.Point ~name:"value"
        (Attribute.Float values) |> get_ok] in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology ~attributes () |> get_ok

let fixture () = geometry_owned
    [0.,0.,0.;1.,0.,0.;0.,2.,0.;2.,0.,0.;1.,3.,0.;10.,0.,0.;14.,0.,0.]
    [|0,1;0,2;1,3;1,4;5,6|]
    (Some [|10.;2.;5.;7.;1.;20.;3.|])

let values name geometry = match Geometry.find_attribute
    ~owner:Attribute.Point name geometry with
  | Some attribute -> (match Attribute.Private.storage attribute with
      | Attribute.Float values -> values | _ -> fail "wrong output storage")
  | None -> fail "missing output attribute"

let with_parent parents geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:"parent"
      (Attribute.Int parents) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let close_array left right = Array.length left = Array.length right
  && Array.for_all2 (fun a b -> abs_float (a -. b) < 1e-9) left right

let group owner name length predicate = Group.init ~grain:1 ~owner ~name length predicate

let expect_code code = function
  | Error error when Error.code error = code -> ()
  | Error error -> fail (Printf.sprintf "expected %s, got %s: %s"
      code (Error.code error) (Error.to_string error))
  | Ok _ -> fail ("expected error " ^ code)

let equal_geometry left right =
  let lv = values "distance" left and rv = values "distance" right in
  lv = rv && Geometry.point_count left = Geometry.point_count right

let long_curve point_count =
  let positions = Array.init point_count (fun point ->
      float_of_int point *. 0.001, sin (float_of_int point *. 0.003) *. 0.02, 0.)
      |> Array.to_list in
  let edges = Array.init (point_count - 1) (fun edge -> edge, edge + 1) in
  geometry_owned positions edges None

let curve_geometry positions vertex_points primitive_offsets primitive_kinds
    attributes =
  let positions = Array.of_list positions in
  let point_count = Array.length positions in
  let x = Array.map (fun (x,_,_) -> x) positions
  and y = Array.map (fun (_,y,_) -> y) positions
  and z = Array.map (fun (_,_,z) -> z) positions in
  let topology = Topology.create_owned ~point_count ~vertex_points
      ~primitive_offsets ~primitive_kinds |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology ~attributes () |> get_ok

let curve_fixture () =
  let point_values = Attribute.create_owned ~owner:Attribute.Point ~name:"value"
      (Attribute.Float [|10.;2.;5.;20.;3.;7.|]) |> get_ok
  and vertex_values = Attribute.create_owned ~owner:Attribute.Vertex
      ~name:"vertex_value" (Attribute.Float [|5.;2.;10.;20.;3.;7.|]) |> get_ok in
  curve_geometry
    [0.,0.,0.;1.,0.,0.;3.,0.,0.;0.,2.,0.;2.,2.,0.;5.,2.,0.]
    [|2;1;0;3;4;5|] [|0;3;6|]
    [|Topology.Open_polyline;Topology.Open_polyline|]
    [point_values;vertex_values]

let many_curves curve_count curve_size =
  let point_count = curve_count * curve_size in
  let positions = Array.init point_count (fun point ->
      let curve = point / curve_size and local = point mod curve_size in
      float_of_int local *. 0.01, float_of_int curve *. 0.002, 0.)
      |> Array.to_list in
  curve_geometry positions (Array.init point_count Fun.id)
    (Array.init (curve_count + 1) (fun curve -> curve * curve_size))
    (Array.make curve_count Topology.Open_polyline) []

let () =
  let source = fixture () in
  let transport = Ops.edge_transport ~attribute:"value" source |> get_pdk in
  check (close_array (values "value" transport)
      [|10.;10.;10.;10.;10.;20.;20.|]) "Edge Transport hold";
  let zero = Ops.edge_transport ~attribute:"value"
      ~root_value:Ops.Transport_root_zero source |> get_pdk in
  check (values "value" zero = Array.make 7 0.) "Edge Transport zero root";
  let from_root = Ops.edge_transport ~attribute:"value"
      ~operation:Ops.Transport_from_root source |> get_pdk in
  check (values "value" from_root = values "value" transport)
    "Edge Transport from root";
  let from_zero = Ops.edge_transport ~attribute:"value"
      ~operation:Ops.Transport_from_root
      ~root_value:Ops.Transport_root_zero source |> get_pdk in
  check (values "value" from_zero = Array.make 7 0.)
    "Edge Transport from-root zero policy";
  let total = Ops.edge_transport ~attribute:"value"
      ~operation:Ops.Transport_total source |> get_pdk in
  check (close_array (values "value" total) [|0.;10.;10.;12.;12.;0.;20.|])
    "Edge Transport total";
  let depth = Ops.edge_transport ~attribute:"depth"
      ~operation:Ops.Transport_total ~integrate_constant:true source |> get_pdk in
  check (close_array (values "depth" depth) [|0.;1.;1.;2.;2.;0.;1.|])
    "Edge Transport constant depth";
  let distance = Ops.edge_transport ~attribute:"distance"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true source |> get_pdk in
  check (close_array (values "distance" distance) [|0.;1.;2.;2.;4.;0.;4.|])
    "Edge Transport distance";
  let maximum = Ops.edge_transport ~attribute:"value"
      ~operation:Ops.Transport_maximum source |> get_pdk in
  check (close_array (values "value" maximum) [|10.;10.;10.;10.;10.;20.;20.|])
    "Edge Transport maximum";
  let minimum = Ops.edge_transport ~attribute:"value"
      ~operation:Ops.Transport_minimum source |> get_pdk in
  check (close_array (values "value" minimum) [|10.;2.;5.;2.;1.;20.;3.|])
    "Edge Transport minimum";
  let split = Ops.edge_transport ~attribute:"value"
      ~split:Ops.Transport_split source |> get_pdk in
  check (close_array (values "value" split)
      [|10.;5.;5.;2.5;2.5;20.;20.|]) "Edge Transport split";
  let backward merge = Ops.edge_transport ~attribute:"value"
      ~direction:Ops.Transport_backward ~merge source |> get_pdk
      |> values "value" in
  check (backward Ops.Transport_merge_add = [|13.;8.;5.;7.;1.;3.;3.|])
    "Edge Transport backward add";
  check (backward Ops.Transport_merge_maximum = [|7.;7.;5.;7.;1.;3.;3.|])
    "Edge Transport backward maximum merge";
  check (backward Ops.Transport_merge_minimum = [|1.;1.;5.;7.;1.;3.;3.|])
    "Edge Transport backward minimum merge";
  let backward_zero = Ops.edge_transport ~attribute:"value"
      ~direction:Ops.Transport_backward ~root_value:Ops.Transport_root_zero
      source |> get_pdk in
  check (values "value" backward_zero = Array.make 7 0.)
    "Edge Transport backward zero leaves";
  let backward_total = Ops.edge_transport ~attribute:"depth"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true ~merge:Ops.Transport_merge_add source |> get_pdk in
  check (values "depth" backward_total = [|4.;2.;0.;0.;0.;1.;0.|])
    "Edge Transport backward total";
  let backward_distance = Ops.edge_transport ~attribute:"distance"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true ~scale_by_edge_length:true
      ~merge:Ops.Transport_merge_add source |> get_pdk in
  check (close_array (values "distance" backward_distance)
      [|7.;4.;0.;0.;0.;4.;0.|]) "Edge Transport backward distance";
  let backward_max = Ops.edge_transport ~attribute:"value"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_maximum
      ~merge:Ops.Transport_merge_maximum source |> get_pdk in
  let backward_min = Ops.edge_transport ~attribute:"value"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_minimum
      ~merge:Ops.Transport_merge_minimum source |> get_pdk in
  check (values "value" backward_max = [|10.;7.;5.;7.;1.;20.;3.|]
      && values "value" backward_min = [|1.;1.;5.;7.;1.;3.;3.|])
    "Edge Transport backward extrema";
  let normalized = Ops.edge_transport ~attribute:"depth"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~normalization:Ops.Transport_normalize_global source |> get_pdk in
  check (close_array (values "depth" normalized)
      [|0.;0.5;0.5;1.;1.;0.;0.5|]) "Edge Transport global normalization";
  let normalized = Ops.edge_transport ~attribute:"depth"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~normalization:Ops.Transport_normalize_components source |> get_pdk in
  check (close_array (values "depth" normalized)
      [|0.;0.5;0.5;1.;1.;0.;1.|]) "Edge Transport component normalization";

  let roots = group Group.Point "roots" 7 (fun point -> point = 2) in
  let rooted = Ops.edge_transport ~attribute:"value"
      ~roots:(Ops.Transport_root_group roots) source |> get_pdk in
  check (close_array (values "value" rooted) [|5.;5.;5.;5.;5.;20.;3.|])
    "Edge Transport explicit roots or unreachable preservation";
  let no_roots = group Group.Point "no_roots" 7 (Fun.const false) in
  let unrooted = Ops.edge_transport ~attribute:"value"
      ~roots:(Ops.Transport_root_group no_roots) source |> get_pdk in
  check (unrooted == source) "Edge Transport empty roots were not identity";
  let selected = group Group.Point "path" 7 (fun point ->
      point = 0 || point = 1 || point = 3) in
  let restricted = Ops.edge_transport ~attribute:"value" ~points:selected source
      |> get_pdk in
  check (close_array (values "value" restricted)
      [|10.;10.;5.;10.;1.;20.;3.|]) "Edge Transport point restriction";
  let last = Ops.edge_transport ~attribute:"value"
      ~roots:Ops.Transport_last_point source |> get_pdk in
  check ((values "value" last).(0) = 1. && (values "value" last).(6) = 3.)
    "Edge Transport last-point roots";
  check (Geometry.topology distance == Geometry.topology source)
    "Edge Transport rebuilt topology";
  let missing = Ops.edge_transport ~attribute:"missing" source |> get_pdk in
  check (missing == source) "Edge Transport missing attribute was not identity";

  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"P" source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value" ~integrate_constant:true source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value" ~scale_by_edge_length:true source);
  let wrong = group Group.Primitive "wrong" 5 (Fun.const true) in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value" ~points:wrong source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value"
       ~roots:(Ops.Transport_root_group wrong) source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~grain:0 ~attribute:"value" source);
  let integer_attribute = Attribute.create_owned ~owner:Attribute.Point
      ~name:"integer" (Attribute.Int (Array.make 7 1)) |> get_ok in
  let integer_source = Geometry.with_attribute integer_attribute source |> get_ok in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"integer" integer_source);
  let non_finite = geometry_owned [0.,0.,0.;nan,0.,0.] [|0,1|]
      (Some [|1.;2.|]) in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value" non_finite);
  let long_edge = Float.max_float *. 0.6 in
  let overflow_path = geometry_owned
      [0.,0.,0.;long_edge,0.,0.;0.,0.,0.;long_edge,0.,0.]
      [|0,1;1,2;2,3|] (Some [|1.;1.;1.;1.|]) in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport ~attribute:"value" ~operation:Ops.Transport_total
       ~scale_by_edge_length:true overflow_path);
  let cancelled = Cancel.create () in Cancel.cancel cancelled;
  expect_code "cancelled"
    (Ops.edge_transport ~cancel:cancelled ~attribute:"value" source);

  let large = long_curve 100_000 in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.edge_transport ~grain:127 ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true large |> get_pdk) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "Edge Transport differs across domain counts";
  check (Geometry.point_count one = 100_000
      && Geometry.primitive_count one = 99_999)
    "Edge Transport scale cardinality";
  let backward_scale = many_curves 10_000 10 in
  let run_backward domains = Parallel.run ~domains (fun () ->
      Ops.edge_transport ~grain:127 ~attribute:"depth"
        ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
        ~integrate_constant:true ~merge:Ops.Transport_merge_add backward_scale
        |> get_pdk) in
  let backward_one = run_backward 1 and backward_four = run_backward 4 in
  check (values "depth" backward_one = values "depth" backward_four)
    "Edge Transport backward differs across domain counts";

  let curves = curve_fixture () in
  let curve_transport = Ops.edge_transport_curves ~attribute:"value" curves
      |> get_pdk in
  check (close_array (values "value" curve_transport)
      [|10.;10.;10.;20.;20.;20.|]) "Edge Transport Each Curve direction";
  let curve_zero = Ops.edge_transport_curves ~attribute:"value"
      ~operation:Ops.Transport_from_root ~root_value:Ops.Transport_root_zero
      curves |> get_pdk in
  check (values "value" curve_zero = Array.make 6 0.)
    "Edge Transport Each Curve root zero";
  let curve_distance = Ops.edge_transport_curves ~attribute:"distance"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true curves |> get_pdk in
  check (close_array (values "distance" curve_distance)
      [|0.;1.;3.;0.;2.;5.|]) "Edge Transport Each Curve distance";
  let curve_reverse = Ops.edge_transport_curves ~attribute:"distance"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true ~scale_by_edge_length:true curves |> get_pdk in
  check (close_array (values "distance" curve_reverse)
      [|3.;2.;0.;5.;3.;0.|]) "Edge Transport Each Curve backward";
  let curve_maximum = Ops.edge_transport_curves ~attribute:"value"
      ~operation:Ops.Transport_maximum curves |> get_pdk in
  let curve_minimum = Ops.edge_transport_curves ~attribute:"value"
      ~operation:Ops.Transport_minimum curves |> get_pdk in
  check (values "value" curve_maximum = [|10.;10.;10.;20.;20.;20.|]
      && values "value" curve_minimum = [|10.;2.;2.;20.;3.;3.|])
    "Edge Transport Each Curve extrema";
  let curve_components = Ops.edge_transport_curves ~attribute:"distance"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true
      ~normalization:Ops.Transport_normalize_components curves |> get_pdk in
  check (close_array (values "distance" curve_components)
      [|0.;1. /. 3.;1.;0.;0.4;1.|])
    "Edge Transport Each Curve component normalization";
  let curve_global = Ops.edge_transport_curves ~attribute:"distance"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true
      ~normalization:Ops.Transport_normalize_global curves |> get_pdk in
  check (close_array (values "distance" curve_global)
      [|0.;0.2;0.6;0.;0.4;1.|])
    "Edge Transport Each Curve global normalization";
  let vertex_transport = Ops.edge_transport_curves ~owner:Attribute.Vertex
      ~attribute:"vertex_value" curves |> get_pdk in
  check (match Geometry.find_attribute ~owner:Attribute.Vertex "vertex_value"
      vertex_transport with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float values -> values = [|10.;10.;10.;20.;20.;20.|]
        | _ -> false)
    | None -> false) "Edge Transport Each Curve vertex field";
  let first_curve = group Group.Primitive "first_curve" 2 ((=) 0) in
  let restricted_curve = Ops.edge_transport_curves ~primitives:first_curve
      ~attribute:"value" curves |> get_pdk in
  check (values "value" restricted_curve = [|10.;10.;10.;20.;3.;7.|])
    "Edge Transport Each Curve primitive restriction";
  let closed = curve_geometry
      [0.,0.,0.;1.,0.,0.;1.,1.,0.;0.,1.,0.] [|2;0;3;1|] [|0;4|]
      [|Topology.Closed_polyline|] [] in
  let closed_forward = Ops.edge_transport_curves ~attribute:"depth"
      ~operation:Ops.Transport_total ~integrate_constant:true closed |> get_pdk in
  let closed_backward = Ops.edge_transport_curves ~attribute:"depth"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true closed |> get_pdk in
  check (values "depth" closed_forward = [|0.;2.;1.;3.|]
      && values "depth" closed_backward = [|0.;2.;3.;1.|])
    "Edge Transport Each Curve closed seam and direction";
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~attribute:"value" source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~owner:Attribute.Primitive ~attribute:"value"
       curves);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~grain:0 ~attribute:"value" curves);
  let integer_attribute = Attribute.create_owned ~owner:Attribute.Point
      ~name:"integer" (Attribute.Int (Array.make 6 1)) |> get_ok in
  let integer_curves = Geometry.with_attribute integer_attribute curves |> get_ok in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~attribute:"integer" integer_curves);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~primitives:wrong ~attribute:"value" curves);
  let non_finite_curve = curve_geometry [0.,0.,0.;nan,0.,0.] [|0;1|]
      [|0;2|] [|Topology.Open_polyline|] [] in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_curves ~attribute:"distance"
       ~operation:Ops.Transport_total ~integrate_constant:true
       ~scale_by_edge_length:true non_finite_curve);
  let cancelled = Cancel.create () in Cancel.cancel cancelled;
  expect_code "cancelled"
    (Ops.edge_transport_curves ~cancel:cancelled ~attribute:"value" curves);
  let large_curves = many_curves 10_000 10 in
  let run_curves domains = Parallel.run ~domains (fun () ->
      Ops.edge_transport_curves ~grain:127 ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true large_curves |> get_pdk) in
  let curve_one = run_curves 1 and curve_four = run_curves 4 in
  check (equal_geometry curve_one curve_four)
    "Edge Transport Each Curve differs across domain counts";
  check (Geometry.point_count curve_one = 100_000
      && Geometry.primitive_count curve_one = 10_000)
    "Edge Transport Each Curve scale cardinality";

  let parent_source = with_parent [|0;0;0;1;1;5;5|] source in
  let parent_transport = Ops.edge_transport_parent ~attribute:"value"
      parent_source |> get_pdk in
  check (values "value" parent_transport
      = [|10.;10.;10.;10.;10.;20.;20.|])
    "Edge Transport Parent forward transport";
  let parent_zero = Ops.edge_transport_parent ~attribute:"value"
      ~operation:Ops.Transport_from_root
      ~root_value:Ops.Transport_root_zero parent_source |> get_pdk in
  check (values "value" parent_zero = Array.make 7 0.)
    "Edge Transport Parent from-root zero";
  let parent_total = Ops.edge_transport_parent ~attribute:"value"
      ~operation:Ops.Transport_total parent_source |> get_pdk in
  check (values "value" parent_total = [|0.;10.;10.;12.;12.;0.;20.|])
    "Edge Transport Parent total";
  let parent_distance = Ops.edge_transport_parent ~attribute:"distance"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~scale_by_edge_length:true parent_source |> get_pdk in
  check (close_array (values "distance" parent_distance)
      [|0.;1.;2.;2.;4.;0.;4.|]) "Edge Transport Parent distance";
  let parent_maximum = Ops.edge_transport_parent ~attribute:"value"
      ~operation:Ops.Transport_maximum parent_source |> get_pdk in
  let parent_minimum = Ops.edge_transport_parent ~attribute:"value"
      ~operation:Ops.Transport_minimum parent_source |> get_pdk in
  check (values "value" parent_maximum
      = [|10.;10.;10.;10.;10.;20.;20.|]
      && values "value" parent_minimum = [|10.;2.;5.;2.;1.;20.;3.|])
    "Edge Transport Parent forward extrema";
  let parent_split = Ops.edge_transport_parent ~attribute:"value"
      ~split:Ops.Transport_split parent_source |> get_pdk in
  check (close_array (values "value" parent_split)
      [|10.;5.;5.;2.5;2.5;20.;20.|]) "Edge Transport Parent split";
  let parent_components = Ops.edge_transport_parent ~attribute:"depth"
      ~operation:Ops.Transport_total ~integrate_constant:true
      ~normalization:Ops.Transport_normalize_components parent_source |> get_pdk in
  check (close_array (values "depth" parent_components)
      [|0.;0.5;0.5;1.;1.;0.;1.|])
    "Edge Transport Parent component normalization";

  let backward merge = Ops.edge_transport_parent ~attribute:"value"
      ~direction:Ops.Transport_backward ~merge parent_source |> get_pdk
      |> values "value" in
  check (backward Ops.Transport_merge_add = [|13.;8.;5.;7.;1.;3.;3.|])
    "Edge Transport Parent backward add";
  check (backward Ops.Transport_merge_maximum = [|7.;7.;5.;7.;1.;3.;3.|])
    "Edge Transport Parent backward maximum merge";
  check (backward Ops.Transport_merge_minimum = [|1.;1.;5.;7.;1.;3.;3.|])
    "Edge Transport Parent backward minimum merge";
  let backward_total = Ops.edge_transport_parent ~attribute:"depth"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true ~merge:Ops.Transport_merge_add parent_source
      |> get_pdk in
  check (values "depth" backward_total = [|4.;2.;0.;0.;0.;1.;0.|])
    "Edge Transport Parent backward total";
  let backward_distance = Ops.edge_transport_parent ~attribute:"distance"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
      ~integrate_constant:true ~scale_by_edge_length:true
      ~merge:Ops.Transport_merge_add parent_source |> get_pdk in
  check (close_array (values "distance" backward_distance)
      [|7.;4.;0.;0.;0.;4.;0.|])
    "Edge Transport Parent backward distance";
  let backward_max = Ops.edge_transport_parent ~attribute:"value"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_maximum
      ~merge:Ops.Transport_merge_maximum parent_source |> get_pdk in
  let backward_min = Ops.edge_transport_parent ~attribute:"value"
      ~direction:Ops.Transport_backward ~operation:Ops.Transport_minimum
      ~merge:Ops.Transport_merge_minimum parent_source |> get_pdk in
  check (values "value" backward_max = [|10.;7.;5.;7.;1.;20.;3.|]
      && values "value" backward_min = [|1.;1.;5.;7.;1.;3.;3.|])
    "Edge Transport Parent backward extrema";
  check (Geometry.topology parent_distance == Geometry.topology parent_source)
    "Edge Transport Parent rebuilt topology";

  let cycle_source = with_parent [|1;0;0;1;1;5;5|] source in
  let cycle_output = Ops.edge_transport_parent ~attribute:"value" cycle_source
      |> get_pdk in
  check (values "value" cycle_output = [|10.;2.;5.;7.;1.;20.;20.|])
    "Edge Transport Parent did not preserve unreachable cycle";
  let restricted_parent = Ops.edge_transport_parent ~points:selected
      ~attribute:"value" parent_source |> get_pdk in
  check (values "value" restricted_parent = [|10.;10.;5.;10.;1.;20.;3.|])
    "Edge Transport Parent point restriction";
  let missing_parent = Geometry.without_attribute ~owner:Attribute.Point
      "parent" parent_source in
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_parent ~attribute:"value" missing_parent);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_parent ~parent_attribute:"value" ~attribute:"value"
       parent_source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_parent ~points:wrong ~attribute:"value" parent_source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_parent ~grain:0 ~attribute:"value" parent_source);
  expect_code "invalid_edge_transport"
    (Ops.edge_transport_parent ~parent_attribute:" " ~attribute:"value"
       parent_source);
  let cancelled = Cancel.create () in Cancel.cancel cancelled;
  expect_code "cancelled"
    (Ops.edge_transport_parent ~cancel:cancelled ~attribute:"value"
       parent_source);

  let parent_scale = many_curves 10_000 10 in
  let parents = Array.init 100_000 (fun point ->
      if point mod 10 = 0 then point else point - 1) in
  let parent_scale = with_parent parents parent_scale in
  let run_parent domains = Parallel.run ~domains (fun () ->
      Ops.edge_transport_parent ~grain:127 ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true parent_scale |> get_pdk) in
  let parent_one = run_parent 1 and parent_four = run_parent 4 in
  check (equal_geometry parent_one parent_four)
    "Edge Transport Parent differs across domain counts";
  check (Geometry.point_count parent_one = 100_000
      && Geometry.primitive_count parent_one = 10_000)
    "Edge Transport Parent scale cardinality";
  print_endline "edge transport tests passed"
