open Ogpu_metal

let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let get_metal = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
let expect kind = function Error error when error.Ogpu.Error.kind = kind -> () | _ -> failwith "wrong rejection"

let configuration width height : Ogpu.Surface.configuration =
  { logical_width=width; logical_height=height
  ; physical_width=width; physical_height=height
  ; format=Bgra8_unorm; present_mode=Fifo; max_acquired=3 }

let texture_descriptor width height usage : Ogpu.Types.texture_descriptor =
  { label=None; width; height; depth=1; mip_levels=1; sample_count=1; usage }

let rgba_pixels width height =
  let colors =
    [| (0xff,0x00,0x00,0xff); (0x00,0xff,0x00,0x80)
     ; (0x00,0x00,0xff,0x40); (0x11,0x22,0x33,0x44) |]
  in
  let bytes = Bytes.create (width * height * 4) in
  for pixel = 0 to (width * height) - 1 do
    let red,green,blue,alpha = colors.(pixel mod Array.length colors) in
    let offset = pixel * 4 in
    Bytes.set_uint8 bytes offset red;
    Bytes.set_uint8 bytes (offset+1) green;
    Bytes.set_uint8 bytes (offset+2) blue;
    Bytes.set_uint8 bytes (offset+3) alpha
  done;
  bytes

let bgra_of_rgba rgba =
  let result = Bytes.copy rgba in
  for pixel = 0 to (Bytes.length rgba / 4) - 1 do
    let offset = pixel * 4 in
    Bytes.set result offset (Bytes.get rgba (offset+2));
    Bytes.set result (offset+2) (Bytes.get rgba offset)
  done;
  result

let create_source device width height =
  let descriptor =
    texture_descriptor width height
      [Ogpu.Types.Texture_binding; Texture_copy_dst]
  in
  let texture =
    get (Texture.create device ~memory:Texture.Shared ~format:Texture.Rgba8_unorm descriptor)
  in
  let pixels = rgba_pixels width height in
  get (Texture.write_bytes device texture ~mip_level:0 ~bytes_per_row:(width*4) pixels);
  texture,pixels

let () =
  match Device.system_default () with
  | Error _ -> print_endline "ogpu_metal surface: skipped (no device)"
  | Ok device ->
      let native_device = Device.Private.metal device in
      let layer =
        get_metal
          (Metal.Metal_layer.create native_device
             (Metal.Metal_layer.default ~width:4 ~height:4))
      in
      let before = get_metal (Metal.Release_queue.stats ()) in
      expect Ogpu.Error.Invalid_argument
        (Surface.create device ~layer
           {(configuration 4 4) with format=Rgba8_unorm});
      let production = get (Surface.create device ~layer (configuration 4 4)) in
      if not (Metal.Metal_layer.config layer).framebuffer_only then
        failwith "production surface must be framebuffer-only";
      Surface.destroy production;
      let surface =
        get (Surface.Private.create_readable device ~layer (configuration 4 4))
      in
      if (Metal.Metal_layer.config layer).framebuffer_only then
        failwith "readable test surface remained framebuffer-only";
      let queue = get (Queue.create device) in
      let retained_on_failed_configure =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "transactional configure drawable unavailable"
      in
      let generation_before_failed_configure = Surface.generation surface
      and layer_before_failed_configure = Metal.Metal_layer.config layer in
      expect Ogpu.Error.Invalid_argument
        (Surface.configure surface {(configuration 4 4) with max_acquired=0});
      if Surface.generation surface <> generation_before_failed_configure ||
         Metal.Metal_layer.config layer <> layer_before_failed_configure then
        failwith "failed configure mutated native or portable surface";
      ignore (get (Surface.frame_texture retained_on_failed_configure));
      get (Surface.discard surface retained_on_failed_configure);
      Surface.set_availability surface Force_timeout;
      (match get (Surface.acquire surface) with Timeout -> () | _ -> failwith "timeout mapping");
      Surface.set_availability surface Force_occluded;
      (match get (Surface.acquire surface) with Occluded -> () | _ -> failwith "occlusion mapping");
      Surface.set_availability surface Force_device_lost;
      (match get (Surface.acquire surface) with Device_lost -> () | _ -> failwith "device-loss mapping");
      Surface.set_availability surface Available;

      let source4,rgba4 = create_source device 4 4 in
      let expected4 = bgra_of_rgba rgba4 in
      let target4 =
        get (Texture.create device ~memory:Texture.Shared ~format:Texture.Bgra8_unorm
               (texture_descriptor 4 4 [Render_attachment;Texture_copy_src]))
      in
      get (Surface.Private.render_for_test surface ~queue ~source:source4 ~target:target4);
      let ordinary = get (Texture.read_bytes device target4 ~mip_level:0 ~bytes_per_row:16) in
      if ordinary <> expected4 then failwith "ordinary BGRA presentation bytes mismatch";

      let missing_binding =
        get (Texture.create device ~memory:Texture.Shared ~format:Texture.Rgba8_unorm
               (texture_descriptor 4 4 [Render_attachment;Texture_copy_dst]))
      in
      expect Ogpu.Error.Invalid_argument
        (Surface.Private.render_for_test surface ~queue ~source:missing_binding ~target:target4);
      let rejected_frame =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "rejection drawable unavailable"
      in
      expect Ogpu.Error.Invalid_argument
        (Surface.present_from surface rejected_frame ~queue ~source:missing_binding);
      ignore (get (Surface.frame_texture rejected_frame));
      get (Surface.discard surface rejected_frame);
      get (Texture.destroy missing_binding);

      let other =
        get (Surface.Private.create_readable device ~layer (configuration 4 4))
      in
      let foreign =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "foreign-frame drawable unavailable"
      in
      expect Ogpu.Error.Cross_device
        (Surface.present_from other foreign ~queue ~source:source4);
      ignore (get (Surface.frame_texture foreign));
      get (Surface.discard surface foreign);
      Surface.destroy other;

      let first =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "first drawable unavailable"
      in
      get (Surface.Private.render_source_into_frame surface first ~queue ~source:source4);
      ignore (get (Surface.frame_texture first));
      get (Surface.Private.copy_frame_for_test surface first ~queue ~target:target4);
      let drawable = get (Texture.read_bytes device target4 ~mip_level:0 ~bytes_per_row:16) in
      if drawable <> expected4 then
        failwith "actual drawable BGRA presentation bytes mismatch";
      get (Surface.present_from surface first ~queue ~source:source4);
      expect Ogpu.Error.Invalid_state (Surface.discard surface first);

      for frame_index = 2 to 600 do
        match get (Surface.acquire surface) with
        | Acquired frame ->
            get (Surface.present_from surface frame ~queue ~source:source4);
            if frame_index=2 || frame_index=60 || frame_index=600 then
              expect Ogpu.Error.Invalid_state (Surface.discard surface frame)
        | _ -> failwith "drawable unavailable"
      done;

      let stale =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "stale setup"
      in
      let old_generation = Surface.frame_generation stale in
      get (Surface.resize surface ~logical_width:8 ~logical_height:8
             ~physical_width:8 ~physical_height:8);
      if Surface.generation surface <= old_generation then
        failwith "resize generation did not advance";
      expect Ogpu.Error.Stale_handle
        (Surface.present_from surface stale ~queue ~source:source4);
      let source8,_ = create_source device 8 8 in
      (match get (Surface.acquire surface) with
       | Acquired frame -> get (Surface.present_from surface frame ~queue ~source:source8)
       | _ -> failwith "resized drawable unavailable");

      expect Ogpu.Error.Invalid_state (Device.destroy device);
      get (Texture.destroy source8);
      get (Texture.destroy target4);
      get (Texture.destroy source4);
      Surface.destroy surface;
      get (Queue.destroy queue);
      if Metal.Metal_layer.destroyed layer then failwith "borrowed layer was destroyed";
      ignore (get_metal (Metal.Release_queue.drain ()));
      let settled = get_metal (Metal.Release_queue.stats ()) in
      if settled.live_handles <> before.live_handles then
        failwith
          (Printf.sprintf "surface presentation handle delta before=%d after=%d"
             before.live_handles settled.live_handles);
      get_metal (Metal.Metal_layer.destroy layer);
      get (Device.destroy device);
      print_endline
        "ogpu_metal surface: exact RGBA/BGRA drawable, frames 1/2/60/600/resize, zero handle delta"
