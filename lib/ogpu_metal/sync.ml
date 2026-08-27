let error operation kind message = Error (Ogpu.Error.make operation kind message)

type fence =
  { device : Device.t; portable : Ogpu.Sync.fence; metal : Metal.Fence.t;
    mutable dead : bool }

type event =
  { device : Device.t; portable : Ogpu.Sync.event; metal : Metal.Shared_event.t;
    mutable dead : bool }

type query_set =
  { device : Device.t; portable : Ogpu.Sync.query_set; kind : Ogpu.Sync.query_kind;
    count : int; descriptor : Metal.Counters.Descriptor.t option;
    samples : Metal.Resource100.Sample_buffer.t option; mutable dead : bool }

let validate_device operation device owner dead =
  if dead then error operation Ogpu.Error.Stale_handle "synchronization object is destroyed"
  else if Device.destroyed device then error operation Ogpu.Error.Stale_handle "device is destroyed"
  else if Device.id device <> Device.id owner then error operation Ogpu.Error.Cross_device "object belongs to another device"
  else Ok ()

let create_fence device ~initial =
  let operation = "Ogpu_metal.Sync.create_fence" in
  if initial < 0L then error operation Ogpu.Error.Invalid_argument "initial value must be nonnegative"
  else match Ogpu.Sync.create_fence (Device.Private.handle device) ~initial with
  | Error _ as failure -> failure
  | Ok portable -> (match Metal.Device.new_fence (Device.Private.metal device) with
      | Error value -> Ogpu.Sync.destroy_fence portable; Error (Adapter.error ~operation value)
      | Ok metal -> Device.Private.attach_resource device;
          Ok ({device; portable; metal; dead=false} : fence))

let unsupported_fence operation device (value:fence) =
  match validate_device operation device value.device value.dead with
  | Error _ as failure -> failure
  | Ok () -> error operation Ogpu.Error.Unsupported
      "portable timeline fence operations require an active Metal encoder"

let signal_fence device value _ = unsupported_fence "Ogpu_metal.Sync.signal_fence" device value
let wait_fence device value _ = unsupported_fence "Ogpu_metal.Sync.wait_fence" device value

let destroy_fence (value:fence) =
  if value.dead then Ok () else match Metal.Fence.destroy value.metal with
  | Error metal -> Error (Adapter.error ~operation:"Ogpu_metal.Sync.destroy_fence" metal)
  | Ok () -> value.dead <- true; Ogpu.Sync.destroy_fence value.portable;
      Device.Private.detach_resource value.device; Ok ()

let create_event device ~initial =
  let operation = "Ogpu_metal.Sync.create_event" in
  if initial < 0L then error operation Ogpu.Error.Invalid_argument "initial value must be nonnegative"
  else match Ogpu.Sync.create_event (Device.Private.handle device) ~initial with
  | Error _ as failure -> failure
  | Ok portable -> (match Metal.Device.new_shared_event (Device.Private.metal device) with
      | Error value -> Ogpu.Sync.destroy_event portable; Error (Adapter.error ~operation value)
      | Ok metal -> (match Metal.Shared_event.set_signaled_value metal initial with
          | Error value -> ignore (Metal.Shared_event.destroy metal); Ogpu.Sync.destroy_event portable;
              Error (Adapter.error ~operation value)
          | Ok () -> Device.Private.attach_resource device;
              Ok ({device; portable; metal; dead=false} : event)))

let signal_event device (value:event) next =
  let operation = "Ogpu_metal.Sync.signal_event" in
  match validate_device operation device value.device value.dead with Error _ as failure -> failure | Ok () ->
  if next <= Ogpu.Sync.event_value value.portable then
    error operation Ogpu.Error.Invalid_argument "event values must increase"
  else match Metal.Shared_event.set_signaled_value value.metal next with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok () -> Ogpu.Sync.signal_event (Device.Private.handle device) value.portable next

let wait_event device (value:event) target =
  let operation = "Ogpu_metal.Sync.wait_event" in
  match validate_device operation device value.device value.dead with Error _ as failure -> failure | Ok () ->
  match Metal.Shared_event.signaled_value value.metal with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok current when current < target -> error operation Ogpu.Error.Unsupported
      "nonblocking event wait has not yet reached the requested value"
  | Ok _ -> Ogpu.Sync.wait_event (Device.Private.handle device) value.portable target

let destroy_event (value:event) =
  if value.dead then Ok () else match Metal.Shared_event.destroy value.metal with
  | Error metal -> Error (Adapter.error ~operation:"Ogpu_metal.Sync.destroy_event" metal)
  | Ok () -> value.dead <- true; Ogpu.Sync.destroy_event value.portable;
      Device.Private.detach_resource value.device; Ok ()

let create_query_set device ~kind ~count =
  let operation = "Ogpu_metal.Sync.create_query_set" in
  if count <= 0 then error operation Ogpu.Error.Invalid_argument "query count must be positive" else
  let supported = match kind with
    | Ogpu.Sync.Counter -> false
    | Timestamp -> (match Metal.Counters.supports (Device.Private.metal device) Metal.Counters.Blit_boundary with Ok value -> value | Error _ -> false)
  in
  match Ogpu.Sync.create_query_set (Device.Private.handle device) ~supported ~kind ~count with
  | Error _ as failure -> failure
  | Ok portable ->
      match Metal.Counters.sets (Device.Private.metal device) with
      | Error value -> Ogpu.Sync.destroy_query_set portable; Error (Adapter.error ~operation value)
      | Ok [] -> Ogpu.Sync.destroy_query_set portable; error operation Ogpu.Error.Unsupported "no Metal counter set is available"
      | Ok (set::_) -> (match Metal.Counters.Descriptor.create (Device.Private.metal device)
          ~set_name:set.name ~sample_count:(Int64.of_int count) ~storage:Metal.Buffer.Shared () with
        | Error value -> Ogpu.Sync.destroy_query_set portable; Error (Adapter.error ~operation value)
        | Ok descriptor -> match Metal.Counters.Descriptor.create_buffer descriptor with
          | Error value -> ignore (Metal.Counters.Descriptor.destroy descriptor); Ogpu.Sync.destroy_query_set portable;
              Error (Adapter.error ~operation value)
          | Ok samples -> Device.Private.attach_resource device;
              Ok ({device;portable;kind;count;descriptor=Some descriptor;samples=Some samples;dead=false} : query_set))

let query_supported (value:query_set) = value.samples <> None

let execute_query_pass device (value:query_set) ~first ~count ~destination ~destination_offset ~completion_epoch =
  let operation = "Ogpu_metal.Sync.execute_query_pass" in
  match validate_device operation device value.device value.dead with Error _ as failure -> failure | Ok () ->
  match Buffer.descriptor device destination with Error _ as failure -> failure | Ok destination_descriptor ->
  if value.kind <> Ogpu.Sync.Timestamp then error operation Ogpu.Error.Unsupported "only timestamp queries map to Metal counters"
  else if first < 0 || count <= 0 || first > value.count || count > value.count - first then
    error operation Ogpu.Error.Invalid_argument "query range is out of bounds"
  else
  match value.samples with None -> error operation Ogpu.Error.Unsupported "Metal timestamp queries are unavailable" | Some samples ->
  let portable_command = Ogpu.Command.begin_encoder () in
  match Ogpu.Command.begin_pass portable_command Ogpu.Command.Transfer with Error _ as failure -> failure | Ok () ->
  match Ogpu.Command.end_pass portable_command with Error _ as failure -> failure | Ok () ->
  match Ogpu.Command.end_encoder portable_command with Error _ as failure -> failure | Ok () ->
  let descriptor : Ogpu.Query_pass.descriptor = {pass=Ogpu.Command.Transfer;queries=value.portable;first;count;
    destination=Buffer.Private.resource_handle destination;destination_resource_id=Buffer.id destination;
    destination_size=destination_descriptor.size;destination_offset;completion_epoch} in
  match Ogpu.Query_pass.create (Device.Private.handle device) ~timestamp_queries:true descriptor with Error _ as failure -> failure | Ok pass ->
  match Metal.Command_queue.create (Device.Private.metal device) with Error metal -> Error (Adapter.error ~operation metal) | Ok queue ->
  let finish result = ignore (Metal.Command_queue.destroy queue); result in
  match Metal.Command_buffer.create queue () with Error metal -> finish (Error (Adapter.error ~operation metal)) | Ok command ->
  let finish_command result = ignore (Metal.Command_buffer.destroy command); finish result in
  match Metal.Blit_encoder.create command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok encoder ->
  let rec sample index = if index = first + count then Ok () else
    match Metal.Resource100.Sample_buffer.sample encoder samples ~index:(Int64.of_int index) with Error value -> Error value | Ok () -> sample (index+1) in
  (match sample first with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
   match Metal.Blit_encoder.end_encoding encoder with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
   match Metal.Command_buffer.commit command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
   match Metal.Command_buffer.wait_until_completed command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
   match Metal.Counters.resolve samples ~first:(Int64.of_int first) ~count:(Int64.of_int count) with
   | Error metal -> finish_command (Error (Adapter.error ~operation metal))
   | Ok bytes -> match Buffer.write_bytes device destination ~dst_offset:destination_offset bytes with
     | Error _ as failure -> finish_command failure | Ok () -> finish_command (Ok (Ogpu.Query_pass.describe pass)))

let destroy_query_set (value:query_set) =
  if value.dead then Ok () else
  let sample_result = match value.samples with None -> Ok () | Some samples -> Metal.Resource100.Sample_buffer.destroy samples in
  match sample_result with Error metal -> Error (Adapter.error ~operation:"Ogpu_metal.Sync.destroy_query_set" metal) | Ok () ->
  let descriptor_result = match value.descriptor with None -> Ok () | Some descriptor -> Metal.Counters.Descriptor.destroy descriptor in
  match descriptor_result with Error metal -> Error (Adapter.error ~operation:"Ogpu_metal.Sync.destroy_query_set" metal) | Ok () ->
  value.dead <- true; Ogpu.Sync.destroy_query_set value.portable;
  if value.samples <> None then Device.Private.detach_resource value.device; Ok ()
