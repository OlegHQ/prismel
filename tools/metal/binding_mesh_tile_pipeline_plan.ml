open Binding_mesh_tile_pipeline_spec

type selection =
  { declarations : declaration list
  ; classes : declaration list
  ; methods : declaration list
  ; properties : declaration list
  ; mechanical_properties : declaration list
  ; handwritten_properties : declaration list
  ; owners : string list
  }

let expected_declaration_count = 105
let expected_class_count = 6
let expected_method_count = 66
let expected_property_count = 33
let expected_mechanical_property_count = 16
let expected_handwritten_property_count = 17
let expected_identifier_sha256 =
  "2f628d76d2b44077a8eea16e77bb9aa95319a3298e620db32ac565d2d98a577a"

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal mesh/tile pipeline plan: " ^ message))
    format

let select inventory =
  let declarations = List.filter selected inventory in
  let by_kind kind =
    List.filter (fun declaration -> declaration.kind = kind) declarations
  in
  let classes = by_kind "class" in
  let methods = by_kind "method" in
  let properties = by_kind "property" in
  let mechanical_properties, handwritten_properties =
    List.partition
      (fun declaration -> mechanically_generated (property_kind declaration))
      properties
  in
  let owners =
    declarations
    |> List.filter_map (fun declaration -> declaration.owner)
    |> List.sort_uniq String.compare
  in
  let expect label expected actual =
    if expected <> actual then fail "%s: expected %d, got %d" label expected actual
  in
  expect "declarations" expected_declaration_count (List.length declarations);
  expect "classes" expected_class_count (List.length classes);
  expect "methods" expected_method_count (List.length methods);
  expect "properties" expected_property_count (List.length properties);
  expect "mechanical properties" expected_mechanical_property_count
    (List.length mechanical_properties);
  expect "handwritten properties" expected_handwritten_property_count
    (List.length handwritten_properties);
  if inventory_id_digest declarations <> expected_identifier_sha256 then
    fail "identifier digest drift";
  { declarations; classes; methods; properties; mechanical_properties
  ; handwritten_properties; owners
  }

let source_paths =
  [ "tools/metal/binding_mesh_tile_pipeline_spec.ml"
  ; "tools/metal/binding_mesh_tile_pipeline_spec.mli"
  ; "tools/metal/binding_mesh_tile_pipeline_plan.ml"
  ; "tools/metal/binding_mesh_tile_pipeline_plan.mli"
  ]
