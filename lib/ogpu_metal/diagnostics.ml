type t = { portable:Ogpu_core.Diagnostics.t }

let create device ~capacity =
  if capacity <= 0 then Error (Ogpu_core.Error.make "Ogpu_metal.Diagnostics.create" Ogpu_core.Error.Invalid_argument "capacity must be positive")
  else Result.map (fun portable->{portable})
    (Ogpu_core.Diagnostics.create ~device:(Device.Private.handle device) ~message_capacity:capacity
       ~trace_capacity:capacity ~max_label_length:256 ~max_message_length:4096)

let classify_metal_error ~operation value = Device.of_metal_error ~operation value

let category = function
  | Ogpu_core.Error.Device_lost -> Ogpu_core.Diagnostics.Submission
  | Stale_handle | Cross_device -> Resource
  | Invalid_argument | Invalid_state | Unsupported | No_adapter | Capacity -> Validation

let add_error value ?label error =
  Ogpu_core.Diagnostics.add_message value.portable ~severity:Ogpu_core.Diagnostics.Error
    ~category:(category error.Ogpu_core.Error.kind) ?label error.message

let messages value = Ogpu_core.Diagnostics.messages value.portable
let dropped value = Ogpu_core.Diagnostics.dropped_messages value.portable

let destroy value = Ogpu_core.Diagnostics.destroy value.portable
