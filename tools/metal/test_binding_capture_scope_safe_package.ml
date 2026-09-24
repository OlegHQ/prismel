let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected CaptureScope rejection"

let () =
  let open Binding_capture_scope_safe_package in
  validate_handoff ();
  let queue = { token = 4; device = 7; kind = Classic; destroyed = false } in
  let source = Bytes.of_string "capture" in
  let scope = ok (create ~device:7 ~queue:(Some queue) ~label:(Some (Bytes.unsafe_to_string source))) in
  Bytes.fill source 0 (Bytes.length source) 'x';
  if device scope <> 7 || label scope <> Some "capture" then failwith "capture-scope identity/label snapshot";
  (match ok (command_queue ~metal4_available:false scope) with
   | Some retained when retained.token = queue.token -> () | _ -> failwith "classic queue identity");
  error (create ~device:8 ~queue:(Some queue) ~label:None);
  error (create ~device:7 ~queue:(Some { queue with destroyed = true }) ~label:None);
  let active = ok (begin_scope ~native_ok:true scope) in
  error (begin_scope ~native_ok:true active);
  error (end_scope ~native_ok:false active);
  if not (is_active active) then failwith "failed endScope did not roll back";
  let inactive = ok (end_scope ~native_ok:true active) in
  error (end_scope ~native_ok:true inactive);
  let failed_begin = begin_scope ~native_ok:false inactive in
  error failed_begin;
  if is_active inactive then failwith "failed beginScope changed state";
  let mtl4 = ok (create ~device:7 ~queue:(Some { queue with kind = Metal4 }) ~label:None) in
  error (mtl4_command_queue ~metal4_available:false mtl4);
  ignore (ok (mtl4_command_queue ~metal4_available:true mtl4));
  Printf.printf
    "CaptureScope safe package: callable11 lifecycle2/queue4/device2/label3 balance/rollback/identity/MTL4 passed\n%!"
