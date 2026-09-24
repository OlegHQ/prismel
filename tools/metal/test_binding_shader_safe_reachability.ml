let ()=
  Binding_shader_safe_reachability.validate();
  Printf.printf "Shader157 public audit: %d promotable, %d blocked; exact157 closed\n"
    (List.length Binding_shader_safe_reachability.promotable_ids)
    (List.length Binding_shader_safe_reachability.blocked)
