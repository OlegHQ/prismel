let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected BlitPass rejection"

let () =
  let open Binding_blit_pass_safe_package in
  validate_handoff ();
  let buffer = { token = 4; device = 7; sample_count = 8; destroyed = false } in
  let sample = { buffer = Some buffer; start_index = 2; end_index = 5 } in
  let source = [| Some sample; None |] in
  let descriptor = ok (create ~device:7 ~max_attachments:4 source) in
  source.(0) <- None;
  if retained_tokens descriptor <> [ 4 ] then failwith "blit descriptor snapshot/retention";
  (match ok (attachment descriptor ~index:0) with
   | Some attachment when sample_buffer attachment = Some buffer -> ()
   | _ -> failwith "sample buffer identity");
  error (set_attachment descriptor ~index:2 (Some sample));
  error (set_attachment descriptor ~index:1 (Some { sample with start_index = 6; end_index = 5 }));
  error (set_attachment descriptor ~index:1 (Some { sample with end_index = 8 }));
  error (set_attachment descriptor ~index:1 (Some { sample with buffer = Some { buffer with device = 8 } }));
  error (set_attachment descriptor ~index:1 (Some { sample with buffer = Some { buffer with destroyed = true } }));
  error (set_attachment descriptor ~index:1 (Some { sample with buffer = None }));
  ignore (ok (set_attachment descriptor ~index:1
    (Some { buffer = None; start_index = dont_sample; end_index = dont_sample })));
  if retained_tokens descriptor <> [ 4 ] then failwith "failed replacement mutated graph";
  reset descriptor;
  if retained_tokens descriptor <> [] then failwith "blit reset did not release buffers";
  error (create ~device:7 ~max_attachments:1 [| Some sample; None |]);
  Printf.printf
    "BlitPass safe package: callable8 metadata2 excluded; descriptor/array/buffer/index/device/lifetime/reset passed\n%!"
