type error_kind =
  | Native_error
  | Wrong_domain
  | Destroyed
  | Parent_has_dependents
  | Invalid_argument
  | Invalid_state
  | Unsupported
  | Device_mismatch
  | Release_queue_overflow

type error =
  { operation : string
  ; kind : error_kind
  ; message : string
  }

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }
let native_error operation message = error operation Native_error message

let contains_nul value = String.contains value '\000'

module Provenance = struct
  let sdk_version = Generated_provenance.sdk_version
  let deployment_target = Generated_provenance.deployment_target
  let target_triple = Generated_provenance.target_triple
  let header_count = Generated_provenance.header_count
  let header_sha256 = Generated_provenance.header_aggregate_sha256
end

module Thread = struct
  let is_initial_domain = Domain.is_main_domain
  let is_platform_main_thread = Metal_raw.is_main_thread

  let require operation =
    if not (is_initial_domain ()) then
      error operation Wrong_domain
        "Metal operation must run on the initial OCaml domain"
    else if not (is_platform_main_thread ()) then
      error operation Wrong_domain
        "Metal operation must run on the platform main thread"
    else Ok ()
end

let on_main operation callback =
  match Thread.require operation with
  | Error _ as failure -> failure
  | Ok () ->
      ignore (Metal_raw.drain_releases ());
      let dropped = Metal_raw.dropped_releases () in
      if dropped <> 0 then
        error operation Release_queue_overflow
          (Printf.sprintf
             "the bounded Metal finalizer queue overflowed and dropped %d token(s)"
             dropped)
      else callback ()

module Release_queue = struct
  type stats =
    { pending : int
    ; dropped : int
    ; live_handles : int
    ; total_created : int64
    ; total_released : int64
    ; resident_bytes : int64
    }

  let drain () =
    match Thread.require "Metal.Release_queue.drain" with
    | Error _ as failure -> failure
    | Ok () ->
        let drained = Metal_raw.drain_releases () in
        let dropped = Metal_raw.dropped_releases () in
        if dropped <> 0 then
          error "Metal.Release_queue.drain" Release_queue_overflow
            (Printf.sprintf "dropped %d finalizer release token(s)" dropped)
        else Ok drained

  let stats () =
    match Thread.require "Metal.Release_queue.stats" with
    | Error _ as failure -> failure
    | Ok () ->
        let resident_bytes = Metal_raw.resident_bytes () in
        if resident_bytes < 0L then
          native_error "Metal.Release_queue.stats"
            "mach task_info could not read resident memory"
        else
          Ok
            { pending = Metal_raw.pending_releases ()
            ; dropped = Metal_raw.dropped_releases ()
            ; live_handles = Metal_raw.live_handles ()
            ; total_created = Metal_raw.total_created ()
            ; total_released = Metal_raw.total_released ()
            ; resident_bytes
            }
end

type lifetime =
  { destroyed : bool Atomic.t
  ; dependents : int Atomic.t
  }

let lifetime () =
  { destroyed = Atomic.make false; dependents = Atomic.make 0 }

let is_destroyed lifetime = Atomic.get lifetime.destroyed
let dependent_count lifetime = Atomic.get lifetime.dependents

let attach lifetime = Atomic.incr lifetime.dependents
let detach lifetime = Atomic.decr lifetime.dependents

let finalize_child lifetime parent =
  if Atomic.compare_and_set lifetime.destroyed false true then detach parent

let ensure_live operation lifetime =
  if is_destroyed lifetime then error operation Destroyed "handle is destroyed"
  else Ok ()

let destroy_leaf operation lifetime raw detach_parent =
  on_main operation (fun () ->
    if Atomic.compare_and_set lifetime.destroyed false true then begin
      ignore (Metal_raw.destroy raw);
      detach_parent ()
    end;
    Ok ())

let destroy_parent operation lifetime raw detach_parent =
  on_main operation (fun () ->
    if is_destroyed lifetime then Ok ()
    else
      let dependents = dependent_count lifetime in
      if dependents <> 0 then
        error operation Parent_has_dependents
          (Printf.sprintf "handle still owns %d live dependent(s)" dependents)
      else begin
        Atomic.set lifetime.destroyed true;
        ignore (Metal_raw.destroy raw);
        detach_parent ();
        Ok ()
      end)

type device =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; registry_id : int64
  }

type buffer =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; length : int64
  ; storage : buffer_storage_mode
  }

and buffer_storage_mode =
  | Shared
  | Managed
  | Private

type library =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  }

type function_handle =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; library : library
  }

type compute_pipeline =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; thread_execution_width : int
  ; max_total_threads : int
  }

type command_queue =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  }

type command_phase =
  | Recording
  | Submitted

type command_buffer =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; queue : command_queue
  ; mutable phase : command_phase
  }

type compute_encoder =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; command_buffer : command_buffer
  ; mutable pipeline : compute_pipeline option
  }

let make_device raw =
  ({ raw; lifetime = lifetime (); registry_id = Metal_raw.device_registry_id raw }
    : device)

let attach_finalizer value lifetime parent =
  Gc.finalise (fun _ -> finalize_child lifetime parent) value

let same_device left right = Int64.equal left.registry_id right.registry_id

let ensure_same_device operation expected actual =
  if same_device expected actual then Ok ()
  else
    error operation Device_mismatch
      "resources belong to different Metal devices"

module Device = struct
  type t = device

  type family =
    | Apple1
    | Apple2
    | Apple3
    | Apple4
    | Apple5
    | Apple6
    | Apple7
    | Apple8
    | Apple9
    | Apple10
    | Mac2
    | Common1
    | Common2
    | Common3
    | Metal3
    | Metal4

  type info =
    { name : string
    ; registry_id : int64
    ; low_power : bool
    ; removable : bool
    ; headless : bool
    ; unified_memory : bool
    ; recommended_max_working_set_size : int64
    ; current_allocated_size : int64
    ; max_buffer_length : int64
    ; raytracing : bool
    ; raytracing_from_render : bool
    ; dynamic_libraries : bool
    ; function_pointers : bool
    }

  let system_default () =
    on_main "Metal.Device.system_default" (fun () ->
      match Metal_raw.default_device () with
      | Ok raw -> Ok (make_device raw)
      | Error message -> native_error "Metal.Device.system_default" message)

  let all () =
    on_main "Metal.Device.all" (fun () ->
      match Metal_raw.all_devices () with
      | Ok devices -> Ok (Array.to_list (Array.map make_device devices))
      | Error message -> native_error "Metal.Device.all" message)

  let generation (value : t) = Metal_raw.generation value.raw
  let registry_id (value : t) = value.registry_id
  let same = same_device
  let destroyed (value : t) = is_destroyed value.lifetime

  let info (value : t) =
    on_main "Metal.Device.info" (fun () ->
      match ensure_live "Metal.Device.info" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          Ok
            { name = Metal_raw.device_name value.raw
            ; registry_id = value.registry_id
            ; low_power = Metal_raw.device_is_low_power value.raw
            ; removable = Metal_raw.device_is_removable value.raw
            ; headless = Metal_raw.device_is_headless value.raw
            ; unified_memory = Metal_raw.device_has_unified_memory value.raw
            ; recommended_max_working_set_size =
                Metal_raw.device_recommended_max_working_set_size value.raw
            ; current_allocated_size =
                Metal_raw.device_current_allocated_size value.raw
            ; max_buffer_length = Metal_raw.device_max_buffer_length value.raw
            ; raytracing = Metal_raw.device_supports_raytracing value.raw
            ; raytracing_from_render =
                Metal_raw.device_supports_raytracing_from_render value.raw
            ; dynamic_libraries =
                Metal_raw.device_supports_dynamic_libraries value.raw
            ; function_pointers =
                Metal_raw.device_supports_function_pointers value.raw
            })

  let family_code = function
    | Apple1 -> 1001
    | Apple2 -> 1002
    | Apple3 -> 1003
    | Apple4 -> 1004
    | Apple5 -> 1005
    | Apple6 -> 1006
    | Apple7 -> 1007
    | Apple8 -> 1008
    | Apple9 -> 1009
    | Apple10 -> 1010
    | Mac2 -> 2002
    | Common1 -> 3001
    | Common2 -> 3002
    | Common3 -> 3003
    | Metal3 -> 5001
    | Metal4 -> 5002

  let supports_family (value : t) family =
    on_main "Metal.Device.supports_family" (fun () ->
      match ensure_live "Metal.Device.supports_family" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_family value.raw (family_code family)))

  let destroy (value : t) =
    destroy_parent "Metal.Device.destroy" value.lifetime value.raw (fun () -> ())
end

module Buffer = struct
  type t = buffer
  type storage_mode = buffer_storage_mode = Shared | Managed | Private

  let storage_code = function Shared -> 0 | Managed -> 1 | Private -> 2

  let create ~(device : Device.t) ~length ~storage ?label () =
    on_main "Metal.Buffer.create" (fun () ->
      match ensure_live "Metal.Buffer.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () when length <= 0L ->
          error "Metal.Buffer.create" Invalid_argument
            "buffer length must be positive"
      | Ok () when length > Metal_raw.device_max_buffer_length device.raw ->
          error "Metal.Buffer.create" Invalid_argument
            "buffer length exceeds the device limit"
      | Ok () ->
          (match label with
           | Some label when contains_nul label ->
               error "Metal.Buffer.create" Invalid_argument
                 "label contains a NUL byte"
           | _ ->
               match Metal_raw.buffer_create device.raw length (storage_code storage) with
               | Error message -> native_error "Metal.Buffer.create" message
               | Ok raw ->
                   let value : t =
                     { raw; lifetime = lifetime (); device; length; storage }
                   in
                   attach device.lifetime;
                   attach_finalizer value value.lifetime device.lifetime;
                   (match label with
                    | None -> Ok value
                    | Some label ->
                        (match Metal_raw.buffer_set_label raw label with
                         | Ok () -> Ok value
                         | Error message ->
                             ignore (Metal_raw.destroy raw);
                             if Atomic.compare_and_set value.lifetime.destroyed false true
                             then detach device.lifetime;
                             native_error "Metal.Buffer.create" message))))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let length (value : t) = value.length
  let storage_mode (value : t) = value.storage
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Buffer.label" (fun () ->
      match ensure_live "Metal.Buffer.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.buffer_label value.raw))

  let set_label (value : t) label =
    on_main "Metal.Buffer.set_label" (fun () ->
      match ensure_live "Metal.Buffer.set_label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when contains_nul label ->
          error "Metal.Buffer.set_label" Invalid_argument
            "label contains a NUL byte"
      | Ok () ->
          (match Metal_raw.buffer_set_label value.raw label with
           | Ok () -> Ok ()
           | Error message -> native_error "Metal.Buffer.set_label" message))

  let validate_range operation ~total ~offset ~length =
    if offset < 0L || length < 0 then
      error operation Invalid_argument "range is negative"
    else
      let length64 = Int64.of_int length in
      if offset > total || length64 > Int64.sub total offset then
        error operation Invalid_argument "range exceeds the buffer"
      else Ok ()

  let write_bytes (value : t) ?(src_offset = 0) ~dst_offset bytes =
    on_main "Metal.Buffer.write_bytes" (fun () ->
      match ensure_live "Metal.Buffer.write_bytes" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.storage = Private ->
          error "Metal.Buffer.write_bytes" Unsupported
            "private buffers have no CPU mapping"
      | Ok () ->
          let source_length = Bytes.length bytes in
          if src_offset < 0 || src_offset > source_length then
            error "Metal.Buffer.write_bytes" Invalid_argument
              "source offset is outside the byte buffer"
          else
            let length = source_length - src_offset in
            match
              validate_range "Metal.Buffer.write_bytes" ~total:value.length
                ~offset:dst_offset ~length
            with
            | Error _ as failure -> failure
            | Ok () ->
                (match
                   Metal_raw.buffer_write value.raw dst_offset bytes src_offset length
                 with
                 | Ok () -> Ok ()
                 | Error message ->
                     native_error "Metal.Buffer.write_bytes" message))

  let read_bytes (value : t) ~offset ~length =
    on_main "Metal.Buffer.read_bytes" (fun () ->
      match ensure_live "Metal.Buffer.read_bytes" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.storage = Private ->
          error "Metal.Buffer.read_bytes" Unsupported
            "private buffers have no CPU mapping"
      | Ok () when length > Sys.max_string_length ->
          error "Metal.Buffer.read_bytes" Invalid_argument
            "read length exceeds the maximum OCaml byte-buffer size"
      | Ok () ->
          (match
             validate_range "Metal.Buffer.read_bytes" ~total:value.length ~offset
               ~length
           with
           | Error _ as failure -> failure
           | Ok () ->
               match Metal_raw.buffer_read value.raw offset length with
               | Ok bytes -> Ok bytes
               | Error message -> native_error "Metal.Buffer.read_bytes" message))

  let destroy (value : t) =
    destroy_leaf "Metal.Buffer.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Library = struct
  type t = library

  let compile_source ~(device : Device.t) source =
    on_main "Metal.Library.compile_source" (fun () ->
      match ensure_live "Metal.Library.compile_source" device.lifetime with
      | Error _ as failure -> failure
      | Ok () when source = "" ->
          error "Metal.Library.compile_source" Invalid_argument
            "shader source is empty"
      | Ok () when contains_nul source ->
          error "Metal.Library.compile_source" Invalid_argument
            "shader source contains a NUL byte"
      | Ok () ->
          (match Metal_raw.library_compile device.raw source with
           | Error message -> native_error "Metal.Library.compile_source" message
           | Ok raw ->
               let value : t = { raw; lifetime = lifetime (); device } in
               attach device.lifetime;
               attach_finalizer value value.lifetime device.lifetime;
               Ok value))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_parent "Metal.Library.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Function = struct
  type t = function_handle

  let find ~(library : Library.t) name =
    on_main "Metal.Function.find" (fun () ->
      match ensure_live "Metal.Function.find" library.lifetime with
      | Error _ as failure -> failure
      | Ok () when name = "" || contains_nul name ->
          error "Metal.Function.find" Invalid_argument
            "function name must be nonempty and contain no NUL byte"
      | Ok () ->
          (match Metal_raw.function_find library.raw name with
           | Error message -> native_error "Metal.Function.find" message
           | Ok raw ->
               let value : t = { raw; lifetime = lifetime (); library } in
               attach library.lifetime;
               attach_finalizer value value.lifetime library.lifetime;
               Ok value))

  let name (value : t) =
    on_main "Metal.Function.name" (fun () ->
      match ensure_live "Metal.Function.name" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.function_name value.raw))

  let device (value : t) = value.library.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_leaf "Metal.Function.destroy" value.lifetime value.raw
      (fun () -> detach value.library.lifetime)
end

module Compute_pipeline = struct
  type t = compute_pipeline

  let create (function_value : Function.t) =
    on_main "Metal.Compute_pipeline.create" (fun () ->
      match ensure_live "Metal.Compute_pipeline.create" function_value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          let device = function_value.library.device in
          (match
             Metal_raw.compute_pipeline_create device.raw function_value.raw
           with
           | Error message -> native_error "Metal.Compute_pipeline.create" message
           | Ok raw ->
               let value : t =
                 { raw
                 ; lifetime = lifetime ()
                 ; device
                 ; thread_execution_width =
                     Metal_raw.compute_pipeline_thread_execution_width raw
                 ; max_total_threads =
                     Metal_raw.compute_pipeline_max_total_threads raw
                 }
               in
               attach device.lifetime;
               attach_finalizer value value.lifetime device.lifetime;
               Ok value))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let thread_execution_width (value : t) = value.thread_execution_width
  let max_total_threads_per_threadgroup (value : t) = value.max_total_threads
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_leaf "Metal.Compute_pipeline.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Command_queue = struct
  type t = command_queue

  let create (device : Device.t) =
    on_main "Metal.Command_queue.create" (fun () ->
      match ensure_live "Metal.Command_queue.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.command_queue_create device.raw with
           | Error message -> native_error "Metal.Command_queue.create" message
           | Ok raw ->
               let value : t = { raw; lifetime = lifetime (); device } in
               attach device.lifetime;
               attach_finalizer value value.lifetime device.lifetime;
               Ok value))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_parent "Metal.Command_queue.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Command_buffer = struct
  type t = command_buffer

  type status =
    | Not_enqueued
    | Enqueued
    | Committed
    | Scheduled
    | Completed
    | Error of string
    | Unknown of int

  let create (queue : Command_queue.t) ?label () =
    on_main "Metal.Command_buffer.create" (fun () ->
      match ensure_live "Metal.Command_buffer.create" queue.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match label with
           | Some label when contains_nul label ->
               error "Metal.Command_buffer.create" Invalid_argument
                 "label contains a NUL byte"
           | _ ->
               match Metal_raw.command_buffer_create queue.raw with
               | Error message ->
                   native_error "Metal.Command_buffer.create" message
               | Ok raw ->
                   let value : t =
                     { raw; lifetime = lifetime (); queue; phase = Recording }
                   in
                   attach queue.lifetime;
                   attach_finalizer value value.lifetime queue.lifetime;
                   (match label with
                    | None -> Ok value
                    | Some label ->
                        (match Metal_raw.command_buffer_set_label raw label with
                         | Ok () -> Ok value
                         | Error message ->
                             ignore (Metal_raw.destroy raw);
                             if Atomic.compare_and_set value.lifetime.destroyed false true
                             then detach queue.lifetime;
                             native_error "Metal.Command_buffer.create" message))))

  let device (value : t) = value.queue.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let status (value : t) =
    on_main "Metal.Command_buffer.status" (fun () ->
      match ensure_live "Metal.Command_buffer.status" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          let status = Metal_raw.command_buffer_status value.raw in
          Ok
            (match status with
             | 0 -> Not_enqueued
             | 1 -> Enqueued
             | 2 -> Committed
             | 3 -> Scheduled
             | 4 -> Completed
             | 5 ->
                 Error
                   (Option.value (Metal_raw.command_buffer_error value.raw)
                      ~default:"Metal command buffer failed without NSError")
             | value -> Unknown value))

  let commit (value : t) =
    on_main "Metal.Command_buffer.commit" (fun () ->
      match ensure_live "Metal.Command_buffer.commit" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.phase <> Recording ->
          error "Metal.Command_buffer.commit" Invalid_state
            "command buffer was already submitted"
      | Ok () when dependent_count value.lifetime <> 0 ->
          error "Metal.Command_buffer.commit" Invalid_state
            "a command encoder is still open"
      | Ok () ->
          (match Metal_raw.command_buffer_commit value.raw with
           | Error message -> native_error "Metal.Command_buffer.commit" message
           | Ok () -> value.phase <- Submitted; Ok ()))

  let wait_until_completed (value : t) =
    on_main "Metal.Command_buffer.wait_until_completed" (fun () ->
      match ensure_live "Metal.Command_buffer.wait_until_completed" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.phase <> Submitted ->
          error "Metal.Command_buffer.wait_until_completed" Invalid_state
            "command buffer has not been committed"
      | Ok () ->
          Metal_raw.command_buffer_wait value.raw;
          let status = Metal_raw.command_buffer_status value.raw in
          if status = 4 then Ok ()
          else
            native_error "Metal.Command_buffer.wait_until_completed"
              (Option.value (Metal_raw.command_buffer_error value.raw)
                 ~default:
                   (Printf.sprintf "command buffer ended with status %d" status)))

  let destroy (value : t) =
    destroy_parent "Metal.Command_buffer.destroy" value.lifetime value.raw
      (fun () -> detach value.queue.lifetime)
end

module Compute_encoder = struct
  type t = compute_encoder

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Compute_encoder.create" (fun () ->
      match ensure_live "Metal.Compute_encoder.create" command_buffer.lifetime with
      | Error _ as failure -> failure
      | Ok () when command_buffer.phase <> Recording ->
          error "Metal.Compute_encoder.create" Invalid_state
            "command buffer is no longer recording"
      | Ok () when dependent_count command_buffer.lifetime <> 0 ->
          error "Metal.Compute_encoder.create" Invalid_state
            "command buffer already has an open encoder"
      | Ok () ->
          (match Metal_raw.command_buffer_compute_encoder command_buffer.raw with
           | Error message -> native_error "Metal.Compute_encoder.create" message
           | Ok raw ->
               let value : t =
                 { raw
                 ; lifetime = lifetime ()
                 ; command_buffer
                 ; pipeline = None
                 }
               in
               attach command_buffer.lifetime;
               attach_finalizer value value.lifetime command_buffer.lifetime;
               Ok value))

  let destroyed (value : t) = is_destroyed value.lifetime

  let set_pipeline (value : t) (pipeline : Compute_pipeline.t) =
    on_main "Metal.Compute_encoder.set_pipeline" (fun () ->
      match ensure_live "Metal.Compute_encoder.set_pipeline" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live "Metal.Compute_encoder.set_pipeline" pipeline.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               match
                 ensure_same_device "Metal.Compute_encoder.set_pipeline"
                   value.command_buffer.queue.device pipeline.device
               with
               | Error _ as failure -> failure
               | Ok () ->
                   match Metal_raw.compute_encoder_set_pipeline value.raw pipeline.raw with
                   | Error message ->
                       native_error "Metal.Compute_encoder.set_pipeline" message
                   | Ok () -> value.pipeline <- Some pipeline; Ok ()))

  let set_buffer (value : t) ~index ~offset (buffer : Buffer.t) =
    on_main "Metal.Compute_encoder.set_buffer" (fun () ->
      match ensure_live "Metal.Compute_encoder.set_buffer" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live "Metal.Compute_encoder.set_buffer" buffer.lifetime with
           | Error _ as failure -> failure
           | Ok () when index < 0 || index >= 31 ->
               error "Metal.Compute_encoder.set_buffer" Invalid_argument
                 "buffer index must be in [0, 31)"
           | Ok () when offset < 0L || offset > buffer.length ->
               error "Metal.Compute_encoder.set_buffer" Invalid_argument
                 "buffer offset is outside the resource"
           | Ok () ->
               match
                 ensure_same_device "Metal.Compute_encoder.set_buffer"
                   value.command_buffer.queue.device buffer.device
               with
               | Error _ as failure -> failure
               | Ok () ->
                   match
                     Metal_raw.compute_encoder_set_buffer value.raw buffer.raw offset
                       index
                   with
                   | Ok () -> Ok ()
                   | Error message ->
                       native_error "Metal.Compute_encoder.set_buffer" message))

  let positive_size (x, y, z) = x > 0 && y > 0 && z > 0

  let product3 x y z =
    if x > max_int / y then None
    else
      let xy = x * y in
      if xy > max_int / z then None else Some (xy * z)

  let dispatch_threads (value : t) ~threads ~threadgroup =
    on_main "Metal.Compute_encoder.dispatch_threads" (fun () ->
      match ensure_live "Metal.Compute_encoder.dispatch_threads" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Option.is_none value.pipeline ->
          error "Metal.Compute_encoder.dispatch_threads" Invalid_state
            "no compute pipeline is bound"
      | Ok () when not (positive_size threads && positive_size threadgroup) ->
          error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
            "thread and threadgroup dimensions must be positive"
      | Ok () ->
          let tx, ty, tz = threadgroup in
          let pipeline = Option.get value.pipeline in
          (match product3 tx ty tz with
           | None ->
               error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
                 "threadgroup cardinality overflows an OCaml integer"
           | Some product when product > pipeline.max_total_threads ->
               error "Metal.Compute_encoder.dispatch_threads" Invalid_argument
                 "threadgroup exceeds the pipeline's maximum total thread count"
           | Some _ ->
               match
                 Metal_raw.compute_encoder_dispatch value.raw threads threadgroup
               with
               | Ok () -> Ok ()
               | Error message ->
                   native_error "Metal.Compute_encoder.dispatch_threads" message))

  let end_encoding (value : t) =
    on_main "Metal.Compute_encoder.end_encoding" (fun () ->
      match ensure_live "Metal.Compute_encoder.end_encoding" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.compute_encoder_end value.raw with
           | Error message -> native_error "Metal.Compute_encoder.end_encoding" message
           | Ok () ->
               if Atomic.compare_and_set value.lifetime.destroyed false true then begin
                 ignore (Metal_raw.destroy value.raw);
                 detach value.command_buffer.lifetime
               end;
               Ok ()))
end
