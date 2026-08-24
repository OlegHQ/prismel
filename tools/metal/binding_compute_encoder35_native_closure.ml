let callable_ids =
  Binding_compute_command_manifest.ids
  |> List.filter (fun id ->
       String.starts_with ~prefix:"method:-[MTLComputeCommandEncoder " id
       || String.equal id "property:MTLComputeCommandEncoder:dispatchType")

let expected_count = 35
let validate () =
  if List.length callable_ids <> expected_count then
    invalid_arg "ComputeEncoder35 native closure drift";
  if List.length (List.sort_uniq String.compare callable_ids) <> expected_count then
    invalid_arg "ComputeEncoder35 native closure contains duplicate IDs"
