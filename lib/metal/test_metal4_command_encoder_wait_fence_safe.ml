open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let reject kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok _ -> failwith "expected Metal 4 fence-wait rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "MTL4CommandEncoder fence wait: skipped (no device)"
  | Ok device ->
      (match Command4.Allocator.create device with
       | Error error when error.kind = Unsupported || error.kind = Native_error ->
           get (Device.destroy device);
           print_endline "MTL4CommandEncoder fence wait: skipped (macOS26 unavailable)"
       | Error error -> failwith (Format.asprintf "%a" pp_error error)
       | Ok allocator ->
           let fence = get (Fence.create device) in
           let command = get (Command4.Command_buffer.create allocator ()) in
           let producer = get (Command4.Compute_encoder.create command) in
           reject Invalid_argument
             (Command4.Compute_encoder.update_fence producer fence ~after:[]);
           get (Command4.Compute_encoder.update_fence producer fence ~after:[Blit]);
           get (Command4.Compute_encoder.end_encoding producer);
           let consumer = get (Command4.Compute_encoder.create command) in
           reject Invalid_argument
             (Command4.Compute_encoder.wait_for_fence consumer fence ~before:[]);
           get (Command4.Compute_encoder.wait_for_fence consumer fence ~before:[Blit]);
           reject Parent_has_dependents (Fence.destroy fence);
           get (Command4.Compute_encoder.end_encoding consumer);
           get (Command4.Command_buffer.end_recording command);
           get (Command4.Command_buffer.destroy command);
           get (Fence.destroy fence);
           get (Command4.Allocator.destroy allocator);
           get (Device.destroy device);
           print_endline "MTL4CommandEncoder fence wait: producer/consumer retention passed")
