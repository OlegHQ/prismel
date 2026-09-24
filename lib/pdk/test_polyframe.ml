open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function Ok value -> value | Error error -> fail (Error.to_string error)
let get_string = function Ok value -> value | Error error -> fail error
let near ?(epsilon = 1e-9) left right = abs_float (left -. right) <= epsilon

let float3_attribute ~owner geometry name =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Packed.Float3.Private.view values
       | _ -> fail (name ^ " has unexpected storage"))
  | None -> fail ("missing attribute " ^ name)

let equal_storage left right =
  match Attribute.storage left, Attribute.storage right with
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

let norm (values : Packed.Float3.Private.view) index =
  sqrt ((values.x.(index) *. values.x.(index))
    +. (values.y.(index) *. values.y.(index))
    +. (values.z.(index) *. values.z.(index)))

let dot (left : Packed.Float3.Private.view)
    (right : Packed.Float3.Private.view) index =
  (left.x.(index) *. right.x.(index))
    +. (left.y.(index) *. right.y.(index))
    +. (left.z.(index) *. right.z.(index))

let frame_orientation (normal : Packed.Float3.Private.view)
    (tangent : Packed.Float3.Private.view)
    (bitangent : Packed.Float3.Private.view) index =
  let cx = (tangent.y.(index) *. bitangent.z.(index))
      -. (tangent.z.(index) *. bitangent.y.(index))
  and cy = (tangent.z.(index) *. bitangent.x.(index))
      -. (tangent.x.(index) *. bitangent.z.(index))
  and cz = (tangent.x.(index) *. bitangent.y.(index))
      -. (tangent.y.(index) *. bitangent.x.(index)) in
  (cx *. normal.x.(index)) +. (cy *. normal.y.(index))
    +. (cz *. normal.z.(index))

let expect_invalid = function
  | Error error when Error.code error = "invalid_geometry" -> ()
  | Error error -> fail ("unexpected error " ^ Error.to_string error)
  | Ok _ -> fail "expected invalid PolyFrame input"

let with_attribute owner name storage geometry =
  let attribute = Attribute.create_owned ~owner ~name storage |> get_string in
  Geometry.with_attribute attribute geometry |> get_string

let check_point_styles () =
  let source = Ops.grid ~columns:1 ~rows:1 ~size:2. () |> get_ok in
  let first = Ops.polyframe ~orthogonal:true Ops.First_edge source |> get_ok
  and two = Ops.polyframe ~orthogonal:true Ops.Two_edges source |> get_ok
  and radial = Ops.polyframe ~orthogonal:true Ops.Primitive_centroid source
      |> get_ok in
  List.iter (fun geometry ->
    let normal = float3_attribute ~owner:Attribute.Point geometry "N"
    and tangent = float3_attribute ~owner:Attribute.Point geometry "tangentu"
    and bitangent = float3_attribute ~owner:Attribute.Point geometry "tangentv" in
    for point = 0 to Geometry.point_count geometry - 1 do
      check (near (norm normal point) 1. && near (norm tangent point) 1.
          && near (norm bitangent point) 1.) "point PolyFrame normalization";
      check (near (dot normal tangent point) 0.
          && near (dot tangent bitangent point) 0.)
        "point PolyFrame orthogonality"
    done) [first; two; radial];
  let first_tangent = float3_attribute ~owner:Attribute.Point first "tangentu"
  and two_tangent = float3_attribute ~owner:Attribute.Point two "tangentu" in
  check (not (near first_tangent.x.(0) two_tangent.x.(0)
      && near first_tangent.z.(0) two_tangent.z.(0)))
    "First Edge and Two Edges collapsed to the same style";
  let topology_value = Geometry.topology source in
  let topology = Topology.Private.view topology_value
  and positions = Packed.Float3.Private.view (Geometry.positions source) in
  let index = Topology_index.create topology_value in
  let view = Topology_index.Private.view index in
  let corner = Topology_index.point_vertex index ~point:0 ~local:0 in
  let previous = topology.vertex_points.(view.previous_vertex.(corner))
  and next = topology.vertex_points.(view.next_vertex.(corner)) in
  let ex = (positions.x.(previous) -. positions.x.(0))
      +. (positions.x.(next) -. positions.x.(0))
  and ey = (positions.y.(previous) -. positions.y.(0))
      +. (positions.y.(next) -. positions.y.(0))
  and ez = (positions.z.(previous) -. positions.z.(0))
      +. (positions.z.(next) -. positions.z.(0)) in
  let length = sqrt ((ex *. ex) +. (ey *. ey) +. (ez *. ez)) in
  check (near ((two_tangent.x.(0) *. ex +. two_tangent.y.(0) *. ey
      +. two_tangent.z.(0) *. ez) /. length) 1.)
    "Two Edges tangent is not the sum of both point-relative edge vectors";
  let normal_only = Ops.polyframe ~tangent_attribute:None
      ~bitangent_attribute:None Ops.First_edge source |> get_ok in
  check (Geometry.find_attribute ~owner:Attribute.Point "N" normal_only <> None
      && Geometry.find_attribute ~owner:Attribute.Point "tangentu" normal_only = None)
    "PolyFrame output toggles";
  let bitangent_only = Ops.polyframe ~orthogonal:true ~tangent_attribute:None
      ~bitangent_attribute:(Some "frame_v") Ops.First_edge source |> get_ok in
  let bitangent = float3_attribute ~owner:Attribute.Point bitangent_only
      "frame_v" in
  check (Geometry.find_attribute ~owner:Attribute.Point "tangentu"
           bitangent_only = None
      && near (norm bitangent 0) 1.)
    "PolyFrame bitangent-only output";
  let left = Ops.polyframe ~orthogonal:true ~left_handed:true Ops.First_edge
      source |> get_ok in
  let rn = float3_attribute ~owner:Attribute.Point first "N"
  and rt = float3_attribute ~owner:Attribute.Point first "tangentu"
  and rb = float3_attribute ~owner:Attribute.Point first "tangentv"
  and ln = float3_attribute ~owner:Attribute.Point left "N"
  and lt = float3_attribute ~owner:Attribute.Point left "tangentu"
  and lb = float3_attribute ~owner:Attribute.Point left "tangentv" in
  check (frame_orientation rn rt rb 0 > 0.99
      && frame_orientation ln lt lb 0 < -0.99)
    "PolyFrame orthogonal handedness"

let check_gradient_styles () =
  let source = Ops.grid ~columns:4 ~rows:3 ~uv_attribute:"uv" ~size:2. ()
      |> get_ok in
  let point = Ops.polyframe ~orthogonal:true (Ops.Texture_uv "uv") source
      |> get_ok in
  let default_point = Ops.polyframe ~orthogonal:true (Ops.Texture_uv "") source
      |> get_ok in
  check (equal_geometry point default_point)
    "empty Texture UV attribute name did not resolve to uv";
  let pn = float3_attribute ~owner:Attribute.Point point "N"
  and pt = float3_attribute ~owner:Attribute.Point point "tangentu"
  and pb = float3_attribute ~owner:Attribute.Point point "tangentv" in
  for index = 0 to Geometry.point_count point - 1 do
    check (near (norm pn index) 1. && near (norm pt index) 1.
        && near (norm pb index) 1. && near (dot pn pt index) 0.)
      "Texture UV point frame"
  done;
  let vertex = Ops.polyframe ~orthogonal:true
      (Ops.Attribute_gradient "uv") source |> get_ok in
  let texture_gradient = Ops.polyframe ~orthogonal:true
      (Ops.Texture_uv_gradient "uv") source |> get_ok in
  check (equal_geometry vertex texture_gradient)
    "Texture UV Gradient and UV Attribute Gradient disagree";
  let vn = float3_attribute ~owner:Attribute.Vertex vertex "N"
  and vt = float3_attribute ~owner:Attribute.Vertex vertex "tangentu"
  and vb = float3_attribute ~owner:Attribute.Vertex vertex "tangentv" in
  for index = 0 to Geometry.vertex_count vertex - 1 do
    check (near (norm vn index) 1. && near (norm vt index) 1.
        && near (norm vb index) 1. && near (dot vn vt index) 0.
        && near (dot vt vb index) 0.)
      "Attribute Gradient vertex frame"
  done

let check_selection () =
  let source = Ops.grid ~columns:1 ~rows:1 ~size:2. () |> get_ok in
  let count = Geometry.point_count source in
  let source = with_attribute Attribute.Point "tangentu"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make count 9.) ~y:(Array.make count 8.)
        ~z:(Array.make count 7.))) source in
  let group = Group.init ~owner:Group.Point ~name:"one" count
      (fun point -> point = 0) in
  let framed = Ops.polyframe ~selection:(Ops.Selected_points group)
      Ops.First_edge source |> get_ok in
  let tangent = float3_attribute ~owner:Attribute.Point framed "tangentu" in
  check (near (norm tangent 0) 1. && tangent.x.(1) = 9.
      && tangent.y.(1) = 8. && tangent.z.(1) = 7.)
    "PolyFrame selection did not preserve output outside the group"

let check_validation () =
  let source = Ops.grid ~columns:1 ~rows:1 ~uv_attribute:"uv" ~size:1. ()
      |> get_ok in
  expect_invalid (Ops.polyframe (Ops.Texture_uv "missing") source);
  expect_invalid (Ops.polyframe ~normal_attribute:"P" Ops.First_edge source);
  expect_invalid (Ops.polyframe ~normal_attribute:"frame"
      ~tangent_attribute:(Some "frame") Ops.First_edge source);
  let wrong = source |> with_attribute Attribute.Point "bad"
      (Attribute.Float (Array.make (Geometry.point_count source) 0.)) in
  expect_invalid (Ops.polyframe (Ops.Texture_uv "bad") wrong);
  let nonfinite = source |> with_attribute Attribute.Point "bad_uv"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.make (Geometry.point_count source) Float.nan)
        ~y:(Array.make (Geometry.point_count source) 0.) |> get_string)) in
  expect_invalid (Ops.polyframe (Ops.Texture_uv "bad_uv") nonfinite);
  let wrong_output = source |> with_attribute Attribute.Point "frame"
      (Attribute.Float (Array.make (Geometry.point_count source) 0.)) in
  expect_invalid (Ops.polyframe ~normal_attribute:"frame" Ops.First_edge
      wrong_output);
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.polyframe ~cancel:cancelled Ops.First_edge source with
   | Error error when Error.code error = "cancelled" -> ()
   | _ -> fail "PolyFrame ignored cancellation")

let check_parallel_exact () =
  let source = Ops.grid ~columns:300 ~rows:240 ~uv_attribute:"uv" ~size:20. ()
      |> get_ok in
  let run style domains = Parallel.run ~domains (fun () ->
      Ops.polyframe ~grain:257 ~orthogonal:true style source |> get_ok) in
  List.iter (fun style ->
    let one = run style 1 and many = run style 4 in
    check (equal_geometry one many)
      "one-domain and four-domain PolyFrame geometry differ")
    [Ops.Two_edges; Ops.Texture_uv "uv"; Ops.Texture_uv_gradient "uv";
     Ops.Attribute_gradient "uv"]

let () =
  check_point_styles ();
  check_gradient_styles ();
  check_selection ();
  check_validation ();
  check_parallel_exact ();
  print_endline "PolyFrame tests passed"
