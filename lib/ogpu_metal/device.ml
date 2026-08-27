type t =
  { metal : Metal.Device.t
  ; handle : Ogpu.Handle.device
  ; capabilities : Ogpu.Capabilities.t
  ; mutable generation : int64
  ; mutable live_buffers : int
  }

let error operation kind message = Error (Ogpu.Error.make operation kind message)

let system_default () =
  let operation = "Ogpu_metal.Device.system_default" in
  match Metal.Device.system_default () with
  | Error value -> Error (Adapter.error ~operation value)
  | Ok metal ->
      (match Metal.Device.info metal with
       | Error value ->
           ignore (Metal.Device.destroy metal);
           Error (Adapter.error ~operation value)
       | Ok info ->
           let source : Adapter.capability_source =
             { max_buffer_size = info.max_buffer_length
             ; ray_tracing = info.raytracing
             ; metal_fx = false
             }
           in
           match Adapter.capabilities source with
           | Error _ as failure -> ignore (Metal.Device.destroy metal); failure
           | Ok capabilities ->
               Ok { metal; handle = Ogpu.Handle.create_device (); capabilities;
                    generation = 1L; live_buffers = 0 })

let id value = Ogpu.Handle.device_id value.handle
let generation value = value.generation
let capabilities value = value.capabilities
let destroyed value = Ogpu.Handle.device_destroyed value.handle

let destroy value =
  let operation = "Ogpu_metal.Device.destroy" in
  if destroyed value then Ok ()
  else if value.live_buffers <> 0 then
    error operation Ogpu.Error.Invalid_state "device still owns live buffers"
  else
    match Metal.Device.destroy value.metal with
    | Error metal -> Error (Adapter.error ~operation metal)
    | Ok () ->
        Ogpu.Handle.destroy_device value.handle;
        value.generation <- Int64.succ value.generation;
        Ok ()

module Private = struct
  let metal value = value.metal
  let handle value = value.handle
  let attach_buffer value = value.live_buffers <- value.live_buffers + 1
  let detach_buffer value = value.live_buffers <- value.live_buffers - 1
end
