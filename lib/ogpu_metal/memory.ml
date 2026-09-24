let error operation kind message = Error (Ogpu.Error.make operation kind message)

type heap =
  { device : Device.t; portable : Ogpu.Memory.heap; metal : Metal.Heap.t;
    descriptor : Ogpu.Memory.descriptor; mutable allocations : allocation list;
    mutable dead : bool }
and allocation =
  { heap : heap; portable : Ogpu.Memory.allocation; metal : Metal.Buffer.t;
    interval : Ogpu.Memory.interval; mutable aliasing : bool; mutable dead : bool }

let metal_options = function
  | Ogpu.Memory.Private -> Metal.Buffer.Private, Metal.Heap.Default_cache
  | Shared | Readback -> Metal.Buffer.Shared, Metal.Heap.Default_cache
  | Upload -> Metal.Buffer.Shared, Metal.Heap.Write_combined

let validate_heap operation device (value:heap) =
  if value.dead then error operation Ogpu.Error.Stale_handle "heap is destroyed"
  else if Device.destroyed device then error operation Ogpu.Error.Stale_handle "device is destroyed"
  else if Device.id device <> Device.id value.device then error operation Ogpu.Error.Cross_device "heap belongs to another device"
  else Ok ()

let validate_allocation operation device (value:allocation) =
  if value.dead then error operation Ogpu.Error.Stale_handle "allocation is freed"
  else if value.aliasing then error operation Ogpu.Error.Invalid_state "allocation is in its alias transition"
  else validate_heap operation device value.heap

let create device descriptor =
  let operation = "Ogpu_metal.Memory.create" in
  if Device.destroyed device then error operation Ogpu.Error.Stale_handle "device is destroyed" else
  match Ogpu.Memory.create ~device:(Device.Private.handle device) descriptor with
  | Error _ as failure -> failure
  | Ok portable ->
      let storage,cpu_cache = metal_options descriptor.Ogpu.Memory.storage in
      let native = Metal.Heap.make_descriptor ~size:descriptor.size ~storage ~cpu_cache
        ~hazard_tracking:Metal.Heap.Untracked ~kind:Metal.Heap.Placement () in
      match Metal.Heap.create ~device:(Device.Private.metal device) native with
      | Error value -> Ogpu.Memory.destroy portable; Error (Adapter.error ~operation value)
      | Ok metal -> Device.Private.attach_resource device;
          Ok {device;portable;metal;descriptor;allocations=[];dead=false}

let create_sparse _ _ =
  error "Ogpu_metal.Memory.create_sparse" Ogpu.Error.Unsupported
    "portable sparse heaps are unavailable on this Metal profile"

let max_i64 a b = if a >= b then a else b

let allocate device heap ~size ~alignment =
  let operation = "Ogpu_metal.Memory.allocate" in
  match validate_heap operation device heap with Error _ as failure -> failure | Ok () ->
  if size <= 0L || size > heap.descriptor.size || alignment <= 0L
     || Int64.logand alignment (Int64.pred alignment) <> 0L
     || alignment < heap.descriptor.alignment
  then error operation Ogpu.Error.Invalid_argument "invalid allocation size or alignment"
  else
  let storage,cpu_cache = metal_options heap.descriptor.storage in
  match Metal.Heap.buffer_size_and_align ~device:(Device.Private.metal device) ~length:size
    ~storage ~cpu_cache ~hazard_tracking:Metal.Heap.Untracked () with
  | Error value -> Error (Adapter.error ~operation value)
  | Ok layout ->
      let effective_alignment = max_i64 alignment layout.alignment in
      match Ogpu.Memory.allocate ~device:(Device.Private.handle device) heap.portable
        ~size:layout.size ~alignment:effective_alignment with
      | Error _ as failure -> failure
      | Ok portable ->
          let interval = Ogpu.Memory.allocation_interval portable in
          match Metal.Heap.create_buffer heap.metal ~offset:interval.offset ~length:size () with
          | Error value -> ignore (Ogpu.Memory.free portable); Error (Adapter.error ~operation value)
          | Ok metal ->
              let allocation = {heap;portable;metal;interval;aliasing=false;dead=false} in
              heap.allocations <- allocation :: heap.allocations; Ok allocation

let interval (value:allocation) = value.interval

let with_map operation device (value:allocation) ~access ~offset ~length action =
  match validate_allocation operation device value with Error _ as failure -> failure | Ok () ->
  match Ogpu.Memory.map_range value.portable ~access ~offset ~length:(Int64.of_int length) with
  | Error _ as failure -> failure
  | Ok mapped -> Fun.protect ~finally:(fun () -> if Ogpu.Memory.mapped_active mapped then ignore (Ogpu.Memory.unmap mapped)) action

let write_bytes device value ~offset bytes =
  let operation = "Ogpu_metal.Memory.write_bytes" in
  with_map operation device value ~access:Ogpu.Memory.Write ~offset ~length:(Bytes.length bytes) (fun () ->
    match Metal.Buffer.write_bytes value.metal ~dst_offset:offset bytes with
    | Ok () -> Ok () | Error metal -> Error (Adapter.error ~operation metal))

let read_bytes device value ~offset ~length =
  let operation = "Ogpu_metal.Memory.read_bytes" in
  with_map operation device value ~access:Ogpu.Memory.Read ~offset ~length (fun () ->
    match Metal.Buffer.read_bytes value.metal ~offset ~length with
    | Ok bytes -> Ok bytes | Error metal -> Error (Adapter.error ~operation metal))

let begin_alias device (value:allocation) =
  let operation = "Ogpu_metal.Memory.begin_alias" in
  match validate_allocation operation device value with Error _ as failure -> failure | Ok () ->
  match Metal.Buffer.make_aliasable value.metal with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok () -> (match Ogpu.Memory.begin_alias value.portable with
      | Ok () -> value.aliasing <- true; Ok ()
      | Error _ as failure -> failure)

let end_alias device (value:allocation) =
  let operation = "Ogpu_metal.Memory.end_alias" in
  if value.dead then error operation Ogpu.Error.Stale_handle "allocation is freed"
  else if Device.id device <> Device.id value.heap.device then error operation Ogpu.Error.Cross_device "allocation belongs to another device"
  else match Ogpu.Memory.end_alias value.portable with
  | Error _ as failure -> failure
  | Ok () -> value.aliasing <- false; Ok ()

let free (value:allocation) =
  let operation = "Ogpu_metal.Memory.free" in
  if value.dead then error operation Ogpu.Error.Stale_handle "allocation is already freed"
  else if value.aliasing then error operation Ogpu.Error.Invalid_state "end aliasing before freeing the allocation"
  else match Metal.Buffer.destroy value.metal with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok () -> (match Ogpu.Memory.free value.portable with
      | Error _ as failure -> failure
      | Ok () -> value.dead <- true;
          value.heap.allocations <- List.filter ((!=) value) value.heap.allocations; Ok ())

let live_allocations (value:heap) = List.length value.allocations
let destroyed (value:heap) = value.dead

let destroy (value:heap) =
  let operation = "Ogpu_metal.Memory.destroy" in
  if value.dead then Ok ()
  else if value.allocations <> [] then error operation Ogpu.Error.Invalid_state "heap still owns live allocations"
  else match Metal.Heap.destroy value.metal with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok () -> Ogpu.Memory.destroy value.portable; value.dead <- true;
      Device.Private.detach_resource value.device; Ok ()
