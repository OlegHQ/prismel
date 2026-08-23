open Metal

let fail format = Printf.ksprintf failwith format
let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let queue = get (Command_queue.create device) in
  let layer = get (Metal_layer.create device (Metal_layer.default ~width:8 ~height:8)) in
  let drawable =
    match get (Drawable.acquire layer) with
    | Ok drawable -> drawable
    | Error Drawable.Timeout_or_unavailable -> fail "unexpected drawable loss"
  in
  let texture = get (Drawable.texture drawable) in
  expect Parent_has_dependents (Drawable.destroy drawable);
  let commands = get (Command_buffer.create queue ()) in
  let encoder = get (Render_encoder.create commands ~target:texture ()) in
  get (Render_encoder.end_encoding encoder);
  expect Invalid_argument
    (Command_buffer.present commands drawable ~at:(Command_buffer.At_time nan) ());
  expect Invalid_argument
    (Command_buffer.present commands drawable
       ~at:(Command_buffer.After_minimum_duration (-1.)) ());
  get (Command_buffer.present commands drawable ());
  let scheduled = Atomic.make 0 and completed = Atomic.make 0 in
  get (Command_buffer.add_scheduled_handler commands (fun () -> Atomic.incr scheduled));
  get (Command_buffer.add_completed_handler commands (fun () -> Atomic.incr completed));
  get (Command_buffer.add_completed_handler commands (fun () -> raise Exit));
  let before = get (Release_queue.stats ()) in
  expect Invalid_state (Command_buffer.present commands drawable ());
  let after = get (Release_queue.stats ()) in
  if before.total_created <> after.total_created || before.live_handles <> after.live_handles
  then fail "duplicate presentation allocated a native handle";
  expect Parent_has_dependents (Drawable.destroy drawable);
  get (Command_buffer.commit commands);
  expect Parent_has_dependents (Command_buffer.destroy commands);
  get (Command_buffer.wait_until_completed commands);
  if Atomic.get scheduled <> 1 || Atomic.get completed <> 1 then
    fail "command callback cardinality drift";
  get (Texture.destroy texture);
  get (Drawable.destroy drawable);
  get (Command_buffer.destroy commands);
  (* Abandoning many uncommitted Metal command buffers makes AGX report context
     leaks even when our callback tokens and roots are reclaimed.  Exercise the
     real integration once here; the native token prototype covers 10,000
     concurrent fire/cancel races without creating driver-invalid work. *)
  let before_cancel = get (Release_queue.stats ()) in
  let callback_commands = get (Command_buffer.create queue ()) in
  get (Command_buffer.add_completed_handler callback_commands (fun () -> ()));
  get (Command_buffer.destroy callback_commands);
  ignore (get (Release_queue.drain ()));
  let after_cancel = get (Release_queue.stats ()) in
  if after_cancel.live_handles <> before_cancel.live_handles then
    fail "callback cancellation leaked native handles";
  let pass = get (Render_pass_descriptor.create ~width:8 ~height:8 ()) in
  if Render_pass_descriptor.size pass <> (8,8)
     || Render_pass_descriptor.array_length pass <> 1
     || Render_pass_descriptor.sample_count pass <> 1
  then fail "render-pass snapshot drift";
  get (Render_pass_descriptor.destroy pass);
  get (Metal_layer.destroy layer);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
