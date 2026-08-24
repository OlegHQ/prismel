let ()=let open Binding_compute_pipeline11_safe_closure in
  if List.sort_uniq String.compare(promotable_ids@blocked_ids)
     |>List.length<>11 then failwith"ComputePipeline11 closure overlap";
  print_endline"ComputePipeline11: promotable10, blocked binary-handle1"
