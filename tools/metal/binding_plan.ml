include Binding_spec

let expected_sdk_version = "26.5"

let source_paths =
  [ "tools/metal/binding_plan.ml"
  ; "tools/metal/binding_plan.mli"
  ; "tools/metal/binding_plan_compute.ml"
  ; "tools/metal/binding_plan_render.ml"
  ; "tools/metal/binding_plan_resource.ml"
  ; "tools/metal/binding_spec.ml"
  ; "tools/metal/binding_spec.mli"
  ]

let source_sha256 ~root =
  source_paths
  |> List.map (fun relative ->
    relative, Support.read_file (Filename.concat root relative))
  |> aggregate_source_sha256

let entries =
  Binding_plan_render.entries @ Binding_plan_compute.entries
  @ Binding_plan_resource.entries

let generated_entries =
  List.filter
    (fun entry ->
      match entry.disposition with Generate _ -> true | _ -> false)
    entries

let bound_identifiers =
  generated_entries
  |> List.filter (fun entry -> Option.is_some entry.safe_api)
  |> List.concat_map (fun entry ->
    entry.sdk_id
    :: List.map (fun (companion : companion) -> companion.sdk_id)
         entry.companions)
