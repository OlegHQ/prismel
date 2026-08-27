type memory = Device_local | Shared | Upload | Readback
type t =
  { metal : Metal.Buffer.t
  ; handle : unit Ogpu.Handle.t
  ; device : Device.t
  ; descriptor : Ogpu.Types.buffer_descriptor
  ; memory : memory
  }

let validate_memory (descriptor : Ogpu.Types.buffer_descriptor) memory =
  let operation = "Ogpu_metal.Buffer.create" in
  match memory with
  | Device_local | Shared | Upload -> Ok ()
  | Readback ->
      if List.mem Ogpu.Types.Copy_dst descriptor.Ogpu.Types.usage then Ok ()
      else Error (Ogpu.Error.make operation Ogpu.Error.Invalid_argument
        "readback buffers require Copy_dst usage")

let create device ~memory descriptor =
  let operation = "Ogpu_metal.Buffer.create" in
  if Device.destroyed device then
    Error (Ogpu.Error.make operation Ogpu.Error.Stale_handle "device is destroyed")
  else
    match Ogpu.Types.validate_buffer (Device.capabilities device) descriptor with
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
            | Error metal -> Error (Adapter.error ~operation metal)
            | Ok metal ->
                let value = { metal; handle = Ogpu.Handle.create ~device:(Device.Private.handle device);
                  device; descriptor; memory } in
                Device.Private.attach_resource device;
                Ok value

let id value = Ogpu.Handle.id value.handle
let generation value = Ogpu.Handle.generation value.handle
let device_id value = Device.id value.device
let destroyed value = Ogpu.Handle.destroyed value.handle

let validate operation device value =
  Ogpu.Handle.validate_for ~operation (Device.Private.handle device) value.handle

let descriptor device value =
  Result.map (fun () -> value.descriptor)
    (validate "Ogpu_metal.Buffer.descriptor" device value)

let memory device value =
  Result.map (fun () -> value.memory)
    (validate "Ogpu_metal.Buffer.memory" device value)

let write_bytes device value ~dst_offset bytes =
  let operation="Ogpu_metal.Buffer.write_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  match Metal.Buffer.write_bytes value.metal~dst_offset bytes with Ok()->Ok()|Error e->Error(Adapter.error~operation e)

let read_bytes device value ~offset ~length =
  let operation="Ogpu_metal.Buffer.read_bytes"in match validate operation device value with Error _ as e->e|Ok()->
  match Metal.Buffer.read_bytes value.metal~offset~length with Ok x->Ok x|Error e->Error(Adapter.error~operation e)

let destroy value =
  let operation = "Ogpu_metal.Buffer.destroy" in
  if destroyed value then Ok ()
  else
    match Metal.Buffer.destroy value.metal with
    | Error metal -> Error (Adapter.error ~operation metal)
    | Ok () ->
        Ogpu.Handle.destroy value.handle;
        Device.Private.detach_resource value.device;
        Ok ()

module Private = struct
  let metal value=value.metal
  let resource_handle value=value.handle
end
