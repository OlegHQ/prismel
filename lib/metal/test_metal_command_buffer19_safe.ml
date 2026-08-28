open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected: %a" pp_error error)
  | Ok _ -> failwith "expected rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "command-buffer19: skipped"
  | Ok device ->
      let queue = get (Command_queue.create device) in
      let command =
        get (Command_buffer.create_with_descriptor queue
               ~retained_references:true ~error_options:1L ())
      in
      expect Invalid_state (Command_buffer.encoder_infos command);
      let callbacks = ref 0 in
      get (Command_buffer.add_completed_handler command
             (fun () -> incr callbacks));
      let buffer = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
      let blit = get (Blit_encoder.create command) in
      get (Blit_encoder.fill_buffer blit buffer ~offset:0L ~length:64L ~byte:0x5a);
      get (Blit_encoder.end_encoding blit);
      expect Parent_has_dependents (Buffer.destroy buffer);
      expect Parent_has_dependents (Command_queue.destroy queue);
      get (Command_buffer.commit command);
      get (Command_buffer.wait_until_completed command);
      if !callbacks <> 1 then failwith "completion handler was not exactly once";
      expect Invalid_state (Command_buffer.encoder_infos command);
      get (Buffer.destroy buffer);
      get (Command_buffer.destroy command);
      let handles_before_abandon = (get (Release_queue.stats ())).live_handles in
      let abandon_completed_command () =
        let command = get (Command_buffer.create queue ()) in
        get (Command_buffer.commit command);
        get (Command_buffer.wait_until_completed command)
      in
      abandon_completed_command ();
      Gc.full_major ();
      Gc.full_major ();
      ignore (get (Release_queue.drain ()));
      let handles_after_abandon = (get (Release_queue.stats ())).live_handles in
      if handles_after_abandon <> handles_before_abandon then
        failwith "abandoned command buffer retained a native handle";
      get (Command_queue.destroy queue);
      get (Device.destroy device);
      print_endline "command-buffer19 safe: ownership/completion/diagnostics ok"
