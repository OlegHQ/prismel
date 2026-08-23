let () =
  let mechanical = Binding_render_encoder_audit.count Mechanical_value in
  let handwritten = Binding_render_encoder_audit.count Handwritten_command in
  if Binding_render_encoder_manifest.count <> 102 || mechanical <> 14 || handwritten <> 88
  then failwith "render-command102 partition drift";
  let descriptor,stage,draw_state = 19,53,16 in
  if descriptor+stage+draw_state<>handwritten then failwith "handwritten materializer count drift";
  Printf.printf "render-command102: %d mechanical + %d handwritten (%d descriptor/%d stage/%d draw-state) integration assets green\n" mechanical handwritten descriptor stage draw_state
