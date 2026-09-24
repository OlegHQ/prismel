let () =
  if Binding_presentation_spec.expected_count <> 125 then failwith "count drift";
  if List.length Binding_presentation_plan.lifecycle_requirements <> 7 then
    failwith "lifecycle evidence drift";
  if List.length Binding_presentation_evidence.gates <> 10 then
    failwith "gate drift";
  let native = Binding_presentation_codegen.emit_native_contract () in
  if not (String.contains native '[') then failwith "missing typed selector";
  Printf.printf "presentation foundation: %d exact unreviewed IDs, %d gates\n"
    Binding_presentation_spec.expected_count
    (List.length Binding_presentation_evidence.gates)
