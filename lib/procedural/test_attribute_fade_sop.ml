open Prismel
open Pdk
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error _ -> fail "unexpected error"

let contains text pattern =
  let rec search offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || search (offset + 1)) in
  pattern = "" || search 0

let source () =
  let geometry = Ops.grid ~connectivity:Ops.Grid_quads ~columns:260 ~rows:160
      ~size:12. () |> function
    | Ok value -> value
    | Error error -> fail (Error.to_string error) in
  let point_count = Geometry.point_count geometry in
  let fade = Attribute.create_owned ~owner:Attribute.Point ~name:"fade"
      (Attribute.Float (Array.init point_count (fun point ->
        0.25 +. float_of_int (point mod 31) /. 32.))) |> Result.get_ok
  and start = Attribute.create_owned ~owner:Attribute.Point ~name:"start"
      (Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point mod 173) *. 0.75))) |> Result.get_ok
  and hold = Attribute.create_owned ~owner:Attribute.Point ~name:"hold"
      (Attribute.Int (Array.init point_count (fun point -> point mod 5)))
      |> Result.get_ok
  and selected = Group.init ~grain:257 ~owner:Group.Point ~name:"fade_points"
      point_count (fun point -> point mod 7 <> 0) in
  geometry |> Geometry.with_attribute fade |> Result.get_ok
  |> Geometry.with_attribute start |> Result.get_ok
  |> Geometry.with_attribute hold |> Result.get_ok
  |> Geometry.with_group selected |> Result.get_ok

let float_values geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "fade" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> values
       | _ -> fail "fade storage changed")
  | None -> fail "fade attribute missing"

let color_values geometry =
  match Geometry.find_attribute ~owner:Attribute.Point "Cd" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Packed.Float4.Private.view values
       | _ -> fail "Cd storage changed")
  | None -> fail "Cd attribute missing"

let context ?(frame = 137L) ?(time = 0.) ?(seed = 211L) domains =
  Context.create ~frame ~time ~seed ~domains ~grain:257 () |> get

let cook session context graph =
  match Session.cook session ~context graph with
  | Ok output -> output.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  Sop.snapshot (source ())
  |> Sop.attribute_fade ~label:"timed-fade" ~group:"fade_points"
       ~start_source:(Sop.snapshot (source ()))
       ~hold_source:(Sop.snapshot (source ()))
       ~start_attribute:"start" ~start_retime:(3., 0.75)
       ~hold_scale_attribute:"hold" ~frame_offset:2.
       ~fade_in:8. ~fade_hold:6. ~fade_out:16.
       ~fade_in_ramp:[0.,0.;0.3,0.08;0.72,0.9;1.,1.]
       ~fade_out_ramp:[0.,1.;0.25,0.96;0.65,0.18;1.,0.]
       ~visualize:true

let () =
  let graph = graph () in
  let parameters = Node.parameters graph in
  check (contains parameters "group=fade_points"
      && contains parameters "start_source=true"
      && contains parameters "hold_source=true"
      && contains parameters "fade_in_ramp="
      && contains parameters "visualize=true")
    "Attribute Fade SOP cache identity omits controls";
  check (List.length (Node.inputs graph) = 3)
    "Attribute Fade SOP did not retain its three role-specific inputs";
  let dependencies = Node.dependencies graph in
  check (Context.Dependencies.mem Context.Dependencies.Frame dependencies
      && not (Context.Dependencies.mem Context.Dependencies.Time dependencies)
      && not (Context.Dependencies.mem Context.Dependencies.Seed dependencies))
    "Attribute Fade SOP context dependency declaration is not frame-only";
  let session = Session.create ~max_entries:12 ~max_payload_bytes:220_000_000
      |> get in
  let first = cook session (context 1) graph in
  let stats_before = Session.stats session in
  let repeated = cook session (context ~time:99. ~seed:999L 4) graph in
  let stats_after = Session.stats session in
  check (first == repeated && stats_after.hits > stats_before.hits)
    "Attribute Fade SOP missed cache across irrelevant time/seed/domain facts";
  let next = cook session (context ~frame:138L 1) graph in
  check (next != first && float_values next <> float_values first)
    "Attribute Fade SOP did not invalidate on frame change";
  Session.close session;
  let cook_fresh domains =
    let session = Session.create ~max_entries:12 ~max_payload_bytes:220_000_000
        |> get in
    let output = cook session (context domains) graph in
    Session.close session;
    output in
  let one = cook_fresh 1 and four = cook_fresh 4 in
  check (float_values one = float_values four)
    "Attribute Fade SOP one/four-domain fade differs";
  let one_color = color_values one and four_color = color_values four in
  check (one_color.x = four_color.x && one_color.y = four_color.y
      && one_color.z = four_color.z && one_color.w = four_color.w)
    "Attribute Fade SOP one/four-domain visualization differs";
  let hold_only = Sop.snapshot (source ())
      |> Sop.attribute_fade ~hold_source:(Sop.snapshot (source ()))
           ~hold_scale_attribute:"hold" ~fade_in:0. ~fade_hold:1.
           ~fade_out:1. in
  check (List.length (Node.inputs hold_only) = 2
      && contains (Node.parameters hold_only) "start_source=false"
      && contains (Node.parameters hold_only) "hold_source=true")
    "Attribute Fade SOP hold-only input role identity is incorrect";
  let hold_only_session = Session.create ~max_entries:4
      ~max_payload_bytes:220_000_000 |> get in
  ignore (cook hold_only_session (context 4) hold_only);
  Session.close hold_only_session;
  let one_mesh = Prismel_mesh.to_mesh one |> function
    | Ok value -> value | Error error -> fail (Error.to_string error)
  and four_mesh = Prismel_mesh.to_mesh four |> function
    | Ok value -> value | Error error -> fail (Error.to_string error) in
  check (Mesh.Private.packed_view one_mesh = Mesh.Private.packed_view four_mesh)
    "Attribute Fade SOP one/four-domain render mesh differs";
  let missing = Sop.snapshot (source ())
      |> Sop.attribute_fade ~group:"missing" in
  let invalid = Sop.snapshot (source ())
      |> Sop.attribute_fade ~fade_in:(-1.) in
  let bad_reference = Sop.snapshot (source ())
      |> Sop.attribute_fade ~start_source:(Sop.points [|(0.,0.,0.)|])
           ~start_attribute:"start" in
  let session = Session.create ~max_entries:6 ~max_payload_bytes:220_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.code = "missing_group")
       "Attribute Fade SOP missing-group diagnostic"
   | Ok _ -> fail "Attribute Fade SOP accepted a missing group");
  List.iter (fun graph -> match Session.cook session ~context:(context 1) graph with
    | Error error -> check (error.code = "invalid_attribute_fade")
        "Attribute Fade SOP structured PDK diagnostic"
    | Ok _ -> fail "Attribute Fade SOP accepted invalid controls")
    [invalid; bad_reference];
  Session.close session;
  print_endline "attribute fade SOP tests passed"
