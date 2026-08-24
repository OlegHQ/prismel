let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected Event rejection"

let () =
  let open Binding_event_safe_package in
  validate_handoff ();
  let queue = { token = 3; destroyed = false } in
  let listener = ok (create_listener ~max_pending:2 (Some queue)) in
  (match listener_queue listener with Some retained when retained.token = 3 -> () | _ -> failwith "queue identity");
  let label = Bytes.of_string "shared" in
  let event = create_event ~token:5 ~device:7 ~label:(Some (Bytes.unsafe_to_string label)) in
  let handle = export_handle event in
  Bytes.fill label 0 (Bytes.length label) 'x';
  if event_device event <> 7 || handle.device <> 7 || handle.label <> Some "shared" then failwith "event identity/label";
  let calls = ref 0 in
  ignore (ok (notify_at event listener ~value:4L (fun () -> incr calls)));
  let cancelled = ok (notify_at event listener ~value:5L (fun () -> incr calls)) in
  if retained_callback_count listener <> 2 || not (cancel cancelled) then failwith "callback retention/cancel";
  signal event 3L; signal event 4L; signal event 8L;
  if !calls <> 1 || retained_callback_count listener <> 0 then failwith "callback exactly-once";
  ignore (ok (notify_at event listener ~value:9L (fun () -> failwith "callback")));
  signal event 9L;
  if callback_error_count listener <> 1 then failwith "callback exception isolation";
  ignore (ok (notify_at event listener ~value:10L (fun () -> incr calls)));
  destroy_listener listener; destroy_listener listener;
  if retained_callback_count listener <> 0 then failwith "destroy cancellation lifetime";
  error (notify_at event listener ~value:11L (fun () -> ()));
  error (create_listener ~max_pending:0 None);
  Printf.printf
    "Event safe package: callable10 listener3/queue2/export1/label2/device1/notify1 bounded/exactly-once passed\n%!"
