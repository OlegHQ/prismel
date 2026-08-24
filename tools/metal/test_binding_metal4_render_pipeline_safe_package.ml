let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4RenderPipeline rejection"

let () =
  let open Binding_metal4_render_pipeline_safe_package in
  validate_handoff ();
  error (create_attachment ~available:false);
  error (create_array ~available:false ~length:2);
  let attachment = ok (create_attachment ~available:true) in
  ignore (ok (configure attachment ~pixel_format:80 ~write_mask:3 ~blending:true));
  if ok (snapshot attachment) <> (Some 80, 3, true) then failwith "configured attachment state";
  ignore (ok (reset_attachment attachment)); ignore (ok (reset_attachment attachment));
  if ok (snapshot attachment) <> (None, 0xf, false) then failwith "attachment reset defaults";
  let array = ok (create_array ~available:true ~length:2) in
  ignore (ok (set array ~index:0 (Some attachment)));
  if retained_count array <> 1 then failwith "array retained graph";
  error (set array ~index:2 (Some attachment));
  ignore (ok (reset_array array)); ignore (ok (reset_array array));
  if retained_count array <> 0 then failwith "array reset release";
  destroy_attachment attachment; destroy_attachment attachment;
  error (reset_attachment attachment);
  destroy_array array; destroy_array array;
  error (reset_array array);
  Printf.printf
    "MTL4RenderPipeline3 safe package: callable2 reset defaults/lifetime/availability; metadata1 excluded\n%!"
