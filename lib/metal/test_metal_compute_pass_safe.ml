open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok value -> value | Error error -> fail "%s" error.message
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" error.message
  | Ok _ -> fail "expected rejection"

let run () =
  let device = get (Device.system_default ()) in
  let pass = get (Compute_pass.create device ()) in
  (match Resource100.Sample_buffer.create device ~sample_count:4L () with
   | Error {kind=Unsupported;_} -> ()
   | Error error -> fail "%s" error.message
   | Ok samples ->
       (* An encoder created from the pass samples its stage boundaries and
          keeps the pass and sample buffer alive until the command completes. *)
       let queue = get (Command_queue.create device) in
       let command = get (Command_buffer.create queue ()) in
       let encoder = get (Compute_pass.create_encoder command pass) in
       expect Invalid_state (Compute_pass.create_encoder command pass);
       get (Compute_encoder.end_encoding encoder);
       expect Parent_has_dependents (Compute_pass.destroy pass);
       get (Command_buffer.commit command);
       get (Command_buffer.wait_until_completed command);
       expect Invalid_state (Compute_pass.create_encoder command pass);
       get (Command_buffer.destroy command);
       get (Command_queue.destroy queue);
       get (Resource100.Sample_buffer.destroy samples));
  get (Compute_pass.destroy pass);
  get (Device.destroy device)
