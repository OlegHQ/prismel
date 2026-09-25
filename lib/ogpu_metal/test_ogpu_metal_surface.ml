open Ogpu_metal_native

let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let get_metal = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
let expect kind = function Error error when error.Ogpu.Error.kind = kind -> () | _ -> failwith "wrong rejection"

let configuration width height : Ogpu.Surface.configuration =
  { logical_width=width; logical_height=height
  ; physical_width=width; physical_height=height
  ; format=Bgra8_unorm; present_mode=Fifo; max_acquired=3;layer=None }

(* Surface lifecycle over a standalone layer: configuration is transactional,
   availability maps to typed acquire results, frames are discarded or go
   stale across resize, and nothing leaks. Presentation itself runs through
   [Backend.commit_present] in the windowed runtime tests. *)
let run () =
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
      let surface = get (Surface.create device ~layer (configuration 4 4)) in
      if not (Metal.Metal_layer.config layer).framebuffer_only then
        failwith "production surface must be framebuffer-only";
      let retained_on_failed_configure =
        match get (Surface.acquire surface) with
        | Acquired frame -> frame
        | _ -> failwith "transactional configure drawable unavailable"
      in
      let generation_before_failed_configure = Surface.generation surface
      and layer_before_failed_configure = Metal.Metal_layer.config layer in
      expect Ogpu.Error.Invalid_argument
        (Surface.configure surface {(configuration 4 4) with max_acquired=0;layer=None});
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
      let frames = Option.value ~default:10
          (Option.bind (Sys.getenv_opt "PRISMEL_SURFACE_FRAMES") int_of_string_opt) in
      for _ = 1 to frames do
        match get (Surface.acquire surface) with
        | Acquired frame ->
            ignore (get (Surface.frame_texture frame));
            get (Surface.discard surface frame);
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
      expect Ogpu.Error.Stale_handle (Surface.frame_texture stale);
      expect Ogpu.Error.Stale_handle (Surface.discard surface stale);
      (match get (Surface.acquire surface) with
       | Acquired frame ->
           let descriptor = Metal.Texture.descriptor (get (Surface.frame_texture frame)) in
           if descriptor.width <> 8 || descriptor.height <> 8 then failwith "resized drawable extent";
           get (Surface.discard surface frame)
       | _ -> failwith "resized drawable unavailable");
      expect Ogpu.Error.Invalid_state (Device.destroy device);
      Surface.destroy surface;
      if Metal.Metal_layer.destroyed layer then failwith "borrowed layer was destroyed";
      ignore (get_metal (Metal.Release_queue.drain ()));
      let settled = get_metal (Metal.Release_queue.stats ()) in
      if settled.live_handles <> before.live_handles then
        failwith
          (Printf.sprintf "surface handle delta before=%d after=%d"
             before.live_handles settled.live_handles);
      get_metal (Metal.Metal_layer.destroy layer);
      get (Device.destroy device);
      print_endline
        "ogpu_metal surface: transactional configure, typed availability, frames 1..N discard, resize staleness, zero handle delta"
