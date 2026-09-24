open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error message -> fail message
let get_pdk = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

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
      && equal_storage left right)
      (Geometry.attributes left) (Geometry.attributes right)
  && List.equal (fun left right ->
      Group.owner left = Group.owner right
      && String.equal (Group.name left) (Group.name right)
      && Group.ordered_elements left = Group.ordered_elements right
      && Group.length left = Group.length right
      && let equal = ref true in
         for element = 0 to Group.length left - 1 do
           if Group.mem element left <> Group.mem element right then equal := false
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

let source_geometry () =
  let source = Ops.box ~size:(Vec3.create 0.5 0.75 1.) () |> get_pdk in
  let points = Geometry.point_count source
  and vertices = Geometry.vertex_count source
  and primitives = Geometry.primitive_count source in
  let source = source
  |> add_attribute (Attribute.create_owned ~name:"point_id"
       ~owner:Attribute.Point (Attribute.Int (Array.init points Fun.id)) |> get_ok)
  |> add_attribute (Attribute.create_owned ~name:"corner_weight"
       ~owner:Attribute.Vertex (Attribute.Float (Array.init vertices
         (fun index -> float_of_int index *. 0.125))) |> get_ok)
  |> add_attribute (Attribute.create_owned ~name:"piece"
       ~owner:Attribute.Primitive (Attribute.Text (Array.init primitives
         (fun index -> if index land 1 = 0 then "even" else "odd"))) |> get_ok) in
  let point_group = Group.init ~owner:Group.Point ~name:"selected_points"
      points (fun point -> point mod 3 = 0)
  and primitive_group = Group.ordered ~owner:Group.Primitive
      ~name:"primitive_path" ~length:primitives [|2; 0; 5|] |> get_ok in
  let source = Geometry.with_group point_group source |> get_ok in
  let source = Geometry.with_group primitive_group source |> get_ok in
  Ops.group_edges ~grain:1 ~name:"prototype_edges" source |> get_pdk

let transforms count = Array.init count (fun instance ->
  let angle = float_of_int instance *. 0.17 in
  Mat4.mul
    (Mat4.translation (Vec3.create (float_of_int instance *. 1.25)
      (sin angle *. 0.5) (cos angle *. 0.25)))
    (Mat4.mul (Mat4.rotation_y angle)
      (Mat4.scaling (Vec3.create 1. (0.75 +. float_of_int (instance mod 3)
        *. 0.125) 1.))))

let legacy_materialize matrices source =
  Array.to_list matrices
  |> List.map (fun matrix -> Ops.transform ~grain:1 matrix source)
  |> Ops.merge ~grain:1
  |> get_pdk

let () =
  let source = source_geometry () in
  let matrices = transforms 17 in
  let expected = legacy_materialize matrices source in
  let actual = Ops.materialize_instances ~grain:1 ~transforms:matrices source
      |> get_pdk in
  check (geometry_equal expected actual)
    "packed materialization differs from transform-plus-merge semantics";

  let one = Parallel.run ~domains:1 (fun () ->
    Ops.materialize_instances ~grain:7 ~transforms:matrices source |> get_pdk)
  and four = Parallel.run ~domains:4 (fun () ->
    Ops.materialize_instances ~grain:7 ~transforms:matrices source |> get_pdk) in
  check (geometry_equal one four)
    "packed materialization differs across domain counts";

  let identity = Ops.materialize_instances ~transforms:[|Mat4.identity|] source
      |> get_pdk in
  check (Geometry.data_id identity = Geometry.data_id source)
    "single identity materialization did not preserve the immutable snapshot";

  let single_matrix = Mat4.mul (Mat4.translation (Vec3.create 3. 2. 1.))
      (Mat4.rotation_x 0.37) in
  let single = Ops.materialize_instances ~grain:1
      ~transforms:[|single_matrix|] source |> get_pdk
  and single_expected = Ops.transform ~grain:1 single_matrix source in
  check (geometry_equal single_expected single)
    "single-instance fast path changed transform semantics";
  check (Geometry.topology single == Geometry.topology source)
    "single-instance materialization copied unchanged topology";
  let source_id = Geometry.find_attribute ~owner:Attribute.Point "point_id" source
      |> Option.get
  and single_id = Geometry.find_attribute ~owner:Attribute.Point "point_id" single
      |> Option.get in
  check (Attribute.storage_id source_id = Attribute.storage_id single_id)
    "single-instance materialization copied an unchanged attribute";

  let raw_expected = Ops.merge ~grain:1 (List.init 17 (fun _ -> source)) |> get_pdk
  and raw = Ops.materialize_instances ~grain:1 ~apply_transform:false
      ~transforms:matrices source |> get_pdk in
  check (geometry_equal raw_expected raw)
    "disabled transform application changed prototype-space copies";

  let with_detail = source |> add_attribute
      (Attribute.create_owned ~name:"generation" ~owner:Attribute.Detail
        (Attribute.Int [|7|]) |> get_ok) in
  let empty = Ops.materialize_instances ~transforms:[||] with_detail |> get_pdk in
  check (Geometry.point_count empty = 0 && Geometry.vertex_count empty = 0
      && Geometry.primitive_count empty = 0)
    "empty instance materialization emitted topology";
  check (match Geometry.find_attribute ~owner:Attribute.Detail "generation" empty with
    | Some attribute ->
        Attribute.get (Attribute.key ~name:"generation" ~owner:Attribute.Detail
          Attribute.int) attribute = Some [|7|]
    | None -> false)
    "empty instance materialization lost detail attributes";
  check (List.for_all (fun group -> Group.cardinality group = 0)
      (Geometry.groups empty)
      && List.for_all (fun group -> Edge_group.cardinality group = 0)
        (Geometry.edge_groups empty))
    "empty instance materialization retained group members";

  let singular = Ops.materialize_instances
      ~transforms:[|Mat4.scaling (Vec3.create 1. 0. 1.)|] source |> get_pdk in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" singular = None
      && Geometry.find_attribute ~owner:Attribute.Vertex "N" singular = None)
    "singular instance transform retained invalid normals";

  let invalid = Mat4.of_rows (Float.nan, 0., 0., 0.) (0., 1., 0., 0.)
      (0., 0., 1., 0.) (0., 0., 0., 1.) in
  (match Ops.materialize_instances ~transforms:[|invalid|] source with
   | Error error when Error.code error = "invalid_parameter" -> ()
   | _ -> fail "non-finite instance transform was accepted");

  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.materialize_instances ~cancel:cancelled
      ~transforms:(transforms 10_000) source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "cancelled instance materialization published geometry");

  let triangle = Ops.polyline ~closed:true
      [|(0., 0., 0.); (1., 0., 0.); (0., 1., 0.)|] |> get_pdk in
  let scale_count = 100_000 in
  let scaled = Ops.materialize_instances ~grain:2_048
      ~transforms:(Array.make scale_count Mat4.identity) triangle |> get_pdk in
  check (Geometry.point_count scaled = scale_count * 3
      && Geometry.vertex_count scaled = scale_count * 3
      && Geometry.primitive_count scaled = scale_count)
    "scale materialization cardinality is not exact";
  print_endline "PDK instance materialization tests passed"
