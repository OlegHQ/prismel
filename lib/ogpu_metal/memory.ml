let error operation kind message = Error (Ogpu_core.Error.make operation kind message)

type heap =
  { device : Device.t; portable : Ogpu_core.Memory.heap; metal : Metal.Heap.t;
    descriptor : Ogpu_core.Memory.descriptor; mutable allocations : allocation list;
    mutable dead : bool }
and allocation =
  { heap : heap; portable : Ogpu_core.Memory.allocation; metal : Metal.Buffer.t;
    interval : Ogpu_core.Memory.interval; mutable aliasing : bool; mutable dead : bool }

let metal_options = function
  | Ogpu_core.Memory.Private -> Metal.Buffer.Private, Metal.Heap.Default_cache
  | Shared | Readback -> Metal.Buffer.Shared, Metal.Heap.Default_cache
  | Upload -> Metal.Buffer.Shared, Metal.Heap.Write_combined

let validate_heap operation device (value:heap) =
  if value.dead then error operation Ogpu_core.Error.Stale_handle "heap is destroyed"
  else if Device.destroyed device then error operation Ogpu_core.Error.Stale_handle "device is destroyed"
  else if Device.id device <> Device.id value.device then error operation Ogpu_core.Error.Cross_device "heap belongs to another device"
  else Ok ()

let validate_allocation operation device (value:allocation) =
  if value.dead then error operation Ogpu_core.Error.Stale_handle "allocation is freed"
  else if value.aliasing then error operation Ogpu_core.Error.Invalid_state "allocation is in its alias transition"
  else validate_heap operation device value.heap

let create device descriptor =
  let operation = "Ogpu_metal.Memory.create" in
  if Device.destroyed device then error operation Ogpu_core.Error.Stale_handle "device is destroyed" else
  match Ogpu_core.Memory.create ~device:(Device.Private.handle device) descriptor with
  | Error _ as failure -> failure
  | Ok portable ->
      let storage,cpu_cache = metal_options descriptor.Ogpu_core.Memory.storage in
      let native = Metal.Heap.make_descriptor ~size:descriptor.size ~storage ~cpu_cache
        ~hazard_tracking:Metal.Heap.Untracked ~kind:Metal.Heap.Placement () in
      match Metal.Heap.create ~device:(Device.Private.metal device) native with
      | Error value -> Ogpu_core.Memory.destroy portable; Error (Device.of_metal_error ~operation value)
      | Ok metal -> Device.Private.attach_resource device;
          Ok {device;portable;metal;descriptor;allocations=[];dead=false}

let create_sparse _ _ =
  error "Ogpu_metal.Memory.create_sparse" Ogpu_core.Error.Unsupported
    "portable sparse heaps are unavailable on this Metal profile"

let max_i64 a b = if a >= b then a else b

let allocate device heap ~size ~alignment =
  let operation = "Ogpu_metal.Memory.allocate" in
  match validate_heap operation device heap with Error _ as failure -> failure | Ok () ->
  if size <= 0L || size > heap.descriptor.size || alignment <= 0L
     || Int64.logand alignment (Int64.pred alignment) <> 0L
     || alignment < heap.descriptor.alignment
  then error operation Ogpu_core.Error.Invalid_argument "invalid allocation size or alignment"
  else
  let storage,cpu_cache = metal_options heap.descriptor.storage in
  match Metal.Heap.buffer_size_and_align ~device:(Device.Private.metal device) ~length:size
    ~storage ~cpu_cache ~hazard_tracking:Metal.Heap.Untracked () with
  | Error value -> Error (Device.of_metal_error ~operation value)
  | Ok layout ->
      let effective_alignment = max_i64 alignment layout.alignment in
      match Ogpu_core.Memory.allocate ~device:(Device.Private.handle device) heap.portable
        ~size:layout.size ~alignment:effective_alignment with
      | Error _ as failure -> failure
      | Ok portable ->
          let interval = Ogpu_core.Memory.allocation_interval portable in
          match Metal.Heap.create_buffer heap.metal ~offset:interval.offset ~length:size () with
          | Error value -> ignore (Ogpu_core.Memory.free portable); Error (Device.of_metal_error ~operation value)
          | Ok metal ->
              let allocation = {heap;portable;metal;interval;aliasing=false;dead=false} in
              heap.allocations <- allocation :: heap.allocations; Ok allocation

let interval (value:allocation) = value.interval

let with_map operation device (value:allocation) ~access ~offset ~length action =
  match validate_allocation operation device value with Error _ as failure -> failure | Ok () ->
  match Ogpu_core.Memory.map_range value.portable ~access ~offset ~length:(Int64.of_int length) with
  | Error _ as failure -> failure
  | Ok mapped -> Fun.protect ~finally:(fun () -> if Ogpu_core.Memory.mapped_active mapped then ignore (Ogpu_core.Memory.unmap mapped)) action

let write_bytes device value ~offset bytes =
  let operation = "Ogpu_metal.Memory.write_bytes" in
  with_map operation device value ~access:Ogpu_core.Memory.Write ~offset ~length:(Bytes.length bytes) (fun () ->
    match Metal.Buffer.write_bytes value.metal ~dst_offset:offset bytes with
    | Ok () -> Ok () | Error metal -> Error (Device.of_metal_error ~operation metal))

let read_bytes device value ~offset ~length =
  let operation = "Ogpu_metal.Memory.read_bytes" in
  with_map operation device value ~access:Ogpu_core.Memory.Read ~offset ~length (fun () ->
    match Metal.Buffer.read_bytes value.metal ~offset ~length with
    | Ok bytes -> Ok bytes | Error metal -> Error (Device.of_metal_error ~operation metal))

let begin_alias device (value:allocation) =
  let operation = "Ogpu_metal.Memory.begin_alias" in
  match validate_allocation operation device value with Error _ as failure -> failure | Ok () ->
  match Metal.Buffer.make_aliasable value.metal with
  | Error metal -> Error (Device.of_metal_error ~operation metal)
  | Ok () -> (match Ogpu_core.Memory.begin_alias value.portable with
      | Ok () -> value.aliasing <- true; Ok ()
      | Error _ as failure -> failure)

let end_alias device (value:allocation) =
  let operation = "Ogpu_metal.Memory.end_alias" in
  if value.dead then error operation Ogpu_core.Error.Stale_handle "allocation is freed"
  else if Device.id device <> Device.id value.heap.device then error operation Ogpu_core.Error.Cross_device "allocation belongs to another device"
  else match Ogpu_core.Memory.end_alias value.portable with
  | Error _ as failure -> failure
  | Ok () -> value.aliasing <- false; Ok ()

let free (value:allocation) =
  let operation = "Ogpu_metal.Memory.free" in
  if value.dead then error operation Ogpu_core.Error.Stale_handle "allocation is already freed"
  else if value.aliasing then error operation Ogpu_core.Error.Invalid_state "end aliasing before freeing the allocation"
  else match Metal.Buffer.destroy value.metal with
  | Error metal -> Error (Device.of_metal_error ~operation metal)
  | Ok () -> (match Ogpu_core.Memory.free value.portable with
      | Error _ as failure -> failure
      | Ok () -> value.dead <- true;
          value.heap.allocations <- List.filter ((!=) value) value.heap.allocations; Ok ())

let live_allocations (value:heap) = List.length value.allocations

let destroy (value:heap) =
  let operation = "Ogpu_metal.Memory.destroy" in
  if value.dead then Ok ()
  else if value.allocations <> [] then error operation Ogpu_core.Error.Invalid_state "heap still owns live allocations"
  else match Metal.Heap.destroy value.metal with
  | Error metal -> Error (Device.of_metal_error ~operation metal)
  | Ok () -> Ogpu_core.Memory.destroy value.portable; value.dead <- true;
      Device.Private.detach_resource value.device; Ok ()
