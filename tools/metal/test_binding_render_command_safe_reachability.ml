let () =
  let module Audit = Binding_render_command_safe_reachability in
  Audit.validate ();
  List.iter
    (fun item ->
      if item.Audit.public_operation = "" || item.required_test = "" then
        failwith ("empty Render-command102 evidence: " ^ item.id))
    Audit.items;
  Printf.printf
    "Render-command102 public audit: %d promotable, %d blocked; exact102 closed\n"
    (List.length Audit.promotable_ids)
    (List.length Audit.blocked)
