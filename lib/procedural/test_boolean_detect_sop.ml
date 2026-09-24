open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let get = function Ok value -> value | Error message -> fail message

let contains text pattern =
  let rec loop offset = offset + String.length pattern <= String.length text
      && (String.sub text offset (String.length pattern) = pattern
          || loop (offset + 1)) in
  pattern = "" || loop 0

let context domains = Context.create ~domains ~grain:31 ~seed:73L () |> get

let cook session domains graph =
  match Session.cook session ~context:(context domains) graph with
  | Ok output -> output.Session.geometry
  | Error error -> fail (Diagnostic.error_to_string error)

let graph () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:64 ~rows:48 ~size:12. () in
  let collision = Sop.transform (Mat4.rotation_x (Float.pi /. 2.)) source in
  Sop.boolean_detect ~label:"surface-crossings" ~collision
    ~tolerance:1e-9 ~include_coplanar:false
    ~intersecting_group:(Some "intersections")
    ~intersections_attribute:"collision_primitives"
    ~count_attribute:"intersection_count" source

let self_graph () =
  let source = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:48 ~rows:36 ~size:10. () in
  let crossing = Sop.transform (Mat4.rotation_x (Float.pi /. 2.)) source in
  Sop.merge [source; crossing]
  |> Sop.boolean_detect ~label:"self-crossings" ~include_coplanar:false
       ~self_intersections_attribute:"self_primitives"
       ~self_count_attribute:"self_count"

let signature geometry =
  let rows = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "collision_primitives" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Int_array values -> Pdk.Packed.Int_array.Private.view values
         | _ -> fail "Boolean Detect SOP list has wrong storage")
    | None -> fail "Boolean Detect SOP list is missing" in
  let counts = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "intersection_count" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Int values -> values
         | _ -> fail "Boolean Detect SOP count has wrong storage")
    | None -> fail "Boolean Detect SOP count is missing" in
  let group = Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive "intersections"
      geometry |> Option.get in
  let membership = Array.init (Pdk.Geometry.primitive_count geometry)
      (fun primitive -> Pdk.Group.mem primitive group) in
  rows.offsets, rows.values, counts, membership

let fresh graph domains =
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
      |> get in
  let geometry = cook session domains graph in
  Session.close session;
  geometry

let self_signature geometry =
  let rows = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "self_primitives" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Int_array values -> Pdk.Packed.Int_array.Private.view values
         | _ -> fail "Boolean Detect SOP AxA list has wrong storage")
    | None -> fail "Boolean Detect SOP AxA list is missing" in
  let counts = match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive
      "self_count" geometry with
    | Some attribute ->
        (match Pdk.Attribute.Private.storage attribute with
         | Pdk.Attribute.Int values -> values
         | _ -> fail "Boolean Detect SOP AxA count has wrong storage")
    | None -> fail "Boolean Detect SOP AxA count is missing" in
  let group = Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
      "boolean_self_intersections" geometry |> Option.get in
  rows.offsets, rows.values, counts,
  Array.init (Pdk.Geometry.primitive_count geometry)
    (fun primitive -> Pdk.Group.mem primitive group)

let test_identity_cache_and_parallel () =
  let graph = graph () in
  check (Node.operation graph = "boolean_detect"
      && Node.cook_mode graph = Node.Duplicate_input 0
      && List.length (Node.inputs graph) = 2
      && contains (Node.parameters graph) "tolerance="
      && contains (Node.parameters graph) "include_coplanar=false"
      && contains (Node.parameters graph) "intersections_attribute=collision_primitives"
      && contains (Node.parameters graph) "count_attribute=intersection_count")
    "Boolean Detect SOP cache identity omits behavior controls";
  let session = Session.create ~max_entries:8 ~max_payload_bytes:128_000_000
      |> get in
  let first = cook session 1 graph and before = Session.stats session in
  let repeated = cook session 4 graph and after = Session.stats session in
  check (first == repeated && after.hits > before.hits)
    "Boolean Detect SOP missed its static cook cache";
  Session.close session;
  let one = fresh graph 1 and four = fresh graph 4 in
  check (signature one = signature four)
    "Boolean Detect SOP differs across one and four domains";
  let _, values, counts, membership = signature one in
  check (Array.length values > 0 && Array.exists Fun.id membership
      && Array.fold_left ( + ) 0 counts >= Array.length values)
    "Boolean Detect SOP scale fixture found no intersections";
  let self_graph = self_graph () in
  check (Node.operation self_graph = "boolean_detect"
      && List.length (Node.inputs self_graph) = 1
      && contains (Node.parameters self_graph) "collision_input=false"
      && contains (Node.parameters self_graph)
           "self_intersecting_group=boolean_self_intersections")
    "Boolean Detect SOP one-input AxA identity";
  let self_one = fresh self_graph 1 and self_four = fresh self_graph 4 in
  check (self_signature self_one = self_signature self_four)
    "Boolean Detect SOP AxA differs across one and four domains";
  let _, self_values, _, self_membership = self_signature self_one in
  check (Array.length self_values > 0 && Array.exists Fun.id self_membership)
    "Boolean Detect SOP AxA scale fixture found no intersections"

let test_diagnostics_and_constructor_validation () =
  let source = Sop.grid ~columns:4 ~rows:4 ~size:2. ()
  and collision = Sop.grid ~columns:4 ~rows:4 ~size:2. () in
  let missing = Sop.boolean_detect ~source_group:"missing" ~collision source in
  let session = Session.create ~max_entries:4 ~max_payload_bytes:8_000_000
      |> get in
  (match Session.cook session ~context:(context 1) missing with
   | Error error -> check (error.Diagnostic.code = "missing_group")
       "Boolean Detect SOP missing-source-group diagnostic"
   | Ok _ -> fail "Boolean Detect SOP accepted a missing source group");
  Session.close session;
  let invalid thunk = try ignore (thunk ()); false with Invalid_argument _ -> true in
  check (invalid (fun () -> Sop.boolean_detect ~collision
      ~intersecting_group:None source))
    "Boolean Detect SOP accepted no outputs";
  check (invalid (fun () -> Sop.boolean_detect ~collision
      ~intersections_attribute:"same" ~count_attribute:"same" source))
    "Boolean Detect SOP accepted conflicting output attributes";
  check (invalid (fun () -> Sop.boolean_detect ~collision
      ~intersecting_group:(Some "") source))
    "Boolean Detect SOP accepted an empty output name";
  check (invalid (fun () -> Sop.boolean_detect ~collision_group:"faces" source))
    "Boolean Detect SOP accepted a collision group without collision input";
  check (invalid (fun () -> Sop.boolean_detect ~collision
      ~self_intersecting_group:(Some "boolean_intersections") source))
    "Boolean Detect SOP accepted colliding AxA/AxB group names"

let () =
  test_identity_cache_and_parallel ();
  test_diagnostics_and_constructor_validation ();
  print_endline "boolean detect SOP tests passed"
