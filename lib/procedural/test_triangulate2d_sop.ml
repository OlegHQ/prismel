open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop at = at + String.length pattern <= String.length text
      && (String.sub text at (String.length pattern) = pattern || loop (at + 1)) in
  pattern = "" || loop 0

let input () =
  let geometry = Pdk.Ops.points
      [|0.,0.,0.; 1.,0.,1.; 1.,1.,3.; 0.,1.,2.; 4.,4.,12.|] in
  let group = Pdk.Group.ordered ~owner:Pdk.Group.Point ~name:"square" ~length:5
      [|0;1;2;3|] |> Result.get_ok in
  Pdk.Geometry.with_group group geometry |> Result.get_ok

let cook domains node =
  let session = Session.create ~max_entries:4 ~max_payload_bytes:10_000_000 |> get in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:2 () |> get in
    match Session.cook session ~context node with
    | Ok output -> output.Session.geometry
    | Error error -> fail (Diagnostic.error_to_string error))

let signature geometry =
  let topology = Pdk.Topology.Private.view (Pdk.Geometry.topology geometry) in
  Array.copy topology.vertex_points,Array.copy topology.primitive_offsets

let () =
  let source = Sop.snapshot (input ()) in
  let node = Sop.triangulate_2d ~label:"planar"
      ~point_group:"square" ~projection:Pdk.Ops.Triangulate_2d_best_fit
      ~seed:37L ~triangle_group:"triangles" source in
  check (Node.operation node = "triangulate_2d" && Node.version node = 11
      && contains (Node.parameters node) "point_group=square"
      && contains (Node.parameters node) "constraint_edge_group="
      && contains (Node.parameters node) "constraint_primitive_group="
      && contains (Node.parameters node) "projection=best_fit"
      && contains (Node.parameters node) "seed=37"
      && contains (Node.parameters node) "split_crossing_constraints=false"
      && contains (Node.parameters node) "flood_from_hull_boundary=false"
      && contains (Node.parameters node)
        "remove_outside_constraint_polygons=false"
      && contains (Node.parameters node) "silhouette_constraints=false"
      && contains (Node.parameters node) "remove_outside_silhouette=false"
      && contains (Node.parameters node) "ignore_non_constraint_points=false"
      && contains (Node.parameters node) "remove_duplicate_points=false"
      && contains (Node.parameters node) "refine=false"
      && contains (Node.parameters node) "allow_constraint_splitting=true"
      && contains (Node.parameters node) "minimum_angle="
      && contains (Node.parameters node) "maximum_area=none"
      && contains (Node.parameters node) "target_edge_length=none"
      && contains (Node.parameters node) "minimum_edge_length="
      && contains (Node.parameters node) "maximum_new_points=100000"
      && contains (Node.parameters node) "regularization_steps=0"
      && contains (Node.parameters node)
        "allow_movement_of_interior_input_points=false"
      && contains (Node.parameters node) "keep_primitives=false"
      && contains (Node.parameters node) "remove_unused_points=false"
      && contains (Node.parameters node) "recompute_point_normals=false"
      && contains (Node.parameters node) "split_point_group="
      && contains (Node.parameters node) "refinement_point_group="
      && contains (Node.parameters node) "triangle_group=triangles")
    "Triangulate 2D node identity omits behavior";
  let one = cook 1 node and four = cook 4 node in
  check (signature one = signature four) "Triangulate 2D domain result differs";
  check (Pdk.Geometry.primitive_count one = 2)
    "Triangulate 2D point selection cardinality";
  let kept_source =
    let positions = Pdk.Packed.Float3.Private.of_owned_exn
        ~x:[|0.;2.;2.;0.|] ~y:[|0.;0.;2.;2.|] ~z:[|0.;0.;0.;0.|] in
    let topology = Pdk.Topology.polygons_owned ~point_count:4
        ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
        |> Result.get_ok in
    Pdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let kept_node = Sop.snapshot kept_source |> Sop.triangulate_2d
      ~projection:Pdk.Ops.Triangulate_2d_xy ~keep_primitives:true
      ~triangle_group:"generated" in
  check (contains (Node.parameters kept_node) "keep_primitives=true")
    "Triangulate 2D Keep Primitives is absent from identity";
  let kept = cook 4 kept_node in
  check (Pdk.Geometry.primitive_count kept = 3
      && Pdk.Topology.primitive_size (Pdk.Geometry.topology kept) 0 = 4)
    "Triangulate 2D SOP Keep Primitives topology";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "generated" kept with
   | Some group -> check (Pdk.Group.cardinality group = 2
       && not (Pdk.Group.mem 0 group))
       "Triangulate 2D SOP Keep Primitives output group"
   | None -> fail "Triangulate 2D SOP Keep Primitives output group is missing");
  let refinement_node = Pdk.Ops.points
      [|0.,0.,0.;2.,0.,0.;2.,2.,0.;0.,2.,0.|]
      |> Sop.snapshot |> Sop.triangulate_2d
          ~projection:Pdk.Ops.Triangulate_2d_xy ~refine:true
          ~maximum_area:0.3 ~maximum_new_points:64
          ~regularization_steps:2
          ~refinement_point_group:"refined" in
  check (contains (Node.parameters refinement_node) "refine=true"
      && contains (Node.parameters refinement_node) "maximum_area="
      && contains (Node.parameters refinement_node) "maximum_new_points=64"
      && contains (Node.parameters refinement_node) "regularization_steps=2"
      && contains (Node.parameters refinement_node)
        "refinement_point_group=refined")
    "Triangulate 2D refinement policy is absent from identity";
  let refined_one = cook 1 refinement_node and refined_four = cook 4 refinement_node in
  check (signature refined_one = signature refined_four
      && Pdk.Geometry.point_count refined_one > 4)
    "Triangulate 2D SOP refinement domain/cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point "refined" refined_one with
   | Some group -> check (Pdk.Group.cardinality group =
         Pdk.Geometry.point_count refined_one - 4)
       "Triangulate 2D SOP refinement group cardinality"
   | None -> fail "Triangulate 2D SOP refinement group is missing");
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;1.;0.|] ~y:[|0.;0.;1.;1.|] ~z:[|0.;0.;0.;0.|] in
  let topology = Pdk.Topology.create_owned ~point_count:4
      ~vertex_points:[|1;3|] ~primitive_offsets:[|0;2|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline|] |> Result.get_ok in
  let constrained = Pdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let group = Pdk.Group.init ~owner:Pdk.Group.Primitive ~name:"constraint" 1
      (fun _ -> true) in
  let constrained = Pdk.Geometry.with_group group constrained |> Result.get_ok in
  let constrained_node = Sop.snapshot constrained |> Sop.triangulate_2d
      ~projection:Pdk.Ops.Triangulate_2d_xy
      ~constraint_primitive_group:"constraint" ~constraint_group:"constraints" in
  let constrained_output = cook 1 constrained_node in
  let output_index = Pdk.Topology_index.create
      (Pdk.Geometry.topology constrained_output) in
  let diagonal = Pdk.Topology_index.find_edge_index output_index ~a:1 ~b:3 in
  (match Pdk.Geometry.find_edge_group "constraints" constrained_output with
   | Some group -> check (diagonal >= 0 && Pdk.Edge_group.mem diagonal group)
       "Triangulate 2D SOP did not recover its primitive constraint"
   | None -> fail "Triangulate 2D SOP constraint output group is missing");
  let crossing_topology = Pdk.Topology.create_owned ~point_count:4
      ~vertex_points:[|0;2;1;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline;Pdk.Topology.Open_polyline|]
      |> Result.get_ok in
  let crossing_positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;2.;0.|] ~y:[|0.;0.;2.;2.|] ~z:[|0.;0.;0.;0.|] in
  let crossing = Pdk.Geometry.create ~positions:crossing_positions
      ~topology:crossing_topology () |> Result.get_ok in
  let crossing_group = Pdk.Group.init ~owner:Pdk.Group.Primitive
      ~name:"crossing_constraints" 2 (fun _ -> true) in
  let crossing = Pdk.Geometry.with_group crossing_group crossing |> Result.get_ok in
  let crossing_node = Sop.snapshot crossing |> Sop.triangulate_2d
      ~projection:Pdk.Ops.Triangulate_2d_xy
      ~constraint_primitive_group:"crossing_constraints"
      ~split_crossing_constraints:true ~split_point_group:"split"
      ~constraint_group:"constraints" in
  check (contains (Node.parameters crossing_node)
      "split_crossing_constraints=true"
      && contains (Node.parameters crossing_node) "split_point_group=split")
    "Triangulate 2D crossing policy is absent from identity";
  let crossing_output = cook 4 crossing_node in
  check (Pdk.Geometry.point_count crossing_output = 5
      && Pdk.Geometry.primitive_count crossing_output = 4)
    "Triangulate 2D SOP crossing split cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point "split" crossing_output with
   | Some group -> check (Pdk.Group.cardinality group = 1)
       "Triangulate 2D SOP split group cardinality"
   | None -> fail "Triangulate 2D SOP split group is missing");
  let flood_node = Pdk.Ops.points [|0.,0.,0.;1.,0.,0.;0.,1.,0.|]
      |> Sop.snapshot |> Sop.triangulate_2d
          ~projection:Pdk.Ops.Triangulate_2d_xy
          ~flood_from_hull_boundary:true in
  check (contains (Node.parameters flood_node) "flood_from_hull_boundary=true")
    "Triangulate 2D hull-flood policy is absent from identity";
  check (Pdk.Geometry.primitive_count (cook 4 flood_node) = 0)
    "Triangulate 2D SOP did not apply hull flooding";
  let polygon_node = Pdk.Ops.points [|0.,0.,0.;1.,0.,0.;0.,1.,0.|]
      |> Sop.snapshot |> Sop.triangulate_2d
          ~projection:Pdk.Ops.Triangulate_2d_xy
          ~remove_outside_constraint_polygons:true in
  check (contains (Node.parameters polygon_node)
      "remove_outside_constraint_polygons=true")
    "Triangulate 2D polygon outside policy is absent from identity";
  check (Pdk.Geometry.primitive_count (cook 4 polygon_node) = 0)
    "Triangulate 2D SOP did not apply polygon outside removal";
  let silhouette_geometry =
    let positions = Pdk.Packed.Float3.Private.of_owned_exn
        ~x:[|-1.;1.;1.;-1.;0.|] ~y:[|-1.;-1.;1.;1.;0.|]
        ~z:[|0.;0.;0.;0.;0.|] in
    let topology = Pdk.Topology.polygons_owned ~point_count:5
        ~vertex_points:[|0;1;2;0;2;3|] ~primitive_offsets:[|0;3;6|]
        |> Result.get_ok in
    Pdk.Geometry.create ~positions ~topology () |> Result.get_ok in
  let silhouette_node = Sop.snapshot silhouette_geometry |> Sop.triangulate_2d
      ~projection:Pdk.Ops.Triangulate_2d_xy
      ~silhouette_constraints:true ~remove_outside_silhouette:true in
  check (contains (Node.parameters silhouette_node) "silhouette_constraints=true"
      && contains (Node.parameters silhouette_node)
        "remove_outside_silhouette=true")
    "Triangulate 2D silhouette policy is absent from identity";
  check (Pdk.Geometry.primitive_count (cook 4 silhouette_node) = 4)
    "Triangulate 2D SOP silhouette removal cardinality";
  let ignored_node = Sop.snapshot silhouette_geometry |> Sop.triangulate_2d
      ~projection:Pdk.Ops.Triangulate_2d_xy ~silhouette_constraints:true
      ~ignore_non_constraint_points:true ~remove_unused_points:true in
  check (contains (Node.parameters ignored_node)
      "ignore_non_constraint_points=true"
      && contains (Node.parameters ignored_node) "remove_unused_points=true")
    "Triangulate 2D Ignore Non-Constraint Points is absent from identity";
  let ignored = cook 4 ignored_node in
  check (Pdk.Geometry.point_count ignored = 4
      && Pdk.Geometry.primitive_count ignored = 2)
    "Triangulate 2D SOP Ignore Non-Constraint Points cardinality";
  let duplicate_geometry = Pdk.Ops.points
      [|0.,0.,0.;1.,0.,0.;1.,1.,0.;0.,1.,0.;0.,0.,3.;9.,9.,9.|] in
  let duplicate_selection = Pdk.Group.ordered ~owner:Pdk.Group.Point
      ~name:"selected_with_duplicate" ~length:6 [|0;1;2;3;4|]
      |> Result.get_ok in
  let duplicate_geometry = Pdk.Geometry.with_group duplicate_selection
      duplicate_geometry |> Result.get_ok in
  let duplicate_node = Sop.snapshot duplicate_geometry |> Sop.triangulate_2d
      ~point_group:"selected_with_duplicate"
      ~projection:Pdk.Ops.Triangulate_2d_xy ~remove_duplicate_points:true in
  check (contains (Node.parameters duplicate_node) "remove_duplicate_points=true")
    "Triangulate 2D duplicate policy is absent from identity";
  let deduplicated = cook 4 duplicate_node in
  check (Pdk.Geometry.point_count deduplicated = 5
      && Pdk.Geometry.primitive_count deduplicated = 2)
    "Triangulate 2D SOP duplicate removal cardinality";
  let deduplicated_positions = Pdk.Packed.Float3.Private.view
      (Pdk.Geometry.positions deduplicated) in
  check (deduplicated_positions.x.(4) = 9.
      && deduplicated_positions.y.(4) = 9.)
    "Triangulate 2D SOP duplicate removal lost the unselected point";
  let missing = Sop.snapshot (input ()) |> Sop.triangulate_2d
      ~point_group:"missing" in
  let session = Session.create ~max_entries:2 ~max_payload_bytes:1_000_000 |> get in
  let context = Context.create ~domains:1 () |> get in
  (match Session.cook session ~context missing with
   | Error error -> check (error.code = "missing_group")
       "Triangulate 2D missing group diagnostic"
   | Ok _ -> fail "Triangulate 2D accepted missing group");
  Session.close session;
  check (try ignore (Sop.triangulate_2d ~point_group:" " source); false
    with Invalid_argument _ -> true) "Triangulate 2D accepted empty group";
  print_endline "triangulate 2d SOP tests passed"
