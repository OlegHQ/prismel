let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4RenderPass rejection"

let () =
  let open Binding_metal4_render_pass_safe_package in
  validate_handoff ();
  error (create ~available:false ~device:7 ~width:640 ~height:480 ~sample_count:2 ~max_sample_positions:4);
  let descriptor = ok (create ~available:true ~device:7 ~width:640 ~height:480
    ~sample_count:2 ~max_sample_positions:4) in
  let source = [| { x = 0.25; y = 0.25 }; { x = 0.75; y = 0.75 } |] in
  ignore (ok (set_sample_positions descriptor source));
  source.(0) <- { x = 2.; y = 2. };
  if sample_positions descriptor <> [| { x = 0.25; y = 0.25 }; { x = 0.75; y = 0.75 } |]
  then failwith "sample-position snapshot";
  error (set_sample_positions descriptor [| { x = 0.5; y = 0.5 } |]);
  error (set_sample_positions descriptor [| { x = -0.1; y = 0.5 }; { x = 0.5; y = 0.5 } |]);
  let map = { token = 1; device = 7; screen_width = 640; screen_height = 480; destroyed = false } in
  ignore (ok (set_rate_map descriptor (Some map)));
  if rate_map descriptor <> Some map then failwith "rate-map identity";
  error (set_rate_map descriptor (Some { map with device = 8 }));
  error (set_rate_map descriptor (Some { map with screen_width = 320 }));
  let depth = { token = 2; device = 7; kind = Depth; sample_count = 2; destroyed = false } in
  let stencil = { token = 3; device = 7; kind = Stencil; sample_count = 2; destroyed = false } in
  ignore (ok (set_depth_attachment descriptor (Some depth)));
  ignore (ok (set_stencil_attachment descriptor (Some stencil)));
  error (set_depth_attachment descriptor (Some stencil));
  error (set_stencil_attachment descriptor (Some { stencil with sample_count = 1 }));
  error (set_depth_attachment descriptor (Some { depth with destroyed = true }));
  if List.sort compare (retained_tokens descriptor) <> [ 1; 2; 3 ] then failwith "render-pass retained graph";
  reset descriptor; reset descriptor;
  if retained_tokens descriptor <> [] || sample_positions descriptor <> [||] then failwith "render-pass reset";
  Printf.printf
    "MTL4RenderPass7 safe package: samples2/rate-map3/attachments2 macOS26/device/range/sample/ownership/reset passed\n%!"
