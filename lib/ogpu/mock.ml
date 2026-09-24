type profile = M1 | M3_plus | Missing_ray_tracing | Missing_metal_fx | Future_unknown
type operation = Create_queue | Create_buffer | Create_texture
type capacities = { queues : int; buffers : int; textures : int }

type device =
  { handle : Handle.device
  ; capabilities : Capabilities.t
  ; capacities : capacities
  ; mutable next_id : int64
  ; mutable queues : int
  ; mutable buffers : int
  ; mutable textures : int
  ; mutable fault : operation option
  }

type queue_kind
type buffer_kind
type texture_kind
type queue = { id : int64; owner : device; handle : queue_kind Handle.t; mutable counted : bool }
type buffer =
  { id : int64; owner : device; handle : buffer_kind Handle.t
  ; descriptor : Types.buffer_descriptor; mutable counted : bool }
type texture =
  { id : int64; owner : device; handle : texture_kind Handle.t
  ; descriptor : Types.texture_descriptor; mutable counted : bool }

let error operation kind message = Error (Error.make operation kind message)

let capabilities_for = function
  | M1 | Missing_ray_tracing -> { Capabilities.minimum_m1 with metal_fx = true }
  | Missing_metal_fx -> { Capabilities.minimum_m1 with ray_tracing = true; metal_fx = false }
  | M3_plus | Future_unknown ->
      { Capabilities.limits =
          { Capabilities.minimum_m1.limits with max_buffer_size = Int64.shift_left 1L 34 }
      ; ray_tracing = true; metal_fx = true }

let create_device ~profile ~(capacities : capacities) =
  if capacities.queues < 0 || capacities.buffers < 0 || capacities.textures < 0 then
    error "Mock.create_device" Error.Invalid_argument "capacities must be nonnegative"
  else
    let capabilities = capabilities_for profile in
    match Capabilities.validate capabilities with
    | Error value -> Error value
    | Ok () ->
        Ok { handle = Handle.create_device (); capabilities; capacities; next_id = 1L
           ; queues = 0; buffers = 0; textures = 0; fault = None }

let device_id (value : device) = Handle.device_id value.handle
let capabilities (value : device) = value.capabilities
let destroy_device (value : device) = Handle.destroy_device value.handle
let inject_fault (value : device) operation = value.fault <- Some operation

let live_device operation (value : device) =
  if Handle.device_destroyed value.handle then
    error operation Error.Stale_handle "device is destroyed"
  else Ok ()

let require_feature operation enabled =
  if enabled then Ok () else error operation Error.Invalid_state "feature is unsupported by this profile"

let require_ray_tracing (value : device) =
  match live_device "Mock.require_ray_tracing" value with
  | Error _ as error -> error
  | Ok () -> require_feature "Mock.require_ray_tracing" value.capabilities.ray_tracing

let require_metal_fx (value : device) =
  match live_device "Mock.require_metal_fx" value with
  | Error _ as error -> error
  | Ok () -> require_feature "Mock.require_metal_fx" value.capabilities.metal_fx

let allocate_id (value : device) = let id = value.next_id in value.next_id <- Int64.succ id; id

let preflight (value : device) name operation count capacity =
  match live_device name value with
  | Error _ as error -> error
  | Ok () when value.fault = Some operation ->
      value.fault <- None;
      error name Error.Invalid_state "injected deterministic failure"
  | Ok () when count >= capacity -> error name Error.Invalid_state "mock capacity exhausted"
  | Ok () -> Ok ()

let create_queue (owner : device) =
  match preflight owner "Mock.create_queue" Create_queue owner.queues owner.capacities.queues with
  | Error _ as error -> error
  | Ok () ->
      let value = { id = allocate_id owner; owner; handle = Handle.create ~device:owner.handle; counted = true } in
      owner.queues <- owner.queues + 1;
      Ok value

let queue_id (value : queue) = value.id
let validate_queue (owner : device) (value : queue) =
  Handle.validate_for ~operation:"Mock.validate_queue" owner.handle value.handle
let destroy_queue (value : queue) =
  if value.counted then begin value.counted <- false; value.owner.queues <- value.owner.queues - 1 end;
  Handle.destroy value.handle

let create_buffer (owner : device) descriptor =
  match Types.validate_buffer owner.capabilities descriptor with
  | Error _ as error -> error
  | Ok () ->
      match preflight owner "Mock.create_buffer" Create_buffer owner.buffers owner.capacities.buffers with
      | Error _ as error -> error
      | Ok () ->
          let value : buffer =
            { id = allocate_id owner; owner; handle = Handle.create ~device:owner.handle
            ; descriptor; counted = true }
          in
          owner.buffers <- owner.buffers + 1;
          Ok value

let buffer_id (value : buffer) = value.id
let buffer_descriptor (owner : device) (value : buffer) =
  match Handle.validate_for ~operation:"Mock.buffer_descriptor" owner.handle value.handle with
  | Error _ as error -> error | Ok () -> Ok value.descriptor
let destroy_buffer (value : buffer) =
  if value.counted then begin value.counted <- false; value.owner.buffers <- value.owner.buffers - 1 end;
  Handle.destroy value.handle

let create_texture (owner : device) descriptor =
  match Types.validate_texture owner.capabilities descriptor with
  | Error _ as error -> error
  | Ok () ->
      match preflight owner "Mock.create_texture" Create_texture owner.textures owner.capacities.textures with
      | Error _ as error -> error
      | Ok () ->
          let value : texture =
            { id = allocate_id owner; owner; handle = Handle.create ~device:owner.handle
            ; descriptor; counted = true }
          in
          owner.textures <- owner.textures + 1;
          Ok value

let texture_id (value : texture) = value.id
let texture_descriptor (owner : device) (value : texture) =
  match Handle.validate_for ~operation:"Mock.texture_descriptor" owner.handle value.handle with
  | Error _ as error -> error | Ok () -> Ok value.descriptor
let destroy_texture (value : texture) =
  if value.counted then begin value.counted <- false; value.owner.textures <- value.owner.textures - 1 end;
  Handle.destroy value.handle

let live_counts (value : device) = value.queues, value.buffers, value.textures
