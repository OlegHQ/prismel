open Binding_render_encoder_safe_graph
let get=function Ok x->x|Error e->failwith e
let reject=function Error _->()|Ok _->failwith "expected rejection"
let ()=
  let mechanical=Binding_render_encoder_audit.count Mechanical_value and handwritten=Binding_render_encoder_audit.count Handwritten_command in
  if mechanical+handwritten<>102 then failwith "partition";
  let buffer={id=1;device=7;length=4096;live=true} in
  let encoder=get(bind_buffer(empty~device:7)~index:0~offset:256 buffer) in
  get(validate_draw encoder~vertex_start:0~vertex_count:3~instance_count:1);
  reject(bind_buffer encoder~index:31~offset:0 buffer);
  reject(use_resources encoder[{buffer with device=8}]);
  let ended=get(finish encoder) in reject(validate_draw ended~vertex_start:0~vertex_count:3~instance_count:1);
  Printf.printf "render/counter102: %d direct value selectors + %d handwritten commands\n" mechanical handwritten
