open Prismel
open Procedural

let fail message = raise (Failure message)

type controls = {
  translate_x : float [@sop.default 0.] [@sop.label "Translate X"]
    [@sop.folder "Transform"] [@sop.min (-5.)] [@sop.max 5.];
  time_scale : float [@sop.default 0.] [@sop.label "Time scale"]
    [@sop.folder "Animation"] [@sop.min (-2.)] [@sop.max 2.];
} [@@deriving sop_params]

let cook session context node = match Session.cook session ~context node with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let x geometry =
  let positions = Pdk.Packed.Float3.Private.view
      (Pdk.Geometry.positions geometry) in
  positions.x.(0)

let () =
  let input = Sop.points [|0., 0., 0.|] in
  let node = Custom.map ~label:"animated wrangle" ~version:2
      ~dependencies:(Context.Dependencies.one Context.Dependencies.Time)
      ~operation:"animated_translate" ~schema:controls_schema
      ~values:{ translate_x = 1.; time_scale = 2. } input
      (fun ~parameters ~context geometry ->
        let offset = parameters.translate_x
            +. (parameters.time_scale *. Context.time context) in
        Ok (Pdk.Ops.transform
          (Mat4.translation (Vec3.create offset 0. 0.)) geometry)) in
  if List.length (Node.parameter_fields node) <> 2
     || not (Node.has_parameters node)
     || not (Context.Dependencies.mem Context.Dependencies.Time
        (Node.dependencies node))
  then fail "custom SOP did not own PPX parameters or dependencies";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:1_000_000
      |> Result.get_ok in
  let context time = Context.create ~time () |> Result.get_ok in
  if x (cook session (context 3.) node) <> 7. then
    fail "custom SOP did not receive parameters and timeline context";
  let before_key = Node.parameters node and node_id = Node.id node in
  let edited, effects = Graph.apply_parameters node ~node_id
      ["translate_x", Parameter.Float_value 4.] |> Result.get_ok in
  if not effects.cook || Node.id edited <> node_id
     || Node.parameters edited = before_key
  then fail "custom SOP edit lost stable identity or cache-key invalidation";
  if x (cook session (context 3.) edited) <> 10. then
    fail "custom SOP edit did not rebuild its cook closure";
  let fields = Node.parameter_fields edited in
  let translated = List.find (fun field -> field.Parameter.name = "translate_x")
      fields in
  if translated.current <> Parameter.Float_value 4. then
    fail "custom SOP inspector metadata did not retain edited values";
  Session.close session;
  print_endline "custom SOP tests passed"
