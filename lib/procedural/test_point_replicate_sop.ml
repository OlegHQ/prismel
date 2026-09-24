open Procedural

let fail message = prerr_endline ("test_point_replicate_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let context domains = Context.create ~domains ~grain:31 ~seed:44L () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:64_000_000 |> get
let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let geometry = Pdk.Ops.points [|0.,0.,0.; 2.,0.,0.|] in
  let density = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"density" (Pdk.Attribute.Float [|2.;1.|]) |> Result.get_ok
  and id = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"id"
      (Pdk.Attribute.Int [|11;22|]) |> Result.get_ok
  and pscale = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"pscale" (Pdk.Attribute.Float [|2.;2.|]) |> Result.get_ok
  and flow = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"flow"
      (Pdk.Attribute.Float3 (Pdk.Packed.Float3.Private.of_owned_exn
        ~x:[|1.;1.|] ~y:[|2.;2.|] ~z:[|3.;3.|])) |> Result.get_ok
  and selected = Pdk.Group.init ~grain:1 ~owner:Pdk.Group.Point ~name:"emit"
      2 (fun point -> point = 0) in
  geometry |> Pdk.Geometry.with_attribute density |> Result.get_ok
  |> Pdk.Geometry.with_attribute id |> Result.get_ok
  |> Pdk.Geometry.with_attribute pscale |> Result.get_ok
  |> Pdk.Geometry.with_attribute flow |> Result.get_ok
  |> Pdk.Geometry.with_group selected |> Result.get_ok

let cook evaluator domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let () =
  let custom = Sop.points [|(0.,0.,0.); (0.,0.,1.)|] in
  let graph = Sop.snapshot (source ())
      |> Sop.point_replicate ~label:"replicate-test" ~group:"emit" ~seed:71
           ~shape:Pdk.Ops.Replicate_custom ~custom_shape:custom
           ~generated_group:"cloud" ~keep_source_attributes:true
           ~transform_attributes:"flow"
           ~quasi_stratified:true ~noise_seed:72
           ~noise_amplitude:(Prismel.Vec3.create 0.1 0.15 0.2)
           ~noise_turbulence:2 ~points_per_point:2.
           ~scale_attribute:"density" in
  let evaluator = session () in
  let output = cook evaluator 4 graph in
  if Pdk.Geometry.point_count output <> 4
      || Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "shapeptnum"
           output = None
      || Pdk.Geometry.find_group ~owner:Pdk.Group.Point "cloud" output = None then
    fail "custom SOP output";
  let flow = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "flow"
      output with
    | Some attribute -> (match Pdk.Attribute.Private.storage attribute with
        | Pdk.Attribute.Float3 values -> Pdk.Packed.Float3.Private.view values
        | _ -> fail "transformed flow storage")
    | None -> fail "missing transformed flow" in
  if flow.x <> [|2.;2.;2.;2.|] || flow.y <> [|4.;4.;4.;4.|]
      || flow.z <> [|6.;6.;6.;6.|] then fail "transformed flow values";
  if Node.operation graph <> "point_replicate"
      || not (contains (Node.parameters graph) "group=emit")
      || not (contains (Node.parameters graph) "shape=custom")
      || not (contains (Node.parameters graph) "custom_shape=true")
      || not (contains (Node.parameters graph) "transform_attributes=flow")
      || not (contains (Node.parameters graph) "quasi=true")
      || not (contains (Node.parameters graph) "noise_turbulence=2") then
    fail ("cache identity: " ^ Node.parameters graph);
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator 4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;

  let missing_group = Sop.snapshot (source ())
      |> Sop.point_replicate ~group:"absent" ~points_per_point:1. in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing_group with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing group accepted");
  Session.close evaluator;
  print_endline "test_point_replicate_sop: ok"
