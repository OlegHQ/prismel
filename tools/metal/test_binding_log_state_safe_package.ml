let ok = function Result.Ok value -> value | Result.Error error -> failwith error
let error = function Result.Error _ -> () | Result.Ok _ -> failwith "expected LogState rejection"

let () =
  let open Binding_log_state_safe_package in
  validate_handoff ();
  let descriptor = ok (create_descriptor ~max_buffer_size:4096 ~level:Notice ~buffer_size:1024) in
  if descriptor.level <> Notice || descriptor.buffer_size <> 1024 then failwith "descriptor snapshot";
  error (create_descriptor ~max_buffer_size:4096 ~level:Debug ~buffer_size:0);
  error (create_descriptor ~max_buffer_size:4096 ~level:Debug ~buffer_size:4097);
  let state = ok (create_state ~max_handlers:2) in
  let messages = ref [] in
  let first = ok (add_handler state (fun level message -> messages := (level, message) :: !messages)) in
  ignore (ok (add_handler state (fun _ _ -> failwith "handler exception")));
  error (add_handler state (fun _ _ -> ()));
  let source = Bytes.of_string "validation" in
  emit state Error (Some (Bytes.unsafe_to_string source));
  Bytes.fill source 0 (Bytes.length source) 'x';
  if !messages <> [ Error, Some "validation" ] || handler_error_count state <> 1 then
    failwith "handler snapshot/exception isolation";
  if not (cancel first) || cancel first || rooted_handler_count state <> 1 then failwith "handler cancellation";
  cleanup state; cleanup state;
  if rooted_handler_count state <> 0 then failwith "handler cleanup";
  error (add_handler state (fun _ _ -> ()));
  Printf.printf
    "LogState safe package: callable7 descriptor6/handler1 bounded/snapshot/exception/cancel/cleanup passed\n%!"
