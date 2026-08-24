open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected fence rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "fence6 safe: skipped"
  | Ok device ->
      let queue = get (Command_queue.create device) in
      for iteration = 0 to 255 do
        let fence = get (Device.new_fence device) in
        let label = Printf.sprintf "fence-%d" iteration in
        get (Fence.set_label fence (Some label));
        if get (Fence.label fence) <> Some label
           || not (Device.same (Fence.device fence) device)
        then failwith "fence label/device snapshot mismatch";
        get (Fence.set_label fence None);
        if get (Fence.label fence) <> None then failwith "fence nil-label reset failed";
        expect Invalid_argument (Fence.set_label fence (Some "bad\000label"));
        let source = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
        let destination = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
        let command = get (Command_buffer.create queue ()) in
        let producer = get (Blit_encoder.create command) in
        get (Blit_encoder.fill_buffer producer source ~offset:0L ~length:64L
               ~byte:(iteration land 255));
        get (Blit_encoder.update_fence producer fence);
        get (Blit_encoder.end_encoding producer);
        let consumer = get (Blit_encoder.create command) in
        get (Blit_encoder.wait_for_fence consumer fence);
        get (Blit_encoder.copy_buffer consumer ~source ~source_offset:0L
               ~destination ~destination_offset:0L ~length:64L);
        get (Blit_encoder.end_encoding consumer);
        expect Parent_has_dependents (Fence.destroy fence);
        get (Command_buffer.commit command);
        get (Command_buffer.wait_until_completed command);
        let bytes = get (Buffer.read_bytes destination ~offset:0L ~length:64) in
        Bytes.iter (fun byte ->
          if Char.code byte <> iteration land 255 then failwith "fence ordering failed") bytes;
        get (Command_buffer.destroy command);
        get (Fence.destroy fence);
        get (Buffer.destroy source);
        get (Buffer.destroy destination)
      done;
      get (Command_queue.destroy queue);
      get (Device.destroy device);
      print_endline "fence6 safe: 256 label/device/order/lifetime iterations ok"
