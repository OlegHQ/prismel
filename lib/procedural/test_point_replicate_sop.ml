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
  let geometry = Rdk.Line_geometry.points [|0.,0.,0.; 2.,0.,0.|] in
  let density = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"density" (Rdk.Attribute.Float [|2.;1.|]) |> Result.get_ok
  and id = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"id"
      (Rdk.Attribute.Int [|11;22|]) |> Result.get_ok
  and pscale = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"pscale" (Rdk.Attribute.Float [|2.;2.|]) |> Result.get_ok
  and flow = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"flow"
      (Rdk.Attribute.Float3 (Rdk.Packed.Float3.Private.of_owned_exn
        ~x:[|1.;1.|] ~y:[|2.;2.|] ~z:[|3.;3.|])) |> Result.get_ok
  and selected = Rdk.Group.init ~grain:1 ~owner:Rdk.Group.Point ~name:"emit"
      2 (fun point -> point = 0) in
  geometry |> Rdk.Geometry.with_attribute density |> Result.get_ok
  |> Rdk.Geometry.with_attribute id |> Result.get_ok
  |> Rdk.Geometry.with_attribute pscale |> Result.get_ok
  |> Rdk.Geometry.with_attribute flow |> Result.get_ok
  |> Rdk.Geometry.with_group selected |> Result.get_ok

let cook evaluator domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let run () =
  let custom = Sop.points [|(0.,0.,0.); (0.,0.,1.)|] in
  let graph = Sop.snapshot (source ())
      |> (fun replication_source -> Sop.point_replicate ~label:"replicate-test" ~group:"emit" ~seed:71
           ~shape:Rdk.Point_replication.Replicate_custom
           ~generated_group:"cloud" ~keep_source_attributes:true
           ~transform_attributes:"flow"
           ~quasi_stratified:true ~noise_seed:72
           ~use_noise:true ~noise_amplitude:(Rays.Vec3.create 0.1 0.15 0.2)
           ~noise_turbulence:2 ~points_per_point:2.
           ~scale_attribute:"density" replication_source (Some custom)) in
  let evaluator = session () in
  let output = cook evaluator 4 graph in
  if Rdk.Geometry.point_count output <> 4
      || Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "shapeptnum"
           output = None
      || Rdk.Geometry.find_group ~owner:Rdk.Group.Point "cloud" output = None then
    fail "custom SOP output";
  let flow = match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point "flow"
      output with
    | Some attribute -> (match Rdk.Attribute.Private.storage attribute with
        | Rdk.Attribute.Float3 values -> Rdk.Packed.Float3.Private.view values
        | _ -> fail "transformed flow storage")
    | None -> fail "missing transformed flow" in
  if flow.x <> [|2.;2.;2.;2.|] || flow.y <> [|4.;4.;4.;4.|]
      || flow.z <> [|6.;6.;6.;6.|] then fail "transformed flow values";
  if Node.operation graph <> "point_replicate"
      || not (contains (Node.parameters graph) "group=emit")
      || not (contains (Node.parameters graph) "shape=custom")
      || not (contains (Node.parameters graph) "shape=custom")
      || not (contains (Node.parameters graph) "transform_attributes=flow")
      || not (contains (Node.parameters graph) "quasi_stratified=true")
      || not (contains (Node.parameters graph) "noise_turbulence=2") then
    fail ("cache identity: " ^ Node.parameters graph);
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator 4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;

  let missing_group = Sop.snapshot (source ())
      |> (fun replication_source -> Sop.point_replicate ~group:"absent" ~points_per_point:1. replication_source None) in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing_group with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing group accepted");
  Session.close evaluator;
  print_endline "test_point_replicate_sop: ok"
