open Prismel
open Procedural

let fail message = raise (Failure message)

let string_ok = function Ok value -> value | Error message -> fail message

let geometry () =
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|-2.5; -1.5; -2.; 1.5; 2.5; 2.|]
      ~y:[|-0.5; -0.5; 0.5; -0.5; -0.5; 0.5|]
      ~z:(Array.make 6 0.) in
  let topology = Pdk.Topology.polygons_owned ~point_count:6
      ~vertex_points:[|0; 1; 2; 3; 4; 5|]
      ~primitive_offsets:[|0; 3; 6|] |> string_ok in
  let geometry = Pdk.Geometry.create ~positions ~topology () |> string_ok in
  let normals = Pdk.Attribute.create_owned ~name:"N"
      ~owner:Pdk.Attribute.Vertex
      (Pdk.Attribute.Float3 (Pdk.Packed.Float3.Private.of_owned_exn
        ~x:(Array.make 6 0.) ~y:(Array.make 6 1.) ~z:(Array.make 6 0.)))
      |> string_ok in
  let geometry = Pdk.Geometry.with_attribute normals geometry |> string_ok in
  let pieces = Pdk.Attribute.create_owned ~name:"class"
      ~owner:Pdk.Attribute.Primitive (Pdk.Attribute.Int [|0; 1|]) |> string_ok in
  Pdk.Geometry.with_attribute pieces geometry |> string_ok

let positions mesh = (Mesh.Private.packed_view mesh).vertices

let frame mouse_buttons = {
  Frame.width = 100; height = 100; size = 100, 100;
  drawable_width = 100; drawable_height = 100; drawable_size = 100, 100;
  pixel_scale = 1., 1.; time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse = 0, 0; mouse_delta = 0, 0; keys = []; mouse_buttons; events = [];
}

let timeline_frame ?(dt = 0.25) ?(events = []) ?(buttons = []) () = {
  (frame buttons) with Frame.dt = dt; events
}

let test_timeline_and_schedule () =
  let timeline = Sketch_support.Timeline.create () in
  let timeline, changes = Sketch_support.Timeline.update timeline
      (timeline_frame ()) in
  if Sketch_support.Timeline.time timeline <> 0.25
     || Sketch_support.Timeline.frame timeline <> 1L
     || not (Sketch_support.Timeline.changed_context changes)
  then fail "sketch timeline did not advance deterministically";
  let timeline, _ = Sketch_support.Timeline.update timeline
      (timeline_frame ~events:[Event.KeyPressed (Input.KeyChar 'p')] ()) in
  if Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Paused
     || Sketch_support.Timeline.time timeline <> 0.25
  then fail "sketch timeline pause shortcut did not freeze time";
  let timeline, _ = Sketch_support.Timeline.update timeline
      (timeline_frame ~events:[Event.KeyPressed (Input.KeyChar 's')] ()) in
  if Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Stopped
     || Sketch_support.Timeline.time timeline <> 0.
     || Sketch_support.Timeline.frame timeline <> 0L
  then fail "sketch timeline stop shortcut did not rewind";
  let timeline, reset_changes = Sketch_support.Timeline.update timeline
      (timeline_frame ~events:[Event.KeyPressed (Input.KeyChar 'r')] ()) in
  if Sketch_support.Timeline.mode timeline <> Sketch_support.Timeline.Playing
     || Sketch_support.Timeline.time timeline <> 0.25
     || not (Sketch_support.Timeline.changed_context reset_changes)
  then fail "sketch timeline reset shortcut did not restart playback";
  ignore (Sketch_support.Timeline.context timeline |> string_ok);

  let static_graph = Sop.points [|0., 0., 0.|] in
  let dynamic_graph = Sop.custom ~operation:"timeline_test"
      ~dependencies:(Context.Dependencies.one Context.Dependencies.Time)
      [static_graph] (fun ~context:_ inputs -> Ok inputs.(0)) in
  let schedule, fire = Sketch_support.Reactive_sop.schedule
      Sketch_support.Reactive_sop.schedule_initial ~graph:static_graph
      ~effects:Parameter.no_effects ~context_changed:false ~force:false
      ~busy:false
      ~frame:(timeline_frame ()) in
  if not fire then fail "cook scheduler skipped the initial graph";
  let schedule, fire = Sketch_support.Reactive_sop.schedule schedule
      ~graph:static_graph ~effects:Parameter.no_effects ~context_changed:true
      ~force:false ~busy:false ~frame:(timeline_frame ()) in
  if fire then fail "static graph recooked for an unrelated clock change";
  let schedule, fire = Sketch_support.Reactive_sop.schedule schedule
      ~graph:dynamic_graph ~effects:Parameter.no_effects ~context_changed:true
      ~force:false ~busy:false
      ~frame:(timeline_frame ~buttons:[Input.LeftButton] ()) in
  if fire then fail "dynamic graph cooked while a parameter drag was held";
  let _, fire = Sketch_support.Reactive_sop.schedule schedule
      ~graph:dynamic_graph ~effects:Parameter.no_effects ~context_changed:false
      ~force:false ~busy:false ~frame:(timeline_frame ()) in
  if not fire then fail "cook scheduler lost the latest held dynamic request"

let () =
  test_timeline_and_schedule ();
  let pieces = Sketch_support.Packed_pieces.of_geometry
      ~piece_attribute:"class" (geometry ()) |> string_ok in
  if Sketch_support.Packed_pieces.piece_count pieces <> 2 then
    fail "Packed_pieces did not preserve two connected pieces";
  let base = Sketch_support.Packed_pieces.mesh ~amount:0. pieces |> positions
  and exploded = Sketch_support.Packed_pieces.mesh ~amount:1. pieces |> positions in
  let base_normals = (Sketch_support.Packed_pieces.mesh ~amount:0. pieces
      |> Mesh.Private.packed_view).normals |> Option.get in
  if not (Array.for_all (( = ) 0.) base_normals.x
      && Array.for_all (( = ) 1.) base_normals.y
      && Array.for_all (( = ) 0.) base_normals.z) then
    fail "Packed_pieces replaced authored vertex normals with flat faces";
  for vertex = 0 to Array.length base.x - 1 do
    let expected = if base.x.(vertex) < 0. then -2. else 2. in
    if abs_float ((exploded.x.(vertex) -. base.x.(vertex)) -. expected) > 1e-12
    then fail "Packed_pieces explosion was not a rigid center translation";
    if exploded.y.(vertex) <> base.y.(vertex)
        || exploded.z.(vertex) <> base.z.(vertex) then
      fail "Packed_pieces explosion changed an orthogonal coordinate"
  done;
  let noisy_a = Sketch_support.Packed_pieces.mesh ~amount:0.7
      ~noise_amount:0.4 ~noise_frequency:1.3 ~noise_seed:19 pieces |> positions
  and noisy_b = Sketch_support.Packed_pieces.mesh ~amount:0.7
      ~noise_amount:0.4 ~noise_frequency:1.3 ~noise_seed:19 pieces |> positions in
  if noisy_a.x <> noisy_b.x || noisy_a.y <> noisy_b.y || noisy_a.z <> noisy_b.z
  then fail "Packed_pieces noise is not deterministic";
  let cook_effect = { Procedural.Parameter.cook = true; view = false;
    export = false } in
  let gate, fire = Sketch_support.Reactive_sop.gate
      Sketch_support.Reactive_sop.clean ~effects:cook_effect
      ~frame:(frame [Input.LeftButton]) in
  if fire then fail "Reactive_sop fired while a slider was held";
  let _, fire = Sketch_support.Reactive_sop.gate gate
      ~effects:Procedural.Parameter.no_effects ~frame:(frame []) in
  if not fire then fail "Reactive_sop did not commit once on pointer release";
  let source = Sop.box ~size:(Vec3.create 2. 2. 2.)
      ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals () in
  let cutter = Sop.grid ~counts:Pdk.Ops.Grid_divisions
      ~connectivity:Pdk.Ops.Grid_triangles ~columns:1 ~rows:1 ~size:3. () in
  let fractured = Sop.boolean_fracture ~require_closed:true
      ~piece_attribute:"piece" ~cutters:cutter source in
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(16 * 1024 * 1024) |> string_ok in
  let context = Context.create ~seed:0L () |> string_ok in
  let output = match Session.cook session ~context fractured with
    | Ok output -> output
    | Error error -> fail (Diagnostic.error_to_string error) in
  Session.close session;
  let pieces = Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "piece" output.geometry |> Option.get |> Pdk.Attribute.storage in
  (match pieces with
   | Pdk.Attribute.Int values ->
       let maximum = Array.fold_left Int.max (-1) values in
       if maximum <> 1 then
         fail "one cutting plane did not produce exactly two Boolean cells";
       let counts = Array.make 2 0 in
       Array.iter (fun piece -> counts.(piece) <- counts.(piece) + 1) values;
       if counts.(0) <= 1 || counts.(1) <= 1 then
         fail "Boolean fracture assigned individual polygons as pieces";
       let packed = Sketch_support.Packed_pieces.of_geometry
           ~piece_attribute:"piece" output.geometry |> string_ok in
       if Sketch_support.Packed_pieces.piece_count packed <> 2 then
         fail "Boolean fracture piece attribute did not pack two rigid shards"
   | _ -> fail "Boolean fracture piece attribute is not integer-valued");
  print_endline "sketch support tests passed"
