open Procedural

let fail message = prerr_endline ("test_point_generate_sop: " ^ message); exit 1
let get = function Ok value -> value | Error message -> fail message
let context domains = Context.create ~domains ~grain:37 ~seed:91L () |> get
let session () = Session.create ~max_entries:16 ~max_payload_bytes:32_000_000 |> get

let contains value needle =
  let rec loop at = at + String.length needle <= String.length value
      && (String.sub value at (String.length needle) = needle || loop (at + 1)) in
  needle = "" || loop 0

let source () =
  let geometry = Rdk.Line_geometry.points [|0., 0., 0.; 1., 0., 0.; 2., 0., 0.|] in
  let density = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"density" (Rdk.Attribute.Float [|1.; 2.; 3.|]) |> Result.get_ok
  and id = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point ~name:"id"
      (Rdk.Attribute.Int [|10; 20; 30|]) |> Result.get_ok
  and selected = Rdk.Group.init ~grain:1 ~owner:Rdk.Group.Point
      ~name:"emit" 3 (fun point -> point <> 1) in
  geometry |> Rdk.Geometry.with_attribute density |> Result.get_ok
  |> Rdk.Geometry.with_attribute id |> Result.get_ok
  |> Rdk.Geometry.with_group selected |> Result.get_ok

let cook evaluator ~domains graph =
  match Session.cook evaluator ~context:(context domains) graph with
  | Ok output -> (Result.get_ok (Procedural.Payload.geometry output.payload))
  | Error error -> fail (Diagnostic.error_to_string error)

let int_values name geometry =
  match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry with
  | Some attribute -> (match Rdk.Attribute.storage attribute with
      | Rdk.Attribute.Int values -> values
      | _ -> fail (name ^ " has wrong storage"))
  | None -> fail ("missing " ^ name)

let run () =
  let graph = Sop.snapshot (source ())
      |> Sop.point_generate ~label:"emit-test" ~group:"emit" ~keep_input:true
           ~seed:7 ~generated_group:"made" ~copy_point_attributes:"id"
           ~mode:Sop.Point_generate_per_point ~points_per_point:2. ~scale_attribute:"density" in
  let evaluator = session () in
  let output = cook evaluator ~domains:4 graph in
  if Rdk.Geometry.point_count output <> 11 then fail "SOP cardinality";
  let sourcepoint = int_values "sourcepoint" output
  and sourceindex = int_values "sourceindex" output in
  if sourcepoint <> [|-1;-1;-1;0;0;2;2;2;2;2;2|] then
    fail ("SOP sourcepoint metadata: " ^
      String.concat "," (Array.to_list (Array.map string_of_int sourcepoint)));
  if sourceindex <> [|-1;-1;-1;0;1;0;1;2;3;4;5|] then
    fail ("SOP sourceindex metadata: " ^
      String.concat "," (Array.to_list (Array.map string_of_int sourceindex)));
  if int_values "id" output <> [|10;20;30;10;10;30;30;30;30;30;30|] then
    fail "SOP point attribute copy";
  let made = Rdk.Geometry.find_group ~owner:Rdk.Group.Point "made" output
      |> Option.get in
  if Rdk.Group.cardinality made <> 8 then fail "SOP generated group";
  if Node.operation graph <> "point_generate"
      || not (contains (Node.parameters graph) "group=emit")
      || not (contains (Node.parameters graph) "mode=per_point")
      || not (contains (Node.parameters graph) "copy_point_attributes=id") then
    fail ("SOP cache identity: " ^ Node.parameters graph);
  let misses = (Session.stats evaluator).misses in
  ignore (cook evaluator ~domains:4 graph);
  if (Session.stats evaluator).misses <> misses then fail "stable graph missed cache";
  Session.close evaluator;

  let origin = Sop.point_generate_origin ~generated_group:"origin" ~points:5 () in
  let evaluator = session () in
  let output = cook evaluator ~domains:1 origin in
  if Rdk.Geometry.point_count output <> 5
      || int_values "sourcepoint" output <> Array.make 5 (-1)
      || int_values "sourceindex" output <> [|0;1;2;3;4|] then
    fail "origin generator";
  Session.close evaluator;

  let missing = Sop.snapshot (source ())
      |> Sop.point_generate ~group:"absent"
           ~context_seed:true ~mode:Sop.Point_generate_per_point ~points_per_point:1. ~scale_attribute:"" in
  let evaluator = session () in
  (match Session.cook evaluator ~context:(context 1) missing with
   | Error error when error.Diagnostic.code = "missing_group" -> ()
   | Error error -> fail ("unexpected diagnostic " ^ error.Diagnostic.code)
   | Ok _ -> fail "missing group accepted");
  Session.close evaluator;
  print_endline "test_point_generate_sop: ok"
