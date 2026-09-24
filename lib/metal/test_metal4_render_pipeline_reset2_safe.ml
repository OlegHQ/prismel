open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let reject_destroyed = function
  | Error error when error.kind = Destroyed -> ()
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok _ -> failwith "expected destroyed reset receiver rejection"

let is_default (value : Metal4_render_pipeline_reset.snapshot) =
  value.format = None && not value.blending && value.write_mask = 0xf

let () =
  match Metal4_render_pipeline_reset.attachment () with
  | Error error when error.kind = Unsupported || error.kind = Native_error ->
      print_endline "MTL4RenderPipeline reset2 safe: skipped (macOS 26 unavailable)"
  | Error error -> failwith (Format.asprintf "%a" pp_error error)
  | Ok attachment ->
      let array = get (Metal4_render_pipeline_reset.attachment_array ()) in
      for index = 0 to 7 do
        get
          (Metal4_render_pipeline_reset.configure attachment
             ~format:(if index land 1 = 0 then Texture.Rgba8_unorm
                      else Texture.Bgra8_unorm)
             ~blending:true ~write_mask:(1 lsl (index land 3)));
        get (Metal4_render_pipeline_reset.set array ~index attachment)
      done;
      let copied = Metal4_render_pipeline_reset.snapshots array in
      if Array.length copied <> 8 || Array.exists is_default copied then
        failwith "all eight configured attachment snapshots were not copied";
      get
        (Metal4_render_pipeline_reset.configure attachment
           ~format:Texture.R8_unorm ~blending:false ~write_mask:0xf);
      if (Metal4_render_pipeline_reset.snapshots array).(0).format = Some Texture.R8_unorm then
        failwith "array retained mutable source instead of copying it";
      for _ = 1 to 20 do
        get (Metal4_render_pipeline_reset.reset_attachment attachment);
        get (Metal4_render_pipeline_reset.reset_array array)
      done;
      if not (is_default (Metal4_render_pipeline_reset.snapshot attachment))
         || Array.exists (fun value -> not (is_default value))
              (Metal4_render_pipeline_reset.snapshots array)
      then failwith "reset did not restore exact defaults";
      get (Metal4_render_pipeline_reset.destroy_attachment attachment);
      get (Metal4_render_pipeline_reset.destroy_array array);
      reject_destroyed
        (Metal4_render_pipeline_reset.reset_attachment attachment);
      reject_destroyed (Metal4_render_pipeline_reset.reset_array array);
      print_endline
        "MTL4RenderPipeline reset2 safe: exact2 defaults/copy/all8/20x passed"
