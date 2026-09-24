let () =
  let ids=Binding_render_pass24_safe_closure.promotable_ids in
  if List.length ids<>24||List.length(List.sort_uniq String.compare ids)<>24
  then failwith "RenderPass24 exact closure drift";
  if List.length(List.filter(fun id->String.starts_with~prefix:"class:" id)ids)<>3
     ||List.length(List.filter(fun id->String.starts_with~prefix:"method:" id)ids)<>15
     ||List.length(List.filter(fun id->String.starts_with~prefix:"property:" id)ids)<>6
  then failwith "RenderPass24 3/15/6 split drift";
  print_endline "RenderPass24: exact24 copied/default/owned closure"
