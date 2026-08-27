open Ogpu_metal

let get = function Ok value -> value | Error error -> failwith (Ogpu.Error.to_string error)
let get_metal = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
let expect kind = function Error error when error.Ogpu.Error.kind = kind -> () | _ -> failwith "wrong rejection"

let descriptor ?(size = 64L) usage : Ogpu.Types.buffer_descriptor =
  { label = Some "ogpu-metal-foundation"; size; usage }

let () =
  let unsupported = get (Adapter.capabilities
    { max_buffer_size = 1_024L; ray_tracing = false; metal_fx = false }) in
  if unsupported.ray_tracing || unsupported.metal_fx then failwith "unsupported profile drift";
  expect Ogpu.Error.Invalid_argument (Adapter.capabilities
    { max_buffer_size = 0L; ray_tracing = false; metal_fx = false });
  match Device.system_default () with
  | Error _ -> print_endline "ogpu_metal foundation: skipped (no Metal device)"
  | Ok device ->
      let other = get (Device.system_default ()) in
      let before = get_metal (Metal.Release_queue.stats ()) in
      expect Ogpu.Error.Invalid_argument
        (Buffer.create device ~memory:Buffer.Shared (descriptor ~size:0L [Ogpu.Types.Copy_src]));
      let values =
        [ Buffer.Device_local, [Ogpu.Types.Storage]
        ; Buffer.Shared, [Ogpu.Types.Uniform]
        ; Buffer.Upload, [Ogpu.Types.Copy_src]
        ; Buffer.Readback, [Ogpu.Types.Copy_dst] ]
        |> List.map (fun (memory, usage) -> get (Buffer.create device ~memory (descriptor usage)))
      in
      expect Ogpu.Error.Invalid_argument
        (Buffer.create device ~memory:Buffer.Readback (descriptor [Ogpu.Types.Uniform]));
      List.iter (fun value ->
        if Buffer.device_id value <> Device.id device then failwith "device identity drift";
        ignore (get (Buffer.descriptor device value));
        ignore (get (Buffer.memory device value))) values;
      expect Ogpu.Error.Cross_device (Buffer.descriptor other (List.hd values));
      expect Ogpu.Error.Invalid_state (Device.destroy device);
      List.iter (fun value ->
        let generation = Buffer.generation value in
        get (Buffer.destroy value);
        if Buffer.generation value <> Int64.succ generation then
          failwith "destroy did not advance buffer generation") values;
      List.iter (fun value -> expect Ogpu.Error.Stale_handle (Buffer.descriptor device value)) values;
      let device_generation = Device.generation device in
      get (Device.destroy device);
      if Device.generation device <> Int64.succ device_generation then
        failwith "destroy did not advance device generation";
      get (Device.destroy other);
      ignore (get_metal (Metal.Release_queue.drain ()));
      let after = get_metal (Metal.Release_queue.stats ()) in
      if after.live_handles <> before.live_handles - 2 then failwith "Metal live-handle delta";
      Printf.printf "ogpu_metal foundation: four memory classes, zero live-handle delta\n%!"
