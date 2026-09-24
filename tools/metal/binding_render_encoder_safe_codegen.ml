open Binding_render_encoder_safe_spec

let obligation_name = function
  | Encoder_open -> "encoder_open"
  | Pipeline_bound -> "pipeline_bound"
  | Same_device -> "same_device"
  | Range_checked -> "range_checked"
  | Finite_values -> "finite_values"
  | Capability_checked -> "capability_checked"
  | Retain_until_completion -> "retain_until_completion"

let entry_json entry =
  `Assoc
    [ "id", `String entry.id; "group", `String (group_name entry.group)
    ; "disposition", `String (match entry.disposition with Active -> "active" | Deprecated_alias -> "deprecated-alias")
    ; "obligations", `List (List.map (fun value -> `String (obligation_name value)) entry.obligations)
    ]

let render_manifest symbols =
  let entries = select symbols in
  `Assoc
    [ "schema", `Int 1; "owner", `String Binding_render_encoder_plan.owner
    ; "declaration_count", `Int (List.length entries)
    ; "active_count", `Int (List.length entries - List.length deprecated_ids)
    ; "deprecated_alias_count", `Int (List.length deprecated_ids)
    ; "entries", `List (List.map entry_json entries) ]

let render_wrapper_templates symbols =
  let output = Buffer.create 65536 in
  Buffer.add_string output "(* Generated safe-wrapper obligations; native calls are filled only by typed templates. *)\n";
  select symbols |> List.iter (fun entry ->
    Printf.bprintf output "(* %s\n   group=%s; disposition=%s; checks=%s *)\n"
      entry.id (group_name entry.group)
      (match entry.disposition with Active -> "active" | Deprecated_alias -> "deprecated-alias")
      (entry.obligations |> List.map obligation_name |> String.concat ","));
  Buffer.contents output
