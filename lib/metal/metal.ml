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
let option_exists predicate = function Some value -> predicate value | None -> false

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

type buffer_mapping =
  { buffer : buffer
  ; offset : int64
  ; length : int
  ; active : bool Atomic.t
  }

type texture_kind =
  | Texture_1d
  | Texture_1d_array
  | Texture_2d
  | Texture_2d_array
  | Texture_2d_multisample
  | Texture_cube
  | Texture_cube_array
  | Texture_3d
  | Texture_2d_multisample_array
  | Texture_buffer

type pixel_format =
  | A8_unorm
  | R8_unorm
  | R8_unorm_srgb
  | R8_uint
  | R16_float
  | R32_float
  | Rg8_unorm
  | Rg8_unorm_srgb
  | Rg16_float
  | Rg32_float
  | Rgba8_unorm
  | Rgba8_unorm_srgb
  | Bgra8_unorm
  | Bgra8_unorm_srgb
  | Rgb10a2_unorm
  | Rg11b10_float
  | Rgba16_float
  | Rgba32_float
  | Depth16_unorm
  | Depth32_float
  | Stencil8
  | Depth24_unorm_stencil8
  | Depth32_float_stencil8

type resource_cpu_cache_mode =
  | Default_cache
  | Write_combined

type resource_hazard_tracking_mode =
  | Default_hazard_tracking
  | Untracked
  | Tracked

type texture_usage =
  | Shader_read
  | Shader_write
  | Render_target
  | Pixel_format_view
  | Shader_atomic

type texture_descriptor =
  { kind : texture_kind
  ; format : pixel_format
  ; width : int
  ; height : int
  ; depth : int
  ; mip_levels : int
  ; sample_count : int
  ; array_length : int
  ; storage : buffer_storage_mode
  ; cpu_cache : resource_cpu_cache_mode
  ; hazard_tracking : resource_hazard_tracking_mode
  ; usage : texture_usage list
  ; allow_gpu_optimized_contents : bool
  ; label : string option
  }

type texture =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : texture_descriptor
  ; parent_lifetime : lifetime
  }

type sampler_filter =
  | Nearest
  | Linear

type sampler_mip_filter =
  | Not_mipmapped
  | Mip_nearest
  | Mip_linear

type sampler_address_mode =
  | Clamp_to_edge
  | Mirror_clamp_to_edge
  | Repeat
  | Mirror_repeat
  | Clamp_to_zero
  | Clamp_to_border_color

type sampler_border_color =
  | Transparent_black
  | Opaque_black
  | Opaque_white

type sampler_compare_function =
  | Never
  | Less
  | Equal
  | Less_equal
  | Greater
  | Not_equal
  | Greater_equal
  | Always

type sampler_descriptor =
  { min_filter : sampler_filter
  ; mag_filter : sampler_filter
  ; mip_filter : sampler_mip_filter
  ; max_anisotropy : int
  ; s_address : sampler_address_mode
  ; t_address : sampler_address_mode
  ; r_address : sampler_address_mode
  ; border_color : sampler_border_color
  ; normalized_coordinates : bool
  ; lod_min_clamp : float
  ; lod_max_clamp : float
  ; lod_average : bool
  ; compare_function : sampler_compare_function
  ; support_argument_buffers : bool
  ; label : string option
  }

type sampler =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : sampler_descriptor
  }

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

  let supports_texture_sample_count (value : t) sample_count =
    on_main "Metal.Device.supports_texture_sample_count" (fun () ->
      match ensure_live "Metal.Device.supports_texture_sample_count" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when sample_count <= 0 ->
          error "Metal.Device.supports_texture_sample_count" Invalid_argument
            "texture sample count must be positive"
      | Ok () ->
          Ok
            (Metal_raw.device_supports_texture_sample_count value.raw sample_count))

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

  module Mapping = struct
    type t = buffer_mapping

    let ensure_active operation value =
      match Thread.require operation with
      | Error _ as failure -> failure
      | Ok () when not (Atomic.get value.active) ->
          error operation Destroyed "mapped range has left its lexical scope"
      | Ok () -> ensure_live operation value.buffer.lifetime

    let length value =
      match ensure_active "Metal.Buffer.Mapping.length" value with
      | Error _ as failure -> failure
      | Ok () -> Ok value.length

    let validate_local operation value ~offset ~length =
      if offset < 0 || length < 0 || offset > value.length
         || length > value.length - offset
      then error operation Invalid_argument "range exceeds the mapped buffer span"
      else Ok ()

    let read_bytes value ~offset ~length =
      match ensure_active "Metal.Buffer.Mapping.read_bytes" value with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_local "Metal.Buffer.Mapping.read_bytes" value ~offset
               ~length
           with
           | Error _ as failure -> failure
           | Ok () ->
               read_bytes value.buffer
                 ~offset:(Int64.add value.offset (Int64.of_int offset)) ~length)

    let write_bytes value ?(src_offset = 0) ~dst_offset bytes =
      match ensure_active "Metal.Buffer.Mapping.write_bytes" value with
      | Error _ as failure -> failure
      | Ok () ->
          let source_length = Bytes.length bytes in
          if src_offset < 0 || src_offset > source_length then
            error "Metal.Buffer.Mapping.write_bytes" Invalid_argument
              "source offset is outside the byte buffer"
          else
            let length = source_length - src_offset in
            match
              validate_local "Metal.Buffer.Mapping.write_bytes" value
                ~offset:dst_offset ~length
            with
            | Error _ as failure -> failure
            | Ok () ->
                write_bytes value.buffer ~src_offset
                  ~dst_offset:(Int64.add value.offset (Int64.of_int dst_offset))
                  bytes
  end

  let with_mapping (value : t) ~offset ~length callback =
    on_main "Metal.Buffer.with_mapping" (fun () ->
      match ensure_live "Metal.Buffer.with_mapping" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.storage = Private ->
          error "Metal.Buffer.with_mapping" Unsupported
            "private buffers have no CPU mapping"
      | Ok () ->
          (match
             validate_range "Metal.Buffer.with_mapping" ~total:value.length
               ~offset ~length
           with
           | Error _ as failure -> failure
           | Ok () ->
               let mapping : Mapping.t =
                 { buffer = value
                 ; offset
                 ; length
                 ; active = Atomic.make true
                 }
               in
               attach value.lifetime;
               Fun.protect
                 ~finally:(fun () ->
                   Atomic.set mapping.active false;
                   detach value.lifetime)
                 (fun () -> Ok (callback mapping))))

  let destroy (value : t) =
    destroy_parent "Metal.Buffer.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Texture = struct
  type t = texture
  type kind = texture_kind =
    | Texture_1d
    | Texture_1d_array
    | Texture_2d
    | Texture_2d_array
    | Texture_2d_multisample
    | Texture_cube
    | Texture_cube_array
    | Texture_3d
    | Texture_2d_multisample_array
    | Texture_buffer

  type format = pixel_format =
    | A8_unorm
    | R8_unorm
    | R8_unorm_srgb
    | R8_uint
    | R16_float
    | R32_float
    | Rg8_unorm
    | Rg8_unorm_srgb
    | Rg16_float
    | Rg32_float
    | Rgba8_unorm
    | Rgba8_unorm_srgb
    | Bgra8_unorm
    | Bgra8_unorm_srgb
    | Rgb10a2_unorm
    | Rg11b10_float
    | Rgba16_float
    | Rgba32_float
    | Depth16_unorm
    | Depth32_float
    | Stencil8
    | Depth24_unorm_stencil8
    | Depth32_float_stencil8

  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined
  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type usage = texture_usage =
    | Shader_read
    | Shader_write
    | Render_target
    | Pixel_format_view
    | Shader_atomic

  type descriptor = texture_descriptor =
    { kind : kind
    ; format : format
    ; width : int
    ; height : int
    ; depth : int
    ; mip_levels : int
    ; sample_count : int
    ; array_length : int
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; usage : usage list
    ; allow_gpu_optimized_contents : bool
    ; label : string option
    }

  type region =
    { x : int
    ; y : int
    ; z : int
    ; width : int
    ; height : int
    ; depth : int
    }

  let descriptor_2d ?(mipmapped = false) ?(storage = Private)
      ?(usage = [ Shader_read ]) ?label ~format ~width ~height () =
    let max_dimension = max width height in
    let rec mip_count dimension count =
      if dimension <= 1 then count
      else mip_count (dimension / 2) (count + 1)
    in
    { kind = Texture_2d
    ; format
    ; width
    ; height
    ; depth = 1
    ; mip_levels = if mipmapped then mip_count max_dimension 1 else 1
    ; sample_count = 1
    ; array_length = 1
    ; storage
    ; cpu_cache = Default_cache
    ; hazard_tracking = Default_hazard_tracking
    ; usage
    ; allow_gpu_optimized_contents = true
    ; label
    }

  let kind_code = function
    | Texture_1d -> 0
    | Texture_1d_array -> 1
    | Texture_2d -> 2
    | Texture_2d_array -> 3
    | Texture_2d_multisample -> 4
    | Texture_cube -> 5
    | Texture_cube_array -> 6
    | Texture_3d -> 7
    | Texture_2d_multisample_array -> 8
    | Texture_buffer -> 9

  let format_code = function
    | A8_unorm -> 1
    | R8_unorm -> 10
    | R8_unorm_srgb -> 11
    | R8_uint -> 13
    | R16_float -> 25
    | R32_float -> 55
    | Rg8_unorm -> 30
    | Rg8_unorm_srgb -> 31
    | Rg16_float -> 65
    | Rg32_float -> 105
    | Rgba8_unorm -> 70
    | Rgba8_unorm_srgb -> 71
    | Bgra8_unorm -> 80
    | Bgra8_unorm_srgb -> 81
    | Rgb10a2_unorm -> 90
    | Rg11b10_float -> 92
    | Rgba16_float -> 115
    | Rgba32_float -> 125
    | Depth16_unorm -> 250
    | Depth32_float -> 252
    | Stencil8 -> 253
    | Depth24_unorm_stencil8 -> 255
    | Depth32_float_stencil8 -> 260

  let bytes_per_pixel = function
    | A8_unorm | R8_unorm | R8_unorm_srgb | R8_uint | Stencil8 -> 1
    | R16_float | Rg8_unorm | Rg8_unorm_srgb | Depth16_unorm -> 2
    | R32_float | Rg16_float | Rgba8_unorm | Rgba8_unorm_srgb
    | Bgra8_unorm | Bgra8_unorm_srgb | Rgb10a2_unorm | Rg11b10_float
    | Depth32_float | Depth24_unorm_stencil8 -> 4
    | Rg32_float | Rgba16_float | Depth32_float_stencil8 -> 8
    | Rgba32_float -> 16

  let storage_code = function Shared -> 0 | Managed -> 1 | Private -> 2
  let cache_code = function Default_cache -> 0 | Write_combined -> 1

  let hazard_code = function
    | Default_hazard_tracking -> 0
    | Untracked -> 1
    | Tracked -> 2

  let usage_bit = function
    | Shader_read -> 0x1
    | Shader_write -> 0x2
    | Render_target -> 0x4
    | Pixel_format_view -> 0x10
    | Shader_atomic -> 0x20

  let usage_bits usages =
    List.fold_left (fun bits usage -> bits lor usage_bit usage) 0 usages

  let max_mip_levels (descriptor : descriptor) =
    let largest = max descriptor.width (max descriptor.height descriptor.depth) in
    let rec count dimension levels =
      if dimension <= 1 then levels
      else count (dimension / 2) (levels + 1)
    in
    count largest 1

  let is_array = function
    | Texture_1d_array | Texture_2d_array | Texture_cube_array
    | Texture_2d_multisample_array -> true
    | Texture_1d | Texture_2d | Texture_2d_multisample | Texture_cube
    | Texture_3d | Texture_buffer -> false

  let is_multisample = function
    | Texture_2d_multisample | Texture_2d_multisample_array -> true
    | Texture_1d | Texture_1d_array | Texture_2d | Texture_2d_array
    | Texture_cube | Texture_cube_array | Texture_3d | Texture_buffer -> false

  let validate_descriptor device (descriptor : descriptor) =
    let operation = "Metal.Texture.create" in
    let invalid message = error operation Invalid_argument message in
    if descriptor.width <= 0 || descriptor.height <= 0 || descriptor.depth <= 0
       || descriptor.mip_levels <= 0 || descriptor.sample_count <= 0
       || descriptor.array_length <= 0
    then invalid "texture dimensions and counts must be positive"
    else if descriptor.width > 16_384 || descriptor.height > 16_384
            || descriptor.depth > 2_048
    then invalid "texture dimensions exceed the binding's checked Metal limits"
    else if descriptor.mip_levels > max_mip_levels descriptor then
      invalid "texture mip count exceeds its dimensions"
    else if descriptor.array_length >= 2_048 then
      invalid "texture array length must be below 2048"
    else if List.length descriptor.usage <> List.length (List.sort_uniq compare descriptor.usage)
    then invalid "texture usage contains duplicates"
    else
      match descriptor.label with
      | Some label when contains_nul label -> invalid "texture label contains a NUL byte"
      | _ ->
          let structural_error =
            match descriptor.kind with
            | Texture_1d | Texture_buffer
              when descriptor.height <> 1 || descriptor.depth <> 1 ->
                Some "1D and buffer textures require height=depth=1"
            | Texture_1d_array
              when descriptor.height <> 1 || descriptor.depth <> 1 ->
                Some "1D-array textures require height=depth=1"
            | Texture_2d | Texture_2d_array | Texture_2d_multisample
            | Texture_2d_multisample_array | Texture_cube | Texture_cube_array
              when descriptor.depth <> 1 ->
                Some "2D, cube, and multisample textures require depth=1"
            | Texture_cube | Texture_cube_array
              when descriptor.width <> descriptor.height ->
                Some "cube textures must be square"
            | Texture_3d when descriptor.array_length <> 1 ->
                Some "3D textures cannot be arrays"
            | _ -> None
          in
          (match structural_error with
           | Some message -> invalid message
           | None when is_array descriptor.kind && descriptor.array_length < 2 ->
               invalid "array textures require at least two elements"
           | None when not (is_array descriptor.kind) && descriptor.array_length <> 1 ->
               invalid "non-array textures require array_length=1"
           | None when is_multisample descriptor.kind && descriptor.mip_levels <> 1 ->
               invalid "multisample textures require exactly one mip level"
           | None when is_multisample descriptor.kind && descriptor.sample_count = 1 ->
               invalid "multisample textures require more than one sample"
           | None when not (is_multisample descriptor.kind)
                       && descriptor.sample_count <> 1 ->
               invalid "non-multisample textures require sample_count=1"
           | None when descriptor.kind = Texture_buffer
                       && descriptor.mip_levels <> 1 ->
               invalid "buffer textures require exactly one mip level"
           | None ->
               if descriptor.sample_count = 1 then Ok ()
               else
                 match Device.supports_texture_sample_count device descriptor.sample_count with
                 | Error _ as failure -> failure
                 | Ok true -> Ok ()
                 | Ok false -> invalid "device does not support the texture sample count")

  let descriptor_tuple (descriptor : descriptor) =
    ( kind_code descriptor.kind
    , format_code descriptor.format
    , descriptor.width
    , descriptor.height
    , descriptor.depth
    , descriptor.mip_levels
    , descriptor.sample_count
    , descriptor.array_length
    , storage_code descriptor.storage
    , cache_code descriptor.cpu_cache
    , hazard_code descriptor.hazard_tracking
    , usage_bits descriptor.usage
    , descriptor.allow_gpu_optimized_contents )

  let verify_info operation raw descriptor =
    let info = Metal_raw.texture_info raw in
    if Array.length info <> 10 then
      native_error operation "Metal returned malformed texture properties"
    else
      let expected =
        [| kind_code descriptor.kind; format_code descriptor.format
         ; descriptor.width; descriptor.height; descriptor.depth
         ; descriptor.mip_levels; descriptor.sample_count
         ; descriptor.array_length; usage_bits descriptor.usage
         ; storage_code descriptor.storage
        |]
      in
      if info = expected then Ok ()
      else
        native_error operation
          "Metal changed a checked texture descriptor during creation"

  let finish_create operation ~device ~descriptor ~parent_lifetime raw =
    match verify_info operation raw descriptor with
    | Error _ as failure -> ignore (Metal_raw.destroy raw); failure
    | Ok () ->
        let value : t =
          { raw; lifetime = lifetime (); device; descriptor; parent_lifetime }
        in
        attach parent_lifetime;
        attach_finalizer value value.lifetime parent_lifetime;
        Ok value

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Texture.create" (fun () ->
      match ensure_live "Metal.Texture.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_descriptor device descriptor with
           | Error _ as failure -> failure
           | Ok () ->
               match
                 Metal_raw.texture_create device.raw (descriptor_tuple descriptor)
                   descriptor.label
               with
               | Error message -> native_error "Metal.Texture.create" message
               | Ok raw ->
                   finish_create "Metal.Texture.create" ~device ~descriptor
                     ~parent_lifetime:device.lifetime raw))

  let device (value : t) = value.device
  let descriptor (value : t) = value.descriptor
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Texture.label" (fun () ->
      match ensure_live "Metal.Texture.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.texture_label value.raw))

  let set_label (value : t) label =
    on_main "Metal.Texture.set_label" (fun () ->
      match ensure_live "Metal.Texture.set_label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when contains_nul label ->
          error "Metal.Texture.set_label" Invalid_argument
            "texture label contains a NUL byte"
      | Ok () ->
          (match Metal_raw.texture_set_label value.raw label with
           | Ok () -> Ok ()
           | Error message -> native_error "Metal.Texture.set_label" message))

  let mip_dimension dimension level = max 1 (dimension lsr level)

  let total_slices (descriptor : descriptor) =
    match descriptor.kind with
    | Texture_1d_array | Texture_2d_array | Texture_2d_multisample_array ->
        descriptor.array_length
    | Texture_cube -> 6
    | Texture_cube_array -> descriptor.array_length * 6
    | Texture_1d | Texture_2d | Texture_2d_multisample | Texture_3d
    | Texture_buffer -> 1

  let checked_mul left right =
    if left = 0 || right = 0 then Some 0
    else if left > max_int / right then None
    else Some (left * right)

  let validate_transfer operation (value : t) ~region ~mip_level ~slice ~bytes_per_row
      ~bytes_per_image =
    let invalid message = error operation Invalid_argument message in
    if value.descriptor.storage = Private then
      error operation Unsupported "private textures have no CPU transfer mapping"
    else if is_multisample value.descriptor.kind then
      error operation Unsupported "multisample textures do not support CPU transfer"
    else if mip_level < 0 || mip_level >= value.descriptor.mip_levels then
      invalid "mip level is outside the texture"
    else if slice < 0 || slice >= total_slices value.descriptor then
      invalid "slice is outside the texture"
    else if region.x < 0 || region.y < 0 || region.z < 0 || region.width <= 0
            || region.height <= 0 || region.depth <= 0
    then invalid "texture region coordinates and dimensions are invalid"
    else
      let width = mip_dimension value.descriptor.width mip_level in
      let height = mip_dimension value.descriptor.height mip_level in
      let depth = mip_dimension value.descriptor.depth mip_level in
      if region.x > width || region.width > width - region.x
         || region.y > height || region.height > height - region.y
         || region.z > depth || region.depth > depth - region.z
      then invalid "texture region exceeds the selected mip level"
      else
        let pixel_bytes = bytes_per_pixel value.descriptor.format in
        match checked_mul region.width pixel_bytes with
        | None -> invalid "texture row cardinality overflows an OCaml integer"
        | Some minimum_row
          when bytes_per_row < minimum_row || bytes_per_row mod pixel_bytes <> 0 ->
            invalid "texture row pitch is too small or not pixel-aligned"
        | Some _ ->
            (match checked_mul bytes_per_row region.height with
             | None -> invalid "texture image cardinality overflows an OCaml integer"
             | Some minimum_image when bytes_per_image < minimum_image ->
                 invalid "texture image pitch is smaller than its rows"
             | Some _ ->
                 match checked_mul bytes_per_image region.depth with
                 | None ->
                     invalid "texture transfer cardinality overflows an OCaml integer"
                 | Some total when total > Sys.max_string_length ->
                     invalid "texture transfer exceeds the maximum OCaml byte buffer"
                 | Some total -> Ok total)

  let transfer_tuple region ~mip_level ~slice ~source_offset ~bytes_per_row
      ~bytes_per_image =
    ( (region.x, region.y, region.z, region.width, region.height, region.depth)
    , mip_level
    , slice
    , source_offset
    , bytes_per_row
    , bytes_per_image )

  let write_bytes (value : t) ~region ~mip_level ~slice ?(src_offset = 0)
      ~bytes_per_row ~bytes_per_image bytes =
    on_main "Metal.Texture.write_bytes" (fun () ->
      match ensure_live "Metal.Texture.write_bytes" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_transfer "Metal.Texture.write_bytes" value ~region
               ~mip_level ~slice ~bytes_per_row ~bytes_per_image
           with
           | Error _ as failure -> failure
           | Ok total ->
               if src_offset < 0 || src_offset > Bytes.length bytes
                  || total > Bytes.length bytes - src_offset
               then
                 error "Metal.Texture.write_bytes" Invalid_argument
                   "source bytes do not contain the complete pitched region"
               else
                 match
                   Metal_raw.texture_write value.raw
                     (transfer_tuple region ~mip_level ~slice
                        ~source_offset:src_offset ~bytes_per_row ~bytes_per_image)
                     bytes
                 with
                 | Ok () -> Ok ()
                 | Error message ->
                     native_error "Metal.Texture.write_bytes" message))

  let read_bytes (value : t) ~region ~mip_level ~slice ~bytes_per_row
      ~bytes_per_image =
    on_main "Metal.Texture.read_bytes" (fun () ->
      match ensure_live "Metal.Texture.read_bytes" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_transfer "Metal.Texture.read_bytes" value ~region
               ~mip_level ~slice ~bytes_per_row ~bytes_per_image
           with
           | Error _ as failure -> failure
           | Ok _ ->
               match
                 Metal_raw.texture_read value.raw
                   (transfer_tuple region ~mip_level ~slice ~source_offset:0
                      ~bytes_per_row ~bytes_per_image)
               with
               | Ok bytes -> Ok bytes
               | Error message -> native_error "Metal.Texture.read_bytes" message))

  let compatible_view_format source target =
    source = target
    ||
    match source, target with
    | R8_unorm, R8_unorm_srgb | R8_unorm_srgb, R8_unorm
    | Rg8_unorm, Rg8_unorm_srgb | Rg8_unorm_srgb, Rg8_unorm
    | Rgba8_unorm, Rgba8_unorm_srgb | Rgba8_unorm_srgb, Rgba8_unorm
    | Bgra8_unorm, Bgra8_unorm_srgb | Bgra8_unorm_srgb, Bgra8_unorm -> true
    | _ -> false

  let create_view (parent : t) ~format ~base_mip ~mip_count ~base_slice
      ~slice_count ?label () =
    on_main "Metal.Texture.create_view" (fun () ->
      match ensure_live "Metal.Texture.create_view" parent.lifetime with
      | Error _ as failure -> failure
      | Ok () when not (List.mem Pixel_format_view parent.descriptor.usage) ->
          error "Metal.Texture.create_view" Invalid_argument
            "parent texture usage does not permit pixel-format views"
      | Ok () when not (compatible_view_format parent.descriptor.format format) ->
          error "Metal.Texture.create_view" Invalid_argument
            "requested texture-view format is not in a compatible format class"
      | Ok () when base_mip < 0 || mip_count <= 0
                   || base_mip > parent.descriptor.mip_levels
                   || mip_count > parent.descriptor.mip_levels - base_mip ->
          error "Metal.Texture.create_view" Invalid_argument
            "texture-view mip range is invalid"
      | Ok () when base_slice < 0 || slice_count <= 0
                   || base_slice > total_slices parent.descriptor
                   || slice_count > total_slices parent.descriptor - base_slice ->
          error "Metal.Texture.create_view" Invalid_argument
            "texture-view slice range is invalid"
      | Ok () when option_exists contains_nul label ->
          error "Metal.Texture.create_view" Invalid_argument
            "texture-view label contains a NUL byte"
      | Ok () ->
          let array_length =
            match parent.descriptor.kind with
            | Texture_cube_array -> slice_count / 6
            | kind when is_array kind -> slice_count
            | _ -> 1
          in
          let slice_shape_valid =
            match parent.descriptor.kind with
            | Texture_cube -> base_slice = 0 && slice_count = 6
            | Texture_cube_array -> base_slice mod 6 = 0 && slice_count mod 6 = 0
            | kind when is_array kind -> true
            | _ -> base_slice = 0 && slice_count = 1
          in
          if not slice_shape_valid then
            error "Metal.Texture.create_view" Invalid_argument
              "texture-view slices do not preserve the texture kind"
          else
            let descriptor : descriptor =
              { parent.descriptor with
                format
              ; width = mip_dimension parent.descriptor.width base_mip
              ; height = mip_dimension parent.descriptor.height base_mip
              ; depth = mip_dimension parent.descriptor.depth base_mip
              ; mip_levels = mip_count
              ; array_length
              ; label
              }
            in
            match
              Metal_raw.texture_create_view parent.raw
                ( format_code format
                , kind_code descriptor.kind
                , base_mip
                , mip_count
                , base_slice
                , slice_count )
                label
            with
            | Error message -> native_error "Metal.Texture.create_view" message
            | Ok raw ->
                finish_create "Metal.Texture.create_view" ~device:parent.device
                  ~descriptor ~parent_lifetime:parent.lifetime raw)

  let destroy (value : t) =
    destroy_parent "Metal.Texture.destroy" value.lifetime value.raw
      (fun () -> detach value.parent_lifetime)
end

module Sampler = struct
  type t = sampler
  type filter = sampler_filter = Nearest | Linear
  type mip_filter = sampler_mip_filter =
    | Not_mipmapped
    | Mip_nearest
    | Mip_linear

  type address_mode = sampler_address_mode =
    | Clamp_to_edge
    | Mirror_clamp_to_edge
    | Repeat
    | Mirror_repeat
    | Clamp_to_zero
    | Clamp_to_border_color

  type border_color = sampler_border_color =
    | Transparent_black
    | Opaque_black
    | Opaque_white

  type compare_function = sampler_compare_function =
    | Never
    | Less
    | Equal
    | Less_equal
    | Greater
    | Not_equal
    | Greater_equal
    | Always

  type descriptor = sampler_descriptor =
    { min_filter : filter
    ; mag_filter : filter
    ; mip_filter : mip_filter
    ; max_anisotropy : int
    ; s_address : address_mode
    ; t_address : address_mode
    ; r_address : address_mode
    ; border_color : border_color
    ; normalized_coordinates : bool
    ; lod_min_clamp : float
    ; lod_max_clamp : float
    ; lod_average : bool
    ; compare_function : compare_function
    ; support_argument_buffers : bool
    ; label : string option
    }

  let default ?label () =
    { min_filter = Nearest
    ; mag_filter = Nearest
    ; mip_filter = Not_mipmapped
    ; max_anisotropy = 1
    ; s_address = Clamp_to_edge
    ; t_address = Clamp_to_edge
    ; r_address = Clamp_to_edge
    ; border_color = Transparent_black
    ; normalized_coordinates = true
    ; lod_min_clamp = 0.
    ; lod_max_clamp = 3.402823466e38
    ; lod_average = false
    ; compare_function = Never
    ; support_argument_buffers = false
    ; label
    }

  let filter_code = function Nearest -> 0 | Linear -> 1

  let mip_code = function
    | Not_mipmapped -> 0
    | Mip_nearest -> 1
    | Mip_linear -> 2

  let address_code = function
    | Clamp_to_edge -> 0
    | Mirror_clamp_to_edge -> 1
    | Repeat -> 2
    | Mirror_repeat -> 3
    | Clamp_to_zero -> 4
    | Clamp_to_border_color -> 5

  let border_code = function
    | Transparent_black -> 0
    | Opaque_black -> 1
    | Opaque_white -> 2

  let compare_code = function
    | Never -> 0
    | Less -> 1
    | Equal -> 2
    | Less_equal -> 3
    | Greater -> 4
    | Not_equal -> 5
    | Greater_equal -> 6
    | Always -> 7

  let validate descriptor =
    let invalid message = error "Metal.Sampler.create" Invalid_argument message in
    if descriptor.max_anisotropy < 1 || descriptor.max_anisotropy > 16 then
      invalid "sampler anisotropy must be in [1, 16]"
    else if not (Float.is_finite descriptor.lod_min_clamp)
            || not (Float.is_finite descriptor.lod_max_clamp)
            || descriptor.lod_min_clamp < 0.
            || descriptor.lod_max_clamp < descriptor.lod_min_clamp
            || descriptor.lod_max_clamp > 3.402823466e38
    then invalid "sampler LOD clamps are invalid or exceed float32 range"
    else if option_exists contains_nul descriptor.label then
      invalid "sampler label contains a NUL byte"
    else if not descriptor.normalized_coordinates
            && (descriptor.s_address <> Clamp_to_edge
                || descriptor.t_address <> Clamp_to_edge
                || descriptor.r_address <> Clamp_to_edge
                || descriptor.mip_filter <> Not_mipmapped
                || descriptor.max_anisotropy <> 1)
    then
      invalid
        "unnormalized coordinates require clamp-to-edge, no mip filter, and anisotropy=1"
    else Ok ()

  let descriptor_tuple descriptor =
    ( filter_code descriptor.min_filter
    , filter_code descriptor.mag_filter
    , mip_code descriptor.mip_filter
    , descriptor.max_anisotropy
    , address_code descriptor.s_address
    , address_code descriptor.t_address
    , address_code descriptor.r_address
    , border_code descriptor.border_color
    , descriptor.normalized_coordinates
    , descriptor.lod_min_clamp
    , descriptor.lod_max_clamp
    , descriptor.lod_average
    , compare_code descriptor.compare_function
    , descriptor.support_argument_buffers )

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Sampler.create" (fun () ->
      match ensure_live "Metal.Sampler.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate descriptor with
           | Error _ as failure -> failure
           | Ok () ->
               match
                 Metal_raw.sampler_create device.raw (descriptor_tuple descriptor)
                   descriptor.label
               with
               | Error message -> native_error "Metal.Sampler.create" message
               | Ok raw ->
                   let value : t =
                     { raw; lifetime = lifetime (); device; descriptor }
                   in
                   attach device.lifetime;
                   attach_finalizer value value.lifetime device.lifetime;
                   Ok value))

  let device (value : t) = value.device
  let descriptor (value : t) = value.descriptor
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Sampler.label" (fun () ->
      match ensure_live "Metal.Sampler.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.sampler_label value.raw))

  let destroy (value : t) =
    destroy_leaf "Metal.Sampler.destroy" value.lifetime value.raw
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
