open Binding_presentation_adapter
let ok = function Ok () -> () | Error message -> failwith message
let error = function Error _ -> () | Ok () -> failwith "expected rejection"
let () =
  let layer = { size={width=640;height=480}; pixel_format=Bgra8_unorm;
    colorspace=Some Srgb; framebuffer_only=true; maximum_drawables=3;
    allows_timeout=true; display_sync=true; presents_with_transaction=false } in
  ok (validate_layer layer);
  error (validate_layer {layer with size={width=0;height=480}});
  error (validate_layer {layer with maximum_drawables=4});
  let attachment = {index=0;level=0;slice=0;depth_plane=0;resolve_level=0;
                    resolve_slice=0;resolve_depth_plane=0} in
  let pass = {width=640;height=480;array_length=1;sample_count=1;tile_width=0;
              tile_height=0;threadgroup_memory_length=0;color_attachments=[attachment]} in
  ok (validate_render_pass pass);
  error (validate_render_pass {pass with color_attachments=[attachment;attachment]});
  assert (classify_drawable_loss ~size:{width=0;height=1} ~attached:true ~timed_out:false = Zero_sized);
  assert (classify_drawable_loss ~size:{width=1;height=1} ~attached:false ~timed_out:false = Detached);
  print_endline "presentation safe adapter validation passed"
