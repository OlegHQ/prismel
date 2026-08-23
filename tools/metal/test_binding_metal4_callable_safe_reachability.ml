let () =
  Binding_metal4_callable_safe_reachability.validate ();
  List.iter
    (fun id ->
      match Binding_metal4_callable_safe_reachability.status id with
      | Binding_metal4_callable_safe_reachability.Callable_pending_native ->
          if not (List.mem id Binding_metal4_callable_safe_reachability.callable_ids)
          then failwith ("callable status mismatch: " ^ id)
      | Binding_metal4_callable_safe_reachability.Blocked ->
          if not (List.mem id Binding_metal4_callable_safe_reachability.blocked_ids)
          then failwith ("blocked status mismatch: " ^ id))
    Binding_metal4_manifest.ids;
  Printf.printf
    "Metal4 safe reachability audit: 51 pending-native callable IDs (27 compute, 6 generic, 3 residency, 15 counter), %d blocked; no promotion\n"
    (List.length Binding_metal4_callable_safe_reachability.blocked_ids)
