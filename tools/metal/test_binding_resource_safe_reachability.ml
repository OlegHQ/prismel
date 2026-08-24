let () =
  let module Audit = Binding_resource_safe_reachability in
  Audit.validate ();
  let expected =
    List.sort_uniq String.compare
      (Binding_resource_integration_partition.descriptor_owned
       @ Binding_resource_integration_partition.already_callable
       @ Binding_resource_integration_partition.graph_gated_scalars
       @ Binding_resource_integration_partition.safe_ownership_tail
       @ Audit.safe_constructor_core
       @ Audit.pool_core)
  in
  if Audit.promotable_ids <> expected then
    failwith "Resource100 exact promotable closure drift";
  if List.length Audit.promotable_ids <> 74 || List.length Audit.blocked <> 26 then
    failwith "Resource100 safe/gap partition drift";
  Printf.printf
    "Resource100 public audit: %d promotable, %d blocked; exact100 closed\n"
    (List.length Audit.promotable_ids) (List.length Audit.blocked)
