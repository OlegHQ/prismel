open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)
let expect kind = function Error error when error.kind=kind -> () | Error error -> failwith (Format.asprintf "%a" pp_error error) | Ok _ -> failwith "expected BlitPass rejection"

let run () =
  match Device.system_default () with
  | Error _ -> print_endline "blit pass safe: skipped"
  | Ok device ->
      let pass = get (Blit_pass_descriptor.create device) in
      let attachments = get (Blit_pass_descriptor.attachments pass) in
      expect Invalid_argument (Blit_pass_attachments.get attachments ~index:(-1));
      let attachment = match get (Blit_pass_attachments.get attachments ~index:0) with
        | Some value -> value | None -> failwith "missing default blit attachment" in
      expect Invalid_argument
        (Blit_pass_attachment.configure attachment ~sample_buffer:None
           ~start:(Blit_pass_attachment.Index 0L)
           ~finish:Blit_pass_attachment.Dont_sample);
      (match Resource100.Sample_buffer.create device ~sample_count:4L () with
       | Error error when error.kind=Unsupported -> ()
       | Error error -> failwith (Format.asprintf "%a" pp_error error)
       | Ok samples ->
           expect Invalid_argument
             (Blit_pass_attachment.configure attachment ~sample_buffer:(Some samples)
                ~start:(Blit_pass_attachment.Index 3L)
                ~finish:(Blit_pass_attachment.Index 4L));
           get (Blit_pass_attachment.configure attachment ~sample_buffer:(Some samples)
             ~start:(Blit_pass_attachment.Index 1L)
             ~finish:(Blit_pass_attachment.Index 3L));
           let queue = get (Command_queue.create device) in
           let command = get (Command_buffer.create queue ()) in
           let encoder = get (Blit_pass_descriptor.create_encoder command pass) in
           expect Invalid_state (Blit_pass_descriptor.create_encoder command pass);
           get (Blit_encoder.end_encoding encoder);
           expect Parent_has_dependents (Blit_pass_descriptor.destroy pass);
           get (Command_buffer.commit command);
           get (Command_buffer.wait_until_completed command);
           if Bytes.length (get (Counters.resolve samples ~first:1L ~count:3L)) <> 24 then failwith "blit pass samples did not resolve";
           get (Command_buffer.destroy command);
           get (Command_queue.destroy queue);
           expect Parent_has_dependents (Resource100.Sample_buffer.destroy samples);
           get (Blit_pass_attachment.configure attachment ~sample_buffer:None
             ~start:Blit_pass_attachment.Dont_sample
             ~finish:Blit_pass_attachment.Dont_sample);
           get (Resource100.Sample_buffer.destroy samples));
      expect Parent_has_dependents (Blit_pass_descriptor.destroy pass);
      get (Blit_pass_attachment.destroy attachment);
      get (Blit_pass_attachments.destroy attachments);
      get (Blit_pass_descriptor.destroy pass);
      get (Device.destroy device);
      print_endline "blit pass safe: exact8 ok"
