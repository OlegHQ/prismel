open Procedural

let fail message = prerr_endline ("test_polywire_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|0.;2.;0.;2.|] ~y:[|0.;0.;3.;3.|] ~z:(Array.make 4 0.) in
  let topology = Pdk.Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline; Pdk.Topology.Open_polyline|]
    |> get in
  let selection = Pdk.Group.ordered ~owner:Pdk.Group.Primitive ~name:"first"
      ~length:2 [|0|] |> get
  and divisions = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"div"
      (Pdk.Attribute.Int [|4;6;5;5|]) |> get
  and segments = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"seg"
      (Pdk.Attribute.Int [|1;3;1;1|]) |> get in
  Pdk.Geometry.create ~positions ~topology ~attributes:[divisions;segments]
    ~groups:[selection] () |> get

let context domains = Context.create ~domains ~grain:2 ~seed:91L () |> get
let session () = Session.create ~max_entries:8 ~max_payload_bytes:8_000_000 |> get

let cook evaluator domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let equal left right =
  let lt = Pdk.Topology.Private.view (Pdk.Geometry.topology left)
  and rt = Pdk.Topology.Private.view (Pdk.Geometry.topology right)
  and lp = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions left)
  and rp = Pdk.Packed.Float3.Private.view (Pdk.Geometry.positions right) in
  lt.point_count = rt.point_count
  && lt.vertex_points = rt.vertex_points
  && lt.primitive_offsets = rt.primitive_offsets
  && Bytes.equal lt.primitive_kinds rt.primitive_kinds
  && lp.x = rp.x && lp.y = rp.y && lp.z = rp.z
  && List.for_all2 (fun left right ->
       Pdk.Attribute.owner left = Pdk.Attribute.owner right
       && String.equal (Pdk.Attribute.name left) (Pdk.Attribute.name right)
       && Pdk.Attribute.storage left = Pdk.Attribute.storage right)
       (Pdk.Geometry.attributes left) (Pdk.Geometry.attributes right)

let () =
  let graph = Sop.snapshot (source ())
      |> Sop.polywire ~label:"variable-wire" ~group:"first" ~sides:8
           ~divisions_attribute:"div" ~segments:3 ~segments_attribute:"seg"
           ~segment_scales:(0.15,0.85) ~u_range:(-1.,1.) ~v_range:(2.,4.)
           ~prevent_joint_buckling:true ~maximum_joint_scale:2.5
           ~max_valence:3
           ~caps:true ~cap_group:"caps" ~radius:0.2 in
  let parameters = Node.parameters graph in
  if Node.operation graph <> "polywire"
      || not (contains parameters "group=\"first\"")
      || not (contains parameters "divisions_attribute=\"div\"")
      || not (contains parameters "segments=3")
      || not (contains parameters "segments_attribute=\"seg\"")
      || not (contains parameters "segment_scales=")
      || not (contains parameters "prevent_joint_buckling=true")
      || not (contains parameters "maximum_joint_scale=")
      || not (contains parameters "smooth_point=true")
      || not (contains parameters "max_valence=3")
      || not (contains parameters "generate_uv=true")
      || not (contains parameters "u_range=") then
    fail ("cache identity: " ^ parameters);
  let evaluator = session () in
  let one = cook evaluator 1 graph and four = cook evaluator 4 graph in
  if not (equal one four) then fail "one/four-domain output differs";
  if Pdk.Geometry.point_count one <> 18
      || Pdk.Geometry.vertex_count one <> 62
      || Pdk.Geometry.primitive_count one <> 17 then
    fail "scoped variable PolyWire cardinality";
  (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "caps" one with
   | Some group when Pdk.Group.cardinality group = 2 -> ()
   | _ -> fail "cap output group");
  (match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "uv" one with
   | Some attribute ->
       (match Pdk.Attribute.Private.storage attribute with
        | Pdk.Attribute.Float2 values ->
            let values = Pdk.Packed.Float2.Private.view values in
            if not (Array.exists (( = ) (-1.)) values.x
                && Array.exists (( = ) 1.) values.x) then
              fail "typed U range did not reach its endpoints"
        | _ -> fail "generated uv storage")
   | None -> fail "generated uv missing");
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator 4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;
  let without_uv = Sop.snapshot (source ())
      |> Sop.polywire ~segments:2 ~generate_uv:false ~radius:0.1 in
  let evaluator = session () in
  let without_uv = cook evaluator 1 without_uv in
  if Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "uv" without_uv
      <> None then fail "SOP generate_uv=false still emitted uv";
  Session.close evaluator;
  let rejected = try
      ignore (Sop.snapshot (source ())
        |> Sop.polywire ~segment_scales:(0.9,0.1) ~radius:0.1);
      false
    with Invalid_argument _ -> true in
  if not rejected then fail "invalid SOP segment scales accepted";
  let rejected = try
      ignore (Sop.snapshot (source ())
        |> Sop.polywire ~prevent_joint_buckling:true
             ~maximum_joint_scale:0.5 ~radius:0.1);
      false
    with Invalid_argument _ -> true in
  if not rejected then fail "invalid SOP maximum joint scale accepted";
  let rejected = try
      ignore (Sop.snapshot (source ())
        |> Sop.polywire ~maximum_joint_scale_attribute:"joint_limit"
             ~radius:0.1);
      false
    with Invalid_argument _ -> true in
  if not rejected then
    fail "SOP maximum joint scale attribute accepted without prevention";
  let rejected = try
      ignore (Sop.snapshot (source ())
        |> Sop.polywire ~max_valence:0 ~radius:0.1);
      false
    with Invalid_argument _ -> true in
  if not rejected then fail "invalid SOP max valence accepted";
  let seam_graph = Sop.snapshot (source ())
      |> Sop.polywire ~segment_seam_attribute:"edge_seam" ~radius:0.1 in
  if not (contains (Node.parameters seam_graph)
      "segment_seam_attribute=\"edge_seam\"") then
    fail "segment seam missing from cache identity";
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) seam_graph with
   | Error error when String.equal error.Diagnostic.code "invalid_geometry" -> ()
   | Error error -> fail ("unexpected segment seam diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing segment seam attribute accepted");
  Session.close evaluator;
  let missing = Sop.snapshot (source ()) |> Sop.polywire ~group:"absent" ~radius:0.1 in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing with
   | Error error when String.equal error.Diagnostic.code "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing primitive group accepted");
  Session.close evaluator;
  print_endline "test_polywire_sop: ok"
