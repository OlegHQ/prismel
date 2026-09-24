open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error message -> fail message
let near ?(epsilon = 1e-10) left right = abs_float (left -. right) <= epsilon

let position_view geometry = Packed.Float3.Private.view (Geometry.positions geometry)
let topology_view geometry = Topology.Private.view (Geometry.topology geometry)

let equal_storage left right =
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
  | Attribute.Int_array left, Attribute.Int_array right ->
      let left = Packed.Int_array.Private.view left
      and right = Packed.Int_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | Attribute.Float_array left, Attribute.Float_array right ->
      let left = Packed.Float_array.Private.view left
      and right = Packed.Float_array.Private.view right in
      left.offsets = right.offsets && left.values = right.values
  | _ -> false

let equal_group left right =
  Group.owner left = Group.owner right
  && String.equal (Group.name left) (Group.name right)
  && Group.length left = Group.length right
  && Group.ordered_elements left = Group.ordered_elements right
  && begin
    let same = ref true in
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then same := false
    done;
    !same
  end

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let same = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then same := false
    done;
    !same
  end

let equal_geometry left right =
  let lp = position_view left and rp = position_view right
  and lt = topology_view left and rt = topology_view right in
  lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && List.equal (fun left right ->
       Attribute.owner left = Attribute.owner right
       && String.equal (Attribute.name left) (Attribute.name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let with_group group geometry = Geometry.with_group group geometry |> get_string

let check_attribute_storage geometry owner name expected =
  match Geometry.find_attribute ~owner name geometry with
  | Some actual ->
      let expected = Attribute.create_owned ~owner ~name expected |> get_string in
      check (equal_storage actual expected) ("Sweep attribute ancestry: " ^ name)
  | None -> fail ("Sweep attribute missing: " ^ name)

let backbone () = Ops.polyline [|(0., 0., 0.); (0., 0., 2.)|] |> get_ok
let profile () = Ops.polyline ~closed:true
    [|(-1., -1., 0.); (1., -1., 0.); (1., 1., 0.); (-1., 1., 0.)|]
    |> get_ok

let sweep ?connectivity ?tangent ?continuous_closed ?transform_attributes
    ?reverse_cross_sections ?scale ?roll ?twist ?caps ?cap_group ?uv_attribute
    ?cross_section_prefix backbone cross_section =
  Ops.sweep ~grain:1 ?connectivity ?tangent ?continuous_closed
    ?transform_attributes ?reverse_cross_sections ?scale ?roll ?twist ?caps
    ?cap_group ?uv_attribute ?cross_section_prefix ~backbone ~cross_section ()
  |> get_ok

let check_basic_surface () =
  let result = sweep ~caps:true ~cap_group:"caps" (backbone ()) (profile ()) in
  check (Geometry.point_count result = 8 && Geometry.vertex_count result = 24
      && Geometry.primitive_count result = 6) "Sweep quad/cap cardinality";
  let positions = position_view result and topology = topology_view result in
  check (near positions.x.(0) (-1.) && near positions.y.(0) (-1.)
      && near positions.z.(0) 0. && near positions.x.(6) 1.
      && near positions.y.(6) 1. && near positions.z.(6) 2.)
    "Sweep local XY frame placement";
  check (Array.sub topology.vertex_points 0 16 =
      [|0;1;5;4; 1;2;6;5; 2;3;7;6; 3;0;4;7|])
    "Sweep quad topology/winding";
  check (Array.sub topology.vertex_points 16 8 = [|3;2;1;0; 4;5;6;7|])
    "Sweep cap winding";
  let caps = Geometry.find_group ~owner:Group.Primitive "caps" result
      |> Option.get in
  check (Group.cardinality caps = 2 && Group.mem 4 caps && Group.mem 5 caps)
    "Sweep cap group";
  match Geometry.find_attribute ~owner:Attribute.Vertex "uv" result with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values ->
           let values = Packed.Float2.Private.view values in
           check (near values.x.(0) 0. && near values.y.(0) 0.
               && near values.x.(1) 0.25 && near values.y.(2) 1.)
             "Sweep arc-length surface UV"
       | _ -> fail "Sweep UV has wrong storage")
  | None -> fail "Sweep UV missing"

let check_connectivity () =
  let backbone = backbone () and profile = profile () in
  let expected = [
    Ops.Grid_points, (8, 0, 0);
    Ops.Grid_rows, (8, 8, 2);
    Ops.Grid_columns, (8, 8, 4);
    Ops.Grid_rows_and_columns, (8, 16, 6);
    Ops.Grid_quads, (8, 16, 4);
    Ops.Grid_triangles, (8, 24, 8);
    Ops.Grid_reverse_triangles, (8, 24, 8);
    Ops.Grid_alternating_triangles, (8, 24, 8) ] in
  List.iter (fun (connectivity, (points, vertices, primitives)) ->
    let result = sweep ~connectivity backbone profile in
    check (Geometry.point_count result = points
        && Geometry.vertex_count result = vertices
        && Geometry.primitive_count result = primitives)
      "Sweep connectivity cardinality") expected;
  let regular = sweep ~connectivity:Ops.Grid_triangles backbone profile
  and reverse = sweep ~connectivity:Ops.Grid_reverse_triangles backbone profile in
  check ((topology_view regular).vertex_points <>
      (topology_view reverse).vertex_points) "Sweep triangle modes collapsed"

let check_payload_and_groups () =
  let backbone = backbone ()
      |> with_attribute Attribute.Point "id" (Attribute.Int [|10;20|])
      |> with_attribute Attribute.Vertex "corner" (Attribute.Int [|100;200|])
      |> with_attribute Attribute.Primitive "piece" (Attribute.Text [|"spine"|])
      |> with_group (Group.init ~owner:Group.Point ~name:"start" 2
           (fun point -> point = 0))
      |> fun geometry -> Ops.group_edges ~grain:1 ~name:"spine_edges" geometry
           |> get_ok in
  let profile = profile ()
      |> with_attribute Attribute.Point "id" (Attribute.Int [|1;2;3;4|])
      |> with_attribute Attribute.Vertex "corner" (Attribute.Int [|5;6;7;8|])
      |> with_attribute Attribute.Primitive "piece" (Attribute.Text [|"profile"|])
      |> with_group (Group.init ~owner:Group.Point ~name:"positive_x" 4
           (fun point -> point = 1 || point = 2))
      |> fun geometry -> Ops.group_edges ~grain:1 ~name:"profile_edges" geometry
           |> get_ok in
  let result = sweep ~caps:true backbone profile in
  let point_int name = match Geometry.find_attribute ~owner:Attribute.Point name result with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Int values -> values | _ -> fail (name ^ " storage"))
    | None -> fail (name ^ " missing") in
  check (point_int "id" = [|10;10;10;10;20;20;20;20|])
    "Sweep backbone point ancestry";
  check (point_int "cross_section_id" = [|1;2;3;4;1;2;3;4|])
    "Sweep profile point ancestry";
  let start = Geometry.find_group ~owner:Group.Point "start" result |> Option.get
  and positive = Geometry.find_group ~owner:Group.Point
      "cross_section_positive_x" result |> Option.get in
  check (Group.cardinality start = 4 && Group.cardinality positive = 4)
    "Sweep dual-input point groups";
  let spine_edges = Geometry.find_edge_group "spine_edges" result |> Option.get
  and profile_edges = Geometry.find_edge_group "cross_section_profile_edges" result
      |> Option.get in
  check (Edge_group.cardinality spine_edges = 4)
    "Sweep backbone native-edge ancestry";
  check (Edge_group.cardinality profile_edges = 8)
    "Sweep profile native-edge ancestry"

let check_multiple_and_selection () =
  let backbone_source = Ops.merge [
      Ops.polyline [|(0.,0.,0.); (0.,0.,1.)|] |> get_ok;
      Ops.polyline [|(4.,0.,0.); (4.,0.,1.)|] |> get_ok] |> get_ok in
  let profile_source = Ops.merge [
      Ops.polyline ~closed:true
        [|(0.2,0.,0.); (-0.1,0.17,0.); (-0.1,-0.17,0.)|] |> get_ok;
      profile ()] |> get_ok in
  let all = Ops.sweep ~grain:1 ~backbone:backbone_source
      ~cross_section:profile_source () |> get_ok in
  check (Geometry.point_count all = 28 && Geometry.primitive_count all = 14)
    "Sweep multiple-backbone/profile Cartesian ordering/cardinality";
  let selected_backbone = Group.init ~owner:Group.Primitive ~name:"selected_b"
      2 (fun primitive -> primitive = 1)
  and selected_profile = Group.init ~owner:Group.Primitive ~name:"selected_p"
      2 (fun primitive -> primitive = 1) in
  let selected = Ops.sweep ~grain:1 ~backbones:selected_backbone
      ~cross_sections:selected_profile ~backbone:backbone_source
      ~cross_section:profile_source () |> get_ok in
  check (Geometry.point_count selected = 8
      && Geometry.primitive_count selected = 4
      && near (position_view selected).x.(0) 3.)
    "Sweep typed input curve restrictions"

let check_transform_attributes () =
  let attributed_backbone = backbone ()
      |> with_attribute Attribute.Point "pscale" (Attribute.Float [|2.;0.5|])
      |> with_attribute Attribute.Point "scale"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|1.;1.|] ~y:[|0.5;2.|] ~z:[|1.;1.|]))
      |> with_attribute Attribute.Point "up"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|0.;0.|] ~y:[|1.;1.|] ~z:[|0.;0.|])) in
  let result = sweep attributed_backbone (profile ()) in
  let positions = position_view result in
  check (near positions.x.(0) (-2.) && near positions.y.(0) (-1.)
      && near positions.x.(4) (-0.5) && near positions.y.(4) (-1.))
    "Sweep pscale/scale transform attributes";
  let rotated = sweep ~roll:(Float.pi /. 2.) (backbone ()) (profile ()) in
  let rotated = position_view rotated in
  check (near rotated.x.(0) 1. && near rotated.y.(0) (-1.))
    "Sweep roll did not rotate profile around tangent";
  let reversed = sweep ~reverse_cross_sections:true (backbone ()) (profile ()) in
  let reversed = position_view reversed in
  check (near reversed.x.(0) (-1.) && near reversed.y.(0) 1.)
    "Sweep reverse cross sections"

let check_frame_controls () =
  let corner = Ops.polyline
      [|(0.,0.,0.); (0.,0.,1.); (1.,0.,1.)|] |> get_ok in
  let previous = sweep ~tangent:Ops.Sweep_previous_edge corner (profile ())
  and next = sweep ~tangent:Ops.Sweep_next_edge corner (profile ())
  and fixed = sweep ~tangent:Ops.Sweep_z_axis corner (profile ()) in
  let previous = position_view previous and next = position_view next
  and fixed = position_view fixed in
  check (near previous.x.(4) (-1.) && near previous.y.(4) (-1.)
      && near previous.z.(4) 1.)
    "Sweep previous-edge tangent frame";
  check (near next.x.(4) 0. && near next.y.(4) (-1.)
      && near next.z.(4) 2.)
    "Sweep next-edge tangent frame";
  check (near fixed.x.(8) 0. && near fixed.y.(8) (-1.)
      && near fixed.z.(8) 1.)
    "Sweep fixed-Z tangent frame";
  let half = sqrt 0.5 in
  let oriented = backbone ()
      |> with_attribute Attribute.Point "N"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|1.;1.|] ~y:[|0.;0.|] ~z:[|0.;0.|]))
      |> with_attribute Attribute.Point "up"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|0.;0.|] ~y:[|0.;0.|] ~z:[|1.;1.|]))
      |> with_attribute Attribute.Point "orient"
           (Attribute.Float4 (Packed.Float4.of_owned
             ~x:[|0.;0.|] ~y:[|half;half|] ~z:[|0.;0.|] ~w:[|half;half|]
             |> get_string)) in
  let oriented = sweep oriented (profile ()) |> position_view in
  check (near oriented.x.(0) 0. && near oriented.y.(0) (-1.)
      && near oriented.z.(0) 1.)
    "Sweep orient quaternion precedence and frame";
  let normal_driven = backbone ()
      |> with_attribute Attribute.Point "N"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|1.;1.|] ~y:[|0.;0.|] ~z:[|0.;0.|]))
      |> with_attribute Attribute.Point "up"
           (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
             ~x:[|0.;0.|] ~y:[|1.;1.|] ~z:[|0.;0.|])) in
  let normal_driven = sweep normal_driven (profile ()) |> position_view in
  check (near normal_driven.x.(0) 0. && near normal_driven.y.(0) (-1.)
      && near normal_driven.z.(0) 1.)
    "Sweep N/up frame"

let check_all_storage_ancestry () =
  let float2 x y = Packed.Float2.of_owned ~x ~y |> get_string
  and float3 x y z = Packed.Float3.Private.of_owned_exn ~x ~y ~z
  and float4 x y z w = Packed.Float4.of_owned ~x ~y ~z ~w |> get_string
  and int_rows offsets values =
    Packed.Int_array.create_owned ~offsets ~values |> get_string
  and float_rows offsets values =
    Packed.Float_array.create_owned ~offsets ~values |> get_string in
  let source = profile ()
      |> with_attribute Attribute.Point "f" (Attribute.Float [|1.;2.;3.;4.|])
      |> with_attribute Attribute.Point "i" (Attribute.Int [|1;2;3;4|])
      |> with_attribute Attribute.Point "s"
           (Attribute.Text [|"a";"b";"c";"d"|])
      |> with_attribute Attribute.Point "v2"
           (Attribute.Float2 (float2 [|1.;2.;3.;4.|] [|5.;6.;7.;8.|]))
      |> with_attribute Attribute.Point "v3"
           (Attribute.Float3 (float3 [|1.;2.;3.;4.|] [|5.;6.;7.;8.|]
             [|9.;10.;11.;12.|]))
      |> with_attribute Attribute.Point "v4"
           (Attribute.Float4 (float4 [|1.;2.;3.;4.|] [|5.;6.;7.;8.|]
             [|9.;10.;11.;12.|] [|13.;14.;15.;16.|]))
      |> with_attribute Attribute.Point "ia"
           (Attribute.Int_array (int_rows [|0;2;3;3;4|] [|1;2;3;4|]))
      |> with_attribute Attribute.Point "fa"
           (Attribute.Float_array
             (float_rows [|0;1;1;3;4|] [|1.;3.;4.;5.|])) in
  let result = sweep ~cross_section_prefix:"profile_" (backbone ()) source in
  let twice values = Array.append values values in
  check_attribute_storage result Attribute.Point "profile_f"
    (Attribute.Float (twice [|1.;2.;3.;4.|]));
  check_attribute_storage result Attribute.Point "profile_i"
    (Attribute.Int (twice [|1;2;3;4|]));
  check_attribute_storage result Attribute.Point "profile_s"
    (Attribute.Text (twice [|"a";"b";"c";"d"|]));
  check_attribute_storage result Attribute.Point "profile_v2"
    (Attribute.Float2 (float2 (twice [|1.;2.;3.;4.|])
      (twice [|5.;6.;7.;8.|])));
  check_attribute_storage result Attribute.Point "profile_v3"
    (Attribute.Float3 (float3 (twice [|1.;2.;3.;4.|])
      (twice [|5.;6.;7.;8.|]) (twice [|9.;10.;11.;12.|])));
  check_attribute_storage result Attribute.Point "profile_v4"
    (Attribute.Float4 (float4 (twice [|1.;2.;3.;4.|])
      (twice [|5.;6.;7.;8.|]) (twice [|9.;10.;11.;12.|])
      (twice [|13.;14.;15.;16.|])));
  check_attribute_storage result Attribute.Point "profile_ia"
    (Attribute.Int_array (int_rows [|0;2;3;3;4;6;7;7;8|]
      [|1;2;3;4;1;2;3;4|]));
  check_attribute_storage result Attribute.Point "profile_fa"
    (Attribute.Float_array (float_rows [|0;1;1;3;4;5;5;7;8|]
      [|1.;3.;4.;5.;1.;3.;4.;5.|]))

let normalize (x, y, z) =
  let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
  x /. length, y /. length, z /. length

let transport (tx0, ty0, tz0) (tx1, ty1, tz1) (x, y, z) =
  let ax = (ty0 *. tz1) -. (tz0 *. ty1)
  and ay = (tz0 *. tx1) -. (tx0 *. tz1)
  and az = (tx0 *. ty1) -. (ty0 *. tx1) in
  let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
  and cosine = (tx0 *. tx1) +. (ty0 *. ty1) +. (tz0 *. tz1) in
  if sine <= 1e-12 then x, y, z
  else
    let kx = ax /. sine and ky = ay /. sine and kz = az /. sine in
    let cross_x = (ky *. z) -. (kz *. y)
    and cross_y = (kz *. x) -. (kx *. z)
    and cross_z = (kx *. y) -. (ky *. x)
    and dot = (kx *. x) +. (ky *. y) +. (kz *. z) in
    (x *. cosine) +. (cross_x *. sine) +. (kx *. dot *. (1. -. cosine)),
    (y *. cosine) +. (cross_y *. sine) +. (ky *. dot *. (1. -. cosine)),
    (z *. cosine) +. (cross_z *. sine) +. (kz *. dot *. (1. -. cosine))

let check_closed_continuity () =
  let count = 97 in
  let backbone_values = Array.init count (fun point ->
      let t = 2. *. Float.pi *. float_of_int point /. float_of_int count in
      let radius = 2. +. (0.35 *. cos (3. *. t)) in
      radius *. cos (2. *. t), 0.4 *. sin (3. *. t),
      radius *. sin (2. *. t)) in
  let backbone = Ops.polyline ~closed:true backbone_values |> get_ok
  and profile = Ops.polyline ~closed:true
      [|(0.1,0.,0.); (-0.05,0.0866025403784439,0.);
        (-0.05,-0.0866025403784439,0.)|] |> get_ok in
  let result = sweep ~tangent:Ops.Sweep_central_difference ~twist:2.3
      backbone profile in
  let output = position_view result in
  let bx0, by0, bz0 = backbone_values.(0)
  and bxl, byl, bzl = backbone_values.(count - 1) in
  let first_vector = normalize
      (output.x.(0) -. bx0, output.y.(0) -. by0, output.z.(0) -. bz0)
  and last_at = (count - 1) * 3 in
  let last_vector = normalize
      (output.x.(last_at) -. bxl, output.y.(last_at) -. byl,
       output.z.(last_at) -. bzl) in
  let x_prev, y_prev, z_prev = backbone_values.(count - 2)
  and x_next, y_next, z_next = backbone_values.(1) in
  let last_tangent = normalize
      (bx0 -. x_prev, by0 -. y_prev, bz0 -. z_prev)
  and first_tangent = normalize
      (x_next -. bxl, y_next -. byl, z_next -. bzl) in
  let x, y, z = transport last_tangent first_tangent last_vector in
  let fx, fy, fz = first_vector in
  check (((x *. fx) +. (y *. fy) +. (z *. fz)) > 1. -. 1e-9)
    "Sweep closed continuity did not absorb non-integral twist at the seam"

let expect_invalid = function
  | Error error when Error.code error = "invalid_geometry" -> ()
  | Error error -> fail ("unexpected Sweep error: " ^ Error.to_string error)
  | Ok _ -> fail "expected invalid Sweep input"

let check_validation_and_parallel () =
  expect_invalid (Ops.sweep ~scale:Float.nan ~backbone:(backbone ())
    ~cross_section:(profile ()) ());
  expect_invalid (Ops.sweep ~caps:true ~connectivity:Ops.Grid_rows
    ~backbone:(backbone ()) ~cross_section:(profile ()) ());
  let polygon = Ops.grid ~columns:1 ~rows:1 ~size:1. () |> get_ok in
  expect_invalid (Ops.sweep ~backbone:polygon ~cross_section:(profile ()) ());
  let repeated = Ops.polyline [|(0.,0.,0.); (0.,0.,0.)|] |> get_ok in
  expect_invalid (Ops.sweep ~backbone:repeated ~cross_section:(profile ()) ());
  let partly_invalid = Ops.merge [backbone ();
      Ops.polyline [|(3.,0.,0.); (3.,0.,1.)|] |> get_ok] |> get_ok
      |> with_attribute Attribute.Point "pscale"
           (Attribute.Float [|1.;1.;Float.nan;Float.nan|]) in
  let first_curve = Group.init ~owner:Group.Primitive ~name:"first_curve" 2
      (fun primitive -> primitive = 0) in
  ignore (Ops.sweep ~backbones:first_curve ~backbone:partly_invalid
      ~cross_section:(profile ()) () |> get_ok);
  expect_invalid (Ops.sweep ~cross_section_prefix:""
    ~backbone:(backbone ()
      |> with_attribute Attribute.Point "id" (Attribute.Int [|5;6|]))
    ~cross_section:(profile ()
      |> with_attribute Attribute.Point "id" (Attribute.Int [|1;2;3;4|]))
    ());
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.sweep ~cancel:cancelled ~backbone:(backbone ())
      ~cross_section:(profile ()) () with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "Sweep ignored cancellation");
  let count = 5_001 in
  let dense_backbone = Array.init count (fun point ->
      let t = float_of_int point *. 0.002 in
      0.25 *. sin (t *. 0.7), 0.2 *. cos (t *. 0.43), t)
      |> Ops.polyline |> get_ok
      |> fun geometry -> Ops.group_edges ~grain:257 ~name:"spine_edges" geometry
           |> get_ok in
  let sides = 32 in
  let dense_profile = Array.init sides (fun side ->
      let angle = 2. *. Float.pi *. float_of_int side /. float_of_int sides in
      0.08 *. cos angle, 0.08 *. sin angle, 0.)
      |> Ops.polyline ~closed:true |> get_ok
      |> fun geometry -> Ops.group_edges ~grain:257 ~name:"profile_edges" geometry
           |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.sweep ~grain:257 ~connectivity:Ops.Grid_alternating_triangles
        ~caps:true ~cap_group:"caps" ~twist:2.3 ~backbone:dense_backbone
        ~cross_section:dense_profile () |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain general Sweep geometry differ";
  check (Geometry.point_count one = count * sides
      && Geometry.primitive_count one = ((count - 1) * sides * 2) + 2)
    "dense Sweep cardinality"

let () =
  check_basic_surface ();
  check_connectivity ();
  check_payload_and_groups ();
  check_multiple_and_selection ();
  check_transform_attributes ();
  check_frame_controls ();
  check_all_storage_ancestry ();
  check_closed_continuity ();
  check_validation_and_parallel ();
  print_endline "Sweep tests passed"
