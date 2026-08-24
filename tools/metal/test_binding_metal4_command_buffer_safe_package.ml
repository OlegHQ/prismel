let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4CommandBuffer rejection"

let () =
  let open Binding_metal4_command_buffer_safe_package in
  validate_handoff ();
  error (create_options ~available:false);
  let options = ok (create_options ~available:true) in
  let owned token = { token; device = 7; destroyed = false } in
  ignore (ok (set_log_state ~device:7 options (Some (owned 2))));
  if log_state options <> Some (owned 2) then failwith "log-state identity";
  error (set_log_state ~device:7 options (Some { (owned 2) with device = 8 }));
  let unavailable = create ~available:false ~device:7 in
  error (begin_buffer unavailable ~allocator:(owned 1) ~options);
  let buffer = create ~available:true ~device:7 in
  ignore (ok (begin_buffer buffer ~allocator:(owned 1) ~options));
  error (begin_buffer buffer ~allocator:(owned 1) ~options);
  let render = ok (render_encoder buffer ~descriptor:(owned 3) ~encoder_options:1 ~native_token:10) in
  let ml = ok (machine_learning_encoder ~supported:true buffer ~native_token:11) in
  if child_token render <> 10 || child_token ml <> 11 then failwith "child encoder identity";
  error (machine_learning_encoder ~supported:false buffer ~native_token:12);
  error (end_buffer buffer);
  ignore (ok (end_child render)); ignore (ok (end_child ml));
  error (end_child ml);
  let calls = ref 0 in
  ignore (ok (add_completion_handler buffer (fun () -> incr calls)));
  ignore (ok (add_completion_handler buffer (fun () -> failwith "callback")));
  ignore (ok (end_buffer buffer));
  if List.sort compare (retained_tokens buffer) <> [ 1; 2; 3 ] then failwith "command-buffer retained graph";
  complete buffer; complete buffer;
  if retained_tokens buffer <> [] || !calls <> 1 || callback_error_count buffer <> 1 then
    failwith "completion retention/callback exactly-once";
  ignore (ok (add_completion_handler buffer (fun () -> incr calls)));
  if !calls <> 2 then failwith "late completion callback";
  destroy_options options; destroy_options options;
  error (set_log_state ~device:7 options None);
  Printf.printf
    "MTL4CommandBuffer7 safe package: options/log4 + encoders2 + begin1 macOS26/state/device/retention/callback passed\n%!"
