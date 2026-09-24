let () =
  Binding_indirect_command14_safe_plan.validate ();
  let union = Binding_indirect_command14_safe_plan.already_safe @
              Binding_indirect_command14_safe_plan.pending_safe in
  if List.sort String.compare union <>
     List.sort String.compare Binding_indirect_command14_native_closure.ids then
    failwith "IndirectCommand14 partition membership drift";
  print_endline "IndirectCommand14 safe plan: exact14 = safe7 + pending7"
