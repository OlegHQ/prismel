open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let edit_parameters graph ~node_id changes =
  Result.bind (Edit_graph.apply_parameters (Edit_graph.of_graph graph)
      ~node_id changes) (fun (document, effects) ->
    Result.map (fun graph -> graph, effects) (Edit_graph.compile document))

let cook session node = match Session.cook session
    ~context:(Context.create () |> Result.get_ok) node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let run () =
  let source = Sop_catalog.Box.create ~label:"box"
      ~size:(Vec3.create 2. 2. 2.) ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true () in
  let ordinary_chain = source
    |> Sop_catalog.Transform.create ~label:"transform"
         ~translate:(Vec3.create 1. 0. 0.)
    |> Sop_catalog.Triangulate.create ~label:"triangulate" in
  List.iter (fun node -> check (Node.has_parameters node)
      ("catalog node has no parameters: " ^ Node.label node))
    [ordinary_chain; List.hd (Node.inputs ordinary_chain)];
  let plane = Sop_catalog.Grid.create ~label:"grid" ~columns:2 ~rows:2
      ~size:3. ()
    |> Sop_catalog.Mountain.create ~label:"mountain" ~seed:3 ~height:0.2
         ~frequency:(Vec3.create 0.2 1. 0.2) ~octaves:2 ~lacunarity:2.
         ~roughness:0.5 in
  let targets = Sop_catalog.Point_generate.origin ~label:"points" ~points:4 ()
    |> Sop_catalog.Attribute_noise_quaternion.create ~label:"orient" ~seed:4
         ~owner:Pdk.Attribute.Point ~name:"orient"
         ~location:Pdk.Attribute_ops.Noise_element_number
         ~frequency:(Vec3.create 0.2 0.2 0.2) ~octaves:2
    |> Sop_catalog.Point_jitter.create ~label:"jitter" ~seed:5 ~scale:0.1 in
  let cutters = Sop_catalog.Copy_to_points.create ~label:"copy" ~source:plane
      ~targets () in
  let graph = Sop_catalog.Boolean_fracture.create ~label:"fracture"
      ~cutters source
    |> Sop_catalog.Exploded_view.create in
  let fracture = List.hd (Node.inputs graph) in
  let orient = List.hd (Node.inputs targets) in
  let custom_noise = Sop_catalog.Attribute_noise_quaternion.create
      ~owner:Pdk.Attribute.Point ~name:"orient" ~seed:4
      ~frequency:(Vec3.create 0.2 0.2 0.2) ~octaves:2
      ~location:(Pdk.Attribute_ops.Noise_attribute "rest position")
      ~range:(Pdk.Attribute_ops.Noise_min_max
        (Pdk.Attribute_ops.Vec4 (0., 0.1, 0.2, 0.3),
         Pdk.Attribute_ops.Vec4 (0.7, 0.8, 0.9, 1.)))
      (List.hd (Node.inputs orient)) in
  let field node name = List.find (fun value -> value.Parameter.name = name)
      (Node.parameter_fields node) in
  List.iter (fun (node, names) -> List.iter (fun name ->
    let value = field node name in
    check (value.current = value.default)
      ("catalog create/menu default differs: " ^ name)) names)
    [plane, ["group"; "direction_attribute"; "mask_attribute";
             "height_attribute"; "recompute_normals"];
     orient, ["group"; "owner"; "name"; "location"; "range"];
     targets, ["group"; "mask_attribute"; "id_attribute";
               "axis_x"; "axis_y"; "axis_z"];
     fracture, ["resolve_cutter_self_intersections";
                "detriangulation"; "require_closed"; "piece_attribute"]];
  let changed_graph, effects = edit_parameters targets
      ~node_id:(Node.id orient)
      ["location", (field custom_noise "location").current;
       "range", (field custom_noise "range").current] |> Result.get_ok in
  let changed = Graph.find changed_graph ~node_id:(Node.id orient)
      |> Option.get in
  check (effects.cook && Node.id changed = Node.id orient
      && (field changed "location").current
         = (field custom_noise "location").current
      && (field changed "range").current
         = (field custom_noise "range").current)
    "quaternion noise location/range were not editable schema fields";
  List.iter (fun (node, field, expected) ->
    let before = List.find (fun value -> value.Parameter.name = field)
        (Node.parameter_fields node) in
    check (before.current = Parameter.Text_value expected)
      ("catalog hidden parameter has wrong default: " ^ field);
    let edited, effects = Node.apply_parameters node
        [field, Parameter.Text_value "edited"] |> Result.get_ok in
    let after = List.find (fun value -> value.Parameter.name = field)
        (Node.parameter_fields edited) in
    check (effects.cook && Node.id edited = Node.id node
        && after.current = Parameter.Text_value "edited")
      ("catalog field did not rebuild: " ^ field))
    [plane, "height_attribute", ""; targets, "id_attribute", "";
     orient, "name", "orient"; fracture, "piece_attribute", "piece"];
  let parameterized = Graph.inspect graph
      |> List.filter (fun info -> info.Graph.has_parameters)
      |> List.map (fun info -> info.Graph.label) in
  List.iter (fun label -> check (List.mem label parameterized)
      ("catalog node has no PPX inspector metadata: " ^ label))
    ["box"; "grid"; "mountain"; "points"; "orient"; "jitter"; "copy";
     "fracture"; "exploded-view"];
  let point_node = Graph.inspect graph
      |> List.find (fun info -> info.Graph.label = "points") in
  let edited, effects = edit_parameters graph ~node_id:point_node.id
      ["points", Parameter.Int_value 999] |> Result.get_ok in
  let edited_points = Graph.find edited ~node_id:point_node.id |> Option.get in
  let value = Node.parameter_fields edited_points
      |> List.find (fun field -> field.Parameter.name = "points") in
  check (effects.cook && value.current = Parameter.Int_value 50)
    "catalog point count did not enforce its PPX hard maximum";
  let cube = Sop_catalog.Box.create ~label:"cube" ()
  and dodecahedron = Sop_catalog.Platonic.create ~label:"dodecahedron"
      ~kind:Pdk.Ops.Platonic_dodecahedron ~radius:1. () in
  let switched = Sop_catalog.Switch.create ~label:"source-switch"
      [cube; dodecahedron] in
  check (Node.operation switched = "switch" && Node.has_parameters switched)
    "catalog Switch is not the standard parameterized SOP switch";
  let switched, switch_effects = edit_parameters switched
      ~node_id:(Node.id switched)
      ["input", Parameter.Choice_value "1 · dodecahedron"]
      |> Result.get_ok in
  let switch_value = Node.parameter_fields switched
      |> List.find (fun field -> field.Parameter.name = "input") in
  check (switch_effects.cook
      && switch_value.current
         = Parameter.Choice_value "1 · dodecahedron")
    "catalog Switch did not retain its selected labeled input";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:1_000_000
      |> Result.get_ok in
  let cube_topology = Pdk.Geometry.topology (cook session cube) in
  check (Pdk.Topology.primitive_count cube_topology = 6
      && Pdk.Topology.primitive_size cube_topology 0 = 4)
    "catalog Box default must retain six quad faces";
  check (Pdk.Geometry.primitive_count (cook session switched)
      = Pdk.Geometry.primitive_count (cook session dodecahedron))
    "catalog Switch did not cook the selected dodecahedron branch";
  let replacement = Sop_catalog.Grid.create ~label:"replacement-grid"
      ~columns:2 ~rows:2 ~size:1. () in
  let document = Edit_graph.of_graph switched
      |> Edit_graph.add_node replacement |> Result.get_ok
      |> Edit_graph.connect ~source:(Node.id replacement)
           ~consumer:(Node.id switched) ~input_index:1 |> Result.get_ok in
  let rebuilt_switch = Edit_graph.compile document |> Result.get_ok in
  let switch_field = Node.parameter_fields rebuilt_switch
      |> List.find (fun field -> field.Parameter.name = "input") in
  check (match switch_field.kind with
    | Parameter.Choice_view options -> Array.exists
        (String.equal "1 · replacement-grid") options
    | _ -> false)
    "rewiring a Switch did not rebuild its input-dependent parameter labels";
  Session.close session;
  let factory_keys = List.map Edit_graph.factory_key
      Sop_catalog.Editor.factories in
  check (List.length factory_keys = 154
      && List.length (List.sort_uniq String.compare factory_keys) = 154)
    "PPX SOP manifest has a missing or duplicate factory key";
  check (not (List.mem "delete_attribute" factory_keys))
    "duplicate Delete Attribute factory remains registered";
  check (not (List.mem "bounding_box" factory_keys))
    "duplicate Bounding Box factory remains registered";
  check (not (List.mem "rename_group" factory_keys))
    "duplicate Rename Group factory remains registered";
  check (not (List.mem "rename_attribute" factory_keys))
    "duplicate Rename Attribute factory remains registered";
  check (not (List.mem "group_promote" factory_keys))
    "duplicate Group Promote factory remains registered";
  check (not (List.mem "promote_attribute" factory_keys))
    "duplicate Promote Attribute factory remains registered";
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor catalog is missing " ^ key))
    ["box"; "grid"; "platonic"; "points"; "switch";
     "copy_to_points"; "boolean_fracture"; "boolean"; "boolean_seam";
     "boolean_detect"; "intersection_analysis";
     "attribute_noise_quaternion";
     "point_jitter"; "null"; "normals"; "transform"; "triangulate";
     "mountain"; "line"; "circle"; "spiral"; "uv_sphere"; "torus"; "tube";
     "match_size"; "mirror"; "clip"; "exploded_view"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor topology catalog is missing " ^ key))
    ["crease"; "subdivide"; "edge_divide"; "edge_collapse"; "dissolve";
     "poly_bevel"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor deformation catalog is missing " ^ key))
    ["peak"; "bend"; "smooth"; "reverse"; "clean"; "facet"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor edge/piece catalog is missing " ^ key))
    ["separate_pieces"; "edge_flip"; "edge_cusp"; "edge_straighten";
     "circle_from_edges"; "edge_equalize"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor modeling catalog is missing " ^ key))
    ["snap_to_grid"; "remesh"; "poly_extrude"; "poly_fill";
     "convert_line"; "resample"; "carve"; "ends"; "join_curves";
     "poly_path"; "poly_reduce"; "measure_curvature";
     "attribute_laplacian"; "polyframe"; "duplicate"; "match_axis";
     "convex_hull"; "extract_centroid"; "bound"];
  check (List.mem "fuse" factory_keys) "SOP editor catalog is missing fuse";
  check (List.mem "ray" factory_keys) "SOP editor catalog is missing ray";
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor distance catalog is missing " ^ key))
    ["distance_along_geometry"; "distance_from_geometry";
     "distance_from_target"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor topology/attribute catalog is missing " ^ key))
    ["point_split"; "poly_bridge"; "graph_color"; "edge_relax";
     "poly_loft"; "revolve"; "sweep"; "polywire"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor attribute catalog is missing " ^ key))
    ["measure"; "connectivity"; "set_float"; "set_int"; "set_vector";
     "set_orient"; "set_transform"; "set_color";
     "rest_position"; "enumerate"; "attribute_blur"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor UV catalog is missing " ^ key))
    ["uv_project"; "uv_transform"; "uv_auto_seam"; "uv_unitize";
     "uv_flatten"; "uv_relax"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor group catalog is missing " ^ key))
    ["group_edges"; "group_random"; "group_bounds"; "group_normal";
     "group_non_planar"; "group_backface"; "group_edge_depth";
     "group_unshared"; "group_boundary_components";
     "group_from_attribute_boundary"; "group_promote_boundary";
     "group_promotions"; "group_invert"; "group_delete"; "group_rename";
     "group_find_path";
     "group_copy"; "group_transfer"; "groups_from_name";
     "group_combine"; "group_expand"; "group_range"; "group_ranges";
     "name_from_groups"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor general catalog is missing " ^ key))
    ["poly_cut"; "sort"; "noise_displace"; "color_by_height"; "scatter"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor attribute generator is missing " ^ key))
    ["attribute_noise"; "attribute_remap"; "attribute_randomize";
     "attribute_mirror"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor transport catalog is missing " ^ key))
    ["rewire_vertices"; "edge_transport"; "edge_transport_curves";
     "edge_transport_parent"];
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor metadata utility is missing " ^ key))
    ["compact_points"; "bound"; "group_rename";
     "delete_edge_group"; "rename_edge_group"; "delete_attributes";
     "rename_attributes"; "swap_attributes";
     "triangulate_2d"; "extract_point_from_curve"; "soft_transform";
     "point_generate"; "point_replicate"; "attribute_fade";
     "blast_by_attribute"; "blast"];
  check (List.mem "point_velocity" factory_keys)
    "SOP editor catalog is missing point_velocity";
  List.iter (fun key -> check (List.mem key factory_keys)
      ("SOP editor transfer catalog is missing " ^ key))
    ["attribute_transfer"; "attribute_transfer_all";
     "attribute_transfer_surface"; "attribute_copy";
     "attribute_interpolate";
     "promote_attributes"];
  List.iter (fun factory ->
    let slots = List.init (Edit_graph.factory_arity factory) (fun _ -> None) in
    match Edit_graph.instantiate_optional factory slots with
    | Ok node -> check
        (Node.operation node = Edit_graph.factory_operation factory)
        (Printf.sprintf "registered SOP %s advertises operation %s but builds %s"
          (Edit_graph.factory_key factory)
          (Edit_graph.factory_operation factory) (Node.operation node))
    | Error message -> fail (Printf.sprintf
        "registered SOP %s could not be constructed: %s"
        (Edit_graph.factory_key factory) message))
    Sop_catalog.Editor.factories;
  let match_size_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "match_size")
      Sop_catalog.Editor.factories in
  check (Edit_graph.factory_inputs match_size_factory
      = [Edit_graph.Required; Optional]
      && Result.is_ok (Edit_graph.instantiate_optional match_size_factory
        [None; None]))
    "PPX descriptor lost Match Size's optional target input signature";
  List.iter (fun key ->
    let factory = List.find (fun factory ->
        Edit_graph.factory_key factory = key) Sop_catalog.Editor.factories in
    check (Edit_graph.factory_inputs factory
        = [Edit_graph.Required; Optional]
        && Result.is_ok (Edit_graph.instantiate_optional factory [None; None]))
      (key ^ " lost its optional collision input signature"))
    ["boolean_detect"; "intersection_analysis"; "fuse"; "poly_loft";
     "rest_position"];
  let delete_attributes_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "delete_attributes")
      Sop_catalog.Editor.factories in
  check (Edit_graph.factory_inputs delete_attributes_factory
      = [Edit_graph.Required; Optional]
      && Result.is_ok (Edit_graph.instantiate_optional
        delete_attributes_factory [None; None]))
    "Delete Attributes lost its optional reference input signature";
  let point_replicate_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "point_replicate")
      Sop_catalog.Editor.factories in
  check (Edit_graph.factory_inputs point_replicate_factory
      = [Edit_graph.Required; Optional]
      && Result.is_ok (Edit_graph.instantiate_optional point_replicate_factory
        [None; None]))
    "Point Replicate lost its optional custom-shape input signature";
  let attribute_fade_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "attribute_fade")
      Sop_catalog.Editor.factories in
  check (Edit_graph.factory_inputs attribute_fade_factory
      = [Edit_graph.Required; Optional; Optional]
      && Result.is_ok (Edit_graph.instantiate_optional attribute_fade_factory
        [None; None; None]))
    "Attribute Fade lost its two optional source input signatures";
  let fade_source = Sop_catalog.Box.create ~label:"fade-source" ()
  and fade_hold = Sop_catalog.Box.create ~label:"fade-hold" () in
  let fade = Edit_graph.instantiate_optional attribute_fade_factory
      [Some fade_source; None; Some fade_hold] |> Result.get_ok in
  let fade, _ = Node.apply_parameters fade
      ["fade_in", Parameter.Float_value 3.] |> Result.get_ok in
  check (List.map Node.id (Node.inputs fade)
      = [Node.id fade_source; Node.id fade_hold])
    "Attribute Fade parameter edit reassigned its sparse hold-source port";
  let point_velocity_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "point_velocity")
      Sop_catalog.Editor.factories in
  check (Edit_graph.factory_inputs point_velocity_factory
      = [Edit_graph.Required; Optional; Optional]
      && Result.is_ok (Edit_graph.instantiate_optional point_velocity_factory
        [None; None; None]))
    "Point Velocity lost its previous/next optional input signatures";
  let velocity = Edit_graph.instantiate_optional point_velocity_factory
      [Some fade_source; None; Some fade_hold] |> Result.get_ok in
  let velocity, _ = Node.apply_parameters velocity
      ["dt", Parameter.Float_value 0.1] |> Result.get_ok in
  check (List.map Node.id (Node.inputs velocity)
      = [Node.id fade_source; Node.id fade_hold])
    "Point Velocity parameter edit reassigned its sparse next-sample port";
  let points_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "points") Sop_catalog.Editor.factories in
  let points = Edit_graph.instantiate points_factory [] |> Result.get_ok in
  check (Node.operation points = "point_generate"
      && Edit_graph.factory_arity points_factory = 0)
    "point-generation editor factory has the wrong node or arity";
  let point_session = Session.create ~max_entries:2
      ~max_payload_bytes:1_000_000 |> Result.get_ok in
  let point_mesh = cook point_session points |> Bridge.to_mesh
      |> Result.map_error Pdk.Error.to_string |> Result.get_ok in
  check (Mesh.mode point_mesh = Mesh.Points && Mesh.vertex_count point_mesh = 50)
    "point-only SOP output did not retain point rendering mode";
  Session.close point_session;
  let explosion = Sketch_support.Packed_pieces.explosion graph |> Option.get in
  check (Node.operation graph = "exploded_view" && explosion.amount = 0.32
      && explosion.piece_attribute = "piece")
    "standard Exploded View node lost its operation or PPX defaults";
  let camera_factory = List.find (fun factory ->
      Edit_graph.factory_key factory = "camera") Sop_catalog.Editor.factories in
  let camera_node = Edit_graph.instantiate camera_factory [] |> Result.get_ok in
  let camera, follows = Sop_catalog.Camera.of_node camera_node |> Option.get in
  check (not follows && Camera.position camera = Vec3.create 0. 0. 7.)
    "camera accessor lost the catalog defaults";
  let eye = Vec3.create 2. 3. 8. and target = Vec3.create 1. 0. 0. in
  let edits = Sop_catalog.Camera.to_values ~eye ~target ~fov_y:0.7 in
  let camera_node, _ = Node.apply_parameters camera_node
      (("follow_viewport", Parameter.Bool_value true) :: edits) |> Result.get_ok in
  let camera, follows = Sop_catalog.Camera.of_node camera_node |> Option.get in
  check (follows && Camera.position camera = eye && Camera.target camera = target
      && match Camera.projection camera with
        | Camera.Perspective { fov_y; _ } -> Float.abs (fov_y -. 0.7) < 1e-12
        | _ -> false)
    "camera accessor failed to round-trip viewport values";
  check (Sop_catalog.Camera.of_node source = None)
    "camera accessor accepted a non-camera node";
  print_endline "SOP catalog tests passed"
