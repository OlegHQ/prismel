type memory = Device_local | Shared | Upload | Readback
type t =
  { metal : Metal.Buffer.t
  ; handle : unit Ogpu_core.Handle.t
  ; device : Device.t
  ; descriptor : Ogpu_core.Types.buffer_descriptor
  ; memory : memory
  ; mutable submission_uses : int
  ; mutable destroy_requested : bool
  }

let validate_memory (descriptor : Ogpu_core.Types.buffer_descriptor) memory =
  let operation = "Ogpu_metal.Buffer.create" in
  match memory with
  | Device_local | Shared | Upload -> Ok ()
  | Readback ->
      if List.mem Ogpu_core.Types.Copy_dst descriptor.Ogpu_core.Types.usage then Ok ()
      else Error (Ogpu_core.Error.make operation Ogpu_core.Error.Invalid_argument
        "readback buffers require Copy_dst usage")

let create device ~memory descriptor =
  let operation = "Ogpu_metal.Buffer.create" in
  if Device.destroyed device then
    Error (Ogpu_core.Error.make operation Ogpu_core.Error.Stale_handle "device is destroyed")
  else
    match Ogpu_core.Types.validate_buffer (Device.capabilities device) descriptor with
    | Error _ as failure -> failure
    | Ok () ->
        match validate_memory descriptor memory with
        | Error _ as failure -> failure
        | Ok () ->
            let storage, cpu_cache =
              match memory with
              | Device_local -> Metal.Buffer.Private, Metal.Buffer.Default_cache
              | Shared | Readback -> Metal.Buffer.Shared, Metal.Buffer.Default_cache
              | Upload -> Metal.Buffer.Shared, Metal.Buffer.Write_combined
            in
            match Metal.Buffer.create ~device:(Device.Private.metal device)
                    ~length:descriptor.size ~storage ~cpu_cache ?label:descriptor.label () with
            | Error metal -> Error (Device.of_metal_error ~operation metal)
            | Ok metal ->
                let value = { metal; handle = Ogpu_core.Handle.create ~device:(Device.Private.handle device);
                  device; descriptor; memory;submission_uses=0;destroy_requested=false } in
                Device.Private.attach_resource device;
                Ok value

let id value = Ogpu_core.Handle.id value.handle
let generation value = Ogpu_core.Handle.generation value.handle
let device_id value = Device.id value.device
let destroyed value = Ogpu_core.Handle.destroyed value.handle

let validate operation device value =
  Ogpu_core.Handle.validate_for ~operation (Device.Private.handle device) value.handle

let descriptor device value =
  Result.map (fun () -> value.descriptor)
    (validate "Ogpu_metal.Buffer.descriptor" device value)

let memory device value =
  Result.map (fun () -> value.memory)
    (validate "Ogpu_metal.Buffer.memory" device value)

let write_bytes device value ~dst_offset bytes =
  let operation="Ogpu_metal.Buffer.write_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  match Metal.Buffer.write_bytes value.metal~dst_offset bytes with Ok()->Ok()|Error e->Error(Device.of_metal_error~operation e)

let read_bytes device value ~offset ~length =
  let operation="Ogpu_metal.Buffer.read_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  match Metal.Buffer.read_bytes value.metal~offset~length with Ok x->Ok x|Error e->Error(Device.of_metal_error~operation e)

let destroy value =
  let operation = "Ogpu_metal.Buffer.destroy" in
  if destroyed value then Ok ()
  else if value.submission_uses>0 then(Ogpu_core.Handle.destroy value.handle;value.destroy_requested<-true;Ok())
  else
    match Metal.Buffer.destroy value.metal with
    | Error metal -> Error (Device.of_metal_error ~operation metal)
    | Ok () ->
        Ogpu_core.Handle.destroy value.handle;
        Device.Private.detach_resource value.device;
        Ok ()

module Private = struct
  let metal value=value.metal
  let resource_handle value=value.handle
  let retain_submission value=if destroyed value then Error(Ogpu_core.Error.make"Ogpu_metal.Buffer.retain_submission"Ogpu_core.Error.Stale_handle"buffer is destroyed")else(value.submission_uses<-value.submission_uses+1;Ok())
  let release_submission value=value.submission_uses<-value.submission_uses-1;if value.submission_uses=0&&value.destroy_requested then(match Metal.Buffer.destroy value.metal with Ok()->Device.Private.detach_resource value.device|Error _->())
end
