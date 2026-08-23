let callable_ids =
  List.sort_uniq String.compare
    (Binding_resource_integration_partition.handwritten_ownership
     @ Binding_resource_integration_partition.graph_gated_scalars)

let remaining_ids =
  Binding_resource_integration_partition.ownership_sensitive
  |> List.filter (fun id -> not (List.mem id callable_ids))

let validate () =
  if List.length Binding_resource_integration_partition.handwritten_ownership <> 56
     || List.length Binding_resource_integration_partition.graph_gated_scalars <> 3
     || List.length callable_ids <> 59 || remaining_ids <> []
  then failwith "Resource100 native/raw 59-ID closure drift";
  if callable_ids <>
     List.sort_uniq String.compare
       Binding_resource_integration_partition.ownership_sensitive
  then failwith "Resource100 callable set differs from ownership partition"

let () = validate ()
