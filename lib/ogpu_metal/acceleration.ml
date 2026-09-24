let error operation kind message = Error (Ogpu.Error.make operation kind message)

type triangle_plan =
  { offset : int64; length : int64; vertex_stride : int; vertex_count : int }

type t =
  { device : Device.t; portable : Ogpu.Acceleration.t;
    descriptor : Metal.Acceleration_structure.Triangle.t;
    mutable metal : Metal.Acceleration_structure.t;
    sizes : Metal.Acceleration_structure.sizes; allow_refit : bool;
    mutable dead : bool }

let plan_triangle ~ray_tracing ~buffer_size ~offset ~length ~vertex_stride ~vertex_count =
  let operation = "Ogpu_metal.Acceleration.plan_triangle" in
  if buffer_size < 0L || offset < 0L || length <= 0L
     || offset > Int64.sub buffer_size length
     || Int64.rem offset 4L <> 0L || vertex_stride < 12
     || vertex_stride mod 4 <> 0 || vertex_count < 3 || vertex_count mod 3 <> 0
     || Int64.of_int vertex_count > Int64.div length (Int64.of_int vertex_stride)
  then error operation Ogpu.Error.Invalid_argument "triangle buffer range, stride, or cardinality is invalid"
  else if not ray_tracing then error operation Ogpu.Error.Unsupported "ray tracing is unavailable on this adapter"
  else Ok {offset;length;vertex_stride;vertex_count}

let validate operation device value =
  if value.dead then error operation Ogpu.Error.Stale_handle "acceleration structure is destroyed"
  else if Device.destroyed device then error operation Ogpu.Error.Stale_handle "device is destroyed"
  else if Device.id device <> Device.id value.device then error operation Ogpu.Error.Cross_device "acceleration structure belongs to another device"
  else Ok ()

let validate_scratch_plan ~buffer_size ~offset ~required =
  let operation = "Ogpu_metal.Acceleration.validate_scratch_plan" in
  if buffer_size < 0L || offset < 0L || required < 0L
     || Int64.rem offset 256L <> 0L || offset > Int64.sub buffer_size required
  then error operation Ogpu.Error.Invalid_argument "scratch range is invalid or insufficient"
  else Ok ()

let create_triangle device ~vertices ~offset ~length ~vertex_stride ~vertex_count ~allow_refit =
  let operation = "Ogpu_metal.Acceleration.create_triangle" in
  match Buffer.descriptor device vertices with Error _ as failure -> failure | Ok buffer_descriptor ->
  let ray_tracing = (Device.capabilities device).Ogpu.Capabilities.ray_tracing in
  match plan_triangle ~ray_tracing ~buffer_size:buffer_descriptor.size ~offset ~length
    ~vertex_stride ~vertex_count with Error _ as failure -> failure | Ok plan ->
  let range : Ogpu.Acceleration.buffer_range =
    {buffer=Buffer.Private.resource_handle vertices;buffer_size=buffer_descriptor.size;offset;length} in
  let portable_descriptor = Ogpu.Acceleration.Blas
    {geometries=[|Ogpu.Acceleration.Triangles {vertices=range;vertex_stride;vertex_count}|];allow_refit} in
  match Ogpu.Acceleration.create (Device.Private.handle device) ~ray_tracing:true portable_descriptor with Error _ as failure -> failure | Ok portable ->
  match Metal.Acceleration_structure.Triangle.create ~vertex_buffer:(Buffer.Private.metal vertices)
    ~vertex_offset:plan.offset ~vertex_stride:(Int64.of_int plan.vertex_stride)
    ~triangle_count:(Int64.of_int (plan.vertex_count/3)) () with
  | Error metal -> Ogpu.Acceleration.destroy portable; Error (Adapter.error ~operation metal)
  | Ok descriptor -> (match Metal.Acceleration_structure.sizes ~device:(Device.Private.metal device) descriptor with
      | Error metal -> Ogpu.Acceleration.destroy portable; Error (Adapter.error ~operation metal)
      | Ok sizes -> match Metal.Acceleration_structure.create ~device:(Device.Private.metal device)
          ~size:sizes.acceleration_structure_size with
        | Error metal -> Ogpu.Acceleration.destroy portable; Error (Adapter.error ~operation metal)
        | Ok metal -> Device.Private.attach_resource device;
            Ok {device;portable;descriptor;metal;sizes;allow_refit;dead=false})

let validate_scratch operation device value scratch scratch_offset required =
  match validate operation device value with Error _ as failure -> failure | Ok () ->
  match Buffer.descriptor device scratch with Error _ as failure -> failure | Ok descriptor ->
  validate_scratch_plan ~buffer_size:descriptor.size ~offset:scratch_offset ~required

let with_encoder operation device encode =
  match Metal.Command_queue.create (Device.Private.metal device) with Error metal -> Error (Adapter.error ~operation metal) | Ok queue ->
  let finish result = ignore (Metal.Command_queue.destroy queue); result in
  match Metal.Command_buffer.create queue () with Error metal -> finish (Error (Adapter.error ~operation metal)) | Ok command ->
  let finish_command result = ignore (Metal.Command_buffer.destroy command); finish result in
  match Metal.Acceleration_encoder.create command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok encoder ->
  match encode encoder with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
  match Metal.Acceleration_encoder.end_encoding encoder with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
  match Metal.Command_buffer.commit command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () ->
  match Metal.Command_buffer.wait_until_completed command with Error metal -> finish_command (Error (Adapter.error ~operation metal)) | Ok () -> finish_command (Ok ())

let build device value ~scratch ~scratch_offset =
  let operation = "Ogpu_metal.Acceleration.build" in
  match validate_scratch operation device value scratch scratch_offset value.sizes.build_scratch_buffer_size with Error _ as failure -> failure | Ok () ->
  match with_encoder operation device (fun encoder -> Metal.Acceleration_encoder.build encoder
    ~destination:value.metal ~descriptor:value.descriptor ~scratch:(Buffer.Private.metal scratch) ~scratch_offset) with
  | Error _ as failure -> failure
  | Ok () -> Ogpu.Acceleration.build (Device.Private.handle device) value.portable

let refit device value ~scratch ~scratch_offset =
  let operation = "Ogpu_metal.Acceleration.refit" in
  if not value.allow_refit then error operation Ogpu.Error.Unsupported "descriptor does not permit refit" else
  match validate_scratch operation device value scratch scratch_offset value.sizes.refit_scratch_buffer_size with Error _ as failure -> failure | Ok () ->
  match with_encoder operation device (fun encoder -> Metal.Acceleration_encoder.refit encoder
    ~source:value.metal ~destination:value.metal ~descriptor:value.descriptor
    ~scratch:(Buffer.Private.metal scratch) ~scratch_offset) with
  | Error _ as failure -> failure
  | Ok () -> Ogpu.Acceleration.refit (Device.Private.handle device) value.portable

let copy device value =
  let operation = "Ogpu_metal.Acceleration.copy" in
  match validate operation device value with Error _ as failure -> failure | Ok () ->
  match Metal.Acceleration_structure.create ~device:(Device.Private.metal device) ~size:value.sizes.acceleration_structure_size with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok target -> (match with_encoder operation device (fun encoder -> Metal.Acceleration_encoder.copy encoder ~source:value.metal ~destination:target) with
      | Error _ as failure -> ignore (Metal.Acceleration_structure.destroy target); failure
      | Ok () -> match Ogpu.Acceleration.copy (Device.Private.handle device) value.portable with
        | Error _ as failure -> ignore (Metal.Acceleration_structure.destroy target); failure
        | Ok (portable,description) -> Device.Private.attach_resource device;
            Ok ({device;portable;descriptor=value.descriptor;metal=target;sizes=value.sizes;
                 allow_refit=value.allow_refit;dead=false},description))

let compact device value =
  let operation = "Ogpu_metal.Acceleration.compact" in
  match validate operation device value with Error _ as failure -> failure | Ok () ->
  match Metal.Acceleration_structure.create ~device:(Device.Private.metal device) ~size:value.sizes.acceleration_structure_size with
  | Error metal -> Error (Adapter.error ~operation metal)
  | Ok target -> (match with_encoder operation device (fun encoder -> Metal.Acceleration_encoder.copy_and_compact encoder ~source:value.metal ~destination:target) with
      | Error _ as failure -> ignore (Metal.Acceleration_structure.destroy target); failure
      | Ok () -> match Ogpu.Acceleration.compact (Device.Private.handle device) value.portable with
        | Error _ as failure -> ignore (Metal.Acceleration_structure.destroy target); failure
        | Ok description -> ignore (Metal.Acceleration_structure.destroy value.metal); value.metal <- target; Ok description)

let destroy value =
  if value.dead then Ok () else match Metal.Acceleration_structure.destroy value.metal with
  | Error metal -> Error (Adapter.error ~operation:"Ogpu_metal.Acceleration.destroy" metal)
  | Ok () -> value.dead <- true; Ogpu.Acceleration.destroy value.portable;
      Device.Private.detach_resource value.device; Ok ()
