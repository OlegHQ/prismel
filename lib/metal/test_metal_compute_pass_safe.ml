open Metal

let fail format = Printf.ksprintf failwith format
let get = function Ok value -> value | Error error -> fail "%s" error.message
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" error.message
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let pass = get (Compute_pass.create device ()) in
  if Compute_pass.device pass != device
     || Compute_pass.dispatch pass <> Compute_pass.Serial
     || Array.length (Compute_pass.attachments pass) <> 4
  then fail "compute-pass defaults drift";
  get (Compute_pass.set_dispatch pass Compute_pass.Concurrent);
  if Compute_pass.dispatch pass <> Compute_pass.Concurrent then
    fail "compute dispatch round-trip drift";
  expect Invalid_argument (Compute_pass.set_attachment pass ~index:4 None);
  (match Resource100.Sample_buffer.create device ~sample_count:4L () with
   | Error {kind=Unsupported;_} -> ()
   | Error error -> fail "%s" error.message
   | Ok samples ->
       let attachment : Compute_pass.attachment =
         {sample_buffer=samples;start_index=1L;end_index=3L}
       in
       get (Compute_pass.set_attachment pass ~index:0 (Some attachment));
       expect Parent_has_dependents (Resource100.Sample_buffer.destroy samples);
       expect Invalid_argument
         (Compute_pass.set_attachment pass ~index:1
            (Some {attachment with start_index=3L;end_index=2L}));
       get (Compute_pass.set_attachment pass ~index:0 None);
       get (Resource100.Sample_buffer.destroy samples));
  get (Compute_pass.destroy pass);
  get (Device.destroy device)
