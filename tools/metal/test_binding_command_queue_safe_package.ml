let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected CommandQueue rejection"

let () =
  let open Binding_command_queue_safe_package in
  validate_handoff ();
  let state = { token = 3; device = 7; destroyed = false } in
  let descriptor = ok (create_descriptor ~max_command_buffer_count:2 ~log_state:None) in
  let descriptor = ok (replace_log_state ~device:7 descriptor (Some state)) in
  error (create_descriptor ~max_command_buffer_count:0 ~log_state:None);
  error (replace_log_state ~device:8 descriptor (Some state));
  error (replace_log_state ~device:7 descriptor (Some { state with destroyed = true }));
  let queue = { token = 11; device = 7; label = None; capture_active = true; destroyed = false } in
  let source = Bytes.of_string "main queue" in
  let queue = ok (snapshot_label queue (Some (Bytes.unsafe_to_string source))) in
  Bytes.fill source 0 (Bytes.length source) 'x';
  if queue.label <> Some "main queue" || queue.device <> 7 then failwith "queue label/device snapshot";
  let retained = ok (create_command_buffer queue ~token:21 ~retained_references:true) in
  let unretained = ok (create_command_buffer queue ~token:22 ~retained_references:false) in
  if not retained.ocaml_retained || not unretained.ocaml_retained || unretained.retains_references
  then failwith "command buffer retention policy";
  ignore (ok (insert_capture_boundary queue));
  error (insert_capture_boundary { queue with capture_active = false });
  error (create_command_buffer { queue with destroyed = true } ~token:23 ~retained_references:true);
  Printf.printf
    "CommandQueue safe package: callable14 descriptor-limit3/log3/buffers2/identity5/capture1 validation passed\n%!"
