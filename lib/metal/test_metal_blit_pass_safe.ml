open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)
let expect kind = function Error error when error.kind=kind -> () | Error error -> failwith (Format.asprintf "%a" pp_error error) | Ok _ -> failwith "expected BlitPass rejection"

let () =
  match Device.system_default () with
  | Error _ -> print_endline "blit pass safe: skipped"
  | Ok device ->
      let pass = get (Blit_pass_descriptor.create device) in
      let attachments = get (Blit_pass_descriptor.attachments pass) in
      expect Invalid_argument (Blit_pass_attachments.get attachments ~index:(-1));
      expect Invalid_argument
        (Blit_pass_attachments.get attachments ~index:Blit_pass_attachments.capacity);
      let attachment = match get (Blit_pass_attachments.get attachments ~index:0) with
        | Some value -> value | None -> failwith "missing default blit attachment" in
      if Blit_pass_attachment.range attachment <>
           (Blit_pass_attachment.Dont_sample,Blit_pass_attachment.Dont_sample)
      then failwith "blit pass default sample range drift";
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
           (match get (Blit_pass_attachment.sample_buffer attachment) with
            | Some retained when retained==samples -> ()
            | _ -> failwith "blit sample-buffer identity drift");
           expect Parent_has_dependents (Resource100.Sample_buffer.destroy samples);
           get (Blit_pass_attachment.configure attachment ~sample_buffer:None
             ~start:Blit_pass_attachment.Dont_sample
             ~finish:Blit_pass_attachment.Dont_sample);
           get (Resource100.Sample_buffer.destroy samples));
      get (Blit_pass_attachments.set attachments ~index:1 (Some attachment));
      get (Blit_pass_attachments.set attachments ~index:1 None);
      expect Parent_has_dependents (Blit_pass_descriptor.destroy pass);
      get (Blit_pass_attachment.destroy attachment);
      get (Blit_pass_attachments.destroy attachments);
      get (Blit_pass_descriptor.destroy pass);
      get (Device.destroy device);
      print_endline "blit pass safe: exact8 ok"
