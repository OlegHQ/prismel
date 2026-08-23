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
    ; external_deallocations : int64
    ; external_deallocation_mismatches : int64
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
            ; external_deallocations = Metal_raw.external_deallocations ()
            ; external_deallocation_mismatches =
                Metal_raw.external_deallocation_mismatches ()
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

let finalize_child lifetime parent on_finalize =
  if Atomic.compare_and_set lifetime.destroyed false true then begin
    on_finalize ();
    detach parent
  end

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

type buffer_storage_mode =
  | Shared
  | Managed
  | Private

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

type pixel_format = Metal_format.t

type resource_cpu_cache_mode =
  | Default_cache
  | Write_combined

type resource_hazard_tracking_mode =
  | Default_hazard_tracking
  | Untracked
  | Tracked

type purgeable_state =
  | Nonvolatile
  | Volatile
  | Empty

type sparse_page_size =
  | Page_16_kib
  | Page_64_kib
  | Page_256_kib

type resource_state =
  { relinquished : bool Atomic.t
  ; purgeable : purgeable_state Atomic.t
  }

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

type heap_kind =
  | Automatic
  | Placement
  | Sparse

type heap_descriptor =
  { size : int64
  ; storage : buffer_storage_mode
  ; cpu_cache : resource_cpu_cache_mode
  ; hazard_tracking : resource_hazard_tracking_mode
  ; kind : heap_kind
  ; sparse_page_size : sparse_page_size option
  ; label : string option
  }

type heap_allocation =
  { offset : int64
  ; size : int64
  ; active : bool Atomic.t
  }

type io_surface_plane =
  { width : int
  ; height : int
  ; bytes_per_element : int
  ; bytes_per_row : int
  ; size : int64
  }

type io_surface =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; id : int64
  ; allocation_size : int64
  ; planar : bool
  ; planes : io_surface_plane array
  ; label : string option
  }

type heap =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : heap_descriptor
  ; allocations : heap_allocation list ref
  ; purgeable : purgeable_state Atomic.t
  ; active_uses : int Atomic.t
  }

and external_memory =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; length : int64
  ; alignment : int64
  }

and resource_parent =
  | Device_resource of device
  | Heap_resource of heap
  | External_resource of external_memory

and buffer =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; length : int64
  ; storage : buffer_storage_mode
  ; cpu_cache : resource_cpu_cache_mode
  ; hazard_tracking : resource_hazard_tracking_mode
  ; parent : resource_parent
  ; heap_offset : int64 option
  ; allocation : heap_allocation option
  ; state : resource_state
  }

and texture =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : texture_descriptor
  ; parent : texture_parent
  ; heap_offset : int64 option
  ; allocation : heap_allocation option
  ; state : resource_state
  }

and buffer_texture_backing =
  { buffer : buffer
  ; offset : int64
  ; bytes_per_row : int
  }

and texture_io_surface_backing =
  { surface : io_surface
  ; plane : int
  }

and texture_parent =
  | Texture_resource of resource_parent
  | Texture_buffer_resource of buffer_texture_backing
  | Texture_io_surface_resource of texture_io_surface_backing
  | Texture_view of texture

type shared_texture_handle =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : texture_descriptor
  ; label : string option
  }

type buffer_mapping =
  { buffer : buffer
  ; offset : int64
  ; length : int
  ; active : bool Atomic.t
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

type residency_allocation =
  | Buffer of buffer
  | Texture of texture
  | Heap of heap

type residency_member =
  { allocation : residency_allocation
  ; mutable present : bool
  }

type residency_descriptor =
  { label : string option
  ; initial_capacity : int
  }

type residency_set =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; members : (int64, residency_member) Hashtbl.t
  }

type command_queue =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; residency_sets : residency_set list ref
  }

type command_phase =
  | Recording
  | Submitted

type command_resource =
  | Command_buffer_buffer of buffer
  | Command_buffer_texture of texture
  | Command_residency_set of residency_set

type command_buffer =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; queue : command_queue
  ; mutable phase : command_phase
  ; resources : command_resource list ref
  }

type compute_encoder =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; command_buffer : command_buffer
  ; mutable pipeline : compute_pipeline option
  }

type resource_state_encoder =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; command_buffer : command_buffer
  }

type blit_encoder =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; command_buffer : command_buffer
  }

let make_device raw =
  ({ raw; lifetime = lifetime (); registry_id = Metal_raw.device_registry_id raw }
    : device)

let attach_finalizer ?(on_finalize = fun () -> ()) value lifetime parent =
  Gc.finalise (fun _ -> finalize_child lifetime parent on_finalize) value

let command_resource_lifetime = function
  | Command_buffer_buffer buffer -> buffer.lifetime
  | Command_buffer_texture texture -> texture.lifetime
  | Command_residency_set residency_set -> residency_set.lifetime

let rec command_texture_heap (value : texture) =
  match value.parent with
  | Texture_resource (Heap_resource heap) -> Some heap
  | Texture_resource (Device_resource _ | External_resource _)
  | Texture_io_surface_resource _ -> None
  | Texture_buffer_resource backing ->
      (match backing.buffer.parent with
       | Heap_resource heap -> Some heap
       | Device_resource _ | External_resource _ -> None)
  | Texture_view parent -> command_texture_heap parent

let command_resource_heap = function
  | Command_buffer_buffer { parent = Heap_resource heap; _ } -> Some heap
  | Command_buffer_buffer
      { parent = (Device_resource _ | External_resource _); _ } -> None
  | Command_buffer_texture texture -> command_texture_heap texture
  | Command_residency_set _ -> None

let release_command_resources resources =
  let retained = !resources in
  resources := [];
  List.iter
    (fun resource ->
      detach (command_resource_lifetime resource);
      Option.iter (fun heap -> Atomic.decr heap.active_uses)
        (command_resource_heap resource))
    retained

let retain_command_buffer_buffer (command_buffer : command_buffer) (buffer : buffer) =
  let already_retained =
    List.exists
      (function
        | Command_buffer_buffer retained -> retained.lifetime == buffer.lifetime
        | Command_buffer_texture _ -> false
        | Command_residency_set _ -> false)
      !(command_buffer.resources)
  in
  if not already_retained then begin
    attach buffer.lifetime;
    Option.iter (fun heap -> Atomic.incr heap.active_uses)
      (match buffer.parent with
       | Device_resource _ | External_resource _ -> None
       | Heap_resource heap -> Some heap);
    command_buffer.resources :=
      Command_buffer_buffer buffer :: !(command_buffer.resources)
  end

let retain_command_buffer_texture (command_buffer : command_buffer)
    (texture : texture) =
  let already_retained =
    List.exists
      (function
        | Command_buffer_texture retained ->
            retained.lifetime == texture.lifetime
        | Command_buffer_buffer _ | Command_residency_set _ -> false)
      !(command_buffer.resources)
  in
  if not already_retained then begin
    attach texture.lifetime;
    Option.iter (fun heap -> Atomic.incr heap.active_uses)
      (command_texture_heap texture);
    command_buffer.resources :=
      Command_buffer_texture texture :: !(command_buffer.resources)
  end

let retain_command_buffer_residency_set (command_buffer : command_buffer)
    (residency_set : residency_set) =
  let already_retained =
    List.exists
      (function
        | Command_residency_set retained ->
            retained.lifetime == residency_set.lifetime
        | Command_buffer_buffer _ | Command_buffer_texture _ -> false)
      !(command_buffer.resources)
  in
  if not already_retained then begin
    attach residency_set.lifetime;
    command_buffer.resources :=
      Command_residency_set residency_set :: !(command_buffer.resources)
  end

let release_queue_residency_sets residency_sets =
  let retained = !residency_sets in
  residency_sets := [];
  List.iter (fun (value : residency_set) -> detach value.lifetime) retained

let deactivate_allocation (value : heap_allocation option) =
  match value with
  | None -> ()
  | Some allocation -> Atomic.set allocation.active false

let resource_parent_lifetime = function
  | Device_resource device -> device.lifetime
  | Heap_resource heap -> heap.lifetime
  | External_resource memory -> memory.lifetime

let resource_parent_extra_device (device : device) = function
  | External_resource _ -> Some device.lifetime
  | Device_resource _ | Heap_resource _ -> None

let texture_parent_lifetime = function
  | Texture_resource parent -> resource_parent_lifetime parent
  | Texture_buffer_resource backing -> backing.buffer.lifetime
  | Texture_io_surface_resource backing -> backing.surface.lifetime
  | Texture_view texture -> texture.lifetime

let texture_parent_extra_device (device : device) = function
  | Texture_resource parent -> resource_parent_extra_device device parent
  | Texture_io_surface_resource _ -> Some device.lifetime
  | Texture_buffer_resource _ | Texture_view _ -> None

let resource_state () =
  { relinquished = Atomic.make false; purgeable = Atomic.make Nonvolatile }

let purgeable_code = function
  | Nonvolatile -> 2
  | Volatile -> 3
  | Empty -> 4

let purgeable_state_of_code operation = function
  | 2 -> Ok Nonvolatile
  | 3 -> Ok Volatile
  | 4 -> Ok Empty
  | code ->
      native_error operation (Printf.sprintf "unknown purgeable state %d" code)

let query_purgeable_state operation call tracked =
  match call 1 with
  | Error message -> native_error operation message
  | Ok code ->
      (match purgeable_state_of_code operation code with
       | Error _ as failure -> failure
       | Ok state -> Atomic.set tracked state; Ok state)

let apply_purgeable_state operation call tracked state =
  match call (purgeable_code state) with
  | Error message -> native_error operation message
  | Ok code ->
      (match purgeable_state_of_code operation code with
       | Error _ as failure -> failure
       | Ok previous ->
           Atomic.set tracked state;
           (match query_purgeable_state operation call tracked with
            | Error _ as failure -> failure
            | Ok _current -> Ok previous))

let parent_heap = function
  | Device_resource _ | External_resource _ -> None
  | Heap_resource heap -> Some heap

let rec texture_heap (value : texture) =
  match value.parent with
  | Texture_resource parent -> parent_heap parent
  | Texture_buffer_resource backing -> parent_heap backing.buffer.parent
  | Texture_io_surface_resource _ -> None
  | Texture_view parent -> texture_heap parent

let ensure_heap_nonvolatile operation = function
  | Some heap when Atomic.get heap.purgeable <> Nonvolatile ->
      error operation Invalid_state "resource heap must be nonvolatile"
  | None | Some _ -> Ok ()

let ensure_resource_usable operation state heap =
  if Atomic.get state.relinquished then
    error operation Invalid_state "resource has relinquished its storage for aliasing"
  else
    match Atomic.get state.purgeable with
    | Volatile ->
        error operation Invalid_state
          "resource is volatile and must be restored before access"
    | Empty ->
        error operation Invalid_state
          "resource contents are empty and must be restored before access"
    | Nonvolatile ->
        (match ensure_heap_nonvolatile operation heap with
         | Error _ as failure -> failure
         | Ok () -> Ok ())

let ensure_buffer_usable operation (value : buffer) =
  match ensure_live operation value.lifetime with
  | Error _ as failure -> failure
  | Ok () -> ensure_resource_usable operation value.state (parent_heap value.parent)

let ensure_texture_usable operation (value : texture) =
  match ensure_live operation value.lifetime with
  | Error _ as failure -> failure
  | Ok () -> ensure_resource_usable operation value.state (texture_heap value)

let same_device left right = Int64.equal left.registry_id right.registry_id

let ensure_same_device operation expected actual =
  if same_device expected actual then Ok ()
  else
    error operation Device_mismatch
      "resources belong to different Metal devices"

let storage_code = function Shared -> 0 | Managed -> 1 | Private -> 2
let cache_code = function Default_cache -> 0 | Write_combined -> 1

let hazard_code = function
  | Default_hazard_tracking -> 0
  | Untracked -> 1
  | Tracked -> 2

let resource_options_code ~storage ~cpu_cache ~hazard_tracking =
  cache_code cpu_cache lor (storage_code storage lsl 4)
  lor (hazard_code hazard_tracking lsl 8)

let concrete_hazard_tracking ~heap = function
  | Default_hazard_tracking -> if heap then Untracked else Tracked
  | (Untracked | Tracked) as mode -> mode

let cache_mode_of_code operation = function
  | 0 -> Ok Default_cache
  | 1 -> Ok Write_combined
  | code -> native_error operation (Printf.sprintf "unknown CPU cache mode %d" code)

let hazard_mode_of_code operation = function
  | 0 -> Ok Default_hazard_tracking
  | 1 -> Ok Untracked
  | 2 -> Ok Tracked
  | code ->
      native_error operation (Printf.sprintf "unknown hazard tracking mode %d" code)

module Sparse_page_size = struct
  type t = sparse_page_size =
    | Page_16_kib
    | Page_64_kib
    | Page_256_kib

  let bytes = function
    | Page_16_kib -> 16_384L
    | Page_64_kib -> 65_536L
    | Page_256_kib -> 262_144L
end

let sparse_page_size_code = function
  | Page_16_kib -> 101
  | Page_64_kib -> 102
  | Page_256_kib -> 103

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

  let supports_depth24_stencil8 (value : t) =
    on_main "Metal.Device.supports_depth24_stencil8" (fun () ->
      match ensure_live "Metal.Device.supports_depth24_stencil8" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_depth24_stencil8 value.raw))

  let supports_bc_texture_compression (value : t) =
    on_main "Metal.Device.supports_bc_texture_compression" (fun () ->
      match
        ensure_live "Metal.Device.supports_bc_texture_compression" value.lifetime
      with
      | Error _ as failure -> failure
      | Ok () ->
          Ok (Metal_raw.device_supports_bc_texture_compression value.raw))

  let supports_residency_sets (value : t) =
    on_main "Metal.Device.supports_residency_sets" (fun () ->
      match ensure_live "Metal.Device.supports_residency_sets" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_residency_sets value.raw))

  let supports_sparse_textures (value : t) =
    on_main "Metal.Device.supports_sparse_textures" (fun () ->
      match ensure_live "Metal.Device.supports_sparse_textures" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_sparse_textures value.raw))

  let destroy (value : t) =
    destroy_parent "Metal.Device.destroy" value.lifetime value.raw (fun () -> ())
end

module Buffer = struct
  type t = buffer
  type storage_mode = buffer_storage_mode = Shared | Managed | Private
  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined
  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  module External = struct
    type t = external_memory

    let page_size () =
      on_main "Metal.Buffer.External.page_size" (fun () ->
        let page_size = Metal_raw.external_memory_page_size () in
        if page_size <= 0 then
          native_error "Metal.Buffer.External.page_size"
            "native VM page size is not positive"
        else Ok page_size)

    let create ~length =
      on_main "Metal.Buffer.External.create" (fun () ->
        let page_size = Metal_raw.external_memory_page_size () in
        if length <= 0L then
          error "Metal.Buffer.External.create" Invalid_argument
            "external-memory length must be positive"
        else if page_size <= 0 then
          native_error "Metal.Buffer.External.create"
            "native VM page size is not positive"
        else if Int64.rem length (Int64.of_int page_size) <> 0L then
          error "Metal.Buffer.External.create" Invalid_argument
            "external-memory length must be a whole number of VM pages"
        else
          match Metal_raw.external_memory_create length with
          | Error message -> native_error "Metal.Buffer.External.create" message
          | Ok raw ->
              let actual_length, alignment =
                Metal_raw.external_memory_info raw
              in
              if actual_length <> length
                 || alignment <> Int64.of_int page_size
              then begin
                ignore (Metal_raw.destroy raw);
                native_error "Metal.Buffer.External.create"
                  "native external memory changed its checked page layout"
              end
              else
                Ok { raw; lifetime = lifetime (); length; alignment })

    let generation (value : t) = Metal_raw.generation value.raw
    let length (value : t) = value.length
    let alignment (value : t) = value.alignment
    let destroyed (value : t) = is_destroyed value.lifetime

    let validate_range operation (value : t) ~offset ~length =
      if offset < 0L || length < 0 then
        error operation Invalid_argument "external-memory range is negative"
      else
        let length64 = Int64.of_int length in
        if offset > value.length || length64 > Int64.sub value.length offset then
          error operation Invalid_argument
            "external-memory range exceeds its allocation"
        else Ok ()

    let ensure_exclusive operation (value : t) =
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when dependent_count value.lifetime <> 0 ->
          error operation Parent_has_dependents
            "external memory is borrowed by a no-copy Metal buffer"
      | Ok () -> Ok ()

    let write_bytes (value : t) ?(src_offset = 0) ~dst_offset bytes =
      on_main "Metal.Buffer.External.write_bytes" (fun () ->
        match ensure_exclusive "Metal.Buffer.External.write_bytes" value with
        | Error _ as failure -> failure
        | Ok () ->
            let source_length = Bytes.length bytes in
            if src_offset < 0 || src_offset > source_length then
              error "Metal.Buffer.External.write_bytes" Invalid_argument
                "source offset is outside the byte buffer"
            else
              let length = source_length - src_offset in
              (match
                 validate_range "Metal.Buffer.External.write_bytes" value
                   ~offset:dst_offset ~length
               with
               | Error _ as failure -> failure
               | Ok () ->
                   (match
                      Metal_raw.external_memory_write value.raw dst_offset bytes
                        src_offset length
                    with
                    | Ok () -> Ok ()
                    | Error message ->
                        native_error "Metal.Buffer.External.write_bytes"
                          message)))

    let read_bytes (value : t) ~offset ~length =
      on_main "Metal.Buffer.External.read_bytes" (fun () ->
        match ensure_exclusive "Metal.Buffer.External.read_bytes" value with
        | Error _ as failure -> failure
        | Ok () when length > Sys.max_string_length ->
            error "Metal.Buffer.External.read_bytes" Invalid_argument
              "read length exceeds the maximum OCaml byte-buffer size"
        | Ok () ->
            (match
               validate_range "Metal.Buffer.External.read_bytes" value ~offset
                 ~length
             with
             | Error _ as failure -> failure
             | Ok () ->
                 (match
                    Metal_raw.external_memory_read value.raw offset length
                  with
                  | Ok bytes -> Ok bytes
                  | Error message ->
                      native_error "Metal.Buffer.External.read_bytes"
                        message)))

    let destroy (value : t) =
      destroy_parent "Metal.Buffer.External.destroy" value.lifetime value.raw
        (fun () -> ())
  end

  let validate_create operation (device : Device.t) ~length ~label =
    if length <= 0L then
      error operation Invalid_argument "buffer length must be positive"
    else if length > Metal_raw.device_max_buffer_length device.raw then
      error operation Invalid_argument "buffer length exceeds the device limit"
    else if option_exists contains_nul label then
      error operation Invalid_argument "label contains a NUL byte"
    else Ok ()

  let finish_create operation ~(device : Device.t) ~parent ~length ~storage
      ~cpu_cache ~hazard_tracking ~heap_offset ~allocation ~label raw =
    let actual_length, actual_storage, actual_cache, actual_hazard, actual_offset =
      Metal_raw.buffer_info raw
    in
    let expected_hazard =
      concrete_hazard_tracking
        ~heap:
          (match parent with
           | Heap_resource _ -> true
           | Device_resource _ | External_resource _ -> false)
        hazard_tracking
    in
    if actual_length <> length || actual_storage <> storage_code storage
       || actual_cache <> cache_code cpu_cache
       || actual_hazard <> hazard_code expected_hazard
       || option_exists (fun expected -> expected <> actual_offset) heap_offset
    then begin
      ignore (Metal_raw.destroy raw);
      native_error operation "Metal changed checked buffer properties during creation"
    end
    else
      let label_result =
        match label with
        | None -> Ok ()
        | Some label -> Metal_raw.buffer_set_label raw label
      in
      match label_result with
      | Error message ->
          ignore (Metal_raw.destroy raw);
          native_error operation message
      | Ok () ->
          let parent_lifetime = resource_parent_lifetime parent in
          let value : t =
            { raw
            ; lifetime = lifetime ()
            ; device
            ; length
            ; storage
            ; cpu_cache
            ; hazard_tracking = expected_hazard
            ; parent
            ; heap_offset
            ; allocation
            ; state = resource_state ()
            }
          in
          attach parent_lifetime;
          let extra_device = resource_parent_extra_device device parent in
          Option.iter attach extra_device;
          attach_finalizer
            ~on_finalize:(fun () ->
              deactivate_allocation allocation;
              Option.iter detach extra_device)
            value value.lifetime parent_lifetime;
          Ok value

  let create ~(device : Device.t) ~length ~storage ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?label () =
    on_main "Metal.Buffer.create" (fun () ->
      match ensure_live "Metal.Buffer.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_create "Metal.Buffer.create" device ~length ~label with
           | Error _ as failure -> failure
           | Ok () ->
               let options =
                 resource_options_code ~storage ~cpu_cache ~hazard_tracking
               in
               match Metal_raw.buffer_create device.raw length options with
               | Error message -> native_error "Metal.Buffer.create" message
               | Ok raw ->
                   finish_create "Metal.Buffer.create" ~device
                     ~parent:(Device_resource device) ~length ~storage ~cpu_cache
                   ~hazard_tracking ~heap_offset:None ~allocation:None ~label
                   raw))

  let create_copy ~(device : Device.t) ~storage
      ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?label ?(src_offset = 0)
      ?length bytes =
    on_main "Metal.Buffer.create_copy" (fun () ->
      match ensure_live "Metal.Buffer.create_copy" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          let source_length = Bytes.length bytes in
          if src_offset < 0 || src_offset > source_length then
            error "Metal.Buffer.create_copy" Invalid_argument
              "source offset is outside the byte buffer"
          else
            let length =
              Option.value length ~default:(source_length - src_offset)
            in
            if length <= 0 || length > source_length - src_offset then
              error "Metal.Buffer.create_copy" Invalid_argument
                "buffer copy range is empty or exceeds the source bytes"
            else
              let length64 = Int64.of_int length in
              (match
                 validate_create "Metal.Buffer.create_copy" device
                   ~length:length64 ~label
               with
               | Error _ as failure -> failure
               | Ok () ->
                   let options =
                     resource_options_code ~storage ~cpu_cache ~hazard_tracking
                   in
                   match
                     Metal_raw.buffer_create_copy device.raw bytes src_offset
                       length options
                   with
                   | Error message ->
                       native_error "Metal.Buffer.create_copy" message
                   | Ok raw ->
                       finish_create "Metal.Buffer.create_copy" ~device
                         ~parent:(Device_resource device) ~length:length64
                         ~storage ~cpu_cache ~hazard_tracking ~heap_offset:None
                         ~allocation:None ~label raw))

  let create_no_copy ~(device : Device.t) ~(memory : External.t) ~storage
      ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?label () =
    on_main "Metal.Buffer.create_no_copy" (fun () ->
      match ensure_live "Metal.Buffer.create_no_copy" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live "Metal.Buffer.create_no_copy" memory.lifetime with
           | Error _ as failure -> failure
           | Ok () when dependent_count memory.lifetime <> 0 ->
               error "Metal.Buffer.create_no_copy" Parent_has_dependents
                 "external memory is already borrowed by a Metal buffer"
           | Ok () when storage = Private ->
               error "Metal.Buffer.create_no_copy" Unsupported
                 "no-copy buffers cannot use private storage"
           | Ok () ->
               (match
                  validate_create "Metal.Buffer.create_no_copy" device
                    ~length:memory.length ~label
                with
                | Error _ as failure -> failure
                | Ok () ->
                    let options =
                      resource_options_code ~storage ~cpu_cache
                        ~hazard_tracking
                    in
                    match
                      Metal_raw.buffer_create_no_copy device.raw memory.raw
                        options
                    with
                    | Error message ->
                        native_error "Metal.Buffer.create_no_copy" message
                    | Ok raw ->
                        finish_create "Metal.Buffer.create_no_copy" ~device
                          ~parent:(External_resource memory)
                          ~length:memory.length ~storage ~cpu_cache
                          ~hazard_tracking ~heap_offset:None ~allocation:None
                          ~label raw)))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let length (value : t) = value.length
  let storage_mode (value : t) = value.storage
  let cpu_cache_mode (value : t) = value.cpu_cache
  let hazard_tracking_mode (value : t) = value.hazard_tracking
  let heap_offset (value : t) = value.heap_offset
  let external_memory (value : t) =
    match value.parent with
    | External_resource memory -> Some memory
    | Device_resource _ | Heap_resource _ -> None
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
      match ensure_buffer_usable "Metal.Buffer.write_bytes" value with
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
      match ensure_buffer_usable "Metal.Buffer.read_bytes" value with
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
      | Ok () -> ensure_buffer_usable operation value.buffer

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
      match ensure_buffer_usable "Metal.Buffer.with_mapping" value with
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
               let heap = parent_heap value.parent in
               Option.iter (fun heap -> Atomic.incr heap.active_uses) heap;
               Fun.protect
                 ~finally:(fun () ->
                   Atomic.set mapping.active false;
                   detach value.lifetime;
                   Option.iter (fun heap -> Atomic.decr heap.active_uses) heap)
                 (fun () -> Ok (callback mapping))))

  let purgeable_state (value : t) =
    on_main "Metal.Buffer.purgeable_state" (fun () ->
      match ensure_live "Metal.Buffer.purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          query_purgeable_state "Metal.Buffer.purgeable_state"
            (Metal_raw.resource_set_purgeable_state value.raw)
            value.state.purgeable)

  let set_purgeable_state (value : t) state =
    on_main "Metal.Buffer.set_purgeable_state" (fun () ->
      match ensure_live "Metal.Buffer.set_purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.state.relinquished ->
          error "Metal.Buffer.set_purgeable_state" Invalid_state
            "an aliasable resource cannot change purgeability"
      | Ok () when dependent_count value.lifetime <> 0 ->
          error "Metal.Buffer.set_purgeable_state" Parent_has_dependents
            "buffer has an active mapping, texture, or command dependency"
      | Ok () ->
          (match
             ensure_heap_nonvolatile "Metal.Buffer.set_purgeable_state"
               (parent_heap value.parent)
           with
           | Error _ as failure -> failure
           | Ok () ->
               apply_purgeable_state "Metal.Buffer.set_purgeable_state"
                 (Metal_raw.resource_set_purgeable_state value.raw)
                 value.state.purgeable state))

  let is_aliasable (value : t) =
    on_main "Metal.Buffer.is_aliasable" (fun () ->
      match ensure_live "Metal.Buffer.is_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.resource_is_aliasable value.raw))

  let make_aliasable (value : t) =
    on_main "Metal.Buffer.make_aliasable" (fun () ->
      match ensure_live "Metal.Buffer.make_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.state.relinquished -> Ok ()
      | Ok () when Atomic.get value.state.purgeable <> Nonvolatile ->
          error "Metal.Buffer.make_aliasable" Invalid_state
            "buffer must be nonvolatile before becoming aliasable"
      | Ok () when dependent_count value.lifetime <> 0 ->
          error "Metal.Buffer.make_aliasable" Parent_has_dependents
            "buffer has an active mapping, texture, or command dependency"
      | Ok () ->
          (match value.parent with
           | Device_resource _ ->
               error "Metal.Buffer.make_aliasable" Invalid_state
                 "only heap-backed buffers can become aliasable"
           | External_resource _ ->
               error "Metal.Buffer.make_aliasable" Invalid_state
                 "externally backed buffers cannot become aliasable"
           | Heap_resource heap ->
               (match
                  ensure_heap_nonvolatile "Metal.Buffer.make_aliasable"
                    (Some heap)
                with
                | Error _ as failure -> failure
                | Ok () ->
                    match Metal_raw.resource_make_aliasable value.raw with
                    | Error message ->
                        native_error "Metal.Buffer.make_aliasable" message
                    | Ok () ->
                        if not (Metal_raw.resource_is_aliasable value.raw) then
                          native_error "Metal.Buffer.make_aliasable"
                            "Metal did not make the heap buffer aliasable"
                        else begin
                          Atomic.set value.state.relinquished true;
                          deactivate_allocation value.allocation;
                          Ok ()
                        end)))

  let destroy (value : t) =
    destroy_parent "Metal.Buffer.destroy" value.lifetime value.raw
      (fun () ->
        deactivate_allocation value.allocation;
        detach (resource_parent_lifetime value.parent);
        Option.iter detach
          (resource_parent_extra_device value.device value.parent))
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

  type format = Metal_format.t =
    | A8_unorm
    | R8_unorm
    | R8_unorm_srgb
    | R8_snorm
    | R8_uint
    | R8_sint
    | R16_unorm
    | R16_snorm
    | R16_uint
    | R16_sint
    | R16_float
    | Rg8_unorm
    | Rg8_unorm_srgb
    | Rg8_snorm
    | Rg8_uint
    | Rg8_sint
    | B5g6r5_unorm
    | A1bgr5_unorm
    | Abgr4_unorm
    | Bgr5a1_unorm
    | R32_uint
    | R32_sint
    | R32_float
    | Rg16_unorm
    | Rg16_snorm
    | Rg16_uint
    | Rg16_sint
    | Rg16_float
    | Rgba8_unorm
    | Rgba8_unorm_srgb
    | Rgba8_snorm
    | Rgba8_uint
    | Rgba8_sint
    | Bgra8_unorm
    | Bgra8_unorm_srgb
    | Rgb10a2_unorm
    | Rgb10a2_uint
    | Rg11b10_float
    | Rgb9e5_float
    | Bgr10a2_unorm
    | Bgr10_xr
    | Bgr10_xr_srgb
    | Rg32_uint
    | Rg32_sint
    | Rg32_float
    | Rgba16_unorm
    | Rgba16_snorm
    | Rgba16_uint
    | Rgba16_sint
    | Rgba16_float
    | Bgra10_xr
    | Bgra10_xr_srgb
    | Rgba32_uint
    | Rgba32_sint
    | Rgba32_float
    | Bc1_rgba
    | Bc1_rgba_srgb
    | Bc2_rgba
    | Bc2_rgba_srgb
    | Bc3_rgba
    | Bc3_rgba_srgb
    | Bc4_r_unorm
    | Bc4_r_snorm
    | Bc5_rg_unorm
    | Bc5_rg_snorm
    | Bc6h_rgb_float
    | Bc6h_rgb_ufloat
    | Bc7_rgba_unorm
    | Bc7_rgba_unorm_srgb
    | Eac_r11_unorm
    | Eac_r11_snorm
    | Eac_rg11_unorm
    | Eac_rg11_snorm
    | Eac_rgba8
    | Eac_rgba8_srgb
    | Etc2_rgb8
    | Etc2_rgb8_srgb
    | Etc2_rgb8a1
    | Etc2_rgb8a1_srgb
    | Astc_4x4_srgb
    | Astc_5x4_srgb
    | Astc_5x5_srgb
    | Astc_6x5_srgb
    | Astc_6x6_srgb
    | Astc_8x5_srgb
    | Astc_8x6_srgb
    | Astc_8x8_srgb
    | Astc_10x5_srgb
    | Astc_10x6_srgb
    | Astc_10x8_srgb
    | Astc_10x10_srgb
    | Astc_12x10_srgb
    | Astc_12x12_srgb
    | Astc_4x4_ldr
    | Astc_5x4_ldr
    | Astc_5x5_ldr
    | Astc_6x5_ldr
    | Astc_6x6_ldr
    | Astc_8x5_ldr
    | Astc_8x6_ldr
    | Astc_8x8_ldr
    | Astc_10x5_ldr
    | Astc_10x6_ldr
    | Astc_10x8_ldr
    | Astc_10x10_ldr
    | Astc_12x10_ldr
    | Astc_12x12_ldr
    | Astc_4x4_hdr
    | Astc_5x4_hdr
    | Astc_5x5_hdr
    | Astc_6x5_hdr
    | Astc_6x6_hdr
    | Astc_8x5_hdr
    | Astc_8x6_hdr
    | Astc_8x8_hdr
    | Astc_10x5_hdr
    | Astc_10x6_hdr
    | Astc_10x8_hdr
    | Astc_10x10_hdr
    | Astc_12x10_hdr
    | Astc_12x12_hdr
    | Gbgr422
    | Bgrg422
    | Depth16_unorm
    | Depth32_float
    | Stencil8
    | Depth24_unorm_stencil8
    | Depth32_float_stencil8
    | X32_stencil8
    | X24_stencil8

  type format_layout = Metal_format.layout =
    { block_width : int
    ; block_height : int
    ; bytes_per_block : int
    }

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

  type sparse_info =
    { page_size : Sparse_page_size.t
    ; tile_width : int
    ; tile_height : int
    ; tile_depth : int
    ; tile_size_in_bytes : int64
    ; first_mip_in_tail : int option
    ; tail_size_in_bytes : int64
    }

  type buffer_backing = buffer_texture_backing =
    { buffer : Buffer.t
    ; offset : int64
    ; bytes_per_row : int
    }

  module Io_surface = struct
    type t = io_surface

    type plane_descriptor =
      { width : int
      ; height : int
      ; bytes_per_element : int
      }

    type plane = io_surface_plane =
      { width : int
      ; height : int
      ; bytes_per_element : int
      ; bytes_per_row : int
      ; size : int64
      }

    let plane_descriptor ~width ~height ~bytes_per_element =
      { width; height; bytes_per_element }

    let validate_plane operation index (plane : plane_descriptor) =
      let invalid message =
        error operation Invalid_argument
          (Printf.sprintf "IOSurface plane %d %s" index message)
      in
      if plane.width <= 0 || plane.height <= 0 then
        invalid "dimensions must be positive"
      else if
        not
          (List.mem plane.bytes_per_element [ 1; 2; 4; 8; 16 ])
      then
        invalid "element width must be 1, 2, 4, 8, or 16 bytes"
      else if plane.width > max_int / plane.bytes_per_element then
        invalid "row cardinality overflows an OCaml integer"
      else
        let minimum_row = plane.width * plane.bytes_per_element in
        if plane.height > max_int / minimum_row then
          invalid "plane cardinality overflows an OCaml integer"
        else Ok ()

    let finish_create operation ~requested_planar
        ~(requested_planes : plane_descriptor array) ~label raw =
      let id, allocation_size, planar, layout =
        Metal_raw.io_surface_info raw
      in
      let count = Array.length requested_planes in
      if id <= 0L || allocation_size <= 0L then begin
        ignore (Metal_raw.destroy raw);
        native_error operation "IOSurface returned an invalid identity or size"
      end
      else if planar <> requested_planar || Array.length layout <> count * 4 then begin
        ignore (Metal_raw.destroy raw);
        native_error operation "IOSurface changed its checked plane cardinality"
      end
      else begin
        let rec collect index total reversed =
          if index = count then Ok (Array.of_list (List.rev reversed), total)
          else
            let requested = requested_planes.(index) in
            let offset = index * 4 in
            let width = layout.(offset) in
            let height = layout.(offset + 1) in
            let bytes_per_element = layout.(offset + 2) in
            let bytes_per_row = layout.(offset + 3) in
            if
              width <> requested.width || height <> requested.height
              || bytes_per_element <> requested.bytes_per_element
              || bytes_per_row < width * bytes_per_element
              || bytes_per_row mod bytes_per_element <> 0
              || height > max_int / bytes_per_row
            then Error "IOSurface changed its checked plane layout"
            else
              let size = Int64.of_int (height * bytes_per_row) in
              if Int64.sub Int64.max_int total < size then
                Error "IOSurface plane cardinality exceeds 64 bits"
              else
                collect (index + 1) (Int64.add total size)
                  ({ width; height; bytes_per_element; bytes_per_row; size }
                   :: reversed)
        in
        match collect 0 0L [] with
        | Error message ->
            ignore (Metal_raw.destroy raw);
            native_error operation message
        | Ok (_, total) when allocation_size < total ->
            ignore (Metal_raw.destroy raw);
            native_error operation
              "IOSurface allocation is smaller than its checked plane layout"
        | Ok (actual, _) ->
            Ok
              { raw
              ; lifetime = lifetime ()
              ; id
              ; allocation_size
              ; planar
              ; planes = actual
              ; label
              }
      end

    let create_internal operation ~planar
        ~(planes : plane_descriptor list) ~label =
      on_main operation (fun () ->
        if planes = [] then
          error operation Invalid_argument
            "IOSurface requires at least one image plane"
        else if option_exists contains_nul label then
          error operation Invalid_argument "IOSurface label contains a NUL byte"
        else if List.length planes > Sys.max_array_length / 3 then
          error operation Invalid_argument "IOSurface has too many planes"
        else
          let requested_planes = Array.of_list planes in
          let rec validate index =
            if index = Array.length requested_planes then Ok ()
            else
              match validate_plane operation index requested_planes.(index) with
              | Error _ as failure -> failure
              | Ok () -> validate (index + 1)
          in
          match validate 0 with
          | Error _ as failure -> failure
          | Ok () ->
              let layout = Array.make (Array.length requested_planes * 3) 0 in
              Array.iteri
                (fun index (plane : plane_descriptor) ->
                  let offset = index * 3 in
                  layout.(offset) <- plane.width;
                  layout.(offset + 1) <- plane.height;
                  layout.(offset + 2) <- plane.bytes_per_element)
                requested_planes;
              (match Metal_raw.io_surface_create planar layout label with
               | Error message -> native_error operation message
               | Ok raw ->
                   finish_create operation ~requested_planar:planar
                     ~requested_planes ~label raw))

    let create ?label ~width ~height ~bytes_per_element () =
      create_internal "Metal.Texture.Io_surface.create" ~planar:false
        ~planes:
          [ ({ width; height; bytes_per_element } : plane_descriptor) ]
        ~label

    let create_planar ?label planes =
      create_internal "Metal.Texture.Io_surface.create_planar" ~planar:true
        ~planes ~label

    let id (value : t) = value.id
    let allocation_size (value : t) = value.allocation_size
    let planar (value : t) = value.planar
    let plane_count (value : t) = Array.length value.planes
    let generation (value : t) = Metal_raw.generation value.raw
    let destroyed (value : t) = is_destroyed value.lifetime

    let plane (value : t) index =
      let operation = "Metal.Texture.Io_surface.plane" in
      on_main operation (fun () ->
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () when index < 0 || index >= Array.length value.planes ->
            error operation Invalid_argument "IOSurface plane index is out of range"
        | Ok () -> Ok value.planes.(index))

    let label (value : t) =
      on_main "Metal.Texture.Io_surface.label" (fun () ->
        match
          ensure_live "Metal.Texture.Io_surface.label" value.lifetime
        with
        | Error _ as failure -> failure
        | Ok () -> Ok value.label)

    let validate_range operation (value : t) ~plane ~offset ~length =
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when plane < 0 || plane >= Array.length value.planes ->
          error operation Invalid_argument "IOSurface plane index is out of range"
      | Ok () when offset < 0L || length < 0 ->
          error operation Invalid_argument "IOSurface range is negative"
      | Ok () ->
          let size = value.planes.(plane).size in
          let length64 = Int64.of_int length in
          if offset > size || length64 > Int64.sub size offset then
            error operation Invalid_argument
              "IOSurface range exceeds the selected plane"
          else Ok ()

    let write_bytes (value : t) ~plane ?(src_offset = 0) ~dst_offset bytes =
      let operation = "Metal.Texture.Io_surface.write_bytes" in
      on_main operation (fun () ->
        let source_length = Bytes.length bytes in
        if src_offset < 0 || src_offset > source_length then
          error operation Invalid_argument
            "source offset is outside the byte buffer"
        else
          let length = source_length - src_offset in
          match validate_range operation value ~plane ~offset:dst_offset ~length with
          | Error _ as failure -> failure
          | Ok () ->
              (match
                 Metal_raw.io_surface_write value.raw plane dst_offset bytes
                   src_offset
               with
               | Ok () -> Ok ()
               | Error message -> native_error operation message))

    let read_bytes (value : t) ~plane ~offset ~length =
      let operation = "Metal.Texture.Io_surface.read_bytes" in
      on_main operation (fun () ->
        if length > Sys.max_string_length then
          error operation Invalid_argument
            "read length exceeds the maximum OCaml byte-buffer size"
        else
          match validate_range operation value ~plane ~offset ~length with
          | Error _ as failure -> failure
          | Ok () ->
              (match Metal_raw.io_surface_read value.raw plane offset length with
               | Ok bytes -> Ok bytes
               | Error message -> native_error operation message))

    let destroy (value : t) =
      destroy_parent "Metal.Texture.Io_surface.destroy" value.lifetime value.raw
        (fun () -> ())
  end

  type io_surface_backing = texture_io_surface_backing =
    { surface : Io_surface.t
    ; plane : int
    }

  module Shared_handle = struct
    type t = shared_texture_handle

    let device (value : t) = value.device
    let generation (value : t) = Metal_raw.generation value.raw
    let destroyed (value : t) = is_destroyed value.lifetime

    let label (value : t) =
      on_main "Metal.Texture.Shared_handle.label" (fun () ->
        match
          ensure_live "Metal.Texture.Shared_handle.label" value.lifetime
        with
        | Error _ as failure -> failure
        | Ok () -> Ok value.label)

    let destroy (value : t) =
      destroy_leaf "Metal.Texture.Shared_handle.destroy" value.lifetime
        value.raw (fun () -> detach value.device.lifetime)
  end

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

  let format_code = Metal_format.code
  let format_layout = Metal_format.layout
  let all_formats = Metal_format.all
  let supports_buffer_backing = Metal_format.supports_buffer_backing

  let bytes_per_pixel format =
    let layout = format_layout format in
    if layout.block_width = 1 && layout.block_height = 1 then
      layout.bytes_per_block
    else 0

  let supports_family_raw (device : Device.t) family =
    Metal_raw.device_supports_family device.raw (Device.family_code family)

  let supports_compression_raw (device : Device.t) format =
    match Metal_format.compression_family format with
    | None -> true
    | Some Metal_format.Bc ->
        Metal_raw.device_supports_bc_texture_compression device.raw
    | Some (Metal_format.Eac_etc2 | Metal_format.Astc_ldr) ->
        supports_family_raw device Device.Apple2
        || supports_family_raw device Device.Metal4
    | Some Metal_format.Astc_hdr ->
        supports_family_raw device Device.Apple6
        || supports_family_raw device Device.Metal4

  let supports_compressed_volume_raw (device : Device.t) =
    supports_family_raw device Device.Apple3
    || supports_family_raw device Device.Mac2
    || supports_family_raw device Device.Metal3
    || supports_family_raw device Device.Metal4

  let validate_buffer_kind_format operation ~kind ~format =
    if kind <> Texture_2d && kind <> Texture_buffer then
      error operation Invalid_argument
        "buffer-backed textures must use the 2D or texture-buffer kind"
    else if not (supports_buffer_backing format) then
      error operation Invalid_argument
        "buffer-backed textures require an ordinary or packed color format"
    else Ok ()

  let minimum_buffer_alignment_raw operation (device : Device.t) ~kind ~format =
    match validate_buffer_kind_format operation ~kind ~format with
    | Error _ as failure -> failure
    | Ok () ->
        (match
           Metal_raw.device_minimum_texture_alignment device.raw
             (kind_code kind) (format_code format)
         with
         | Error message -> native_error operation message
         | Ok alignment
           when alignment <= 0L
                || Int64.logand alignment (Int64.pred alignment) <> 0L ->
             native_error operation
               "Metal returned a non-positive or non-power-of-two texture alignment"
         | Ok alignment -> Ok alignment)

  let minimum_buffer_alignment ~(device : Device.t) ~kind ~format =
    on_main "Metal.Texture.minimum_buffer_alignment" (fun () ->
      match
        ensure_live "Metal.Texture.minimum_buffer_alignment" device.lifetime
      with
      | Error _ as failure -> failure
      | Ok () ->
          minimum_buffer_alignment_raw
            "Metal.Texture.minimum_buffer_alignment" device ~kind ~format)

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

  let validate_descriptor operation (device : Device.t)
      (descriptor : descriptor) =
    let invalid message = error operation Invalid_argument message in
    if descriptor.width <= 0 || descriptor.height <= 0 || descriptor.depth <= 0
       || descriptor.mip_levels <= 0 || descriptor.sample_count <= 0
       || descriptor.array_length <= 0
    then invalid "texture dimensions and counts must be positive"
    else if
      (descriptor.kind = Texture_buffer && descriptor.width > 268_435_456)
      || (descriptor.kind <> Texture_buffer
          && (descriptor.width > 16_384 || descriptor.height > 16_384
              || descriptor.depth > 2_048))
    then invalid "texture dimensions exceed the binding's checked Metal limits"
    else if descriptor.mip_levels > max_mip_levels descriptor then
      invalid "texture mip count exceeds its dimensions"
    else if descriptor.array_length >= 2_048 then
      invalid "texture array length must be below 2048"
    else if List.length descriptor.usage <> List.length (List.sort_uniq compare descriptor.usage)
    then invalid "texture usage contains duplicates"
    else if
      descriptor.format = Depth24_unorm_stencil8
      && not (Metal_raw.device_supports_depth24_stencil8 device.raw)
    then
      error operation Unsupported
        "device does not support Depth24Unorm_Stencil8 textures"
    else if not (supports_compression_raw device descriptor.format) then
      error operation Unsupported
        "device does not support the selected compressed texture format"
    else if Metal_format.is_view_only descriptor.format then
      invalid "stencil-plane formats can only be created as texture views"
    else if
      Metal_format.is_compressed descriptor.format
      &&
      (match descriptor.kind with
       | Texture_2d | Texture_2d_array | Texture_cube | Texture_cube_array
       | Texture_3d -> false
       | Texture_1d | Texture_1d_array | Texture_2d_multisample
       | Texture_2d_multisample_array | Texture_buffer -> true)
    then
      invalid
        "compressed formats require a 2D, 2D-array, cube, cube-array, or 3D texture"
    else if
      Metal_format.is_compressed descriptor.format
      && descriptor.kind = Texture_3d
      && not (supports_compressed_volume_raw device)
    then
      error operation Unsupported
        "device does not support compressed volume textures"
    else if
      Metal_format.is_compressed descriptor.format
      && List.exists
           (function
             | Shader_write | Render_target | Shader_atomic -> true
             | Shader_read | Pixel_format_view -> false)
           descriptor.usage
    then
      invalid
        "compressed textures support only shader-read and pixel-format-view usage"
    else if
      Metal_format.is_subsampled descriptor.format
      && (descriptor.kind <> Texture_2d || descriptor.width mod 2 <> 0
          || descriptor.mip_levels <> 1 || descriptor.sample_count <> 1
          || descriptor.array_length <> 1 || descriptor.depth <> 1)
    then
      invalid
        "subsampled 4:2:2 formats require an even-width, single-mip 2D texture"
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

  let verify_info operation raw descriptor ~heap =
    let info = Metal_raw.texture_info raw in
    let actual_hazard =
      concrete_hazard_tracking ~heap descriptor.hazard_tracking
    in
    if Array.length info <> 12 then
      native_error operation "Metal returned malformed texture properties"
    else
      let expected =
        [| kind_code descriptor.kind; format_code descriptor.format
         ; descriptor.width; descriptor.height; descriptor.depth
         ; descriptor.mip_levels; descriptor.sample_count
         ; descriptor.array_length; usage_bits descriptor.usage
         ; storage_code descriptor.storage
         ; cache_code descriptor.cpu_cache; hazard_code actual_hazard
        |]
      in
      if info = expected then
        Ok { descriptor with hazard_tracking = actual_hazard }
      else
        native_error operation
          "Metal changed a checked texture descriptor during creation"

  let finish_create ?expected_shareable operation ~device ~descriptor ~parent
      ~heap_offset ~allocation raw =
    let heap =
      match parent with
      | Texture_resource (Heap_resource _) -> true
      | Texture_resource (Device_resource _ | External_resource _)
      | Texture_io_surface_resource _
      | Texture_view _ -> false
      | Texture_buffer_resource backing ->
          Option.is_some (parent_heap backing.buffer.parent)
    in
    match verify_info operation raw descriptor ~heap with
    | Error _ as failure -> ignore (Metal_raw.destroy raw); failure
    | Ok _
      when option_exists
             (fun expected ->
               expected <> Metal_raw.texture_is_shareable raw)
             expected_shareable ->
        ignore (Metal_raw.destroy raw);
        native_error operation
          "Metal changed the checked texture sharing mode during creation"
    | Ok descriptor ->
        let parent_lifetime = texture_parent_lifetime parent in
        let state =
          match parent with
          | Texture_resource _ -> resource_state ()
          | Texture_buffer_resource backing -> backing.buffer.state
          | Texture_io_surface_resource _ -> resource_state ()
          | Texture_view texture -> texture.state
        in
        let value : t =
          { raw
          ; lifetime = lifetime ()
          ; device
          ; descriptor
          ; parent
          ; heap_offset
          ; allocation
          ; state
          }
        in
        attach parent_lifetime;
        let extra_device = texture_parent_extra_device device parent in
        Option.iter attach extra_device;
        attach_finalizer
          ~on_finalize:(fun () ->
            deactivate_allocation allocation;
            Option.iter detach extra_device)
          value value.lifetime parent_lifetime;
        Ok value

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Texture.create" (fun () ->
      match ensure_live "Metal.Texture.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_descriptor "Metal.Texture.create" device descriptor
           with
           | Error _ as failure -> failure
           | Ok () when descriptor.kind = Texture_buffer ->
               error "Metal.Texture.create" Invalid_argument
                 "texture-buffer resources must be created from a buffer"
           | Ok () ->
               match
                 Metal_raw.texture_create device.raw (descriptor_tuple descriptor)
                   descriptor.label
               with
               | Error message -> native_error "Metal.Texture.create" message
               | Ok raw ->
                   finish_create ~expected_shareable:false
                     "Metal.Texture.create" ~device ~descriptor
                     ~parent:(Texture_resource (Device_resource device))
                     ~heap_offset:None ~allocation:None raw))

  let create_shared ~(device : Device.t) descriptor =
    let operation = "Metal.Texture.create_shared" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () when descriptor.storage <> Private ->
          error operation Invalid_argument
            "shared textures require private storage"
      | Ok () ->
          (match validate_descriptor operation device descriptor with
           | Error _ as failure -> failure
           | Ok () when descriptor.kind = Texture_buffer ->
               error operation Invalid_argument
                 "texture-buffer resources must be created from a buffer"
           | Ok () ->
               match
                 Metal_raw.texture_shared_create device.raw
                   (descriptor_tuple descriptor) descriptor.label
               with
               | Error message -> native_error operation message
               | Ok raw ->
                   finish_create ~expected_shareable:true operation ~device
                     ~descriptor
                     ~parent:(Texture_resource (Device_resource device))
                     ~heap_offset:None ~allocation:None raw))

  let device (value : t) = value.device
  let descriptor (value : t) = value.descriptor
  let heap_offset (value : t) = value.heap_offset
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let rec buffer_backing (value : t) =
    match value.parent with
    | Texture_buffer_resource backing -> Some backing
    | Texture_view parent -> buffer_backing parent
    | Texture_resource _ | Texture_io_surface_resource _ -> None

  let rec io_surface_backing (value : t) =
    match value.parent with
    | Texture_io_surface_resource backing -> Some backing
    | Texture_view parent -> io_surface_backing parent
    | Texture_resource _ | Texture_buffer_resource _ -> None

  let decode_sparse_info operation page_size values =
    if Array.length values <> 6 then
      native_error operation "Metal returned malformed sparse texture metadata"
    else
      let integer index =
        let value = values.(index) in
        if value <= 0L || value > Int64.of_int max_int then None
        else Some (Int64.to_int value)
      in
      match integer 0, integer 1, integer 2 with
      | Some tile_width, Some tile_height, Some tile_depth ->
          let tile_size_in_bytes = values.(3) in
          let first_tail = values.(4) in
          let tail_size_in_bytes = values.(5) in
          if tile_size_in_bytes <> Sparse_page_size.bytes page_size
             || tail_size_in_bytes < 0L
             || first_tail < -1L || first_tail > Int64.of_int max_int
          then
            native_error operation
              "Metal returned inconsistent sparse texture metadata"
          else
            Ok
              { page_size
              ; tile_width
              ; tile_height
              ; tile_depth
              ; tile_size_in_bytes
              ; first_mip_in_tail =
                  (if first_tail < 0L then None
                   else Some (Int64.to_int first_tail))
              ; tail_size_in_bytes
              }
      | None, _, _ | _, None, _ | _, _, None ->
          native_error operation
            "Metal returned invalid sparse texture tile dimensions"

  let sparse_info_raw operation (value : t) =
    if not (Metal_raw.texture_is_sparse value.raw) then Ok None
    else
      match texture_heap value with
      | Some
          { descriptor =
              { kind = Sparse; sparse_page_size = Some page_size; _ }
          ; _ } ->
          (match
             Metal_raw.texture_sparse_info value.device.raw value.raw
               (sparse_page_size_code page_size)
           with
           | Error message -> native_error operation message
           | Ok values ->
               (match decode_sparse_info operation page_size values with
                | Error _ as failure -> failure
                | Ok info -> Ok (Some info)))
      | Some _ | None ->
          native_error operation
            "sparse texture has no matching typed sparse-heap ancestry"

  let sparse_info (value : t) =
    on_main "Metal.Texture.sparse_info" (fun () ->
      match ensure_live "Metal.Texture.sparse_info" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> sparse_info_raw "Metal.Texture.sparse_info" value)

  let is_shareable (value : t) =
    on_main "Metal.Texture.is_shareable" (fun () ->
      match ensure_live "Metal.Texture.is_shareable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.texture_is_shareable value.raw))

  let shared_handle (value : t) =
    let operation = "Metal.Texture.shared_handle" in
    on_main operation (fun () ->
      match ensure_texture_usable operation value with
      | Error _ as failure -> failure
      | Ok () when not (Metal_raw.texture_is_shareable value.raw) ->
          error operation Invalid_state "texture is not shareable"
      | Ok () ->
          (match Metal_raw.texture_shared_handle_create value.raw with
           | Error message -> native_error operation message
           | Ok raw ->
               let registry_id, label =
                 Metal_raw.shared_texture_handle_info raw
               in
               if registry_id <> value.device.registry_id then begin
                 ignore (Metal_raw.destroy raw);
                 native_error operation
                   "shared texture handle belongs to a different device"
               end
               else
                 let handle : Shared_handle.t =
                   { raw
                   ; lifetime = lifetime ()
                   ; device = value.device
                   ; descriptor = { value.descriptor with label }
                   ; label
                   }
                 in
                 attach value.device.lifetime;
                 attach_finalizer handle handle.lifetime value.device.lifetime;
                 Ok handle))

  let import_shared ~(device : Device.t) (handle : Shared_handle.t) =
    let operation = "Metal.Texture.import_shared" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live operation handle.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match ensure_same_device operation device handle.device with
                | Error _ as failure -> failure
                | Ok () ->
                    match
                      Metal_raw.texture_shared_import device.raw handle.raw
                    with
                    | Error message -> native_error operation message
                    | Ok raw ->
                        finish_create ~expected_shareable:true operation ~device
                          ~descriptor:handle.descriptor
                          ~parent:(Texture_resource (Device_resource device))
                          ~heap_offset:None ~allocation:None raw)))

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

  let validate_io_surface_descriptor operation (surface : Io_surface.t) ~plane
      (descriptor : descriptor) =
    let invalid message = error operation Invalid_argument message in
    if plane < 0 || plane >= Array.length surface.planes then
      invalid "IOSurface plane index is out of range"
    else if descriptor.kind <> Texture_2d then
      invalid "IOSurface-backed textures must be two-dimensional"
    else if not (supports_buffer_backing descriptor.format) then
      invalid "IOSurface-backed textures require an ordinary color format"
    else if
      descriptor.depth <> 1 || descriptor.array_length <> 1
      || descriptor.mip_levels <> 1 || descriptor.sample_count <> 1
    then
      invalid
        "IOSurface-backed textures require depth, array length, mip count, and sample count equal to one"
    else if descriptor.storage <> Buffer.Shared then
      invalid "IOSurface-backed textures require shared storage"
    else if descriptor.cpu_cache <> Default_cache then
      invalid "IOSurface-backed textures require the default CPU cache mode"
    else
      let layout = surface.planes.(plane) in
      if descriptor.width <> layout.width || descriptor.height <> layout.height then
        invalid "texture dimensions must match the selected IOSurface plane"
      else if bytes_per_pixel descriptor.format <> layout.bytes_per_element then
        invalid "texture pixel width must match the selected IOSurface plane"
      else Ok ()

  let create_from_io_surface ~(device : Device.t) ~(surface : Io_surface.t)
      ~plane descriptor =
    let operation = "Metal.Texture.create_from_io_surface" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live operation surface.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match validate_descriptor operation device descriptor with
                | Error _ as failure -> failure
                | Ok () ->
                    (match
                       validate_io_surface_descriptor operation surface ~plane
                         descriptor
                     with
                     | Error _ as failure -> failure
                     | Ok () ->
                         match
                           Metal_raw.texture_io_surface_create device.raw
                             surface.raw plane (descriptor_tuple descriptor)
                             descriptor.label
                         with
                         | Error message -> native_error operation message
                         | Ok raw ->
                             let backing : io_surface_backing =
                               { surface; plane }
                             in
                             finish_create ~expected_shareable:false operation
                               ~device ~descriptor
                               ~parent:(Texture_io_surface_resource backing)
                               ~heap_offset:None ~allocation:None raw))))

  let validate_buffer_descriptor operation (buffer : Buffer.t)
      (descriptor : descriptor) =
    let invalid message = error operation Invalid_argument message in
    match
      validate_buffer_kind_format operation ~kind:descriptor.kind
        ~format:descriptor.format
    with
    | Error _ as failure -> failure
    | Ok ()
      when descriptor.depth <> 1 || descriptor.array_length <> 1
           || descriptor.mip_levels <> 1 || descriptor.sample_count <> 1 ->
        invalid
          "buffer-backed textures require depth, array length, mip count, and sample count equal to one"
    | Ok () ->
        let heap = Option.is_some (parent_heap buffer.parent) in
        let expected_hazard =
          concrete_hazard_tracking ~heap descriptor.hazard_tracking
        in
        if
          descriptor.storage <> buffer.storage
          || descriptor.cpu_cache <> buffer.cpu_cache
          || expected_hazard <> buffer.hazard_tracking
        then
          invalid
            "texture storage, cache, and hazard modes must match the backing buffer"
        else
          (match validate_descriptor operation buffer.device descriptor with
           | Error _ as failure -> failure
           | Ok ()
             when List.mem Render_target descriptor.usage
                  && not
                       (Metal_raw.device_supports_family buffer.device.raw
                          (Device.family_code Device.Apple1)) ->
               error operation Unsupported
                 "linear render-target textures require Apple GPU family 1 support"
           | Ok () -> Ok { descriptor with hazard_tracking = expected_hazard })

  let validate_buffer_layout operation (buffer : Buffer.t)
      (descriptor : descriptor) ~offset ~bytes_per_row =
    let invalid message = error operation Invalid_argument message in
    if offset < 0L then invalid "buffer-backed texture offset is negative"
    else if bytes_per_row <= 0 then
      invalid "buffer-backed texture row pitch must be positive"
    else
      match checked_mul descriptor.width (bytes_per_pixel descriptor.format) with
      | None ->
          invalid
            "buffer-backed texture row cardinality overflows an OCaml integer"
      | Some minimum_row when bytes_per_row < minimum_row ->
          invalid "buffer-backed texture row pitch is smaller than one pixel row"
      | Some _ ->
          (match
             minimum_buffer_alignment_raw operation buffer.device
               ~kind:descriptor.kind ~format:descriptor.format
           with
           | Error _ as failure -> failure
           | Ok alignment ->
               let row_pitch = Int64.of_int bytes_per_row in
               let height = Int64.of_int descriptor.height in
               if Int64.rem offset alignment <> 0L
                  || Int64.rem row_pitch alignment <> 0L
               then
                 invalid
                   "buffer-backed texture offset and row pitch do not meet the device alignment"
               else if row_pitch > Int64.div Int64.max_int height then
                 invalid
                   "buffer-backed texture storage cardinality overflows 64 bits"
               else
                 let required = Int64.mul row_pitch height in
                 if
                   offset > buffer.length
                   || required > Int64.sub buffer.length offset
                 then
                   invalid
                     "buffer-backed texture storage exceeds the backing buffer"
                 else Ok ())

  let create_from_buffer ~(buffer : Buffer.t) ~offset ~bytes_per_row
      descriptor =
    let operation = "Metal.Texture.create_from_buffer" in
    on_main operation (fun () ->
      match ensure_buffer_usable operation buffer with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_buffer_descriptor operation buffer descriptor with
           | Error _ as failure -> failure
           | Ok descriptor ->
               (match
                  validate_buffer_layout operation buffer descriptor ~offset
                    ~bytes_per_row
                with
                | Error _ as failure -> failure
                | Ok () ->
                    match
                      Metal_raw.buffer_texture_create buffer.raw
                        (descriptor_tuple descriptor) offset bytes_per_row
                        descriptor.label
                    with
                    | Error message -> native_error operation message
                    | Ok raw ->
                        let backing : buffer_backing =
                          { buffer; offset; bytes_per_row }
                        in
                        finish_create operation ~device:buffer.device ~descriptor
                          ~parent:(Texture_buffer_resource backing)
                          ~heap_offset:buffer.heap_offset ~allocation:None raw)))

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
        let layout = format_layout value.descriptor.format in
        let aligned origin length limit block =
          origin mod block = 0
          && (length mod block = 0 || origin + length = limit)
        in
        if
          not
            (aligned region.x region.width width layout.block_width
             && aligned region.y region.height height layout.block_height)
        then
          invalid "texture region is not aligned to its format blocks"
        else
        let blocks value block = 1 + ((value - 1) / block) in
        match
          checked_mul (blocks region.width layout.block_width)
            layout.bytes_per_block
        with
        | None -> invalid "texture row cardinality overflows an OCaml integer"
        | Some minimum_row
          when bytes_per_row < minimum_row
               || bytes_per_row mod layout.bytes_per_block <> 0 ->
            invalid "texture row pitch is too small or not block-aligned"
        | Some _ ->
            (match
               checked_mul bytes_per_row
                 (blocks region.height layout.block_height)
             with
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
      match ensure_texture_usable "Metal.Texture.write_bytes" value with
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
      match ensure_texture_usable "Metal.Texture.read_bytes" value with
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

  let compatible_view_format = Metal_format.compatible_view

  let create_view (parent : t) ~format ~base_mip ~mip_count ~base_slice
      ~slice_count ?label () =
    on_main "Metal.Texture.create_view" (fun () ->
      match ensure_texture_usable "Metal.Texture.create_view" parent with
      | Error _ as failure -> failure
      | Ok () when not (List.mem Pixel_format_view parent.descriptor.usage) ->
          error "Metal.Texture.create_view" Invalid_argument
            "parent texture usage does not permit pixel-format views"
      | Ok () when not (compatible_view_format parent.descriptor.format format) ->
          error "Metal.Texture.create_view" Invalid_argument
            "requested texture-view format is not in a compatible format class"
      | Ok ()
        when format = X24_stencil8
             && not
                  (Metal_raw.device_supports_depth24_stencil8
                     parent.device.raw) ->
          error "Metal.Texture.create_view" Unsupported
            "device does not support X24_Stencil8 texture views"
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
                  ~descriptor ~parent:(Texture_view parent)
                  ~heap_offset:parent.heap_offset ~allocation:None raw)

  let purgeable_state (value : t) =
    on_main "Metal.Texture.purgeable_state" (fun () ->
      match ensure_live "Metal.Texture.purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok ()
        when option_exists
               (fun (heap : heap) -> heap.descriptor.kind = Sparse)
               (texture_heap value) ->
          error "Metal.Texture.purgeable_state" Invalid_state
            "the sparse heap controls physical-page purgeability"
      | Ok () ->
          (match buffer_backing value with
           | Some backing -> Buffer.purgeable_state backing.buffer
           | None ->
               (match io_surface_backing value with
                | Some _ ->
                    error "Metal.Texture.purgeable_state" Invalid_state
                      "IOSurface controls the backing allocation's purgeability"
                | None ->
                    query_purgeable_state "Metal.Texture.purgeable_state"
                      (Metal_raw.resource_set_purgeable_state value.raw)
                      value.state.purgeable)))

  let set_purgeable_state (value : t) state =
    on_main "Metal.Texture.set_purgeable_state" (fun () ->
      match ensure_live "Metal.Texture.set_purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.state.relinquished ->
          error "Metal.Texture.set_purgeable_state" Invalid_state
            "an aliasable resource cannot change purgeability"
      | Ok () when dependent_count value.lifetime <> 0 ->
          error "Metal.Texture.set_purgeable_state" Parent_has_dependents
            "texture has a live view or command dependency"
      | Ok ()
        when option_exists
               (fun (heap : heap) -> heap.descriptor.kind = Sparse)
               (texture_heap value) ->
          error "Metal.Texture.set_purgeable_state" Invalid_state
            "set purgeability on the sparse heap"
      | Ok () ->
          (match value.parent with
           | Texture_view _ ->
               error "Metal.Texture.set_purgeable_state" Invalid_state
                 "set purgeability on the base texture rather than a view"
           | Texture_buffer_resource _ ->
               error "Metal.Texture.set_purgeable_state" Invalid_state
                 "set purgeability on the backing buffer"
           | Texture_io_surface_resource _ ->
               error "Metal.Texture.set_purgeable_state" Invalid_state
                 "IOSurface controls the backing allocation's purgeability"
           | Texture_resource parent ->
               (match
                  ensure_heap_nonvolatile "Metal.Texture.set_purgeable_state"
                    (parent_heap parent)
                with
                | Error _ as failure -> failure
                | Ok () ->
                    apply_purgeable_state
                      "Metal.Texture.set_purgeable_state"
                      (Metal_raw.resource_set_purgeable_state value.raw)
                      value.state.purgeable state)))

  let is_aliasable (value : t) =
    on_main "Metal.Texture.is_aliasable" (fun () ->
      match ensure_live "Metal.Texture.is_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match buffer_backing value with
           | Some backing -> Buffer.is_aliasable backing.buffer
           | None -> Ok (Metal_raw.resource_is_aliasable value.raw)))

  let make_aliasable (value : t) =
    on_main "Metal.Texture.make_aliasable" (fun () ->
      match ensure_live "Metal.Texture.make_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.state.relinquished -> Ok ()
      | Ok () when Atomic.get value.state.purgeable <> Nonvolatile ->
          error "Metal.Texture.make_aliasable" Invalid_state
            "texture must be nonvolatile before becoming aliasable"
      | Ok () when dependent_count value.lifetime <> 0 ->
          error "Metal.Texture.make_aliasable" Parent_has_dependents
            "texture has a live view or command dependency"
      | Ok () ->
          (match value.parent with
           | Texture_view _ ->
               error "Metal.Texture.make_aliasable" Invalid_state
                 "texture views cannot become aliasable"
           | Texture_buffer_resource _ ->
               error "Metal.Texture.make_aliasable" Invalid_state
                 "make the backing buffer aliasable"
           | Texture_io_surface_resource _ ->
               error "Metal.Texture.make_aliasable" Invalid_state
                 "IOSurface-backed textures cannot become aliasable"
           | Texture_resource (Device_resource _) ->
               error "Metal.Texture.make_aliasable" Invalid_state
                 "only heap-backed textures can become aliasable"
           | Texture_resource (External_resource _) ->
               error "Metal.Texture.make_aliasable" Invalid_state
                 "externally backed textures cannot become aliasable"
           | Texture_resource (Heap_resource heap) ->
               (if heap.descriptor.kind = Sparse then
                  error "Metal.Texture.make_aliasable" Invalid_state
                    "sparse texture mappings are released by unmapping tiles"
                else match
                  ensure_heap_nonvolatile "Metal.Texture.make_aliasable"
                    (Some heap)
                with
                | Error _ as failure -> failure
                | Ok () ->
                    match Metal_raw.resource_make_aliasable value.raw with
                    | Error message ->
                        native_error "Metal.Texture.make_aliasable" message
                    | Ok () ->
                        if not (Metal_raw.resource_is_aliasable value.raw) then
                          native_error "Metal.Texture.make_aliasable"
                            "Metal did not make the heap texture aliasable"
                        else begin
                          Atomic.set value.state.relinquished true;
                          deactivate_allocation value.allocation;
                          Ok ()
                        end)))

  let destroy (value : t) =
    destroy_parent "Metal.Texture.destroy" value.lifetime value.raw
      (fun () ->
        deactivate_allocation value.allocation;
        detach (texture_parent_lifetime value.parent);
        Option.iter detach
          (texture_parent_extra_device value.device value.parent))
end

module Heap = struct
  type t = heap
  type kind = heap_kind = Automatic | Placement | Sparse
  type cpu_cache_mode = resource_cpu_cache_mode = Default_cache | Write_combined
  type hazard_tracking_mode = resource_hazard_tracking_mode =
    | Default_hazard_tracking
    | Untracked
    | Tracked

  type descriptor = heap_descriptor =
    { size : int64
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; kind : kind
    ; sparse_page_size : Sparse_page_size.t option
    ; label : string option
    }

  type size_and_align =
    { size : int64
    ; alignment : int64
    }

  type info =
    { size : int64
    ; used_size : int64
    ; current_allocated_size : int64
    ; storage : Buffer.storage_mode
    ; cpu_cache : cpu_cache_mode
    ; hazard_tracking : hazard_tracking_mode
    ; kind : kind
    }

  let make_descriptor ?(storage = Private) ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?(kind = Automatic)
      ?sparse_page_size ?label ~size () =
    { size; storage; cpu_cache; hazard_tracking; kind; sparse_page_size; label }

  let kind_code = function Automatic -> 0 | Placement -> 1 | Sparse -> 2

  let kind_of_code operation = function
    | 0 -> Ok Automatic
    | 1 -> Ok Placement
    | 2 -> Ok Sparse
    | code -> native_error operation (Printf.sprintf "unknown heap kind %d" code)

  let storage_of_code operation = function
    | 0 -> Ok Shared
    | 1 -> Ok Managed
    | 2 -> Ok Private
    | code -> native_error operation (Printf.sprintf "unknown storage mode %d" code)

  let sparse_tile_size_in_bytes_raw operation (device : Device.t) page_size =
    if not (Metal_raw.device_supports_sparse_textures device.raw) then
      error operation Unsupported "device does not support sparse textures"
    else
      match
        Metal_raw.device_sparse_tile_size_in_bytes device.raw
          (sparse_page_size_code page_size)
      with
      | Error message -> error operation Unsupported message
      | Ok bytes when bytes <> Sparse_page_size.bytes page_size ->
          native_error operation
            "Metal changed the selected sparse page's byte cardinality"
      | Ok bytes -> Ok bytes

  let sparse_tile_size_in_bytes ~(device : Device.t) page_size =
    on_main "Metal.Heap.sparse_tile_size_in_bytes" (fun () ->
      match
        ensure_live "Metal.Heap.sparse_tile_size_in_bytes" device.lifetime
      with
      | Error _ as failure -> failure
      | Ok () ->
          sparse_tile_size_in_bytes_raw
            "Metal.Heap.sparse_tile_size_in_bytes" device page_size)

  let validate_descriptor operation (device : Device.t)
      (descriptor : descriptor) =
    if descriptor.size <= 0L then
      error operation Invalid_argument "heap size must be positive"
    else if descriptor.storage = Managed then
      error operation Unsupported "Metal heaps do not support managed storage"
    else if option_exists contains_nul descriptor.label then
      error operation Invalid_argument "heap label contains a NUL byte"
    else
      match descriptor.kind, descriptor.sparse_page_size with
      | (Automatic | Placement), Some _ ->
          error operation Invalid_argument
            "only sparse heaps accept a sparse page size"
      | Sparse, None ->
          error operation Invalid_argument
            "sparse heaps require an explicit sparse page size"
      | Sparse, Some _
        when descriptor.storage <> Private
             || descriptor.cpu_cache <> Default_cache ->
          error operation Invalid_argument
            "sparse heaps require private default-cache storage"
      | (Automatic | Placement), None -> Ok ()
      | Sparse, Some page_size ->
          (match sparse_tile_size_in_bytes_raw operation device page_size with
           | Error _ as failure -> failure
           | Ok page_bytes when Int64.rem descriptor.size page_bytes <> 0L ->
               error operation Invalid_argument
                 "sparse heap size must be a whole number of sparse pages"
           | Ok _ -> Ok ())

  let descriptor_tuple (descriptor : descriptor) =
    ( descriptor.size
    , storage_code descriptor.storage
    , cache_code descriptor.cpu_cache
    , hazard_code descriptor.hazard_tracking
    , kind_code descriptor.kind
    , Option.fold ~none:0 ~some:sparse_page_size_code
        descriptor.sparse_page_size )

  let decode_info operation raw =
    let values = Metal_raw.heap_info raw in
    if Array.length values <> 7 then
      native_error operation "Metal returned malformed heap properties"
    else
      match
        storage_of_code operation (Int64.to_int values.(3)),
        cache_mode_of_code operation (Int64.to_int values.(4)),
        hazard_mode_of_code operation (Int64.to_int values.(5)),
        kind_of_code operation (Int64.to_int values.(6))
      with
      | Ok storage, Ok cpu_cache, Ok hazard_tracking, Ok kind ->
          Ok
            { size = values.(0)
            ; used_size = values.(1)
            ; current_allocated_size = values.(2)
            ; storage
            ; cpu_cache
            ; hazard_tracking
            ; kind
            }
      | (Error _ as failure), _, _, _
      | _, (Error _ as failure), _, _
      | _, _, (Error _ as failure), _
      | _, _, _, (Error _ as failure) -> failure

  let validate_size_and_align operation ~minimum (size, alignment) =
    if size < minimum || alignment <= 0L
       || Int64.logand alignment (Int64.pred alignment) <> 0L
    then
      native_error operation
        "Metal returned an invalid heap resource size or alignment"
    else Ok { size; alignment }

  let buffer_size_and_align ~(device : Device.t) ~length ~storage
      ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) () =
    on_main "Metal.Heap.buffer_size_and_align" (fun () ->
      match ensure_live "Metal.Heap.buffer_size_and_align" device.lifetime with
      | Error _ as failure -> failure
      | Ok () when storage = Managed ->
          error "Metal.Heap.buffer_size_and_align" Unsupported
            "Metal heaps do not support managed storage"
      | Ok () ->
          (match
             Buffer.validate_create "Metal.Heap.buffer_size_and_align" device
               ~length ~label:None
           with
           | Error _ as failure -> failure
           | Ok () ->
               let options =
                 resource_options_code ~storage ~cpu_cache ~hazard_tracking
               in
               Metal_raw.heap_buffer_size_and_align device.raw length options
               |> validate_size_and_align "Metal.Heap.buffer_size_and_align"
                    ~minimum:length))

  let texture_size_and_align ~(device : Device.t)
      (descriptor : Texture.descriptor) =
    on_main "Metal.Heap.texture_size_and_align" (fun () ->
      match ensure_live "Metal.Heap.texture_size_and_align" device.lifetime with
      | Error _ as failure -> failure
      | Ok () when descriptor.storage = Managed ->
          error "Metal.Heap.texture_size_and_align" Unsupported
            "Metal heaps do not support managed storage"
      | Ok () ->
          (match
             Texture.validate_descriptor "Metal.Heap.texture_size_and_align"
               device descriptor
           with
           | Error _ as failure -> failure
           | Ok () when descriptor.kind = Texture.Texture_buffer ->
               error "Metal.Heap.texture_size_and_align" Invalid_argument
                 "texture-buffer resources must be created from a buffer"
           | Ok () ->
               Metal_raw.heap_texture_size_and_align device.raw
                 (Texture.descriptor_tuple descriptor)
               |> validate_size_and_align "Metal.Heap.texture_size_and_align"
                    ~minimum:1L))

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Heap.create" (fun () ->
      match ensure_live "Metal.Heap.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_descriptor "Metal.Heap.create" device descriptor with
           | Error _ as failure -> failure
           | Ok () ->
               match
                 Metal_raw.heap_create device.raw (descriptor_tuple descriptor)
                   descriptor.label
               with
               | Error message -> native_error "Metal.Heap.create" message
               | Ok raw ->
                   (match decode_info "Metal.Heap.create" raw with
                    | Error _ as failure -> ignore (Metal_raw.destroy raw); failure
                    | Ok info ->
                        let expected_hazard =
                          concrete_hazard_tracking ~heap:true
                            descriptor.hazard_tracking
                        in
                        if info.size < descriptor.size
                           || info.storage <> descriptor.storage
                           || info.cpu_cache <> descriptor.cpu_cache
                           || info.hazard_tracking <> expected_hazard
                           || info.kind <> descriptor.kind
                        then begin
                          ignore (Metal_raw.destroy raw);
                          native_error "Metal.Heap.create"
                            "Metal changed checked heap properties during creation"
                        end
                        else
                          let descriptor =
                            { descriptor with
                              size = info.size
                            ; hazard_tracking = info.hazard_tracking
                            }
                          in
                          let value : t =
                            { raw
                            ; lifetime = lifetime ()
                            ; device
                            ; descriptor
                            ; allocations = ref []
                            ; purgeable = Atomic.make Nonvolatile
                            ; active_uses = Atomic.make 0
                            }
                          in
                          attach device.lifetime;
                          attach_finalizer value value.lifetime device.lifetime;
                          Ok value)))

  let device (value : t) = value.device
  let descriptor (value : t) = value.descriptor
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let info (value : t) =
    on_main "Metal.Heap.info" (fun () ->
      match ensure_live "Metal.Heap.info" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> decode_info "Metal.Heap.info" value.raw)

  let label (value : t) =
    on_main "Metal.Heap.label" (fun () ->
      match ensure_live "Metal.Heap.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.heap_label value.raw))

  let set_label (value : t) label =
    on_main "Metal.Heap.set_label" (fun () ->
      match ensure_live "Metal.Heap.set_label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when contains_nul label ->
          error "Metal.Heap.set_label" Invalid_argument
            "heap label contains a NUL byte"
      | Ok () ->
          (match Metal_raw.heap_set_label value.raw label with
           | Ok () -> Ok ()
           | Error message -> native_error "Metal.Heap.set_label" message))

  let purgeable_state (value : t) =
    on_main "Metal.Heap.purgeable_state" (fun () ->
      match ensure_live "Metal.Heap.purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          query_purgeable_state "Metal.Heap.purgeable_state"
            (Metal_raw.heap_set_purgeable_state value.raw)
            value.purgeable)

  let set_purgeable_state (value : t) state =
    on_main "Metal.Heap.set_purgeable_state" (fun () ->
      match ensure_live "Metal.Heap.set_purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.active_uses <> 0 ->
          error "Metal.Heap.set_purgeable_state" Parent_has_dependents
            "heap has an active CPU mapping or command dependency"
      | Ok () ->
          apply_purgeable_state "Metal.Heap.set_purgeable_state"
            (Metal_raw.heap_set_purgeable_state value.raw)
            value.purgeable state)

  let valid_alignment value =
    value = 0L
    || value > 0L && Int64.logand value (Int64.pred value) = 0L

  let max_available_size (value : t) ~alignment =
    on_main "Metal.Heap.max_available_size" (fun () ->
      match ensure_live "Metal.Heap.max_available_size" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when not (valid_alignment alignment) ->
          error "Metal.Heap.max_available_size" Invalid_argument
            "heap alignment must be zero or a power of two"
      | Ok () -> Ok (Metal_raw.heap_max_available_size value.raw alignment))

  let validate_placement operation (value : t) offset required =
    match value.descriptor.kind, offset with
    | Automatic, None ->
        let available =
          Metal_raw.heap_max_available_size value.raw required.alignment
        in
        if required.size > available then
          error operation Invalid_state
            "automatic heap has insufficient unfragmented capacity"
        else Ok ()
    | Automatic, Some _ ->
        error operation Invalid_argument
          "automatic heaps do not accept placement offsets"
    | Placement, None ->
        error operation Invalid_argument
          "placement heaps require an explicit offset"
    | Placement, Some offset when offset < 0L ->
        error operation Invalid_argument "heap placement offset is negative"
    | Placement, Some offset
      when Int64.rem offset required.alignment <> 0L ->
        error operation Invalid_argument
          "heap placement offset does not meet resource alignment"
    | Placement, Some offset
      when offset > value.descriptor.size
           || required.size > Int64.sub value.descriptor.size offset ->
        error operation Invalid_argument "heap placement exceeds the heap"
    | Placement, Some offset ->
        let active =
          List.filter
            (fun (allocation : heap_allocation) ->
              Atomic.get allocation.active)
            !(value.allocations)
        in
        value.allocations := active;
        let limit = Int64.add offset required.size in
        if
          List.exists
            (fun (allocation : heap_allocation) ->
              offset < Int64.add allocation.offset allocation.size
              && allocation.offset < limit)
            active
        then
          error operation Invalid_state
            "heap placement overlaps a live non-aliasable resource"
        else Ok ()
    | Sparse, None -> Ok ()
    | Sparse, Some _ ->
        error operation Invalid_argument
          "sparse heaps do not accept placement offsets"

  let make_allocation offset (required : size_and_align) =
    Option.map
      (fun offset ->
        ({ offset; size = required.size; active = Atomic.make true }
          : heap_allocation))
      offset

  let register_allocation value allocation result =
    match result with
    | Error _ as failure -> failure
    | Ok resource ->
        Option.iter
          (fun allocation ->
            value.allocations := allocation :: !(value.allocations))
          allocation;
        Ok resource

  let create_buffer (value : t) ?offset ~length ?label () =
    on_main "Metal.Heap.create_buffer" (fun () ->
      match ensure_live "Metal.Heap.create_buffer" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
          error "Metal.Heap.create_buffer" Invalid_state
            "heap must be nonvolatile before allocating resources"
      | Ok () when value.descriptor.kind = Sparse ->
          error "Metal.Heap.create_buffer" Unsupported
            "legacy sparse heaps allocate textures, not buffers"
      | Ok () ->
          match
            Buffer.validate_create "Metal.Heap.create_buffer" value.device
              ~length ~label
          with
          | Error _ as failure -> failure
          | Ok () ->
              let descriptor = value.descriptor in
              let options =
                resource_options_code ~storage:descriptor.storage
                  ~cpu_cache:descriptor.cpu_cache
                  ~hazard_tracking:descriptor.hazard_tracking
              in
              match
                Metal_raw.heap_buffer_size_and_align value.device.raw length
                  options
                |> validate_size_and_align "Metal.Heap.create_buffer"
                     ~minimum:length
              with
              | Error _ as failure -> failure
              | Ok required ->
                  match
                    validate_placement "Metal.Heap.create_buffer" value offset
                      required
                  with
                  | Error _ as failure -> failure
                  | Ok () ->
                      let allocation = make_allocation offset required in
                      let result =
                        match
                          Metal_raw.heap_buffer_create value.raw length options
                            offset
                        with
                        | Error message ->
                            native_error "Metal.Heap.create_buffer" message
                        | Ok raw ->
                            Buffer.finish_create "Metal.Heap.create_buffer"
                              ~device:value.device ~parent:(Heap_resource value)
                              ~length ~storage:descriptor.storage
                              ~cpu_cache:descriptor.cpu_cache
                              ~hazard_tracking:descriptor.hazard_tracking
                              ~heap_offset:offset ~allocation ~label raw
                      in
                      register_allocation value allocation result)

  let create_texture (value : t) ?offset (descriptor : Texture.descriptor) =
    on_main "Metal.Heap.create_texture" (fun () ->
      match ensure_live "Metal.Heap.create_texture" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
          error "Metal.Heap.create_texture" Invalid_state
            "heap must be nonvolatile before allocating resources"
      | Ok () ->
          let expected_hazard =
            concrete_hazard_tracking ~heap:true descriptor.hazard_tracking
          in
          if descriptor.storage <> value.descriptor.storage
             || descriptor.cpu_cache <> value.descriptor.cpu_cache
             || expected_hazard <> value.descriptor.hazard_tracking
          then
            error "Metal.Heap.create_texture" Invalid_argument
              "texture storage, cache, and hazard modes must match the heap"
          else
            match
              Texture.validate_descriptor "Metal.Heap.create_texture"
                value.device descriptor
            with
           | Error _ as failure -> failure
           | Ok () when descriptor.kind = Texture.Texture_buffer ->
               error "Metal.Heap.create_texture" Invalid_argument
                 "texture-buffer resources must be created from a buffer"
           | Ok () ->
               let descriptor =
                 { descriptor with hazard_tracking = expected_hazard }
               in
               match value.descriptor.kind with
               | Sparse ->
                   (match offset, value.descriptor.sparse_page_size with
                    | Some _, _ ->
                        error "Metal.Heap.create_texture" Invalid_argument
                          "sparse heaps do not accept placement offsets"
                    | None, None ->
                        native_error "Metal.Heap.create_texture"
                          "sparse heap lost its checked page size"
                    | None, Some page_size ->
                        let sparse_kind_supported =
                          match descriptor.kind with
                          | Texture.Texture_2d | Texture.Texture_2d_array
                          | Texture.Texture_cube | Texture.Texture_cube_array
                          | Texture.Texture_3d -> true
                          | Texture.Texture_1d | Texture.Texture_1d_array
                          | Texture.Texture_2d_multisample
                          | Texture.Texture_2d_multisample_array
                          | Texture.Texture_buffer -> false
                        in
                        if not sparse_kind_supported then
                          error "Metal.Heap.create_texture" Unsupported
                            "sparse heaps support reviewed 2D, cube, and 3D texture kinds"
                        else if
                          Metal_format.is_depth_or_stencil descriptor.format
                          || Metal_format.is_subsampled descriptor.format
                        then
                          error "Metal.Heap.create_texture" Unsupported
                            "sparse depth, stencil, and subsampled textures are not yet in the reviewed format matrix"
                        else
                          match
                            Metal_raw.device_sparse_texture_tile_size
                              value.device.raw
                              (Texture.kind_code descriptor.kind)
                              (Texture.format_code descriptor.format)
                              descriptor.sample_count
                              (sparse_page_size_code page_size)
                          with
                          | Error message ->
                              error "Metal.Heap.create_texture" Unsupported
                                message
                          | Ok (width, height, depth)
                            when width <= 0 || height <= 0 || depth <= 0 ->
                              native_error "Metal.Heap.create_texture"
                                "Metal returned invalid sparse tile dimensions"
                          | Ok _ ->
                              (match
                                 Metal_raw.heap_texture_create value.raw
                                   (Texture.descriptor_tuple descriptor) None
                                   descriptor.label
                               with
                               | Error message ->
                                   native_error "Metal.Heap.create_texture"
                                     message
                               | Ok raw ->
                                   Texture.finish_create
                                     "Metal.Heap.create_texture"
                                     ~device:value.device ~descriptor
                                     ~parent:
                                       (Texture_resource (Heap_resource value))
                                     ~heap_offset:None ~allocation:None raw))
               | Automatic | Placement ->
                   (match
                      Metal_raw.heap_texture_size_and_align value.device.raw
                        (Texture.descriptor_tuple descriptor)
                      |> validate_size_and_align "Metal.Heap.create_texture"
                           ~minimum:1L
                    with
                    | Error _ as failure -> failure
                    | Ok required ->
                        (match
                           validate_placement "Metal.Heap.create_texture" value
                             offset required
                         with
                         | Error _ as failure -> failure
                         | Ok () ->
                             let allocation = make_allocation offset required in
                             let result =
                               match
                                 Metal_raw.heap_texture_create value.raw
                                   (Texture.descriptor_tuple descriptor) offset
                                   descriptor.label
                               with
                               | Error message ->
                                   native_error "Metal.Heap.create_texture"
                                     message
                               | Ok raw ->
                                   Texture.finish_create
                                     "Metal.Heap.create_texture"
                                     ~device:value.device ~descriptor
                                     ~parent:
                                       (Texture_resource (Heap_resource value))
                                     ~heap_offset:offset ~allocation raw
                             in
                             register_allocation value allocation result)))

  let destroy (value : t) =
    destroy_parent "Metal.Heap.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Residency_set = struct
  type t = residency_set

  type allocation = residency_allocation =
    | Buffer of Buffer.t
    | Texture of Texture.t
    | Heap of Heap.t

  type descriptor = residency_descriptor =
    { label : string option
    ; initial_capacity : int
    }

  let make_descriptor ?label ?(initial_capacity = 0) () =
    { label; initial_capacity }

  let allocation_lifetime = function
    | Buffer value -> value.lifetime
    | Texture value -> value.lifetime
    | Heap value -> value.lifetime

  let allocation_device = function
    | Buffer value -> value.device
    | Texture value -> value.device
    | Heap value -> value.device

  let allocation_raw = function
    | Buffer value -> value.raw
    | Texture value -> value.raw
    | Heap value -> value.raw

  let allocation_generation allocation =
    Metal_raw.generation (allocation_raw allocation)

  let allocation_heap = function
    | Buffer value -> parent_heap value.parent
    | Texture value -> texture_heap value
    | Heap value -> Some value

  let attach_allocation allocation =
    attach (allocation_lifetime allocation);
    Option.iter (fun heap -> Atomic.incr heap.active_uses)
      (allocation_heap allocation)

  let detach_allocation allocation =
    detach (allocation_lifetime allocation);
    Option.iter (fun heap -> Atomic.decr heap.active_uses)
      (allocation_heap allocation)

  let release_members members =
    Hashtbl.iter
      (fun _ (member : residency_member) ->
        detach_allocation member.allocation)
      members;
    Hashtbl.clear members

  let ensure_allocation_live operation = function
    | Buffer value -> ensure_live operation value.lifetime
    | Texture value -> ensure_live operation value.lifetime
    | Heap value -> ensure_live operation value.lifetime

  let ensure_allocation_usable operation = function
    | Buffer value -> ensure_buffer_usable operation value
    | Texture value -> ensure_texture_usable operation value
    | Heap value ->
        (match ensure_live operation value.lifetime with
         | Error _ as failure -> failure
         | Ok () when Atomic.get value.purgeable <> Nonvolatile ->
             error operation Invalid_state
               "heap must be nonvolatile before entering a residency set"
         | Ok () -> Ok ())

  let validate_unique operation allocations =
    let seen = Hashtbl.create (List.length allocations) in
    let rec loop = function
      | [] -> Ok ()
      | allocation :: rest ->
          let generation = allocation_generation allocation in
          if Hashtbl.mem seen generation then
            error operation Invalid_argument
              "residency allocation list contains a duplicate handle"
          else begin
            Hashtbl.add seen generation ();
            loop rest
          end
    in
    loop allocations

  let validate_allocations operation (value : t) ~usable allocations =
    match validate_unique operation allocations with
    | Error _ as failure -> failure
    | Ok () ->
        let rec loop = function
          | [] -> Ok ()
          | allocation :: rest ->
              let live =
                if usable then ensure_allocation_usable operation allocation
                else ensure_allocation_live operation allocation
              in
              (match live with
               | Error _ as failure -> failure
               | Ok () ->
                   (match
                      ensure_same_device operation value.device
                        (allocation_device allocation)
                    with
                    | Error _ as failure -> failure
                    | Ok () -> loop rest))
        in
        loop allocations

  let find_member (value : t) allocation =
    Hashtbl.find_opt value.members (allocation_generation allocation)

  let present_count (value : t) =
    Hashtbl.fold
      (fun _ (member : residency_member) count ->
        if member.present then count + 1 else count)
      value.members 0

  let validate_native_count operation (value : t) =
    match Metal_raw.residency_set_counts value.raw with
    | Error message -> native_error operation message
    | Ok (count, all_count) ->
        let expected = Int64.of_int (present_count value) in
        let retained = Int64.of_int (Hashtbl.length value.members) in
        if count < 0L || all_count < 0L then
          native_error operation
            (Printf.sprintf
               "Metal returned negative residency allocation counts (count=%Ld all=%Ld)"
               count all_count)
        else if all_count <> expected then
          native_error operation
            (Printf.sprintf
               "Metal residency membership diverged from the safe ownership ledger (all=%Ld expected=%Ld)"
               all_count expected)
        else if count <> expected && count <> retained then
          native_error operation
            (Printf.sprintf
               "Metal returned an unexplained residency allocation count (count=%Ld present=%Ld retained=%Ld)"
               count expected retained)
        else if all_count > Int64.of_int max_int then
          native_error operation
            "Metal residency allocation count exceeds an OCaml integer"
        else Ok (Int64.to_int all_count)

  let validate_descriptor operation (descriptor : descriptor) =
    if descriptor.initial_capacity < 0 then
      error operation Invalid_argument
        "residency-set initial capacity must be nonnegative"
    else if option_exists contains_nul descriptor.label then
      error operation Invalid_argument
        "residency-set label contains a NUL byte"
    else Ok ()

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Residency_set.create" (fun () ->
      match ensure_live "Metal.Residency_set.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_descriptor "Metal.Residency_set.create" descriptor
           with
           | Error _ as failure -> failure
           | Ok () when not (Metal_raw.device_supports_residency_sets device.raw) ->
               error "Metal.Residency_set.create" Unsupported
                 "residency sets require macOS 15 and device API support"
           | Ok () ->
               match
                 Metal_raw.residency_set_create device.raw
                   descriptor.initial_capacity descriptor.label
               with
               | Error message ->
                   native_error "Metal.Residency_set.create" message
               | Ok raw ->
                   let members = Hashtbl.create descriptor.initial_capacity in
                   let value : t =
                     { raw; lifetime = lifetime (); device; members }
                   in
                   (match
                      validate_native_count "Metal.Residency_set.create" value
                    with
                    | Error _ as failure ->
                        ignore (Metal_raw.destroy raw);
                        failure
                    | Ok _ ->
                        attach device.lifetime;
                        attach_finalizer
                          ~on_finalize:(fun () -> release_members members)
                          value value.lifetime device.lifetime;
                        Ok value)))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Residency_set.label" (fun () ->
      match ensure_live "Metal.Residency_set.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.residency_set_label value.raw with
           | Ok label -> Ok label
           | Error message -> native_error "Metal.Residency_set.label" message))

  let allocated_size (value : t) =
    on_main "Metal.Residency_set.allocated_size" (fun () ->
      match ensure_live "Metal.Residency_set.allocated_size" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.residency_set_allocated_size value.raw with
           | Error message ->
               native_error "Metal.Residency_set.allocated_size" message
           | Ok size -> Ok size))

  let allocation_size allocation =
    on_main "Metal.Residency_set.allocation_size" (fun () ->
      match
        ensure_allocation_live "Metal.Residency_set.allocation_size" allocation
      with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             Metal_raw.allocation_allocated_size (allocation_raw allocation)
           with
           | Error message ->
               native_error "Metal.Residency_set.allocation_size" message
           | Ok size -> Ok size))

  let allocation_count (value : t) =
    on_main "Metal.Residency_set.allocation_count" (fun () ->
      match ensure_live "Metal.Residency_set.allocation_count" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          validate_native_count "Metal.Residency_set.allocation_count" value)

  let allocations (value : t) =
    on_main "Metal.Residency_set.allocations" (fun () ->
      match ensure_live "Metal.Residency_set.allocations" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_native_count "Metal.Residency_set.allocations" value with
           | Error _ as failure -> failure
           | Ok _ ->
               Ok
                 (List.filter_map
                    (fun (_, (member : residency_member)) ->
                      if member.present then Some member.allocation else None)
                    (Hashtbl.to_seq value.members |> List.of_seq))))

  let add operation ~bulk (value : t) allocations =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () ->
        (match validate_allocations operation value ~usable:true allocations with
         | Error _ as failure -> failure
         | Ok () ->
             let changes =
               List.filter
                 (fun allocation ->
                   match find_member value allocation with
                   | Some member -> not member.present
                   | None -> true)
                 allocations
             in
             if changes = [] then Ok ()
             else
               let raw_result =
                 match bulk, changes with
                 | false, [ allocation ] ->
                     Metal_raw.residency_set_add_allocation value.raw
                       (allocation_raw allocation)
                 | false, _ -> assert false
                 | true, _ ->
                     Metal_raw.residency_set_add_allocations value.raw
                       (Array.of_list (List.map allocation_raw changes))
               in
               match raw_result with
               | Error message -> native_error operation message
               | Ok () ->
                   List.iter
                     (fun allocation ->
                       match find_member value allocation with
                       | Some member -> member.present <- true
                       | None ->
                           attach_allocation allocation;
                           Hashtbl.add value.members
                             (allocation_generation allocation)
                             { allocation; present = true })
                     changes;
                   (match validate_native_count operation value with
                    | Error _ as failure -> failure
                    | Ok _ -> Ok ()))

  let add_allocation (value : t) allocation =
    on_main "Metal.Residency_set.add_allocation" (fun () ->
      add "Metal.Residency_set.add_allocation" ~bulk:false value [ allocation ])

  let add_allocations (value : t) allocations =
    on_main "Metal.Residency_set.add_allocations" (fun () ->
      add "Metal.Residency_set.add_allocations" ~bulk:true value allocations)

  let remove operation ~bulk (value : t) allocations =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () ->
        (match validate_allocations operation value ~usable:false allocations with
         | Error _ as failure -> failure
         | Ok () ->
             let changes =
               List.filter
                 (fun allocation ->
                   match find_member value allocation with
                   | Some member -> member.present
                   | None -> false)
                 allocations
             in
             if changes = [] then Ok ()
             else
               let raw_result =
                 match bulk, changes with
                 | false, [ allocation ] ->
                     Metal_raw.residency_set_remove_allocation value.raw
                       (allocation_raw allocation)
                 | false, _ -> assert false
                 | true, _ ->
                     Metal_raw.residency_set_remove_allocations value.raw
                       (Array.of_list (List.map allocation_raw changes))
               in
               match raw_result with
               | Error message -> native_error operation message
               | Ok () ->
                   List.iter
                     (fun allocation ->
                       match find_member value allocation with
                       | Some member -> member.present <- false
                       | None -> assert false)
                     changes;
                   (match validate_native_count operation value with
                    | Error _ as failure -> failure
                    | Ok _ -> Ok ()))

  let remove_allocation (value : t) allocation =
    on_main "Metal.Residency_set.remove_allocation" (fun () ->
      remove "Metal.Residency_set.remove_allocation" ~bulk:false value
        [ allocation ])

  let remove_allocations (value : t) allocations =
    on_main "Metal.Residency_set.remove_allocations" (fun () ->
      remove "Metal.Residency_set.remove_allocations" ~bulk:true value
        allocations)

  let remove_all_allocations (value : t) =
    on_main "Metal.Residency_set.remove_all_allocations" (fun () ->
      match ensure_live "Metal.Residency_set.remove_all_allocations" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          if present_count value = 0 then Ok ()
          else
            match Metal_raw.residency_set_remove_all value.raw with
            | Error message ->
                native_error "Metal.Residency_set.remove_all_allocations" message
            | Ok () ->
                Hashtbl.iter
                  (fun _ (member : residency_member) ->
                    member.present <- false)
                  value.members;
                (match
                   validate_native_count
                     "Metal.Residency_set.remove_all_allocations" value
                 with
                 | Error _ as failure -> failure
                 | Ok _ -> Ok ()))

  let contains (value : t) allocation =
    on_main "Metal.Residency_set.contains" (fun () ->
      match ensure_live "Metal.Residency_set.contains" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match
             validate_allocations "Metal.Residency_set.contains" value
               ~usable:false [ allocation ]
           with
           | Error _ as failure -> failure
           | Ok () ->
               let expected =
                 match find_member value allocation with
                 | Some member -> member.present
                 | None -> false
               in
               (match
                  Metal_raw.residency_set_contains value.raw
                    (allocation_raw allocation)
                with
                | Error message ->
                    native_error "Metal.Residency_set.contains" message
                | Ok actual ->
                    if actual <> expected then
                      native_error "Metal.Residency_set.contains"
                        "Metal residency membership diverged from the safe ownership ledger"
                    else Ok actual)))

  let commit (value : t) =
    on_main "Metal.Residency_set.commit" (fun () ->
      match ensure_live "Metal.Residency_set.commit" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.residency_set_commit value.raw with
           | Error message -> native_error "Metal.Residency_set.commit" message
           | Ok () ->
               let removed =
                 Hashtbl.fold
                   (fun generation (member : residency_member) removed ->
                     if member.present then removed
                     else (generation, member) :: removed)
                   value.members []
               in
               List.iter
                 (fun (generation, (member : residency_member)) ->
                   Hashtbl.remove value.members generation;
                   detach_allocation member.allocation)
                 removed;
               (match validate_native_count "Metal.Residency_set.commit" value with
                | Error _ as failure -> failure
                | Ok _ -> Ok ())))

  let request_residency (value : t) =
    on_main "Metal.Residency_set.request_residency" (fun () ->
      match ensure_live "Metal.Residency_set.request_residency" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.residency_set_request value.raw with
           | Ok () -> Ok ()
           | Error message ->
               native_error "Metal.Residency_set.request_residency" message))

  let end_residency (value : t) =
    on_main "Metal.Residency_set.end_residency" (fun () ->
      match ensure_live "Metal.Residency_set.end_residency" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.residency_set_end value.raw with
           | Ok () -> Ok ()
           | Error message ->
               native_error "Metal.Residency_set.end_residency" message))

  let destroy (value : t) =
    destroy_parent "Metal.Residency_set.destroy" value.lifetime value.raw
      (fun () ->
        release_members value.members;
        detach value.device.lifetime)
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

  let same_residency_set (left : residency_set) (right : residency_set) =
    left.lifetime == right.lifetime

  let rec validate_unique operation seen = function
    | [] -> Ok ()
    | value :: rest ->
        if List.exists (same_residency_set value) seen then
          error operation Invalid_argument
            "residency-set list contains a duplicate handle"
        else validate_unique operation (value :: seen) rest

  let validate_sets operation (value : t) residency_sets =
    match validate_unique operation [] residency_sets with
    | Error _ as failure -> failure
    | Ok () ->
        let rec loop = function
          | [] -> Ok ()
          | (residency_set : residency_set) :: rest ->
              (match ensure_live operation residency_set.lifetime with
               | Error _ as failure -> failure
               | Ok () ->
                   (match
                      ensure_same_device operation value.device
                        residency_set.device
                    with
                    | Error _ as failure -> failure
                    | Ok () -> loop rest))
        in
        loop residency_sets

  let create (device : Device.t) =
    on_main "Metal.Command_queue.create" (fun () ->
      match ensure_live "Metal.Command_queue.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.command_queue_create device.raw with
           | Error message -> native_error "Metal.Command_queue.create" message
           | Ok raw ->
               let residency_sets = ref [] in
               let value : t =
                 { raw; lifetime = lifetime (); device; residency_sets }
               in
               attach device.lifetime;
               attach_finalizer
                 ~on_finalize:(fun () ->
                   release_queue_residency_sets residency_sets)
                 value value.lifetime device.lifetime;
               Ok value))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let add operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () ->
        (match validate_sets operation value residency_sets with
         | Error _ as failure -> failure
         | Ok () ->
             let changes =
               List.filter
                 (fun residency_set ->
                   not
                     (List.exists (same_residency_set residency_set)
                        !(value.residency_sets)))
                 residency_sets
             in
             if changes = [] then Ok ()
             else
               let raw_result =
                 match bulk, changes with
                 | false, [ residency_set ] ->
                     Metal_raw.command_queue_add_residency_set value.raw
                       residency_set.raw
                 | false, _ -> assert false
                 | true, _ ->
                     Metal_raw.command_queue_add_residency_sets value.raw
                       (Array.of_list
                          (List.map
                             (fun (set : residency_set) -> set.raw)
                             changes))
               in
               match raw_result with
               | Error message -> native_error operation message
               | Ok () ->
                   List.iter
                     (fun (residency_set : residency_set) ->
                       attach residency_set.lifetime)
                     changes;
                   value.residency_sets :=
                     List.rev_append changes !(value.residency_sets);
                   Ok ())

  let add_residency_set (value : t) residency_set =
    on_main "Metal.Command_queue.add_residency_set" (fun () ->
      add "Metal.Command_queue.add_residency_set" ~bulk:false value
        [ residency_set ])

  let add_residency_sets (value : t) residency_sets =
    on_main "Metal.Command_queue.add_residency_sets" (fun () ->
      add "Metal.Command_queue.add_residency_sets" ~bulk:true value
        residency_sets)

  let remove operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () ->
        (match validate_sets operation value residency_sets with
         | Error _ as failure -> failure
         | Ok () ->
             let changes =
               List.filter
                 (fun residency_set ->
                   List.exists (same_residency_set residency_set)
                     !(value.residency_sets))
                 residency_sets
             in
             if changes = [] then Ok ()
             else
               let raw_result =
                 match bulk, changes with
                 | false, [ residency_set ] ->
                     Metal_raw.command_queue_remove_residency_set value.raw
                       residency_set.raw
                 | false, _ -> assert false
                 | true, _ ->
                     Metal_raw.command_queue_remove_residency_sets value.raw
                       (Array.of_list
                          (List.map
                             (fun (set : residency_set) -> set.raw)
                             changes))
               in
               match raw_result with
               | Error message -> native_error operation message
               | Ok () ->
                   value.residency_sets :=
                     List.filter
                       (fun retained ->
                         not
                           (List.exists (same_residency_set retained) changes))
                       !(value.residency_sets);
                   List.iter
                     (fun (residency_set : residency_set) ->
                       detach residency_set.lifetime)
                     changes;
                   Ok ())

  let remove_residency_set (value : t) residency_set =
    on_main "Metal.Command_queue.remove_residency_set" (fun () ->
      remove "Metal.Command_queue.remove_residency_set" ~bulk:false value
        [ residency_set ])

  let remove_residency_sets (value : t) residency_sets =
    on_main "Metal.Command_queue.remove_residency_sets" (fun () ->
      remove "Metal.Command_queue.remove_residency_sets" ~bulk:true value
        residency_sets)

  let destroy (value : t) =
    destroy_parent "Metal.Command_queue.destroy" value.lifetime value.raw
      (fun () ->
        release_queue_residency_sets value.residency_sets;
        detach value.device.lifetime)
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
                     { raw
                     ; lifetime = lifetime ()
                     ; queue
                     ; phase = Recording
                     ; resources = ref []
                     }
                   in
                   attach queue.lifetime;
                   let resources = value.resources in
                   attach_finalizer
                     ~on_finalize:(fun () -> release_command_resources resources)
                     value value.lifetime queue.lifetime;
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

  let retains_residency_set (value : t) (residency_set : residency_set) =
    List.exists
      (function
        | Command_residency_set retained ->
            retained.lifetime == residency_set.lifetime
        | Command_buffer_buffer _ | Command_buffer_texture _ -> false)
      !(value.resources)

  let use operation ~bulk (value : t) residency_sets =
    match ensure_live operation value.lifetime with
    | Error _ as failure -> failure
    | Ok () when value.phase <> Recording ->
        error operation Invalid_state
          "command buffer is no longer recording"
    | Ok () ->
        (match Command_queue.validate_sets operation value.queue residency_sets with
         | Error _ as failure -> failure
         | Ok () ->
             let changes =
               List.filter
                 (fun residency_set ->
                   not (retains_residency_set value residency_set))
                 residency_sets
             in
             if changes = [] then Ok ()
             else
               let raw_result =
                 match bulk, changes with
                 | false, [ residency_set ] ->
                     Metal_raw.command_buffer_use_residency_set value.raw
                       residency_set.raw
                 | false, _ -> assert false
                 | true, _ ->
                     Metal_raw.command_buffer_use_residency_sets value.raw
                       (Array.of_list
                          (List.map
                             (fun (set : residency_set) -> set.raw)
                             changes))
               in
               match raw_result with
               | Error message -> native_error operation message
               | Ok () ->
                   List.iter
                     (retain_command_buffer_residency_set value)
                     changes;
                   Ok ())

  let use_residency_set (value : t) residency_set =
    on_main "Metal.Command_buffer.use_residency_set" (fun () ->
      use "Metal.Command_buffer.use_residency_set" ~bulk:false value
        [ residency_set ])

  let use_residency_sets (value : t) residency_sets =
    on_main "Metal.Command_buffer.use_residency_sets" (fun () ->
      use "Metal.Command_buffer.use_residency_sets" ~bulk:true value
        residency_sets)

  let status (value : t) =
    on_main "Metal.Command_buffer.status" (fun () ->
      match ensure_live "Metal.Command_buffer.status" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          let status = Metal_raw.command_buffer_status value.raw in
          if status = 4 || status = 5 then
            release_command_resources value.resources;
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
          if status = 4 || status = 5 then
            release_command_resources value.resources;
          if status = 4 then Ok () else
            native_error "Metal.Command_buffer.wait_until_completed"
              (Option.value (Metal_raw.command_buffer_error value.raw)
                 ~default:
                   (Printf.sprintf "command buffer ended with status %d" status)))

  let destroy (value : t) =
    destroy_parent "Metal.Command_buffer.destroy" value.lifetime value.raw
      (fun () ->
        release_command_resources value.resources;
        detach value.queue.lifetime)
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
          (match ensure_buffer_usable "Metal.Compute_encoder.set_buffer" buffer with
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
                   | Ok () ->
                       retain_command_buffer_buffer value.command_buffer buffer;
                       Ok ()
                   | Error message ->
                       native_error "Metal.Compute_encoder.set_buffer" message))

  let set_texture (value : t) ~index (texture : Texture.t) =
    on_main "Metal.Compute_encoder.set_texture" (fun () ->
      match ensure_live "Metal.Compute_encoder.set_texture" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_texture_usable "Metal.Compute_encoder.set_texture" texture with
           | Error _ as failure -> failure
           | Ok () when index < 0 || index >= 31 ->
               error "Metal.Compute_encoder.set_texture" Invalid_argument
                 "texture index must be in [0, 31)"
           | Ok () ->
               (match
                  ensure_same_device "Metal.Compute_encoder.set_texture"
                    value.command_buffer.queue.device texture.device
                with
                | Error _ as failure -> failure
                | Ok () ->
                    match
                      Metal_raw.compute_encoder_set_texture value.raw texture.raw
                        index
                    with
                    | Ok () ->
                        retain_command_buffer_texture value.command_buffer texture;
                        Ok ()
                    | Error message ->
                        native_error "Metal.Compute_encoder.set_texture"
                          message)))

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

module Resource_state_encoder = struct
  type t = resource_state_encoder

  type mapping_mode =
    | Map
    | Unmap

  type tile_region =
    { x : int
    ; y : int
    ; z : int
    ; width : int
    ; height : int
    ; depth : int
    }

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Resource_state_encoder.create" (fun () ->
      match
        ensure_live "Metal.Resource_state_encoder.create"
          command_buffer.lifetime
      with
      | Error _ as failure -> failure
      | Ok () when command_buffer.phase <> Recording ->
          error "Metal.Resource_state_encoder.create" Invalid_state
            "command buffer is no longer recording"
      | Ok () when dependent_count command_buffer.lifetime <> 0 ->
          error "Metal.Resource_state_encoder.create" Invalid_state
            "command buffer already has an open encoder"
      | Ok () ->
          (match
             Metal_raw.command_buffer_resource_state_encoder command_buffer.raw
           with
           | Error message ->
               native_error "Metal.Resource_state_encoder.create" message
           | Ok raw ->
               let value : t =
                 { raw; lifetime = lifetime (); command_buffer }
               in
               attach command_buffer.lifetime;
               attach_finalizer value value.lifetime command_buffer.lifetime;
               Ok value))

  let destroyed (value : t) = is_destroyed value.lifetime
  let mode_code = function Map -> 0 | Unmap -> 1

  let ceil_div value divisor =
    1 + ((value - 1) / divisor)

  let region_tuple (region : tile_region) =
    ( region.x
    , region.y
    , region.z
    , region.width
    , region.height
    , region.depth )

  let valid_axis origin length limit =
    origin >= 0 && length > 0 && origin <= limit && length <= limit - origin

  let tile_cardinality operation region =
    if region.width > max_int / region.height then
      error operation Invalid_argument
        "sparse tile-region cardinality overflows an OCaml integer"
    else
      let area = region.width * region.height in
      if area > max_int / region.depth then
        error operation Invalid_argument
          "sparse tile-region cardinality overflows an OCaml integer"
      else Ok (area * region.depth)

  let update_texture_mapping (value : t) ~mode (texture : Texture.t)
      ~mip_level ~slice ~(region : tile_region) =
    let operation = "Metal.Resource_state_encoder.update_texture_mapping" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_texture_usable operation texture with
           | Error _ as failure -> failure
           | Ok () ->
               (match
                  ensure_same_device operation
                    value.command_buffer.queue.device texture.device
                with
                | Error _ as failure -> failure
                | Ok () ->
                    (match Texture.sparse_info_raw operation texture with
                     | Error _ as failure -> failure
                     | Ok None ->
                         error operation Invalid_argument
                           "texture is not sparse"
                     | Ok (Some info) ->
                         let descriptor = texture.descriptor in
                         if mip_level < 0
                            || mip_level >= descriptor.mip_levels
                         then
                           error operation Invalid_argument
                             "sparse mapping mip level is outside the texture"
                         else if slice < 0
                                 || slice >= Texture.total_slices descriptor
                         then
                           error operation Invalid_argument
                             "sparse mapping slice is outside the texture"
                         else
                           let mip_width =
                             Texture.mip_dimension descriptor.width mip_level
                           and mip_height =
                             Texture.mip_dimension descriptor.height mip_level
                           and mip_depth =
                             Texture.mip_dimension descriptor.depth mip_level
                           in
                           let tile_width =
                             ceil_div mip_width info.tile_width
                           and tile_height =
                             ceil_div mip_height info.tile_height
                           and tile_depth =
                             ceil_div mip_depth info.tile_depth
                           in
                           if
                             not
                               (valid_axis region.x region.width tile_width
                                && valid_axis region.y region.height tile_height
                                && valid_axis region.z region.depth tile_depth)
                           then
                             error operation Invalid_argument
                               "sparse tile region exceeds the selected mip level"
                           else
                             let tail_error =
                               match info.first_mip_in_tail with
                               | Some first when mip_level > first ->
                                   Some
                                     "map a sparse mip tail through its first mip level"
                               | Some first when mip_level = first
                                                 && region <>
                                                    { x = 0; y = 0; z = 0
                                                    ; width = 1; height = 1
                                                    ; depth = 1
                                                    } ->
                                   Some
                                     "a sparse mip tail mapping must cover its single tail tile"
                               | None | Some _ -> None
                             in
                             (match tail_error with
                              | Some message ->
                                  error operation Invalid_argument message
                              | None ->
                                  (match tile_cardinality operation region with
                                   | Error _ as failure -> failure
                                   | Ok tile_count ->
                                       let required_bytes =
                                         match info.first_mip_in_tail with
                                         | Some first when mip_level = first ->
                                             info.tail_size_in_bytes
                                         | None | Some _ ->
                                             Int64.mul
                                               (Int64.of_int tile_count)
                                               info.tile_size_in_bytes
                                       in
                                       let sparse_heap =
                                         match texture_heap texture with
                                         | Some heap -> heap
                                         | None -> assert false
                                       in
                                       if required_bytes > sparse_heap.descriptor.size
                                       then
                                         error operation Invalid_argument
                                           "mapping requires more physical pages than the sparse heap owns"
                                       else
                                         match
                                           Metal_raw.resource_state_encoder_update_texture_mapping
                                             value.raw texture.raw
                                             (mode_code mode)
                                             (region_tuple region) mip_level
                                             slice
                                         with
                                         | Error message ->
                                             native_error operation message
                                         | Ok () ->
                                             retain_command_buffer_texture
                                               value.command_buffer texture;
                                             Ok ()))))))

  let end_encoding (value : t) =
    on_main "Metal.Resource_state_encoder.end_encoding" (fun () ->
      match ensure_live "Metal.Resource_state_encoder.end_encoding" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.resource_state_encoder_end value.raw with
           | Error message ->
               native_error "Metal.Resource_state_encoder.end_encoding" message
           | Ok () ->
               if Atomic.compare_and_set value.lifetime.destroyed false true
               then begin
                 ignore (Metal_raw.destroy value.raw);
                 detach value.command_buffer.lifetime
               end;
               Ok ()))
end

module Blit_encoder = struct
  type t = blit_encoder

  let create (command_buffer : Command_buffer.t) =
    on_main "Metal.Blit_encoder.create" (fun () ->
      match ensure_live "Metal.Blit_encoder.create" command_buffer.lifetime with
      | Error _ as failure -> failure
      | Ok () when command_buffer.phase <> Recording ->
          error "Metal.Blit_encoder.create" Invalid_state
            "command buffer is no longer recording"
      | Ok () when dependent_count command_buffer.lifetime <> 0 ->
          error "Metal.Blit_encoder.create" Invalid_state
            "command buffer already has an open encoder"
      | Ok () ->
          (match Metal_raw.command_buffer_blit_encoder command_buffer.raw with
           | Error message -> native_error "Metal.Blit_encoder.create" message
           | Ok raw ->
               let value : t =
                 { raw; lifetime = lifetime (); command_buffer }
               in
               attach command_buffer.lifetime;
               attach_finalizer value value.lifetime command_buffer.lifetime;
               Ok value))

  let destroyed (value : t) = is_destroyed value.lifetime

  let copy_buffer_to_texture (value : t) ~(source : Buffer.t) ~source_offset
      ~source_bytes_per_row ~source_bytes_per_image ~(destination : Texture.t)
      ~destination_slice ~destination_level
      ~(destination_region : Texture.region) =
    let operation = "Metal.Blit_encoder.copy_buffer_to_texture" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_buffer_usable operation source with
           | Error _ as failure -> failure
           | Ok () ->
               (match ensure_texture_usable operation destination with
                | Error _ as failure -> failure
                | Ok () ->
                    let descriptor = destination.descriptor in
                    if source_offset < 0L
                       || source_bytes_per_row <= 0
                       || source_bytes_per_image <= 0
                    then
                      error operation Invalid_argument
                        "blit source offset and pitches must be nonnegative and positive"
                    else if descriptor.sample_count <> 1 then
                      error operation Unsupported
                        "multisample textures do not accept buffer blits"
                    else if destination_level < 0
                            || destination_level >= descriptor.mip_levels
                    then
                      error operation Invalid_argument
                        "blit destination mip level is outside the texture"
                    else if destination_slice < 0
                            || destination_slice >=
                               Texture.total_slices descriptor
                    then
                      error operation Invalid_argument
                        "blit destination slice is outside the texture"
                    else if destination_region.x < 0
                            || destination_region.y < 0
                            || destination_region.z < 0
                            || destination_region.width <= 0
                            || destination_region.height <= 0
                            || destination_region.depth <= 0
                    then
                      error operation Invalid_argument
                        "blit destination region is invalid"
                    else
                      let mip_width =
                        Texture.mip_dimension descriptor.width destination_level
                      and mip_height =
                        Texture.mip_dimension descriptor.height destination_level
                      and mip_depth =
                        Texture.mip_dimension descriptor.depth destination_level
                      in
                      if destination_region.x > mip_width
                         || destination_region.width
                            > mip_width - destination_region.x
                         || destination_region.y > mip_height
                         || destination_region.height
                            > mip_height - destination_region.y
                         || destination_region.z > mip_depth
                         || destination_region.depth
                            > mip_depth - destination_region.z
                      then
                        error operation Invalid_argument
                          "blit destination region exceeds the selected mip level"
                      else
                        let layout =
                          Texture.format_layout descriptor.format
                        in
                        let aligned origin length limit block =
                          origin mod block = 0
                          && (length mod block = 0
                              || origin + length = limit)
                        in
                        if
                          not
                            (aligned destination_region.x
                               destination_region.width mip_width
                               layout.block_width
                             && aligned destination_region.y
                                  destination_region.height mip_height
                                  layout.block_height)
                        then
                          error operation Invalid_argument
                            "blit destination region is not format-block aligned"
                        else
                        let blocks value block = 1 + ((value - 1) / block) in
                        let row_blocks =
                          blocks destination_region.width layout.block_width
                        in
                        (match
                           Texture.checked_mul row_blocks
                             layout.bytes_per_block
                         with
                         | None ->
                             error operation Invalid_argument
                               "blit row cardinality overflows an OCaml integer"
                         | Some minimum_row
                           when source_bytes_per_row < minimum_row
                                || source_bytes_per_row
                                   mod layout.bytes_per_block <> 0 ->
                             error operation Invalid_argument
                               "blit source row pitch is too small or not block-aligned"
                         | Some _ ->
                             (match
                                Texture.checked_mul source_bytes_per_row
                                  (blocks destination_region.height
                                     layout.block_height)
                              with
                              | None ->
                                  error operation Invalid_argument
                                    "blit image cardinality overflows an OCaml integer"
                              | Some minimum_image
                                when source_bytes_per_image < minimum_image ->
                                  error operation Invalid_argument
                                    "blit source image pitch is smaller than its rows"
                              | Some _ ->
                                  let image_bytes =
                                    Int64.of_int source_bytes_per_image
                                  and depth =
                                    Int64.of_int destination_region.depth
                                  in
                                  if image_bytes > Int64.div Int64.max_int depth
                                  then
                                    error operation Invalid_argument
                                      "blit source cardinality overflows 64 bits"
                                  else
                                    let total = Int64.mul image_bytes depth in
                                    if source_offset > source.length
                                       || total
                                          > Int64.sub source.length source_offset
                                    then
                                      error operation Invalid_argument
                                        "blit source range exceeds the buffer"
                                    else (match
                                       ensure_same_device operation
                                         value.command_buffer.queue.device
                                         source.device
                                     with
                                     | Error _ as failure -> failure
                                     | Ok () ->
                                         (match
                                            ensure_same_device operation
                                              value.command_buffer.queue.device
                                              destination.device
                                          with
                                          | Error _ as failure -> failure
                                          | Ok () ->
                                              let copy =
                                                ( source_offset
                                                , source_bytes_per_row
                                                , source_bytes_per_image
                                                , (destination_region.width,
                                                   destination_region.height,
                                                   destination_region.depth)
                                                , destination_slice
                                                , destination_level
                                                , (destination_region.x,
                                                   destination_region.y,
                                                   destination_region.z) )
                                              in
                                              match
                                                Metal_raw.blit_encoder_copy_buffer_to_texture
                                                  value.raw source.raw
                                                  destination.raw copy
                                              with
                                              | Error message ->
                                                  native_error operation message
                                              | Ok () ->
                                                  retain_command_buffer_buffer
                                                    value.command_buffer source;
                                                  retain_command_buffer_texture
                                                    value.command_buffer
                                                    destination;
                                                  Ok ())))))))

  let end_encoding (value : t) =
    on_main "Metal.Blit_encoder.end_encoding" (fun () ->
      match ensure_live "Metal.Blit_encoder.end_encoding" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match Metal_raw.blit_encoder_end value.raw with
           | Error message -> native_error "Metal.Blit_encoder.end_encoding" message
           | Ok () ->
               if Atomic.compare_and_set value.lifetime.destroyed false true
               then begin
                 ignore (Metal_raw.destroy value.raw);
                 detach value.command_buffer.lifetime
               end;
               Ok ()))
end
