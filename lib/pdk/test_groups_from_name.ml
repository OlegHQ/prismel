open Prismel
open Pdk

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get_ok = function
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let point_cloud count =
  Ops.points (Array.init count (fun point -> float_of_int point, 0., 0.))

let mesh () =
  let positions = Packed.Float3.Builder.create 4 in
  Array.iteri (fun point (x, y, z) ->
    Packed.Float3.Builder.set positions point x y z)
    [|(0., 0., 0.); (1., 0., 0.); (1., 1., 0.); (0., 1., 0.)|];
  let topology = Topology.Builder.create ~point_count:4 () in
  Topology.Builder.add_polygon topology [|0; 1; 2|];
  Topology.Builder.add_polygon topology [|0; 2; 3|];
  Geometry.create ~positions:(Packed.Float3.Builder.freeze positions)
    ~topology:(Topology.Builder.freeze topology) ()
  |> Result.get_ok

let with_text owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Text values)
      |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let with_int owner name values geometry =
  let attribute = Attribute.create_owned ~owner ~name (Attribute.Int values)
      |> Result.get_ok in
  Geometry.with_attribute attribute geometry |> Result.get_ok

let with_group group geometry = Geometry.with_group group geometry |> Result.get_ok

let group owner name geometry =
  match Geometry.find_group ~owner name geometry with
  | Some group -> group
  | None -> fail ("missing group " ^ name)

let members group =
  let output = ref [] in
  Group.iter (fun element -> output := element :: !output) group;
  List.rev !output

let expect_members expected group message =
  check (members group = expected) message

let expect_invalid operation message = match operation () with
  | Error error -> check (Error.code error = "invalid_group") message
  | Ok _ -> fail (message ^ ": unexpectedly succeeded")

let test_point_names_and_policies () =
  let source = point_cloud 8 |> with_text Attribute.Point "name"
      [|"red"; ""; "blue"; "red"; "9bad"; "a-b"; "a b"; "ümlaut"|] in
  let ignored = Ops.groups_from_name ~owner:Attribute.Point ~attribute:"name"
      source |> get_ok in
  expect_members [0; 3] (group Group.Point "red" ignored)
    "Groups from Name repeated point value";
  expect_members [2] (group Group.Point "blue" ignored)
    "Groups from Name second point value";
  check (Geometry.find_group ~owner:Group.Point "_9bad" ignored = None
      && Geometry.find_group ~owner:Group.Point "a_b" ignored = None)
    "Groups from Name ignores invalid names by default";
  let generated_names = Geometry.groups ignored |> List.map Group.name in
  check (generated_names = ["red"; "blue"])
    "Groups from Name preserves stable first-seen order";
  let forced = Ops.groups_from_name ~invalid_names:Ops.Force_valid
      ~owner:Attribute.Point ~attribute:"name" source |> get_ok in
  expect_members [4] (group Group.Point "_9bad" forced)
    "Groups from Name protects a leading digit";
  expect_members [5; 6] (group Group.Point "a_b" forced)
    "Groups from Name unions forced-name collisions";
  expect_members [7] (group Group.Point "__mlaut" forced)
    "Groups from Name makes UTF-8 bytes ASCII-safe";
  let prefixed = Ops.groups_from_name ~prefix:"piece_"
      ~owner:Attribute.Point ~attribute:"name" source |> get_ok in
  expect_members [4] (group Group.Point "piece_9bad" prefixed)
    "Groups from Name validates after prefixing";
  check (Geometry.find_group ~owner:Group.Point "piece_" prefixed = None)
    "Groups from Name ignores empty values before prefixing"

let test_primitive_names () =
  let source = mesh () |> with_text Attribute.Primitive "material"
      [|"metal"; "wood"|] in
  let output = Ops.groups_from_name ~owner:Attribute.Primitive
      ~attribute:"material" source |> get_ok in
  expect_members [0] (group Group.Primitive "metal" output)
    "Groups from Name primitive first value";
  expect_members [1] (group Group.Primitive "wood" output)
    "Groups from Name primitive second value"

let test_conflicts_and_empty_output () =
  let existing = Group.ordered ~owner:Group.Point ~name:"red" ~length:6
      [|5; 1|] |> Result.get_ok in
  let source = point_cloud 6 |> with_text Attribute.Point "name"
      [|"red"; "blue"; "blue"; ""; ""; ""|]
      |> with_group existing in
  let replaced = Ops.groups_from_name ~conflict:Ops.Name_replace
      ~owner:Attribute.Point ~attribute:"name" source |> get_ok in
  let red = group Group.Point "red" replaced in
  expect_members [0] red "Groups from Name replace conflict";
  check (not (Group.is_ordered red))
    "Groups from Name replace drops incompatible explicit order";
  let unioned = Ops.groups_from_name ~conflict:Ops.Name_union
      ~owner:Attribute.Point ~attribute:"name" source |> get_ok in
  let red = group Group.Point "red" unioned in
  expect_members [0; 1; 5] red "Groups from Name union conflict";
  check (not (Group.is_ordered red))
    "Groups from Name union emits an unordered group";
  let empty = point_cloud 3 |> with_text Attribute.Point "name"
      [|""; ""; ""|] in
  let unchanged = Ops.groups_from_name ~owner:Attribute.Point
      ~attribute:"name" empty |> get_ok in
  check (unchanged == empty)
    "Groups from Name returns the original geometry when no group is emitted"

let test_bounds_and_failures () =
  let source = point_cloud 8 |> with_text Attribute.Point "name"
      [|"a"; "b"; "a"; "b"; "a"; "b"; "a"; "b"|] in
  expect_invalid (fun () -> Ops.groups_from_name ~max_groups:1
      ~owner:Attribute.Point ~attribute:"name" source)
    "Groups from Name group-count bound";
  expect_invalid (fun () -> Ops.groups_from_name ~max_payload_bytes:1
      ~owner:Attribute.Point ~attribute:"name" source)
    "Groups from Name packed-payload bound";
  expect_invalid (fun () -> Ops.groups_from_name ~max_groups:(-1)
      ~owner:Attribute.Point ~attribute:"name" source)
    "Groups from Name rejects a negative group bound";
  expect_invalid (fun () -> Ops.groups_from_name ~grain:0
      ~owner:Attribute.Point ~attribute:"name" source)
    "Groups from Name rejects a non-positive grain";
  expect_invalid (fun () -> Ops.groups_from_name ~owner:Attribute.Vertex
      ~attribute:"name" source)
    "Groups from Name rejects vertex ownership";
  expect_invalid (fun () -> Ops.groups_from_name ~owner:Attribute.Detail
      ~attribute:"name" source)
    "Groups from Name rejects detail ownership";
  expect_invalid (fun () -> Ops.groups_from_name ~owner:Attribute.Point
      ~attribute:"missing" source)
    "Groups from Name reports a missing attribute";
  let integer_source = point_cloud 8 |> with_int Attribute.Point "name"
      [|0; 1; 0; 1; 0; 1; 0; 1|] in
  expect_invalid (fun () -> Ops.groups_from_name ~owner:Attribute.Point
      ~attribute:"name" integer_source)
    "Groups from Name rejects non-text storage";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.groups_from_name ~cancel:cancelled ~owner:Attribute.Point
      ~attribute:"name" source with
   | Error error -> check (Error.code error = "cancelled")
       "Groups from Name cancellation code"
   | Ok _ -> fail "cancelled Groups from Name published geometry")

let same_group left right =
  Group.owner left = Group.owner right
  && Group.name left = Group.name right
  && Group.length left = Group.length right
  && Group.is_ordered left = Group.is_ordered right
  && members left = members right

let text_values owner name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> values
       | _ -> fail ("non-text attribute " ^ name))
  | None -> fail ("missing attribute " ^ name)

let test_name_from_groups () =
  let alpha = Group.init ~grain:1 ~owner:Group.Point ~name:"alpha" 6
      (fun point -> point = 0 || point = 1)
  and beta = Group.init ~grain:1 ~owner:Group.Point ~name:"beta" 6
      (fun point -> point = 1 || point = 2) in
  let source = point_cloud 6 |> with_group alpha |> with_group beta in
  let last = Ops.name_from_groups ~default:"none" ~owner:Attribute.Point source
      |> get_ok in
  check (text_values Attribute.Point "name" last
      = [|"alpha"; "beta"; "beta"; "none"; "none"; "none"|])
    "Name from Groups stable last-group overlap";
  let first = Ops.name_from_groups ~overlap:Ops.First_group
      ~owner:Attribute.Point source |> get_ok in
  check (text_values Attribute.Point "name" first
      = [|"alpha"; "alpha"; "beta"; ""; ""; ""|])
    "Name from Groups stable first-group overlap";
  expect_invalid (fun () -> Ops.name_from_groups ~overlap:Ops.Error_on_overlap
      ~owner:Attribute.Point source)
    "Name from Groups overlap error";
  let existing = source |> with_text Attribute.Point "piece"
      [|"old0"; "old1"; "old2"; "old3"; "old4"; "old5"|] in
  let filtered = Ops.name_from_groups ~attribute:"piece" ~pattern:"alpha"
      ~delete_groups:true ~owner:Attribute.Point existing |> get_ok in
  check (text_values Attribute.Point "piece" filtered
      = [|"alpha"; "alpha"; "old2"; "old3"; "old4"; "old5"|])
    "Name from Groups preserves existing values outside selected groups";
  check (Geometry.find_group ~owner:Group.Point "alpha" filtered = None
      && Geometry.find_group ~owner:Group.Point "beta" filtered <> None)
    "Name from Groups deletes only pattern-selected source groups";
  let primitive_source = mesh ()
      |> with_group (Group.init ~grain:1 ~owner:Group.Primitive ~name:"face_a" 2
        (fun primitive -> primitive = 0)) in
  let primitive = Ops.name_from_groups ~owner:Attribute.Primitive
      primitive_source |> get_ok in
  check (text_values Attribute.Primitive "name" primitive = [|"face_a"; ""|])
    "Name from Groups primitive ownership";
  let vertex_source = mesh ()
      |> with_group (Group.init ~grain:1 ~owner:Group.Vertex ~name:"corner" 6
        (fun vertex -> vertex mod 2 = 0)) in
  let vertex = Ops.name_from_groups ~owner:Attribute.Vertex vertex_source
      |> get_ok in
  check (text_values Attribute.Vertex "name" vertex
      = [|"corner"; ""; "corner"; ""; "corner"; ""|])
    "Name from Groups vertex ownership";
  expect_invalid (fun () -> Ops.name_from_groups ~owner:Attribute.Detail source)
    "Name from Groups rejects detail ownership";
  let cancelled = Cancel.create () in
  Cancel.cancel cancelled;
  (match Ops.name_from_groups ~cancel:cancelled ~owner:Attribute.Point source with
   | Error error -> check (Error.code error = "cancelled")
       "Name from Groups cancellation code"
   | Ok _ -> fail "cancelled Name from Groups published geometry")

let test_scale_and_parallel_exactness () =
  let count = 200_003 and distinct = 32 in
  let values = Array.init count (fun element ->
    if element mod 97 = 0 then ""
    else Printf.sprintf "piece_%02d" (element mod distinct)) in
  let source = point_cloud count |> with_text Attribute.Point "name" values in
  let run domains = Parallel.run ~domains (fun () ->
    Ops.groups_from_name ~grain:1_009 ~owner:Attribute.Point
      ~attribute:"name" source |> get_ok) in
  let one = run 1 and four = run 4 in
  let one_groups = Geometry.groups one and four_groups = Geometry.groups four in
  check (List.length one_groups = distinct
      && List.length four_groups = distinct)
    "Groups from Name scale cardinality";
  check (List.for_all2 same_group one_groups four_groups)
    "Groups from Name one/four-domain exactness";
  let expected_payload = distinct * ((count + 7) / 8) in
  let actual_payload = List.fold_left
      (fun total group -> total + Group.payload_bytes group) 0 one_groups in
  check (actual_payload = expected_payload)
    "Groups from Name exact packed payload ceiling";
  let round_trip geometry = Ops.name_from_groups ~grain:1_009
      ~attribute:"round_trip" ~delete_groups:true ~owner:Attribute.Point geometry
      |> get_ok in
  let one_named = round_trip one and four_named = round_trip four in
  check (text_values Attribute.Point "round_trip" one_named
      = text_values Attribute.Point "round_trip" four_named)
    "Name from Groups one/four-domain exactness";
  check (Geometry.groups one_named = [] && Geometry.groups four_named = [])
    "Name from Groups scale deletion cardinality"

let () =
  test_point_names_and_policies ();
  test_primitive_names ();
  test_conflicts_and_empty_output ();
  test_bounds_and_failures ();
  test_name_from_groups ();
  test_scale_and_parallel_exactness ();
  print_endline "groups from name tests passed"
