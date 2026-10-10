open Rays
open Rdk
open Rdk_test_support

let equal_storage left right =
  match Attribute.Private.storage left, Attribute.Private.storage right with
  | Attribute.Float left, Attribute.Float right -> left = right
  | Attribute.Int left, Attribute.Int right -> left = right
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
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

let equal_attribute left right =
  Attribute.owner left = Attribute.owner right
  && String.equal (Attribute.name left) (Attribute.name right)
  && equal_storage left right

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Bytes.equal (Group.Private.bits_view left) (Group.Private.bits_view right)
  && Group.Private.order_view left = Group.Private.order_view right

let equal_geometry left right =
  let left_positions = Packed.Float3.Private.view (Geometry.positions left)
  and right_positions = Packed.Float3.Private.view (Geometry.positions right)
  and left_topology = Topology.Private.view (Geometry.topology left)
  and right_topology = Topology.Private.view (Geometry.topology right) in
  left_positions.x = right_positions.x
  && left_positions.y = right_positions.y
  && left_positions.z = right_positions.z
  && left_topology.point_count = right_topology.point_count
  && left_topology.vertex_points = right_topology.vertex_points
  && left_topology.primitive_offsets = right_topology.primitive_offsets
  && Bytes.equal left_topology.primitive_kinds right_topology.primitive_kinds
  && List.equal equal_attribute (Geometry.attributes left)
       (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group (Geometry.edge_groups left)
       (Geometry.edge_groups right)

let with_attribute name storage geometry =
  Geometry.with_attribute
    (Attribute.create_owned ~name ~owner:Attribute.Point storage |> get_string_ok)
    geometry |> get_string_ok

let int_attribute ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let check_clipped_edge_group () =
  let source = Box_generator.box ~connectivity:Box_generator.Box_quads ~consolidate_points:true
      ~size:(Vec3.create 2. 2. 2.) () |> get_ok
      |> Group_mesh.group_edges ~name:"plane_edges" |> get_ok in
  let output = Plane_clip.clip ~fill:true ~clipped_edge_group:"plane_edges"
      ~origin:Vec3.zero ~normal:Vec3.unit_x source |> get_ok in
  let group = Geometry.find_edge_group "plane_edges" output |> Option.get in
  check (Edge_group.cardinality group = 4)
    "clipped edge output did not replace the existing group with the cap boundary";
  let index = Topology_index.create (Geometry.topology output)
  and positions = Packed.Float3.Private.view (Geometry.positions output) in
  Edge_group.iter (fun edge ->
    let a, b = Topology_index.edge_points index edge in
    check (near positions.x.(a) 0. && near positions.x.(b) 0.)
      "clipped edge group contains an edge away from the clipping plane") group;
  let unioned = Plane_clip.clip ~fill:true ~replace_existing_groups:false
      ~clipped_edge_group:"plane_edges" ~origin:Vec3.zero
      ~normal:Vec3.unit_x source |> get_ok in
  let unioned = Geometry.find_edge_group "plane_edges" unioned |> Option.get in
  check (Edge_group.cardinality unioned > Edge_group.cardinality group)
    "Clip Replace Existing=false did not union native edge membership"

let clipped_count selection source =
  let output = Plane_clip.clip ~grain:1 ~selection ~clipped_group:"clipped"
      ~origin:Vec3.zero ~normal:Vec3.unit_x source |> get_ok in
  match Geometry.find_group ~owner:Group.Primitive "clipped" output with
  | Some group -> Group.cardinality group
  | None -> fail "typed selected Clip missing clipped group"

let check_selected_free_points () =
  let source = Line_geometry.points [|(-2.,0.,0.); (-1.,0.,0.); (1.,0.,0.)|]
      |> with_attribute "id" (Attribute.Int [|10; 20; 30|]) in
  let selected = Group.init ~owner:Group.Point ~name:"selected_free" 3
      (fun point -> point = 0) in
  let output = Plane_clip.clip ~selection:(Transform_ops.Selected_points selected)
      ~origin:Vec3.zero ~normal:Vec3.unit_x source |> get_ok in
  check (Geometry.point_count output = 2
      && int_attribute ~owner:Attribute.Point "id" output = [|20; 30|])
    "point-selected Clip did not restrict free-point filtering"

let check_parallel_exact () =
  let source = Plane_generators.grid ~connectivity:Plane_generators.Grid_alternating_triangles
      ~columns:600 ~rows:400 ~size:20. () |> get_ok in
  let positions = Packed.Float3.Private.view (Geometry.positions source) in
  let field = Attribute.create_owned ~name:"field" ~owner:Attribute.Point
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init (Geometry.point_count source) (fun point ->
          positions.x.(point) +. (0.2 *. positions.z.(point))))
        ~y:(Array.copy positions.y) ~z:(Array.copy positions.z)
        ~w:(Array.init (Geometry.point_count source) float_of_int)
        |> get_string_ok)) |> get_string_ok in
  let source = Geometry.with_attribute field source |> get_string_ok
      |> Group_mesh.group_edges ~name:"source_edges" |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Plane_clip.clip ~grain:2048 ~keep:Plane_clip.All ~split_connectivity:true
        ~clip_attribute:"field" ~distance:0.137
        ~clipped_edge_group:"clipped_edges" ~clipped_group:"clipped"
        ~above_group:"above" ~below_group:"below" ~origin:Vec3.zero
        ~normal:(Vec3.create 0.7 0.3 (-0.2)) source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "one-domain and four-domain Clip geometry differ";
  check (Geometry.point_count one > 200_000)
    "Clip scale fixture is unexpectedly small";
  let selected = Group.init ~owner:Group.Primitive ~name:"selected"
      (Geometry.primitive_count source) (fun primitive -> primitive mod 3 = 0) in
  let run_selected domains = Parallel.run ~domains (fun () ->
      Plane_clip.clip ~grain:2048 ~keep:Plane_clip.All ~split_connectivity:true
        ~selection:(Transform_ops.Selected_primitives selected)
        ~clip_attribute:"field" ~distance:0.137
        ~clipped_edge_group:"clipped_edges" ~clipped_group:"clipped"
        ~above_group:"above" ~below_group:"below" ~origin:Vec3.zero
        ~normal:(Vec3.create 0.7 0.3 (-0.2)) source |> get_ok) in
  check (equal_geometry (run_selected 1) (run_selected 4))
    "one-domain and four-domain selected Clip geometry differ"

let check_degenerate_fallback () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 1.; 1.; 0.|] ~y:[|0.; 0.; 1.; 1.|]
      ~z:[|0.; 0.; 0.; 0.|] in
  let topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0; 1; 1; 2; 3|] ~primitive_offsets:[|0; 5|]
      ~primitive_kinds:[|Topology.Polygon|] |> get_string_ok in
  let source = Geometry.create ~positions ~topology () |> get_string_ok in
  let output = Plane_clip.clip ~origin:(Vec3.create (-10.) 0. 0.)
      ~normal:Vec3.unit_x source |> get_ok in
  check (Geometry.primitive_count output = 1
      && Geometry.vertex_count output = 4)
    "adjacent repeated-corner polygon did not retain duplicate suppression";
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|1.; (-1.); 1.|] ~y:[|0.; 0.; 1.|] ~z:[|0.; 0.; 0.|] in
  let topology = Topology.create_owned ~point_count:3
      ~vertex_points:[|0; 1; 0; 2|] ~primitive_offsets:[|0; 4|]
      ~primitive_kinds:[|Topology.Polygon|] |> get_string_ok in
  let source = Geometry.create ~positions ~topology () |> get_string_ok in
  let output = Plane_clip.clip ~origin:Vec3.zero ~normal:Vec3.unit_x source |> get_ok in
  check (Geometry.primitive_count output = 1
      && Geometry.vertex_count output = 4)
    "non-adjacent repeated-corner polygon bypassed general duplicate suppression"

let cap_area_yz geometry group =
  let topology = Topology.Private.view (Geometry.topology geometry)
  and positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and total = ref 0. in
  Group.iter (fun primitive ->
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1)
    and twice_area = ref 0. in
    for vertex = first to last - 1 do
      let next = if vertex + 1 = last then first else vertex + 1 in
      let a = topology.vertex_points.(vertex)
      and b = topology.vertex_points.(next) in
      twice_area := !twice_area
          +. ((positions.y.(a) *. positions.z.(b))
             -. (positions.y.(b) *. positions.z.(a)))
    done;
    total := !total +. (abs_float !twice_area *. 0.5)) group;
  !total

let run () =
  check_clipped_edge_group ();
  check_selected_free_points ();
  check_parallel_exact ();
  check_degenerate_fallback ();
  print_endline "clip tests passed"
