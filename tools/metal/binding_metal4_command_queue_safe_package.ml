type resource = { token : int; device : int; destroyed : bool }
type buffer = { resource : resource; length : int }
type texture = { resource : resource; width : int; height : int; levels : int; slices : int }
type buffer_copy = { source_offset : int; length : int; destination_offset : int }
type texture_copy = { source_level : int; source_slice : int; x : int; y : int; width : int; height : int; destination_level : int; destination_slice : int }
type queue = { device : int; mutable residency : resource list; mutable pending : resource list; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTL4CommandQueue addResidencySet:]"
  ; "method:-[MTL4CommandQueue copyBufferMappingsFromBuffer:toBuffer:operations:count:]"
  ; "method:-[MTL4CommandQueue copyTextureMappingsFromTexture:toTexture:operations:count:]"
  ; "method:-[MTL4CommandQueue signalDrawable:]"
  ; "method:-[MTL4CommandQueue waitForDrawable:]"
  ; "method:-[MTL4CommandQueue waitForEvent:value:]" ]

let create ~available ~device =
  if not available then Error "MTL4 command queues require macOS 26"
  else Ok { device; residency = []; pending = []; destroyed = false }

let validate_resource (queue : queue) (resource : resource) =
  if queue.destroyed then Error "destroyed MTL4 command queue"
  else if resource.destroyed then Error "destroyed MTL4 queue resource"
  else if resource.device <> queue.device then Error "MTL4 queue resource belongs to another device"
  else Ok ()

let retain_pending queue resources = queue.pending <- resources @ queue.pending

let add_residency_set queue resource =
  Result.map (fun () ->
    if not (List.exists (fun item -> item.token = resource.token) queue.residency) then
      queue.residency <- resource :: queue.residency)
    (validate_resource queue resource)

let copy_buffer_mappings queue ~(source : buffer) ~(destination : buffer) (operations : buffer_copy list) =
  match validate_resource queue source.resource, validate_resource queue destination.resource with
  | Error error, _ | _, Error error -> Error error
  | Ok (), Ok () ->
      if operations = [] then Error "sparse buffer mapping copy requires operations"
      else if List.exists (fun operation -> operation.source_offset < 0 || operation.destination_offset < 0
        || operation.length <= 0 || operation.source_offset > source.length
        || operation.destination_offset > destination.length
        || operation.length > source.length - operation.source_offset
        || operation.length > destination.length - operation.destination_offset) operations
      then Error "sparse buffer mapping range out of bounds"
      else begin retain_pending queue [ source.resource; destination.resource ]; Ok () end

let mip_extent size level = max 1 (size lsr level)

let copy_texture_mappings queue ~(source : texture) ~(destination : texture) (operations : texture_copy list) =
  match validate_resource queue source.resource, validate_resource queue destination.resource with
  | Error error, _ | _, Error error -> Error error
  | Ok (), Ok () ->
      let invalid operation =
        operation.source_level < 0 || operation.source_level >= source.levels
        || operation.destination_level < 0 || operation.destination_level >= destination.levels
        || operation.source_slice < 0 || operation.source_slice >= source.slices
        || operation.destination_slice < 0 || operation.destination_slice >= destination.slices
        || operation.x < 0 || operation.y < 0 || operation.width <= 0 || operation.height <= 0
        || operation.width > mip_extent source.width operation.source_level - operation.x
        || operation.height > mip_extent source.height operation.source_level - operation.y
        || operation.width > mip_extent destination.width operation.destination_level
        || operation.height > mip_extent destination.height operation.destination_level
      in
      if operations = [] then Error "sparse texture mapping copy requires operations"
      else if List.exists invalid operations then Error "sparse texture mapping range out of bounds"
      else begin retain_pending queue [ source.resource; destination.resource ]; Ok () end

let sync queue resource = Result.map (fun () -> retain_pending queue [ resource ]) (validate_resource queue resource)
let signal_drawable = sync
let wait_for_drawable = sync

let wait_for_event queue resource ~value:_ = sync queue resource

let retained_tokens queue =
  List.map (fun (resource : resource) -> resource.token) (queue.residency @ queue.pending)

let complete queue = queue.pending <- []
let destroy queue = if not queue.destroyed then begin queue.destroyed <- true; queue.pending <- []; queue.residency <- [] end

let validate_handoff () =
  if List.length callable_ids <> 6 || List.length (List.sort_uniq String.compare callable_ids) <> 6 then
    invalid_arg "MTL4CommandQueue callable6 drift"
