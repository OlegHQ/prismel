open Binding_render_encoder_model

let get = function Ok value -> value | Error _ -> failwith "unexpected rejection"
let reject expected = function
  | Error actual when actual = expected -> ()
  | _ -> failwith "expected render-encoder model rejection"

let () =
  let pipeline = { id = 10L; device = 1L } in
  let buffer = { id = 20L; device = 1L; length = 64L } in
  let value = create ~device:1L in
  reject Missing_pipeline (draw value ~first:0 ~count:3 ~instances:1);
  reject Device_mismatch
    (set_pipeline value { pipeline with device = 2L });
  let value = get (set_pipeline value pipeline) in
  reject Device_mismatch
    (set_vertex_buffer value ~index:0 ~offset:0L
       (Some { buffer with device = 2L }));
  reject Out_of_range
    (set_vertex_buffer value ~index:31 ~offset:0L (Some buffer));
  reject Out_of_range
    (set_vertex_buffer value ~index:0 ~offset:65L (Some buffer));
  let value = get (set_vertex_buffer value ~index:0 ~offset:0L (Some buffer)) in
  let value = get (set_fragment_buffer value ~index:0 ~offset:16L (Some buffer)) in
  let value = get (draw value ~first:0 ~count:3 ~instances:1) in
  if retained_resource_count value <> 2 || List.length (commands value) <> 4
  then failwith "render-encoder retention/command ordering mismatch";
  let value = get (finish value) in
  reject Wrong_state (draw value ~first:0 ~count:3 ~instances:1);
  reject Wrong_state (finish value);
  Printf.printf "Metal render-encoder safe model passed\n"
