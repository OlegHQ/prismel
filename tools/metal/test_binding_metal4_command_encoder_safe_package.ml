let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4CommandEncoder rejection"

let () =
  let open Binding_metal4_command_encoder_safe_package in
  validate_handoff ();
  error (create ~available:false ~device:7);
  let encoder = ok (create ~available:true ~device:7) in
  let fence = { token = 3; device = 7; value = 1L; destroyed = false } in
  ignore (ok (wait_for_fence encoder fence ~before_stages:0x20L));
  ignore (ok (wait_for_fence encoder fence ~before_stages:0x40L));
  if retained_fence_tokens encoder <> [ 3 ] then failwith "fence lifetime/dedup";
  error (wait_for_fence encoder { fence with device = 8 } ~before_stages:0x20L);
  error (wait_for_fence encoder { fence with destroyed = true } ~before_stages:0x20L);
  error (wait_for_fence encoder { fence with value = 0L } ~before_stages:0x20L);
  error (wait_for_fence encoder fence ~before_stages:0L);
  error (wait_for_fence encoder fence ~before_stages:0x400L);
  ignore (ok (end_encoding encoder));
  error (wait_for_fence encoder fence ~before_stages:0x20L);
  error (end_encoding encoder);
  complete encoder;
  if retained_fence_tokens encoder <> [] then failwith "completion did not release fence";
  destroy encoder; destroy encoder;
  Printf.printf
    "MTL4CommandEncoder3 reconciled: remaining callable1; pure visibility metadata2 already bound; availability/state/device/fence/stages/lifetime passed\n%!"
