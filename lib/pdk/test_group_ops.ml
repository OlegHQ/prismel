open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let two_quads () =
  let positions = Packed.Float3.Builder.create 6 in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set positions point x y z)
    [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.);
      (0.,1.,0.); (1.,1.,0.); (2.,1.,0.)|];
  let topology = Topology.Builder.create ~point_count:6
      ~vertex_capacity:8 ~primitive_capacity:2 () in
  Topology.Builder.add_polygon topology [|0; 1; 4; 3|];
  Topology.Builder.add_polygon topology [|1; 2; 5; 4|];
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let point_touching_triangles () =
  let positions = Packed.Float3.Builder.create 5 in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set positions point x y z)
    [|(0.,0.,0.); (-1.,0.,0.); (0.,1.,0.);
      (1.,0.,0.); (0.,-1.,0.)|];
  let topology = Topology.Builder.create ~point_count:5
      ~vertex_capacity:6 ~primitive_capacity:2 () in
  Topology.Builder.add_triangle topology 0 1 2;
  Topology.Builder.add_triangle topology 0 3 4;
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let bent_strip () =
  let positions = Packed.Float3.Builder.create 8 in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set positions point x y z)
    [|(0.,0.,0.); (1.,0.,0.); (2.,0.,0.); (3.,0.,1.);
      (0.,1.,0.); (1.,1.,0.); (2.,1.,0.); (3.,1.,1.)|];
  let topology = Topology.Builder.create ~point_count:8
      ~vertex_capacity:12 ~primitive_capacity:3 () in
  Topology.Builder.add_polygon topology [|0;1;5;4|];
  Topology.Builder.add_polygon topology [|1;2;6;5|];
  Topology.Builder.add_polygon topology [|2;3;7;6|];
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> function Ok geometry -> geometry | Error message -> fail message

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage
      |> function Ok value -> value | Error message -> fail message in
  Geometry.with_attribute attribute geometry
  |> function Ok value -> value | Error message -> fail message

let with_group owner name members geometry =
  let count = match owner with
    | Group.Point -> Geometry.point_count geometry
    | Group.Vertex -> Geometry.vertex_count geometry
    | Group.Primitive -> Geometry.primitive_count geometry in
  Geometry.with_group
    (Group.init ~grain:1 ~owner ~name count (fun index -> members index))
    geometry
  |> function Ok geometry -> geometry | Error message -> fail message

let group owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let edge_group name geometry =
  match Geometry.find_edge_group name geometry with
  | Some group -> group
  | None -> fail ("missing edge group " ^ name)

let int_attribute owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail ("non-integer attribute " ^ name))
  | None -> fail ("missing attribute " ^ name)

let same_group left right =
  Group.owner left = Group.owner right
  && Group.length left = Group.length right
  && let equal = ref true in
     for index = 0 to Group.length left - 1 do
       if Group.mem index left <> Group.mem index right then equal := false
     done;
     !equal
  && Group.ordered_elements left = Group.ordered_elements right

let same_edge_group left right =
  Edge_group.length left = Edge_group.length right
  && let equal = ref true in
     for edge = 0 to Edge_group.length left - 1 do
       if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
     done;
     !equal

let promote ?name ?keep_original ?mode ~source ~destination ~group geometry =
  Group_ops.promote_checked ~grain:1 ?name ?keep_original ?mode ~source ~destination
    ~group geometry |> get_ok

let expand ?name ?steps ?flood ?primitive_connectivity ?normal_spread
    ?normal_attribute ?connectivity_attributes ?connectivity_tolerance ?collision
    ~owner ~group geometry =
  Group_ops.expand_checked ~grain:1 ?name ?steps ?flood ?primitive_connectivity
    ?normal_spread ?normal_attribute ?connectivity_attributes
    ?connectivity_tolerance ?collision ~owner ~group geometry |> get_ok

let test_promote () =
  let base = two_quads () in
  let first_edge_points = with_group Group.Point "edge_points"
      (fun point -> point = 0 || point = 1) base in
  let any = promote ~keep_original:true ~name:"any_faces"
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_primitives
      ~group:"edge_points" first_edge_points in
  check (Group.cardinality (group Group.Primitive "any_faces" any) = 2)
    "Group Promote point-to-primitive any incidence";
  let shared = promote ~keep_original:true ~name:"edge_faces"
      ~mode:Group_ops.Include_shared_edge ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~group:"edge_points" first_edge_points in
  let shared_group = group Group.Primitive "edge_faces" shared in
  check (Group.cardinality shared_group = 1 && Group.mem 0 shared_group)
    "Group Promote shared-edge primitive inclusion";
  let mask = Group_ops.promote_checked ~grain:1 ~output_attribute:"face_mask"
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_primitives
      ~group:"edge_points" first_edge_points |> get_ok in
  check (int_attribute Attribute.Primitive "face_mask" mask = [|1; 1|]
      && Geometry.find_group ~owner:Group.Primitive "edge_points" mask = None
      && Geometry.find_group ~owner:Group.Point "edge_points" mask = None)
    "Group Promote integer-attribute output/source removal";
  let first_face_points = with_group Group.Point "face_points"
      (fun point -> point = 0 || point = 1 || point = 3 || point = 4) base in
  let contained = promote ~keep_original:true ~name:"contained_faces"
      ~mode:Group_ops.Include_all ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~group:"face_points" first_face_points in
  let contained_group = group Group.Primitive "contained_faces" contained in
  check (Group.cardinality contained_group = 1 && Group.mem 0 contained_group)
    "Group Promote entirely-contained primitive inclusion";
  let contained_edges = promote ~keep_original:true ~name:"contained_edges"
      ~mode:Group_ops.Include_all ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_edges ~group:"edge_points" first_edge_points in
  check (Edge_group.cardinality (edge_group "contained_edges" contained_edges) = 1)
    "Group Promote entirely-contained edge inclusion";
  let first_face = with_group Group.Primitive "first" (fun p -> p = 0) base in
  let points = promote ~keep_original:true ~name:"face_points_out"
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_points
      ~group:"first" first_face in
  check (Group.cardinality (group Group.Point "face_points_out" points) = 4)
    "Group Promote primitive-to-point";
  let vertices = promote ~keep_original:true ~name:"face_vertices"
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_vertices
      ~group:"first" first_face in
  check (Group.cardinality (group Group.Vertex "face_vertices" vertices) = 4)
    "Group Promote primitive-to-vertex";
  let touching_edges = promote ~keep_original:true ~name:"touching_edges"
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
      ~group:"first" first_face in
  check (Edge_group.cardinality (edge_group "touching_edges" touching_edges) = 4)
    "Group Promote primitive-to-edge any";
  let interior_edges = promote ~keep_original:true ~name:"owned_edges"
      ~mode:Group_ops.Include_all ~source:Group_ops.Group_primitives
      ~destination:Group_ops.Group_edges ~group:"first" first_face in
  check (Edge_group.cardinality (edge_group "owned_edges" interior_edges) = 3)
    "Group Promote primitive-to-edge complete containment";
  let shared_index = Topology_index.create (Geometry.topology base) in
  let shared_edge = match Topology_index.find_edge shared_index ~a:1 ~b:4 with
    | Some edge -> edge | None -> fail "fixture shared edge missing" in
  let selected_edge = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
      ~index:shared_index ~name:"shared" (fun edge -> edge = shared_edge) in
  let with_edge = Geometry.with_edge_group selected_edge base
      |> function Ok geometry -> geometry | Error message -> fail message in
  let edge_faces = promote ~keep_original:true ~name:"edge_faces_out"
      ~source:Group_ops.Group_edges ~destination:Group_ops.Group_primitives
      ~group:"shared" with_edge in
  check (Group.cardinality (group Group.Primitive "edge_faces_out" edge_faces) = 2)
    "Group Promote edge-to-primitive";
  let edge_points = promote ~keep_original:true ~name:"edge_points_out"
      ~source:Group_ops.Group_edges ~destination:Group_ops.Group_points
      ~group:"shared" with_edge in
  check (Group.cardinality (group Group.Point "edge_points_out" edge_points) = 2)
    "Group Promote edge-to-point";
  let edge_vertices = promote ~keep_original:true ~name:"edge_vertices"
      ~source:Group_ops.Group_edges ~destination:Group_ops.Group_vertices
      ~group:"shared" with_edge in
  check (Group.cardinality (group Group.Vertex "edge_vertices" edge_vertices) = 4)
    "Group Promote edge-to-vertex endpoint incidence";
  let renamed = promote ~name:"renamed" ~source:Group_ops.Group_primitives
      ~destination:Group_ops.Group_points ~group:"first" first_face in
  check (Geometry.find_group ~owner:Group.Primitive "first" renamed = None
      && Geometry.find_group ~owner:Group.Point "renamed" renamed <> None)
    "Group Promote source removal/output rename";
  (match Group_ops.promote_checked ~mode:Group_ops.Include_shared_edge
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_edges
      ~group:"edge_points" first_edge_points with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promote invalid mode code"
   | Ok _ -> fail "Group Promote accepted shared-edge non-primitive output");
  (match Group_ops.promote_checked ~output_attribute:"edge_mask"
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_edges
      ~group:"edge_points" first_edge_points with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promote edge attribute code"
   | Ok _ -> fail "Group Promote created an unsupported edge attribute")

let test_all_promotion_owner_pairs () =
  let base = two_quads () in
  let index = Topology_index.create (Geometry.topology base) in
  let edge_01 = Option.get (Topology_index.find_edge index ~a:0 ~b:1) in
  let sources = [
    Group_ops.Group_points,
      with_group Group.Point "source" (fun point -> point = 0 || point = 1) base,
      [2; 3; 2; 4];
    Group_ops.Group_vertices,
      with_group Group.Vertex "source" (fun vertex -> vertex = 0 || vertex = 1) base,
      [2; 2; 1; 3];
    Group_ops.Group_primitives,
      with_group Group.Primitive "source" (fun primitive -> primitive = 0) base,
      [4; 4; 1; 4];
    Group_ops.Group_edges,
      (let selected = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
          ~index ~name:"source" (fun edge -> edge = edge_01) in
       Geometry.with_edge_group selected base
       |> function Ok geometry -> geometry | Error message -> fail message),
      [2; 2; 1; 1];
  ] in
  let destinations = [|Group_ops.Group_points; Group_ops.Group_vertices;
    Group_ops.Group_primitives; Group_ops.Group_edges|] in
  List.iter (fun (source, geometry, expected) ->
    Array.iteri (fun destination_index destination ->
      let output = promote ~name:"output" ~source ~destination ~group:"source"
          geometry in
      let cardinality = match destination with
        | Group_ops.Group_points -> Group.cardinality (group Group.Point "output" output)
        | Group_ops.Group_vertices -> Group.cardinality
            (group Group.Vertex "output" output)
        | Group_ops.Group_primitives -> Group.cardinality
            (group Group.Primitive "output" output)
        | Group_ops.Group_edges -> Edge_group.cardinality (edge_group "output" output) in
      check (cardinality = List.nth expected destination_index)
        (Printf.sprintf "Group Promote %d->%d owner-pair membership"
          (match source with Group_ops.Group_points -> 0 | Group_ops.Group_vertices -> 1
            | Group_ops.Group_primitives -> 2 | Group_ops.Group_edges -> 3)
          destination_index)) destinations) sources;
  let vertices = with_group Group.Vertex "edge_vertices"
      (fun vertex -> vertex = 0 || vertex = 1) base in
  let contained_edge = promote ~name:"contained_edge" ~mode:Group_ops.Include_all
      ~source:Group_ops.Group_vertices ~destination:Group_ops.Group_edges
      ~group:"edge_vertices" vertices in
  check (Edge_group.cardinality (edge_group "contained_edge" contained_edge) = 1)
    "Group Promote vertex-to-edge complete containment";
  let selected_edge = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
      ~index ~name:"edge" (fun edge -> edge = edge_01) in
  let edge_source = Geometry.with_edge_group selected_edge base
      |> function Ok geometry -> geometry | Error message -> fail message in
  let beginnings = promote ~name:"beginnings" ~mode:Group_ops.Include_all
      ~source:Group_ops.Group_edges ~destination:Group_ops.Group_vertices ~group:"edge"
      edge_source in
  check (Group.cardinality (group Group.Vertex "beginnings" beginnings) = 1
      && Group.mem 0 (group Group.Vertex "beginnings" beginnings))
    "Group Promote edge-to-vertex beginning-corner containment"

let test_ordered_wildcard_promotions () =
  let base = two_quads ()
      |> with_group Group.Point "seed_left"
           (fun point -> point = 0 || point = 1 || point = 3 || point = 4)
      |> with_group Group.Point "seed_right"
           (fun point -> point = 1 || point = 2 || point = 4 || point = 5)
      |> with_group Group.Point "seed_skip" (fun point -> point = 0) in
  let rules = [
    Group_ops.promotion_rule ~new_name:"face_*" ~keep_original:true
      ~mode:Group_ops.Include_all ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~pattern:"seed_* ^seed_skip" ();
    Group_ops.promotion_rule ~new_name:"outline_*"
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
      ~pattern:"face_*" ();
  ] in
  let promoted = Group_ops.promotions_checked ~grain:1 ~rules base |> get_ok in
  check (Geometry.find_group ~owner:Group.Primitive "face_left" promoted = None
      && Geometry.find_group ~owner:Group.Primitive "face_right" promoted = None
      && Edge_group.cardinality (edge_group "outline_left" promoted) = 4
      && Edge_group.cardinality (edge_group "outline_right" promoted) = 4
      && Geometry.find_group ~owner:Group.Point "seed_skip" promoted <> None)
    "Group Promotions ordered wildcard/rewrite chain";
  let collisions = two_quads ()
      |> with_group Group.Point "a" (fun point -> point = 0)
      |> with_group Group.Point "b" (fun point -> point = 1) in
  let collision_rule = Group_ops.promotion_rule ~new_name:"b c"
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_points
      ~pattern:"a b" () in
  let collided = Group_ops.promotions_checked ~grain:1 ~rules:[collision_rule]
      collisions |> get_ok in
  let b = group Group.Point "b" collided and c = group Group.Point "c" collided in
  check (Group.cardinality b = 1 && Group.mem 0 b
      && Group.cardinality c = 1 && Group.mem 1 c
      && Geometry.find_group ~owner:Group.Point "a" collided = None)
    "Group Promotions output collision changed a snapshotted source";
  let attribute_rules = [Group_ops.promotion_rule ~new_name:"mask_*"
      ~output_as_attribute:true ~mode:Group_ops.Include_all
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_primitives
      ~pattern:"seed_* ^seed_skip" ()] in
  let attributes = Group_ops.promotions_checked ~grain:1 ~rules:attribute_rules base
      |> get_ok in
  check (int_attribute Attribute.Primitive "mask_left" attributes = [|1; 0|]
      && int_attribute Attribute.Primitive "mask_right" attributes = [|0; 1|]
      && Geometry.find_group ~owner:Group.Point "seed_left" attributes = None
      && Geometry.find_group ~owner:Group.Point "seed_right" attributes = None
      && Geometry.find_group ~owner:Group.Point "seed_skip" attributes <> None)
    "Group Promotions wildcard integer-attribute outputs";
  let boundary_base = two_quads ()
      |> with_group Group.Primitive "region_left" (fun primitive -> primitive = 0)
      |> with_group Group.Primitive "region_right" (fun primitive -> primitive = 1)
  in
  let boundary_rule = Group_ops.boundary_promotion_rule
      ~new_name:"boundary_*" ~keep_original:true
      ~source:Group_ops.Group_primitives ~destination:Group_ops.Group_edges
      ~pattern:"region_*" () in
  let boundaries = Group_ops.promotions_checked ~grain:1 ~rules:[boundary_rule]
      boundary_base |> get_ok in
  check (Edge_group.cardinality (edge_group "boundary_left" boundaries) = 1
      && Edge_group.cardinality (edge_group "boundary_right" boundaries) = 1)
    "Group Promotions wildcard boundary conversion";
  let disabled = Group_ops.promotion_rule ~mode:Group_ops.Include_shared_edge
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_edges ~pattern:" " () in
  check ((Group_ops.promotions_checked ~rules:[disabled] base |> get_ok) == base)
    "Group Promotions disabled rule lost geometry identity";
  check ((Group_ops.promotions_checked ~rules:[Group_ops.promotion_rule
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_primitives
      ~pattern:"missing*" ()] base |> get_ok) == base)
    "Group Promotions unmatched rule lost geometry identity";
  (match Group_ops.promotions_checked ~rules:[Group_ops.promotion_rule
      ~new_name:"only_one" ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~pattern:"seed_left seed_right" ()]
      base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promotions malformed rewrite error code"
   | Ok _ -> fail "Group Promotions accepted a replacement-count mismatch");
  (match Group_ops.promotions_checked ~max_outputs:1 ~rules:attribute_rules base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promotions output limit error code"
   | Ok _ -> fail "Group Promotions exceeded its output limit");
  (match Group_ops.promotions_checked ~max_payload_bytes:0 ~rules:attribute_rules base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Promotions payload limit error code"
   | Ok _ -> fail "Group Promotions exceeded its payload limit");
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Group_ops.promotions_checked ~cancel:cancelled ~rules base with
   | Error error -> check (Error.code error = "cancelled")
       "Group Promotions cancellation code"
   | Ok _ -> fail "cancelled Group Promotions published geometry")

let test_expand () =
  let base = two_quads () in
  let first_face = with_group Group.Primitive "first" (fun p -> p = 0) base in
  let grown = expand ~steps:1 ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~owner:Group_ops.Group_primitives ~group:"first" first_face in
  check (Group.cardinality (group Group.Primitive "first" grown) = 2)
    "Group Expand primitive edge growth";
  let shrunk = expand ~name:"shrunk" ~steps:(-1)
      ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~owner:Group_ops.Group_primitives ~group:"first" first_face in
  check (Group.cardinality (group Group.Primitive "shrunk" shrunk) = 0)
    "Group Expand primitive erosion";
  let point_seed = with_group Group.Point "seed" (fun point -> point = 0) base in
  let point_ring = expand ~name:"ring" ~steps:1 ~owner:Group_ops.Group_points
      ~group:"seed" point_seed in
  check (Group.cardinality (group Group.Point "ring" point_ring) = 3)
    "Group Expand point edge adjacency";
  let flooded = expand ~name:"component" ~flood:true ~owner:Group_ops.Group_points
      ~group:"seed" point_seed in
  check (Group.cardinality (group Group.Point "component" flooded) = 6)
    "Group Expand point flood fill";
  let unchanged = expand ~steps:0 ~owner:Group_ops.Group_points ~group:"seed"
      point_seed in
  check (group Group.Point "seed" unchanged == group Group.Point "seed" point_seed)
    "Group Expand zero-step structural sharing";
  let stepped = Group_ops.expand_checked ~grain:1 ~name:"stepped" ~steps:2
      ~step_attribute:"grow_step" ~owner:Group_ops.Group_points ~group:"seed"
      point_seed |> get_ok in
  check (int_attribute Attribute.Point "grow_step" stepped
      = [|0; 1; 2; 1; 2; 0|])
    "Group Expand positive step attribute";
  let flooded_steps = Group_ops.expand_checked ~grain:1 ~name:"flooded"
      ~flood:true ~step_attribute:"flood_step" ~owner:Group_ops.Group_points
      ~group:"seed" point_seed |> get_ok in
  check (int_attribute Attribute.Point "flood_step" flooded_steps
      = [|0; 1; 2; 1; 2; 3|])
    "Group Expand flood-distance attribute";
  let almost_all = with_group Group.Point "almost_all"
      (fun point -> point <> 5) base in
  let eroded = Group_ops.expand_checked ~grain:1 ~name:"eroded" ~steps:(-3)
      ~step_attribute:"shrink_step" ~owner:Group_ops.Group_points
      ~group:"almost_all" almost_all |> get_ok in
  check (Group.cardinality (group Group.Point "eroded" eroded) = 0
      && int_attribute Attribute.Point "shrink_step" eroded
         = [|3; 2; 1; 2; 1; 0|])
    "Group Expand shrink-removal step attribute";
  let index = Topology_index.create (Geometry.topology base) in
  let seed_edge = Option.get (Topology_index.find_edge index ~a:0 ~b:1) in
  let edges = Edge_group.init ~grain:1 ~topology:(Geometry.topology base)
      ~index ~name:"edge_seed" (fun edge -> edge = seed_edge) in
  let edge_base = Geometry.with_edge_group edges base
      |> function Ok geometry -> geometry | Error message -> fail message in
  let edge_ring = expand ~name:"edge_ring" ~steps:1 ~owner:Group_ops.Group_edges
      ~group:"edge_seed" edge_base in
  check (Edge_group.cardinality (edge_group "edge_ring" edge_ring) = 4)
    "Group Expand edge endpoint adjacency";
  let vertex_base = with_group Group.Vertex "corner" (fun vertex -> vertex = 0) base in
  let vertex_ring = expand ~name:"corner_ring" ~steps:1
      ~owner:Group_ops.Group_vertices ~group:"corner" vertex_base in
  check (Group.cardinality (group Group.Vertex "corner_ring" vertex_ring) = 3)
    "Group Expand vertex adjacency";
  let touching = point_touching_triangles ()
      |> with_group Group.Primitive "first" (fun primitive -> primitive = 0) in
  let through_point = expand ~name:"through_point" ~steps:1
      ~primitive_connectivity:Group_ops.Primitive_share_points
      ~owner:Group_ops.Group_primitives ~group:"first" touching
  and through_edge = expand ~name:"through_edge" ~steps:1
      ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~owner:Group_ops.Group_primitives ~group:"first" touching in
  check (Group.cardinality
      (group Group.Primitive "through_point" through_point) = 2
      && Group.cardinality
         (group Group.Primitive "through_edge" through_edge) = 1)
    "Group Expand primitive point/edge connectivity distinction";
  let strip = bent_strip ()
      |> with_group Group.Primitive "strip_seed" (fun primitive -> primitive = 0) in
  let normal_limited = expand ~name:"normal_limited" ~flood:true
      ~primitive_connectivity:Group_ops.Primitive_share_edges ~normal_spread:0.2
      ~owner:Group_ops.Group_primitives ~group:"strip_seed" strip in
  let normal_group = group Group.Primitive "normal_limited" normal_limited in
  check (Group.cardinality normal_group = 2 && Group.mem 0 normal_group
      && Group.mem 1 normal_group && not (Group.mem 2 normal_group))
    "Group Expand geometric normal-spread constraint";
  let vertex_flow = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init 12 (fun vertex -> if vertex < 8 then 0. else 1.))
      ~y:(Array.make 12 0.)
      ~z:(Array.init 12 (fun vertex -> if vertex < 8 then 1. else 0.)) in
  let custom_strip = with_attribute Attribute.Vertex "flow"
      (Attribute.Float3 vertex_flow) strip in
  let custom_limited = expand ~name:"custom_limited" ~flood:true
      ~primitive_connectivity:Group_ops.Primitive_share_edges ~normal_spread:0.2
      ~normal_attribute:{ Group_ops.expand_normal_owner = Attribute.Vertex;
        expand_normal_name = "flow" }
      ~owner:Group_ops.Group_primitives ~group:"strip_seed" custom_strip in
  check (Group.cardinality
      (group Group.Primitive "custom_limited" custom_limited) = 2)
    "Group Expand vertex normal-source mapping";
  let region_strip = with_attribute Attribute.Primitive "region"
      (Attribute.Int [|0;0;1|]) strip in
  let region_rule = [{ Group_ops.boundary_attribute_owner = Attribute.Primitive;
    boundary_attribute_pattern = "region" }] in
  let region_limited = expand ~name:"region_limited" ~flood:true
      ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~connectivity_attributes:region_rule ~owner:Group_ops.Group_primitives
      ~group:"strip_seed" region_strip in
  check (Group.cardinality
      (group Group.Primitive "region_limited" region_limited) = 2)
    "Group Expand primitive connectivity-attribute seam";
  let full_strip = with_group Group.Primitive "full_strip" (fun _ -> true)
      region_strip in
  let eroded_regions = Group_ops.expand_checked ~grain:1 ~name:"eroded_regions"
      ~steps:(-1) ~step_attribute:"region_shrink_step"
      ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~connectivity_attributes:region_rule ~owner:Group_ops.Group_primitives
      ~group:"full_strip" full_strip |> get_ok in
  let eroded_region_group = group Group.Primitive "eroded_regions" eroded_regions in
  check (Group.cardinality eroded_region_group = 1
      && Group.mem 0 eroded_region_group
      && int_attribute Attribute.Primitive "region_shrink_step" eroded_regions
         = [|0;1;1|])
    "Group Expand shrink-away connectivity boundary/step attribute";
  let point_regions = point_seed |> with_attribute Attribute.Point "region"
      (Attribute.Int [|0;0;1;0;0;1|]) in
  let point_rule = [{ Group_ops.boundary_attribute_owner = Attribute.Point;
    boundary_attribute_pattern = "region" }] in
  let point_region = expand ~name:"point_region" ~flood:true
      ~connectivity_attributes:point_rule ~owner:Group_ops.Group_points ~group:"seed"
      point_regions in
  let point_region_group = group Group.Point "point_region" point_region in
  check (Group.cardinality point_region_group = 4
      && Group.mem 0 point_region_group && Group.mem 1 point_region_group
      && Group.mem 3 point_region_group && Group.mem 4 point_region_group)
    "Group Expand point connectivity-attribute seam";
  let tolerant_regions = point_seed |> with_attribute Attribute.Point "region_f"
      (Attribute.Float [|0.;0.;1e-7;0.;0.;1e-7|]) in
  let tolerant = expand ~name:"tolerant" ~flood:true
      ~connectivity_attributes:[{ Group_ops.boundary_attribute_owner = Attribute.Point;
        boundary_attribute_pattern = "region_f" }]
      ~connectivity_tolerance:1e-6 ~owner:Group_ops.Group_points ~group:"seed"
      tolerant_regions in
  check (Group.cardinality (group Group.Point "tolerant" tolerant) = 6)
    "Group Expand floating connectivity tolerance";
  let collision_source = point_seed
      |> with_group Group.Point "right_side" (fun point -> point = 2 || point = 5) in
  let collision allow_boundary contain = {
    Group_ops.expand_collision_owner = Group_ops.Group_points;
    expand_collision_group = "right_side";
    expand_collision_contain = contain;
    expand_collision_allow_boundary = allow_boundary;
  } in
  let stopped_before = expand ~name:"stopped_before" ~flood:true
      ~collision:(collision false false) ~owner:Group_ops.Group_points ~group:"seed"
      collision_source in
  check (Group.cardinality (group Group.Point "stopped_before" stopped_before) = 2
      && Group.mem 0 (group Group.Point "stopped_before" stopped_before)
      && Group.mem 3 (group Group.Point "stopped_before" stopped_before))
    "Group Expand collision boundary exclusion";
  let stopped_on = expand ~name:"stopped_on" ~flood:true
      ~collision:(collision true false) ~owner:Group_ops.Group_points ~group:"seed"
      collision_source in
  check (Group.cardinality (group Group.Point "stopped_on" stopped_on) = 4)
    "Group Expand collision boundary inclusion";
  let contained_source = point_seed
      |> with_group Group.Point "left_side"
           (fun point -> point = 0 || point = 1 || point = 3 || point = 4) in
  let contained = expand ~name:"contained" ~flood:true ~collision:{
      Group_ops.expand_collision_owner = Group_ops.Group_points;
      expand_collision_group = "left_side";
      expand_collision_contain = true;
      expand_collision_allow_boundary = true }
      ~owner:Group_ops.Group_points ~group:"seed" contained_source in
  check (Group.cardinality (group Group.Point "contained" contained) = 4)
    "Group Expand collision containment";
  let collision_full = with_group Group.Point "all_points" (fun _ -> true)
      collision_source in
  let collision_eroded = expand ~name:"collision_eroded" ~steps:(-1)
      ~collision:(collision true false) ~owner:Group_ops.Group_points
      ~group:"all_points" collision_full in
  check (Group.cardinality
      (group Group.Point "collision_eroded" collision_eroded) = 2)
    "Group Expand shrink-away collision boundary";
  (match Group_ops.expand_checked ~flood:true ~steps:(-1) ~owner:Group_ops.Group_points
      ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand invalid flood/shrink code"
   | Ok _ -> fail "Group Expand accepted flood shrinking");
  (match Group_ops.expand_checked ~steps:min_int ~owner:Group_ops.Group_points
      ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand minimum-integer step code"
   | Ok _ -> fail "Group Expand accepted an unrepresentable step magnitude");
  (match Group_ops.expand_checked ~step_attribute:"step" ~owner:Group_ops.Group_edges
      ~group:"edge_seed" edge_base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand edge step-attribute code"
   | Ok _ -> fail "Group Expand created an unsupported edge attribute");
  (match Group_ops.expand_checked ~normal_spread:Float.nan ~owner:Group_ops.Group_points
      ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand invalid normal spread code"
   | Ok _ -> fail "Group Expand accepted a non-finite normal spread");
  (match Group_ops.expand_checked ~normal_spread:0.2
      ~normal_attribute:{ Group_ops.expand_normal_owner = Attribute.Point;
        expand_normal_name = "missing" }
      ~owner:Group_ops.Group_points ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand missing normal attribute code"
   | Ok _ -> fail "Group Expand accepted a missing normal attribute");
  let scalar_normals = point_seed |> with_attribute Attribute.Point "scalar_n"
      (Attribute.Float (Array.make 6 1.)) in
  (match Group_ops.expand_checked ~normal_spread:0.2
      ~normal_attribute:{ Group_ops.expand_normal_owner = Attribute.Point;
        expand_normal_name = "scalar_n" }
      ~owner:Group_ops.Group_points ~group:"seed" scalar_normals with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand scalar normal attribute code"
   | Ok _ -> fail "Group Expand accepted a scalar normal attribute");
  (match Group_ops.expand_checked ~connectivity_attributes:[{
        Group_ops.boundary_attribute_owner = Attribute.Point;
        boundary_attribute_pattern = "missing_region" }]
      ~owner:Group_ops.Group_points ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand missing connectivity attribute code"
   | Ok _ -> fail "Group Expand accepted a missing connectivity attribute");
  (match Group_ops.expand_checked ~connectivity_attributes:point_rule
      ~owner:Group_ops.Group_primitives ~group:"first" first_face with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand constrained point-sharing primitive code"
   | Ok _ -> fail "Group Expand accepted constrained point-sharing primitives");
  (match Group_ops.expand_checked ~normal_spread:0.2 ~owner:Group_ops.Group_edges
      ~group:"edge_seed" edge_base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand constrained edge owner code"
   | Ok _ -> fail "Group Expand accepted constrained edge growth");
  (match Group_ops.expand_checked ~collision:{
      Group_ops.expand_collision_owner = Group_ops.Group_edges;
      expand_collision_group = "edge_seed";
      expand_collision_contain = true;
      expand_collision_allow_boundary = true }
      ~owner:Group_ops.Group_points ~group:"seed" edge_base with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand edge collision containment code"
   | Ok _ -> fail "Group Expand accepted edge collision containment");
  (match Group_ops.expand_checked ~collision:{
      Group_ops.expand_collision_owner = Group_ops.Group_points;
      expand_collision_group = "missing";
      expand_collision_contain = false;
      expand_collision_allow_boundary = false }
      ~owner:Group_ops.Group_points ~group:"seed" point_seed with
   | Error error -> check (Error.code error = "invalid_group")
       "Group Expand missing collision group code"
   | Ok _ -> fail "Group Expand accepted a missing collision group")

let test_parallel_and_cancellation () =
  let base = Plane_generators.grid_checked ~columns:500 ~rows:300 ~size:20. () |> get_ok in
  let width = 501 in
  let seeded = with_group Group.Point "stripe"
      (fun point -> point mod width = width / 2) base in
  let seeded = with_group Group.Point "stripe_b"
      (fun point -> point mod width = width / 3) seeded in
  let run domains = Parallel.run ~domains (fun () ->
    let expanded = Group_ops.expand_checked ~grain:257 ~steps:37
        ~step_attribute:"grow_step"
        ~owner:Group_ops.Group_points ~group:"stripe" seeded |> get_ok in
    let promoted = Group_ops.promote_checked ~grain:257 ~keep_original:true ~name:"faces"
      ~mode:Group_ops.Include_shared_edge ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~group:"stripe" expanded |> get_ok in
    let promoted = Group_ops.promotions_checked ~grain:257 ~rules:[
        Group_ops.promotion_rule ~new_name:"wild_faces*" ~keep_original:true
          ~mode:Group_ops.Include_shared_edge ~source:Group_ops.Group_points
          ~destination:Group_ops.Group_primitives ~pattern:"stripe*" ()]
        promoted |> get_ok in
    Group_ops.promote_checked ~grain:257 ~keep_original:true
      ~output_attribute:"face_mask" ~mode:Group_ops.Include_shared_edge
      ~source:Group_ops.Group_points ~destination:Group_ops.Group_primitives
      ~group:"stripe" promoted |> get_ok) in
  let one = run 1 and many = run 4 in
  check (same_group (group Group.Point "stripe" one)
      (group Group.Point "stripe" many))
    "Group Expand one/four-domain exactness";
  check (same_group (group Group.Primitive "faces" one)
      (group Group.Primitive "faces" many))
    "Group Promote one/four-domain exactness";
  check (same_group (group Group.Primitive "wild_faces" one)
      (group Group.Primitive "wild_faces" many)
      && same_group (group Group.Primitive "wild_faces_b" one)
         (group Group.Primitive "wild_faces_b" many))
    "Group Promotions one/four-domain exactness";
  check (int_attribute Attribute.Point "grow_step" one
      = int_attribute Attribute.Point "grow_step" many)
    "Group Expand step attribute one/four-domain exactness";
  check (int_attribute Attribute.Primitive "face_mask" one
      = int_attribute Attribute.Primitive "face_mask" many)
    "Group Promote attribute output one/four-domain exactness";
  let edge_run domains = Parallel.run ~domains (fun () ->
    let boundary = Ops.group_edges ~grain:257 ~name:"boundary"
        ~incidence:Ops.Boundary_edge base |> get_ok in
    Group_ops.expand_checked ~grain:257 ~steps:5 ~owner:Group_ops.Group_edges
      ~group:"boundary" boundary |> get_ok) in
  check (same_edge_group (edge_group "boundary" (edge_run 1))
      (edge_group "boundary" (edge_run 4)))
    "edge Group Expand one/four-domain exactness";
  let primitive_count = Geometry.primitive_count base in
  let constrained = base
      |> with_attribute Attribute.Primitive "region"
           (Attribute.Int (Array.init primitive_count (fun primitive ->
             if primitive < primitive_count / 2 then 0 else 1)))
      |> with_attribute Attribute.Primitive "flow"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:(Array.make primitive_count 0.)
             ~y:(Array.make primitive_count 0.)
             ~z:(Array.make primitive_count 1.)))
      |> with_group Group.Primitive "primitive_seed"
           (fun primitive -> primitive = 0) in
  let constrained_run domains = Parallel.run ~domains (fun () ->
    Group_ops.expand_checked ~grain:257 ~flood:true ~step_attribute:"constrained_step"
      ~primitive_connectivity:Group_ops.Primitive_share_edges ~normal_spread:0.1
      ~normal_attribute:{ Group_ops.expand_normal_owner = Attribute.Primitive;
        expand_normal_name = "flow" }
      ~connectivity_attributes:[{
        Group_ops.boundary_attribute_owner = Attribute.Primitive;
        boundary_attribute_pattern = "region" }]
      ~owner:Group_ops.Group_primitives ~group:"primitive_seed" constrained
      |> get_ok) in
  let constrained_one = constrained_run 1 and constrained_many = constrained_run 4 in
  check (same_group (group Group.Primitive "primitive_seed" constrained_one)
      (group Group.Primitive "primitive_seed" constrained_many)
      && int_attribute Attribute.Primitive "constrained_step" constrained_one
         = int_attribute Attribute.Primitive "constrained_step" constrained_many)
    "constrained Group Expand one/four-domain exactness";
  let constrained_count = Group.cardinality
      (group Group.Primitive "primitive_seed" constrained_one) in
  check (constrained_count > 0 && constrained_count < primitive_count)
    "constrained Group Expand ignored connectivity region";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Group_ops.expand_checked ~cancel:cancelled ~owner:Group_ops.Group_points
      ~group:"stripe" seeded with
   | Error error -> check (Error.code error = "cancelled")
       "Group Expand cancellation code"
   | Ok _ -> fail "cancelled Group Expand published geometry");
  (match Group_ops.expand_checked ~cancel:cancelled ~flood:true
      ~primitive_connectivity:Group_ops.Primitive_share_edges
      ~connectivity_attributes:[{
        Group_ops.boundary_attribute_owner = Attribute.Primitive;
        boundary_attribute_pattern = "region" }]
      ~owner:Group_ops.Group_primitives ~group:"primitive_seed" constrained with
   | Error error -> check (Error.code error = "cancelled")
       "constrained Group Expand cancellation code"
   | Ok _ -> fail "cancelled constrained Group Expand published geometry");
  (match Group_ops.promote_checked ~cancel:cancelled ~source:Group_ops.Group_points
      ~destination:Group_ops.Group_primitives ~group:"stripe" seeded with
   | Error error -> check (Error.code error = "cancelled")
       "Group Promote cancellation code"
   | Ok _ -> fail "cancelled Group Promote published geometry")

let run () =
  test_promote ();
  test_all_promotion_owner_pairs ();
  test_ordered_wildcard_promotions ();
  test_expand ();
  test_parallel_and_cancellation ();
  print_endline "group operation tests passed"
