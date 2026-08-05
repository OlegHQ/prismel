open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error error -> fail error
let near ?(epsilon = 1e-9) left right = abs_float (left -. right) <= epsilon

let float2_attribute geometry name =
  match Geometry.find_attribute ~owner:Attribute.Vertex name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values -> Packed.Float2.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let float3_attribute ~owner geometry name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let equal_storage left right = match Attribute.storage left, Attribute.storage right with
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
    let equal = ref true in
    for element = 0 to Group.length left - 1 do
      if Group.mem element left <> Group.mem element right then equal := false
    done;
    !equal
  end

let equal_edge_group left right =
  String.equal (Edge_group.name left) (Edge_group.name right)
  && Edge_group.length left = Edge_group.length right
  && begin
    let equal = ref true in
    for edge = 0 to Edge_group.length left - 1 do
      if Edge_group.mem edge left <> Edge_group.mem edge right then equal := false
    done;
    !equal
  end

let equal_geometry left right =
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
       && String.equal (Attribute.kind_name left) (Attribute.kind_name right)
       && equal_storage left right)
       (Geometry.attributes left) (Geometry.attributes right)
  && List.equal equal_group (Geometry.groups left) (Geometry.groups right)
  && List.equal equal_edge_group
       (Geometry.edge_groups left) (Geometry.edge_groups right)

let with_float name values geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name
      (Attribute.Float values) |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let with_int name values geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name
      (Attribute.Int values) |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let with_float3 name ~x ~y ~z geometry =
  let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name
      (Attribute.Float3 values) |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let with_vertex_attribute name storage geometry =
  let attribute = Attribute.create_owned ~owner:Attribute.Vertex ~name storage
      |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let attribute ~owner name storage =
  Attribute.create_owned ~owner ~name storage |> get_string

let find_storage ~owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | None -> fail ("missing attribute " ^ name)
  | Some value -> Attribute.Private.storage value

let expect_invalid = function
  | Error error when Error.code error = "invalid_geometry" -> ()
  | Error error -> fail ("unexpected error " ^ Error.to_string error)
  | Ok _ -> fail "expected invalid PolyWire input"

let check_controls () =
  let source = Ops.polyline [|(0., 0., 0.); (2., 0., 0.)|] |> get_ok
      |> with_float "scale" [|1.; 0.5|]
      |> with_int "seam" [|0; 1|]
      |> with_float "vcoord" [|2.; 5.|]
      |> with_float3 "up" ~x:[|0.; 0.|] ~y:[|1.; 1.|] ~z:[|0.; 0.|] in
  let wire = Ops.sweep_circle ~grain:1 ~sides:4 ~scale_attribute:"scale"
      ~seam_attribute:"seam" ~v_attribute:"vcoord" ~up_attribute:"up"
      ~radius:1. source |> get_ok in
  let positions = Packed.Float3.Private.view (Geometry.positions wire)
  and normals = float3_attribute ~owner:Attribute.Point wire "N"
  and uv = float2_attribute wire "uv" in
  check (Geometry.point_count wire = 8 && Geometry.vertex_count wire = 16
      && Geometry.primitive_count wire = 4) "controlled PolyWire cardinality";
  check (near positions.x.(0) 0. && near positions.y.(0) 1.
      && near positions.z.(0) 0. && near normals.y.(0) 1.)
    "joint-up direction did not orient the first ring";
  check (near positions.x.(4) 2. && near positions.y.(4) 0.
      && near positions.z.(4) 0.5 && near normals.z.(4) 1.)
    "point seam offset did not rotate/scale the second ring";
  check (near uv.y.(0) 2. && near uv.y.(1) 2.
      && near uv.y.(2) 5. && near uv.y.(3) 5.)
    "V texture attribute did not override side coordinates";
  let shifted = Ops.sweep_circle ~sides:4 ~seam_offset:max_int
      ~up_attribute:"up" ~radius:1. source |> get_ok in
  check (Geometry.point_count shifted = 8)
    "large snapped seam offset failed safe normalization"

let normalize x y z =
  let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
  x /. length, y /. length, z /. length

let transport tx0 ty0 tz0 tx1 ty1 tz1 nx ny nz =
  let ax = (ty0 *. tz1) -. (tz0 *. ty1)
  and ay = (tz0 *. tx1) -. (tx0 *. tz1)
  and az = (tx0 *. ty1) -. (ty0 *. tx1) in
  let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
  and cosine = (tx0 *. tx1) +. (ty0 *. ty1) +. (tz0 *. tz1) in
  if sine <= 1e-12 then nx, ny, nz
  else
    let kx = ax /. sine and ky = ay /. sine and kz = az /. sine in
    let cross_x = (ky *. nz) -. (kz *. ny)
    and cross_y = (kz *. nx) -. (kx *. nz)
    and cross_z = (kx *. ny) -. (ky *. nx)
    and dot = (kx *. nx) +. (ky *. ny) +. (kz *. nz) in
    (nx *. cosine) +. (cross_x *. sine) +. (kx *. dot *. (1. -. cosine)),
    (ny *. cosine) +. (cross_y *. sine) +. (ky *. dot *. (1. -. cosine)),
    (nz *. cosine) +. (cross_z *. sine) +. (kz *. dot *. (1. -. cosine))

let check_closed_frame () =
  let count = 97 in
  let source_values = Array.init count (fun point ->
      let t = 2. *. Float.pi *. float_of_int point /. float_of_int count in
      let radius = 2. +. (0.45 *. cos (3. *. t)) in
      radius *. cos (2. *. t), 0.45 *. sin (3. *. t),
      radius *. sin (2. *. t)) in
  let source = Ops.polyline ~closed:true source_values |> get_ok in
  let wire = Ops.sweep_circle ~sides:8 ~radius:0.1 source |> get_ok in
  let normals = float3_attribute ~owner:Attribute.Point wire "N" in
  let point index = let x, y, z = source_values.(index) in x, y, z in
  let x_prev, y_prev, z_prev = point (count - 2)
  and x_last, y_last, z_last = point (count - 1)
  and x_first, y_first, z_first = point 0
  and x_next, y_next, z_next = point 1 in
  let tx_last, ty_last, tz_last = normalize
      (x_first -. x_prev) (y_first -. y_prev) (z_first -. z_prev)
  and tx_first, ty_first, tz_first = normalize
      (x_next -. x_last) (y_next -. y_last) (z_next -. z_last) in
  let last = (count - 1) * 8 in
  let nx, ny, nz = transport tx_last ty_last tz_last tx_first ty_first tz_first
      normals.x.(last) normals.y.(last) normals.z.(last) in
  let alignment = (nx *. normals.x.(0)) +. (ny *. normals.y.(0))
      +. (nz *. normals.z.(0)) in
  check (alignment > 1. -. 1e-10)
    (Printf.sprintf "closed PolyWire frame seam alignment %.12g" alignment)

let check_validation () =
  let line = Ops.polyline [|(0., 0., 0.); (1., 0., 0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~scale_attribute:" " ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~seam_attribute:"missing" ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~v_attribute:"missing" ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~up_attribute:"missing" ~radius:0.1 line);
  let wrong_seam = with_float "seam" [|0.; 0.|] line in
  expect_invalid (Ops.sweep_circle ~seam_attribute:"seam" ~radius:0.1 wrong_seam);
  let wrong_v = with_int "v" [|0; 1|] line in
  expect_invalid (Ops.sweep_circle ~v_attribute:"v" ~radius:0.1 wrong_v);
  let wrong = with_float "up" [|1.; 1.|] line in
  expect_invalid (Ops.sweep_circle ~up_attribute:"up" ~radius:0.1 wrong);
  let parallel = with_float3 "up" ~x:[|1.; 1.|] ~y:[|0.; 0.|]
      ~z:[|0.; 0.|] line in
  expect_invalid (Ops.sweep_circle ~up_attribute:"up" ~radius:0.1 parallel);
  let huge_up = with_float3 "up" ~x:[|0.; 0.|]
      ~y:[|max_float; max_float|] ~z:[|0.; 0.|] line in
  let huge_up_wire = Ops.sweep_circle ~up_attribute:"up" ~radius:0.1 huge_up
      |> get_ok in
  let huge_normals = float3_attribute ~owner:Attribute.Point huge_up_wire "N" in
  check (near huge_normals.y.(0) 1.)
    "scale-safe joint-up normalization rejected a finite large vector";
  let invalid_v = with_float "v" [|0.; Float.nan|] line in
  expect_invalid (Ops.sweep_circle ~v_attribute:"v" ~radius:0.1 invalid_v);
  let extreme_seams = with_int "seam" [|min_int; max_int|] line in
  ignore (Ops.sweep_circle ~seam_offset:min_int ~seam_attribute:"seam"
      ~radius:0.1 extreme_seams |> get_ok);
  let overflowing = with_float "scale" [|2.; 2.|] line in
  expect_invalid (Ops.sweep_circle ~scale_attribute:"scale" ~radius:max_float
      overflowing);
  expect_invalid (Ops.sweep_circle ~cap_group:"caps" ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~caps:true ~cap_group:" " ~radius:0.1 line);
  let repeated = Ops.polyline
      [|(0., 0., 0.); (1., 0., 0.); (1., 0., 0.); (2., 0., 0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~radius:0.1 repeated);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.sweep_circle ~cancel:cancelled ~radius:0.1 line with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "PolyWire ignored cancellation")

let check_parallel_exact () =
  let count = 5_001 in
  let source = Array.init count (fun point ->
      let t = float_of_int point *. 0.002 in
      t, sin (t *. 0.7), cos (t *. 0.43) *. 0.6) |> Ops.polyline |> get_ok
      |> with_float "scale" (Array.init count (fun point ->
          0.7 +. (0.3 *. sin (float_of_int point *. 0.017))))
      |> with_int "seam" (Array.init count (fun point -> (point / 97) - 20))
      |> with_float "vcoord" (Array.init count (fun point ->
          float_of_int point *. 0.003))
      |> with_float3 "up" ~x:(Array.make count 0.) ~y:(Array.make count 1.)
           ~z:(Array.init count (fun point ->
             0.2 *. cos (float_of_int point *. 0.013)))
      |> Ops.group_edges ~grain:257 ~name:"spine_edges" |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
      Ops.sweep_circle ~grain:257 ~sides:12 ~scale_attribute:"scale"
        ~seam_offset:(-3) ~seam_attribute:"seam" ~v_attribute:"vcoord"
        ~up_attribute:"up" ~caps:true ~cap_group:"caps" ~radius:0.08 source
      |> get_ok) in
  let one = run 1 and many = run 4 in
  check (equal_geometry one many)
    "one-domain and four-domain advanced PolyWire geometry differ";
  check (Geometry.point_count one = count * 12
      && Geometry.primitive_count one = ((count - 1) * 12) + 2)
    "advanced PolyWire exactness cardinality"

let advanced_source () =
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.; 2.; 0.; 2.; 9.|] ~y:[|0.; 0.; 3.; 3.; 9.|]
      ~z:(Array.make 5 0.) in
  let topology = Topology.create_owned ~point_count:5
      ~vertex_points:[|0;1; 2;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Topology.Open_polyline; Topology.Open_polyline|]
    |> get_string in
  let selection = Group.ordered ~owner:Group.Primitive ~name:"wire"
      ~length:2 [|0|] |> get_string
  and ordered_points = Group.ordered ~owner:Group.Point ~name:"ordered_points"
      ~length:5 [|1;0|] |> get_string
  and ordered_vertices = Group.ordered ~owner:Group.Vertex ~name:"ordered_vertices"
      ~length:4 [|1;0|] |> get_string
  and ordered_primitives = Group.ordered ~owner:Group.Primitive
      ~name:"ordered_primitives" ~length:2 [|1;0|] |> get_string in
  let source_index = Topology_index.create topology in
  let selected_edge = Topology_index.find_edge_index source_index ~a:0 ~b:1 in
  let edges = Edge_group.init ~topology ~index:source_index ~name:"wire_edge"
      (fun edge -> edge = selected_edge) in
  let int_rows = Packed.Int_array.create_owned ~offsets:[|0;1;3;4;6;7|]
      ~values:[|0;10;11;20;30;31;40|] |> get_string
  and float_rows = Packed.Float_array.create_owned ~offsets:[|0;1;3;4;6;7|]
      ~values:[|0.;10.;11.;20.;30.;31.;40.|] |> get_string
  and vertex_rows = Packed.Int_array.create_owned ~offsets:[|0;1;3;4;6|]
      ~values:[|0;10;11;20;30;31|] |> get_string in
  let attributes = [
    attribute ~owner:Attribute.Point "div" (Attribute.Int [|4;6;5;5;5|]);
    attribute ~owner:Attribute.Point "seg" (Attribute.Int [|1;3;1;1;1|]);
    attribute ~owner:Attribute.Point "pf" (Attribute.Float [|0.;10.;20.;30.;40.|]);
    attribute ~owner:Attribute.Point "pi" (Attribute.Int [|0;10;20;30;40|]);
    attribute ~owner:Attribute.Point "pt"
      (Attribute.Text [|"a";"b";"c";"d";"free"|]);
    attribute ~owner:Attribute.Point "p2" (Attribute.Float2
      (Packed.Float2.of_owned ~x:[|0.;10.;20.;30.;40.|]
        ~y:[|1.;11.;21.;31.;41.|] |> get_string));
    attribute ~owner:Attribute.Point "p3" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:[|0.;10.;20.;30.;40.|]
        ~y:[|1.;11.;21.;31.;41.|] ~z:[|2.;12.;22.;32.;42.|]));
    attribute ~owner:Attribute.Point "p4" (Attribute.Float4
      (Packed.Float4.of_owned ~x:[|0.;10.;20.;30.;40.|]
        ~y:[|1.;11.;21.;31.;41.|] ~z:[|2.;12.;22.;32.;42.|]
        ~w:[|3.;13.;23.;33.;43.|] |> get_string));
    attribute ~owner:Attribute.Point "pia" (Attribute.Int_array int_rows);
    attribute ~owner:Attribute.Point "pfa" (Attribute.Float_array float_rows);
    attribute ~owner:Attribute.Vertex "vf" (Attribute.Float [|0.;10.;20.;30.|]);
    attribute ~owner:Attribute.Vertex "via" (Attribute.Int_array vertex_rows);
    attribute ~owner:Attribute.Primitive "primitive_name"
      (Attribute.Text [|"selected";"retained"|]);
    attribute ~owner:Attribute.Detail "detail" (Attribute.Int [|73|]);
  ] in
  Geometry.create ~positions ~topology ~attributes
    ~groups:[selection; ordered_points; ordered_vertices; ordered_primitives]
    ~edge_groups:[edges] () |> get_string

let check_variable_topology_and_selection () =
  let source = advanced_source () in
  let selection = Geometry.find_group ~owner:Group.Primitive "wire" source
      |> Option.get in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:2 ~primitives:selection ~sides:4
      ~divisions_attribute:"div" ~segments_attribute:"seg" ~caps:true
      ~cap_group:"caps" ~radius:0.25 source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "variable/scoped PolyWire differs between one and four domains";
  check (Geometry.point_count one = 19 && Geometry.vertex_count one = 62
      && Geometry.primitive_count one = 17)
    "variable/scoped PolyWire cardinality";
  let output_topology = Geometry.topology one in
  let triangles = ref 0 and quads = ref 0 in
  for primitive = 0 to 13 do
    match Topology.primitive_size output_topology primitive with
    | 3 -> incr triangles | 4 -> incr quads
    | size -> fail (Printf.sprintf "unexpected zipper face size %d" size)
  done;
  check (!triangles = 6 && !quads = 8)
    (Printf.sprintf "minimal 4-to-6 zipper topology: triangles=%d quads=%d"
      !triangles !quads);
  check (Topology.primitive_size output_topology 14 = 4
      && Topology.primitive_size output_topology 15 = 6
      && Topology.primitive_kind output_topology 16 = Topology.Open_polyline)
    "cap or retained-curve layout";
  let output_positions = Packed.Float3.Private.view (Geometry.positions one) in
  check (near output_positions.x.(0) 0. && near output_positions.y.(0) 3.
      && near output_positions.x.(1) 2. && near output_positions.y.(1) 3.
      && near output_positions.x.(2) 9. && near output_positions.y.(2) 9.)
    "retained/free point prefix";
  (match find_storage ~owner:Attribute.Point "pf" one with
   | Attribute.Float values ->
       check (near values.(7) 5. && near values.(0) 20. && near values.(2) 40.)
         "numeric point interpolation or retained/free ancestry"
   | _ -> fail "pf storage");
  (match find_storage ~owner:Attribute.Point "pi" one with
   | Attribute.Int values -> check (values.(7) = 10)
       "nearest point integer tie policy"
   | _ -> fail "pi storage");
  (match find_storage ~owner:Attribute.Point "pt" one with
   | Attribute.Text values -> check (String.equal values.(7) "b")
       "nearest point text tie policy"
   | _ -> fail "pt storage");
  (match find_storage ~owner:Attribute.Point "p2" one with
   | Attribute.Float2 values ->
       let values = Packed.Float2.Private.view values in
       check (near values.x.(7) 5. && near values.y.(7) 6.)
         "float2 interpolation"
   | _ -> fail "p2 storage");
  (match find_storage ~owner:Attribute.Point "p3" one with
   | Attribute.Float3 values ->
       let values = Packed.Float3.Private.view values in
       check (near values.x.(7) 5. && near values.z.(7) 7.)
         "float3 interpolation"
   | _ -> fail "p3 storage");
  (match find_storage ~owner:Attribute.Point "p4" one with
   | Attribute.Float4 values ->
       let values = Packed.Float4.Private.view values in
       check (near values.x.(7) 5. && near values.w.(7) 8.)
         "float4 interpolation"
   | _ -> fail "p4 storage");
  (match find_storage ~owner:Attribute.Point "pia" one with
   | Attribute.Int_array values -> check (Packed.Int_array.get values 7 = [|10;11|])
       "nearest point int-array ancestry"
   | _ -> fail "pia storage");
  (match find_storage ~owner:Attribute.Point "pfa" one with
   | Attribute.Float_array values ->
       check (Packed.Float_array.get values 7 = [|10.;11.|])
         "nearest point float-array ancestry"
   | _ -> fail "pfa storage");
  (match find_storage ~owner:Attribute.Vertex "vf" one with
   | Attribute.Float values ->
       check (Array.exists (near 5.) values && near values.(61) 30.)
         "vertex interpolation or retained ancestry"
   | _ -> fail "vf storage");
  (match find_storage ~owner:Attribute.Primitive "primitive_name" one with
   | Attribute.Text values ->
       check (Array.for_all (String.equal "selected") (Array.sub values 0 16)
           && String.equal values.(16) "retained")
         "primitive ancestry"
   | _ -> fail "primitive payload storage");
  (match find_storage ~owner:Attribute.Detail "detail" one with
   | Attribute.Int values -> check (values = [|73|]) "detail payload sharing"
   | _ -> fail "detail storage");
  (match Geometry.find_group ~owner:Group.Primitive "caps" one with
   | Some group -> check (Group.cardinality group = 2
       && Group.mem 14 group && Group.mem 15 group) "cap group membership"
   | None -> fail "missing cap group");
  (match Geometry.find_group ~owner:Group.Primitive "ordered_primitives" one with
   | Some group -> check (Group.ordered_elements group
       = Some [|16;0;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15|])
       "ordered primitive ancestry"
   | None -> fail "missing ordered primitive group");
  (match Geometry.find_edge_group "wire_edge" one with
   | Some group -> check (Edge_group.cardinality group = 8)
       "longitudinal native-edge ancestry"
   | None -> fail "missing native edge group")

let check_variable_validation () =
  let source = advanced_source () in
  let selection = Geometry.find_group ~owner:Group.Primitive "wire" source
      |> Option.get in
  let empty = Group.init ~owner:Group.Primitive ~name:"empty" 2
      (Fun.const false) in
  let identity = Ops.sweep_circle ~primitives:empty ~segments:2 ~radius:0.1 source
      |> get_ok in
  check (identity == source) "empty PolyWire selection did not preserve identity";
  let identity_missing = Ops.sweep_circle ~primitives:empty
      ~divisions_attribute:"absent" ~radius:0.1 source |> get_ok in
  check (identity_missing == source)
    "empty PolyWire selection resolved unused attributes";
  let wrong_owner = Group.init ~owner:Group.Point ~name:"wrong" 5
      (Fun.const true) in
  expect_invalid (Ops.sweep_circle ~primitives:wrong_owner ~segments:2
      ~radius:0.1 source);
  expect_invalid (Ops.sweep_circle ~primitives:selection
      ~divisions_attribute:"missing" ~radius:0.1 source);
  let bad_div = with_int "bad_div" [|2;6;5;5;5|] source in
  expect_invalid (Ops.sweep_circle ~primitives:selection
      ~divisions_attribute:"bad_div" ~radius:0.1 bad_div);
  let ignored_div = with_int "ignored_div" [|4;6;2;5;5|] source in
  ignore (Ops.sweep_circle ~primitives:selection
      ~divisions_attribute:"ignored_div" ~radius:0.1 ignored_div |> get_ok);
  let bad_seg = with_int "bad_seg" [|0;1;1;1;1|] source in
  expect_invalid (Ops.sweep_circle ~primitives:selection
      ~segments_attribute:"bad_seg" ~radius:0.1 bad_seg);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.sweep_circle ~cancel:cancelled ~primitives:selection ~segments:2
      ~radius:0.1 source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "variable PolyWire ignored cancellation")

let check_scoped_fixed_compatibility () =
  let source = Ops.polyline
      [|(0.,0.,0.); (0.4,0.7,0.2); (1.,1.1,-0.1); (1.5,1.8,0.3)|]
      |> get_ok |> with_float "weight" [|0.;0.3;0.7;1.|] in
  let all = Group.init ~owner:Group.Primitive ~name:"all" 1 (Fun.const true) in
  let source = Geometry.with_group all source |> get_string in
  let legacy = Ops.sweep_circle ~grain:1 ~sides:7 ~caps:true
      ~cap_group:"caps" ~radius:0.13 source |> get_ok
  and scoped = Ops.sweep_circle ~grain:1 ~primitives:all ~sides:7 ~caps:true
      ~cap_group:"caps" ~radius:0.13 source |> get_ok in
  let lp = Packed.Float3.Private.view (Geometry.positions legacy)
  and rp = Packed.Float3.Private.view (Geometry.positions scoped)
  and lt = Topology.Private.view (Geometry.topology legacy)
  and rt = Topology.Private.view (Geometry.topology scoped) in
  check (lt.vertex_points = rt.vertex_points
      && lt.primitive_offsets = rt.primitive_offsets
      && Bytes.equal lt.primitive_kinds rt.primitive_kinds)
    "all-selected fixed PolyWire topology changed";
  for point = 0 to Array.length lp.x - 1 do
    check (near ~epsilon:1e-14 lp.x.(point) rp.x.(point)
        && near ~epsilon:1e-14 lp.y.(point) rp.y.(point)
        && near ~epsilon:1e-14 lp.z.(point) rp.z.(point))
      "all-selected fixed PolyWire position fidelity"
  done

let check_variable_closed_manifold () =
  let count = 6 in
  let source = Ops.polyline ~closed:true (Array.init count (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point /. float_of_int count in
      (1. +. (0.15 *. cos (2. *. angle))) *. cos angle,
      0.2 *. sin (3. *. angle),
      (1. +. (0.15 *. cos (2. *. angle))) *. sin angle)) |> get_ok
      |> with_int "div" [|4;7;5;8;6;9|]
      |> with_int "seg" [|1;2;3;1;2;3|] in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:2 ~divisions_attribute:"div"
      ~segments_attribute:"seg" ~radius:0.08 source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "closed variable PolyWire differs between one and four domains";
  let index = Topology_index.create (Geometry.topology one) in
  check (Topology_index.boundary_edge_count index = 0
      && Topology_index.non_manifold_edge_count index = 0)
    "closed variable PolyWire zipper is not a closed two-manifold"

let check_segment_scales_and_uv () =
  let line = Ops.polyline [|(0.,0.,0.); (10.,0.,0.)|] |> get_ok in
  let scaled = Ops.sweep_circle ~grain:1 ~sides:4 ~segments:4
      ~segment_scales:(0.2,0.8) ~u_range:(-1.,1.) ~v_range:(2.,4.)
      ~radius:0.25 line |> get_ok in
  let positions = Packed.Float3.Private.view (Geometry.positions scaled)
  and uv = float2_attribute scaled "uv" in
  check (Array.to_list (Array.init 5 (fun ring -> positions.x.(ring * 4)))
      = [0.;2.;5.;8.;10.]) "constant segment-scale ring placement";
  check (near uv.x.(0) (-1.) && near uv.x.(1) (-0.5)
      && near uv.x.(2) (-0.5) && near uv.x.(3) (-1.)
      && near uv.y.(0) 2. && near uv.y.(2) 2.4
      && near uv.y.(16) 2.4 && near uv.y.(18) 3.)
    "constant per-edge U/V texture ranges";
  let attributed = Ops.polyline
      [|(0.,0.,0.); (10.,0.,0.); (20.,0.,0.)|] |> get_ok
      |> with_vertex_attribute "segment_scales" (Attribute.Float2
          (Packed.Float2.of_owned ~x:[|0.1;0.4;0.|] ~y:[|0.6;0.9;1.|]
            |> get_string))
      |> with_vertex_attribute "uv_ranges" (Attribute.Float4
          (Packed.Float4.of_owned ~x:[|0.;10.;0.|] ~y:[|1.;20.;1.|]
            ~z:[|2.;30.;0.|] ~w:[|3.;40.;1.|] |> get_string)) in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:1 ~sides:4 ~segments:3
      ~segment_scales_attribute:"segment_scales"
      ~uv_range_attribute:"uv_ranges" ~radius:0.25 attributed |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "per-edge segment scale/UV ranges differ between one and four domains";
  let positions = Packed.Float3.Private.view (Geometry.positions one)
  and uv = float2_attribute one "uv" in
  let expected = [|0.;1.;6.;10.;14.;19.;20.|] in
  Array.iteri (fun ring expected -> check (near positions.x.(ring * 4) expected)
      "outgoing-corner segment-scale placement") expected;
  check (near uv.x.(48) 10. && near uv.x.(49) 12.5
      && near uv.y.(48) 30. && near uv.y.(50) 34.)
    "outgoing-corner float4 UV ranges";
  let extremes = Ops.sweep_circle ~sides:4 ~segments:3
      ~segment_scales:(0.,1.) ~radius:0.1 line |> get_ok in
  let extreme_positions = Packed.Float3.Private.view (Geometry.positions extremes) in
  check (Array.for_all Float.is_finite extreme_positions.x
      && Array.for_all Float.is_finite extreme_positions.y
      && Array.for_all Float.is_finite extreme_positions.z)
    "inclusive segment-scale endpoints produced non-finite geometry";
  let no_uv = Ops.sweep_circle ~sides:4 ~segments:2 ~generate_uv:false
      ~v_attribute:"missing" ~uv_range_attribute:"missing" ~radius:0.1 line
      |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Vertex "uv" no_uv = None)
    "disabled vertex textures still generated UV";
  let source_uv = line |> with_vertex_attribute "uv" (Attribute.Float2
      (Packed.Float2.of_owned ~x:[|0.;1.|] ~y:[|2.;4.|] |> get_string)) in
  let preserved = Ops.sweep_circle ~sides:4 ~segments:2 ~generate_uv:false
      ~radius:0.1 source_uv |> get_ok in
  let uv = float2_attribute preserved "uv" in
  check (near uv.x.(2) 0.5 && near uv.y.(2) 3.)
    "disabled generation did not preserve/interpolate authored UV"

let check_segment_texture_validation () =
  let line = Ops.polyline [|(0.,0.,0.); (1.,0.,0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~segments:2 ~segment_scales:(-0.1,0.8)
      ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~segments:2 ~segment_scales:(0.8,0.2)
      ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~segments:2
      ~segment_scales_attribute:"missing" ~radius:0.1 line);
  let wrong_scale = line |> with_vertex_attribute "scales"
      (Attribute.Float [|0.;1.|]) in
  expect_invalid (Ops.sweep_circle ~segments:2
      ~segment_scales_attribute:"scales" ~radius:0.1 wrong_scale);
  let bad_scale = line |> with_vertex_attribute "scales" (Attribute.Float2
      (Packed.Float2.of_owned ~x:[|0.7;0.|] ~y:[|0.2;1.|] |> get_string)) in
  expect_invalid (Ops.sweep_circle ~segments:2
      ~segment_scales_attribute:"scales" ~radius:0.1 bad_scale);
  expect_invalid (Ops.sweep_circle ~segments:2 ~u_range:(Float.nan,1.)
      ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~segments:2 ~uv_range_attribute:"missing"
      ~radius:0.1 line);
  let bad_uv = line |> with_vertex_attribute "ranges" (Attribute.Float4
      (Packed.Float4.of_owned ~x:[|0.;0.|] ~y:[|1.;1.|]
        ~z:[|0.;0.|] ~w:[|Float.infinity;1.|] |> get_string)) in
  expect_invalid (Ops.sweep_circle ~segments:2 ~uv_range_attribute:"ranges"
      ~radius:0.1 bad_uv)

let check_joint_buckling () =
  let source = Ops.polyline
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.)|] |> get_ok in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:1 ~sides:4 ~prevent_joint_buckling:true
      ~maximum_joint_scale:10. ~radius:1. source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "joint buckling differs between one and four domains";
  let positions = Packed.Float3.Private.view (Geometry.positions one) in
  (* The first radial point of the 90-degree joint lies on both unit-radius
     incident cylinders: its offset from the joint is (-1,1,0). *)
  check (near positions.x.(5) 0. && near positions.y.(5) 1.
      && near positions.z.(5) 0.)
    "joint buckling did not emit the exact radial miter";
  check (near positions.x.(4) 1. && near positions.y.(4) 0.
      && near positions.z.(4) (-1.))
    "joint buckling enlarged the bend-axis-independent side";
  let limited_source = source |> with_float "joint_limit" [|1.;1.1;1.|] in
  let limited = Ops.sweep_circle ~grain:1 ~sides:4
      ~prevent_joint_buckling:true
      ~maximum_joint_scale_attribute:"joint_limit" ~radius:1. limited_source
      |> get_ok in
  let limited_positions = Packed.Float3.Private.view
      (Geometry.positions limited) in
  let dx = limited_positions.x.(5) -. 1.
  and dy = limited_positions.y.(5) in
  check (near (sqrt ((dx *. dx) +. (dy *. dy))) 1.1)
    "point maximum joint scale did not cap radial miter enlargement";
  let closed = Ops.polyline ~closed:true
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.); (0.,1.,0.)|] |> get_ok in
  let closed_wire = Ops.sweep_circle ~grain:1 ~sides:4
      ~prevent_joint_buckling:true ~maximum_joint_scale:2. ~radius:0.1 closed
      |> get_ok in
  let closed_positions = Packed.Float3.Private.view
      (Geometry.positions closed_wire) in
  check (Array.for_all Float.is_finite closed_positions.x
      && Array.for_all Float.is_finite closed_positions.y
      && Array.for_all Float.is_finite closed_positions.z)
    "closed joint buckling produced non-finite geometry"

let check_joint_buckling_validation () =
  let line = Ops.polyline [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~prevent_joint_buckling:true
      ~maximum_joint_scale:0.99 ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~maximum_joint_scale:0.99
      ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~prevent_joint_buckling:true
      ~maximum_joint_scale:Float.nan ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~maximum_joint_scale_attribute:"missing"
      ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~prevent_joint_buckling:true
      ~maximum_joint_scale_attribute:"missing" ~radius:0.1 line);
  let wrong = line |> with_int "joint_limit" [|1;2;1|] in
  expect_invalid (Ops.sweep_circle ~prevent_joint_buckling:true
      ~maximum_joint_scale_attribute:"joint_limit" ~radius:0.1 wrong);
  let invalid = line |> with_float "joint_limit" [|1.;0.5;1.|] in
  expect_invalid (Ops.sweep_circle ~prevent_joint_buckling:true
      ~maximum_joint_scale_attribute:"joint_limit" ~radius:0.1 invalid)

let check_smooth_disconnection () =
  let source = Ops.polyline
      [|(0.,0.,0.); (1.,0.,0.); (1.,1.,0.)|] |> get_ok
      |> with_float "smooth" [|1.;0.;1.|] in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:1 ~sides:4 ~smooth_attribute:"smooth"
      ~radius:0.2 source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "smooth disconnection differs between one and four domains";
  check (Geometry.point_count one = 16 && Geometry.primitive_count one = 8
      && Geometry.vertex_count one = 32)
    "smooth disconnection cardinality";
  (match find_storage ~owner:Attribute.Point "smooth" one with
   | Attribute.Float values ->
       check (values.(4) = 0. && values.(8) = 0.)
         "smooth break did not duplicate exact point payload"
   | _ -> fail "smooth break changed driver storage");
  let positions = Packed.Float3.Private.view (Geometry.positions one) in
  let center first values =
    let total = ref 0. in
    for side = 0 to 3 do total := !total +. values.(first + side) done;
    !total /. 4. in
  check (near (center 4 positions.x) 1. && near (center 4 positions.y) 0.
      && near (center 4 positions.z) 0. && near (center 8 positions.x) 1.
      && near (center 8 positions.y) 0. && near (center 8 positions.z) 0.)
    "disconnected joint rings do not share their source center";
  let index = Topology_index.create (Geometry.topology one) in
  for incoming = 4 to 7 do
    for outgoing = 8 to 11 do
      check (Topology_index.find_edge_index index ~a:incoming ~b:outgoing < 0)
        "smooth=false left a topology edge across the disconnected joint"
    done
  done;
  let all_disconnected = Ops.sweep_circle ~grain:1 ~sides:4
      ~smooth_point:false ~radius:0.2
      (Ops.polyline [|(0.,0.,0.);(1.,0.,0.);(2.,0.,0.);(3.,0.,0.)|]
       |> get_ok) |> get_ok in
  check (Geometry.point_count all_disconnected = 24)
    "constant Smooth Point=false did not split every interior joint";
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;1.;2.;1.|] ~y:[|0.;0.;0.;1.|] ~z:(Array.make 4 0.) in
  let topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;1;3|] ~primitive_offsets:[|0;3;5|]
      ~primitive_kinds:[|Topology.Open_polyline;Topology.Open_polyline|]
      |> get_string in
  let branch = Geometry.create ~positions ~topology () |> get_string in
  let limited = Ops.sweep_circle ~grain:1 ~sides:4 ~max_valence:2
      ~radius:0.2 branch |> get_ok in
  check (Geometry.point_count limited = 24)
    "Max Valence did not disconnect the three-edge branch point";
  let closed = Ops.polyline ~closed:true
      [|(0.,0.,0.);(1.,0.,0.);(1.,1.,0.);(0.,1.,0.)|] |> get_ok
      |> with_float "smooth" [|0.;1.;1.;1.|] in
  let run_closed domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:1 ~sides:4 ~smooth_attribute:"smooth" ~caps:true
      ~cap_group:"caps" ~radius:0.1 closed |> get_ok) in
  let closed = run_closed 1 and closed_four = run_closed 4 in
  check (equal_geometry closed closed_four)
    "closed smooth disconnection differs between one and four domains";
  check (Geometry.point_count closed = 20
      && Geometry.primitive_count closed = 16)
    "closed smooth disconnection cardinality";
  let index = Topology_index.create (Geometry.topology closed) in
  check (Topology_index.boundary_edge_count index = 8)
    "closed smooth disconnection did not leave two uncapped tube ends";
  (match Geometry.find_group ~owner:Group.Primitive "caps" closed with
   | Some group -> check (Group.cardinality group = 0)
       "closed disconnected point unexpectedly generated caps"
   | None -> fail "closed disconnected cap group missing")

let check_smooth_validation () =
  let line = Ops.polyline [|(0.,0.,0.);(1.,0.,0.);(2.,0.,0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~max_valence:0 ~radius:0.1 line);
  expect_invalid (Ops.sweep_circle ~smooth_attribute:"missing" ~radius:0.1 line);
  let wrong = line |> with_int "smooth" [|1;0;1|] in
  expect_invalid (Ops.sweep_circle ~smooth_attribute:"smooth" ~radius:0.1 wrong);
  let invalid = line |> with_float "smooth" [|1.;Float.nan;1.|] in
  expect_invalid (Ops.sweep_circle ~smooth_attribute:"smooth" ~radius:0.1 invalid)

let check_segment_seam () =
  let source = Ops.polyline
      [|(0.,0.,0.);(1.,0.,0.);(2.,0.,0.)|] |> get_ok
      |> with_vertex_attribute "segment_seam" (Attribute.Int [|1;2;0|]) in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.sweep_circle ~grain:1 ~sides:4 ~segments:2
      ~segment_seam_attribute:"segment_seam" ~radius:0.1 source |> get_ok) in
  let one = run 1 and four = run 4 in
  check (equal_geometry one four)
    "per-segment seam differs between one and four domains";
  let topology = Topology.Private.view (Geometry.topology one) in
  check (topology.vertex_points.(16) = 5
      && topology.vertex_points.(18) = 10
      && topology.vertex_points.(19) = 9)
    "first source edge did not keep one seam across all subdivisions";
  check (topology.vertex_points.(32) = 10
      && topology.vertex_points.(33) = 11
      && topology.vertex_points.(35) = 14)
    "outgoing-corner segment seam did not start uniformly at the next edge";
  let uv = float2_attribute one "uv" in
  check (near uv.x.(18) 0.25 && near uv.x.(19) 0.
      && near uv.x.(32) 0.)
    "per-segment seam did not preserve logical seam-safe U coordinates";
  let extreme = Ops.sweep_circle ~grain:1 ~sides:4 ~segments:2
      ~segment_seam_attribute:"segment_seam" ~seam_offset:max_int
      ~radius:0.1 source |> get_ok in
  check (Geometry.point_count extreme = Geometry.point_count one)
    "large combined seam offsets overflowed"

let check_segment_seam_validation () =
  let line = Ops.polyline [|(0.,0.,0.);(1.,0.,0.)|] |> get_ok in
  expect_invalid (Ops.sweep_circle ~segment_seam_attribute:"missing"
      ~radius:0.1 line);
  let wrong = line |> with_vertex_attribute "segment_seam"
      (Attribute.Float [|0.;1.|]) in
  expect_invalid (Ops.sweep_circle ~segment_seam_attribute:"segment_seam"
      ~radius:0.1 wrong)

let () =
  check_controls ();
  check_closed_frame ();
  check_validation ();
  check_parallel_exact ();
  check_variable_topology_and_selection ();
  check_variable_validation ();
  check_scoped_fixed_compatibility ();
  check_variable_closed_manifold ();
  check_segment_scales_and_uv ();
  check_segment_texture_validation ();
  check_joint_buckling ();
  check_joint_buckling_validation ();
  check_smooth_disconnection ();
  check_smooth_validation ();
  check_segment_seam ();
  check_segment_seam_validation ();
  print_endline "PolyWire tests passed"
