let () =
  if Binding_resource_coverage.generated_count + Binding_resource_coverage.handwritten_count <> 100
  then failwith "resource coverage drift";
  if List.length Binding_resource_integration.native_selector_contract <> 10 then failwith "selector drift";
  if List.length Binding_resource_integration.failure_policies <> 6 then failwith "policy drift";
  Printf.printf "resource integration: 100 IDs (%d typed generated, %d safe handwritten)\n"
    Binding_resource_coverage.generated_count Binding_resource_coverage.handwritten_count
