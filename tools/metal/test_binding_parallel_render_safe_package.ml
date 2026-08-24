let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected ParallelRender rejection"

let () =
  let open Binding_parallel_render_safe_package in
  validate_handoff ();
  let color = { token = 1; device = 7; destroyed = false } in
  let depth = { token = 2; device = 7; destroyed = false } in
  let parent = ok (create_parent ~device:7 ~colors:[| Some color; None |] ~depth:(Some depth) ~stencil:None) in
  if List.sort compare (retained_attachment_tokens parent) <> [ 1; 2 ] then failwith "attachment lifetime";
  error (create_parent ~device:8 ~colors:[| Some color |] ~depth:None ~stencil:None);
  error (create_parent ~device:7 ~colors:[| Some { color with destroyed = true } |] ~depth:None ~stencil:None);
  ignore (ok (set_color_store parent ~index:0 Store No_options));
  error (set_color_store parent ~index:1 Store No_options);
  error (set_color_store parent ~index:2 Store No_options);
  error (set_color_store parent ~index:0 Dont_care Custom_sample_positions);
  ignore (ok (set_depth_store parent Store_and_multisample_resolve Custom_sample_positions));
  if parent_device parent <> 7 || configured_write_count parent <> 2 then failwith "typed store writes";
  error (set_stencil_store parent Store No_options);
  let first = ok (create_child parent ~token:10) in
  let second = ok (create_child parent ~token:11) in
  if child_token first <> 10 || child_token second <> 11 then failwith "child identity";
  error (end_parent parent);
  ignore (ok (end_child first));
  error (end_child first);
  ignore (ok (end_child second));
  ignore (ok (end_parent parent));
  error (create_child parent ~token:12);
  error (set_color_store parent ~index:0 Store No_options);
  Printf.printf
    "ParallelRender safe package: callable7 child1/store6 parent-child/device/lifetime/end-order passed\n%!"
