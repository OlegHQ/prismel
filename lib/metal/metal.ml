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

let validate_absolute_path operation path =
  if path = "" then error operation Invalid_argument "path is empty"
  else if contains_nul path then
    error operation Invalid_argument "path contains a NUL byte"
  else if Filename.is_relative path then
    error operation Invalid_argument "path must be absolute"
  else Ok ()

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
    ; placement_mapping_operations : int64
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
            ; placement_mapping_operations =
                Metal_raw.placement_mapping_operations ()
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

type shader_scalar_type =
  | Float
  | Half
  | Int
  | Uint
  | Short
  | Ushort
  | Char
  | Uchar
  | Bool
  | Long
  | Ulong
  | Bfloat

type shader_data_type =
  | No_type
  | Struct
  | Array
  | Scalar of shader_scalar_type
  | Vector of shader_scalar_type * int
  | Matrix of shader_scalar_type * int * int
  | Texture_type
  | Sampler_type
  | Pointer
  | Other_data_type of int

type shader_binding_access =
  | Read_only
  | Read_write
  | Write_only
  | Unknown_access of int

type buffer_binding_layout =
  { alignment : int64
  ; data_size : int64
  ; data_type : shader_data_type
  }

type texture_binding_layout =
  { texture_kind : texture_kind
  ; data_type : shader_data_type
  ; depth : bool
  ; array_length : int64
  }

type sized_binding_layout =
  { alignment : int64
  ; data_size : int64
  }

type shader_binding_kind =
  | Buffer_binding of buffer_binding_layout
  | Threadgroup_memory_binding of sized_binding_layout
  | Texture_binding of texture_binding_layout
  | Sampler_binding
  | Imageblock_data_binding
  | Imageblock_binding
  | Visible_function_table_binding
  | Primitive_acceleration_structure_binding
  | Instance_acceleration_structure_binding
  | Intersection_function_table_binding
  | Object_payload_binding of sized_binding_layout
  | Tensor_binding
  | Unknown_binding of int

type shader_binding =
  { name : string
  ; index : int64
  ; access : shader_binding_access
  ; used : bool
  ; argument : bool
  ; kind : shader_binding_kind
  }

type shader_binding_layout_kind =
  | Buffer_layout
  | Threadgroup_memory_layout
  | Texture_layout
  | Sampler_layout
  | Imageblock_data_layout
  | Imageblock_layout
  | Visible_function_table_layout
  | Primitive_acceleration_structure_layout
  | Instance_acceleration_structure_layout
  | Intersection_function_table_layout
  | Object_payload_layout
  | Tensor_layout
  | Other_binding_layout of int

type shader_binding_layout =
  { name : string
  ; index : int64
  ; access : shader_binding_access
  ; kind : shader_binding_layout_kind
  ; data_type : shader_data_type option
  }

type function_kind =
  | Vertex
  | Fragment
  | Kernel
  | Visible
  | Intersection
  | Mesh
  | Object
  | Unknown_function_kind of int

type function_constant_value =
  | Bool_constant of bool
  | Int8_constant of int
  | Uint8_constant of int
  | Int16_constant of int
  | Uint16_constant of int
  | Int32_constant of int32
  | Uint32_constant of int64
  | Int64_constant of int64
  | Uint64_bits_constant of int64
  | Float16_constant of float
  | Float32_constant of float

type function_constant =
  { name : string
  ; data_type : shader_data_type
  ; index : int64
  ; required : bool
  }

type library_kind =
  | Executable_library
  | Dynamic_library_source
  | Unknown_library_kind of int

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

type texture_compression_type =
  | Lossless
  | Lossy

type texture_swizzle_channel =
  | Zero
  | One
  | Red
  | Green
  | Blue
  | Alpha

type texture_swizzle =
  { red : texture_swizzle_channel
  ; green : texture_swizzle_channel
  ; blue : texture_swizzle_channel
  ; alpha : texture_swizzle_channel
  }

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
  ; compression : texture_compression_type
  ; swizzle : texture_swizzle
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
  ; placement_sparse_page_size : sparse_page_size option
  ; allocation : heap_allocation option
  ; state : resource_state
  ; placement_mappings : placement_mapping list ref
  }

and texture =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; descriptor : texture_descriptor
  ; parent : texture_parent
  ; heap_offset : int64 option
  ; placement_sparse_page_size : sparse_page_size option
  ; allocation : heap_allocation option
  ; state : resource_state
  ; placement_mappings : placement_mapping list ref
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

and placement_mapping_queue =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; mappings : placement_mapping list ref
  }

and placement_mapping =
  { queue : placement_mapping_queue
  ; heap : heap
  ; allocation : heap_allocation
  ; target : placement_mapping_target
  ; page_size : sparse_page_size
  ; heap_offset : int64
  ; mapped_bytes : int64
  ; active : bool Atomic.t
  }

and placement_mapping_target =
  | Placement_buffer_mapping of
      { buffer : buffer
      ; tile_offset : int64
      ; tile_count : int64
      }
  | Placement_texture_mapping of
      { texture : texture
      ; region : int * int * int * int * int * int
      ; mip_level : int
      ; slice : int
      }

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

type sampler_reduction_mode =
  | Weighted_average
  | Minimum
  | Maximum

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
  ; reduction_mode : sampler_reduction_mode
  ; normalized_coordinates : bool
  ; lod_min_clamp : float
  ; lod_max_clamp : float
  ; lod_average : bool
  ; lod_bias : float
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

type dynamic_library =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  }

type binary_archive =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  }

type pipeline_dataset =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; configuration : int
  }

type pipeline_archive =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  }

type binary_function =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; pipeline_independent : bool
  ; name : string
  ; kind : function_kind
  }

type compiler =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; dataset : pipeline_dataset option
  }

type compute_pipeline =
  { raw : Metal_raw.handle
  ; lifetime : lifetime
  ; device : device
  ; bindings : shader_binding array option
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

  let supports_placement_sparse (value : t) =
    on_main "Metal.Device.supports_placement_sparse" (fun () ->
      match
        ensure_live "Metal.Device.supports_placement_sparse" value.lifetime
      with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_placement_sparse value.raw))

  let supports_sampler_reduction (value : t) =
    on_main "Metal.Device.supports_sampler_reduction" (fun () ->
      match ensure_live "Metal.Device.supports_sampler_reduction" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.device_supports_sampler_reduction value.raw))

  let supports_lossy_texture_compression (value : t) =
    on_main "Metal.Device.supports_lossy_texture_compression" (fun () ->
      match
        ensure_live "Metal.Device.supports_lossy_texture_compression"
          value.lifetime
      with
      | Error _ as failure -> failure
      | Ok () ->
          Ok
            (Metal_raw.device_supports_lossy_texture_compression value.raw))

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

  type sparse_tier =
    | Not_sparse
    | Sparse_tier_1

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

  let finish_create ?placement_sparse_page_size operation ~(device : Device.t)
      ~parent ~length ~storage ~cpu_cache ~hazard_tracking ~heap_offset
      ~allocation ~label raw =
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
            ; placement_sparse_page_size
            ; allocation
            ; state = resource_state ()
            ; placement_mappings = ref []
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

  let create_placement_sparse ~(device : Device.t) ~page_size ~length ~storage
      ?(cpu_cache = Default_cache)
      ?(hazard_tracking = Default_hazard_tracking) ?label () =
    let operation = "Metal.Buffer.create_placement_sparse" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () when not (Metal_raw.device_supports_placement_sparse device.raw) ->
          error operation Unsupported
            "device does not support placement sparse resources"
      | Ok () ->
          (match validate_create operation device ~length ~label with
           | Error _ as failure -> failure
           | Ok () ->
               let options =
                 resource_options_code ~storage ~cpu_cache ~hazard_tracking
               in
               match
                 Metal_raw.buffer_placement_sparse_create device.raw length
                   options (sparse_page_size_code page_size)
               with
               | Error message -> error operation Unsupported message
               | Ok raw ->
                   finish_create ~placement_sparse_page_size:page_size operation
                     ~device ~parent:(Device_resource device) ~length ~storage
                     ~cpu_cache ~hazard_tracking ~heap_offset:None
                     ~allocation:None ~label raw))

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
  let placement_sparse_page_size (value : t) =
    value.placement_sparse_page_size

  let sparse_tier (value : t) =
    let operation = "Metal.Buffer.sparse_tier" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Option.is_none value.placement_sparse_page_size ->
          Ok Not_sparse
      | Ok () ->
          (match Metal_raw.buffer_sparse_tier value.raw with
           | 1 -> Ok Sparse_tier_1
           | -1 -> Ok Sparse_tier_1
           | 0 ->
               native_error operation
                 "placement sparse buffer lost its sparse tier"
           | tier ->
               native_error operation
                 (Printf.sprintf "Metal returned unknown buffer sparse tier %d"
                    tier)))
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.write_bytes" Invalid_state
            "placement sparse buffers have no CPU-visible backing until mapped"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.read_bytes" Invalid_state
            "placement sparse buffers have no CPU-visible backing until mapped"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.with_mapping" Invalid_state
            "placement sparse buffers have no CPU-visible backing until mapped"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.purgeable_state" Invalid_state
            "the placement heap controls physical-page purgeability"
      | Ok () ->
          query_purgeable_state "Metal.Buffer.purgeable_state"
            (Metal_raw.resource_set_purgeable_state value.raw)
            value.state.purgeable)

  let set_purgeable_state (value : t) state =
    on_main "Metal.Buffer.set_purgeable_state" (fun () ->
      match ensure_live "Metal.Buffer.set_purgeable_state" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.set_purgeable_state" Invalid_state
            "set purgeability on the placement heap"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.is_aliasable" Invalid_state
            "placement sparse aliasing is controlled by mapping operations"
      | Ok () -> Ok (Metal_raw.resource_is_aliasable value.raw))

  let make_aliasable (value : t) =
    on_main "Metal.Buffer.make_aliasable" (fun () ->
      match ensure_live "Metal.Buffer.make_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Buffer.make_aliasable" Invalid_state
            "placement sparse aliasing is controlled by mapping operations"
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

  type compression_type = texture_compression_type =
    | Lossless
    | Lossy

  type swizzle_channel = texture_swizzle_channel =
    | Zero
    | One
    | Red
    | Green
    | Blue
    | Alpha

  type swizzle = texture_swizzle =
    { red : swizzle_channel
    ; green : swizzle_channel
    ; blue : swizzle_channel
    ; alpha : swizzle_channel
    }

  type sparse_tier =
    | Not_sparse
    | Sparse_tier_1
    | Sparse_tier_2

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
    ; compression : compression_type
    ; swizzle : swizzle
    ; label : string option
    }

  let compression_code = function Lossless -> 0 | Lossy -> 1

  let compression_of_code = function
    | 0 -> Some Lossless
    | 1 -> Some Lossy
    | _ -> None

  let swizzle_channel_code = function
    | Zero -> 0
    | One -> 1
    | Red -> 2
    | Green -> 3
    | Blue -> 4
    | Alpha -> 5

  let swizzle_channel_of_code = function
    | 0 -> Some Zero
    | 1 -> Some One
    | 2 -> Some Red
    | 3 -> Some Green
    | 4 -> Some Blue
    | 5 -> Some Alpha
    | _ -> None

  let swizzle_codes (value : swizzle) =
    ( swizzle_channel_code value.red
    , swizzle_channel_code value.green
    , swizzle_channel_code value.blue
    , swizzle_channel_code value.alpha )

  let default_swizzle = { red = Red; green = Green; blue = Blue; alpha = Alpha }

  let has_writable_usage =
    List.exists (function
      | Shader_write | Shader_atomic -> true
      | Shader_read | Render_target | Pixel_format_view -> false)

  let has_lossy_incompatible_usage =
    List.exists (function
      | Pixel_format_view | Shader_write | Shader_atomic -> true
      | Shader_read | Render_target -> false)

  let valid_xpc_service_name value =
    value <> "" && String.length value <= 255 && not (contains_nul value)

  let valid_xpc_operation value =
    value <> "" && String.length value <= 256 && not (contains_nul value)

  let valid_xpc_payload_bound value =
    value > 0 && value <= 67_108_864

  let valid_xpc_timeout value = value > 0 && value <= 300_000

  let valid_xpc_capacity value = value > 0 && value <= 1024

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

    module Xpc = struct
      type connection =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; service_name : string
        ; max_payload_bytes : int
        }

      type service =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; max_payload_bytes : int
        }

      type request =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; service : service
        ; operation : string
        ; surface : t
        ; data : bytes
        }

      let metadata_magic = "PMTLIOX1"
      let metadata_header_fields = 4
      let metadata_plane_fields = 5
      let metadata_limit = 4096

      let encode_metadata operation (surface : t) =
        let plane_count = Array.length surface.planes in
        let maximum_plane_count =
          (metadata_limit - String.length metadata_magic
           - (metadata_header_fields * 8))
          / (metadata_plane_fields * 8)
        in
        if
          plane_count > maximum_plane_count
        then
          error operation Invalid_argument
            "IOSurface has too many planes for bounded XPC metadata"
        else
          let field_count =
            metadata_header_fields + (plane_count * metadata_plane_fields)
          in
          let metadata =
            Bytes.create (String.length metadata_magic + (field_count * 8))
          in
          Bytes.blit_string metadata_magic 0 metadata 0
            (String.length metadata_magic);
          let set_field index value =
            Bytes.set_int64_le metadata
              (String.length metadata_magic + (index * 8)) value
          in
          set_field 0 surface.id;
          set_field 1 surface.allocation_size;
          set_field 2 (if surface.planar then 1L else 0L);
          set_field 3 (Int64.of_int plane_count);
          Array.iteri
            (fun index (plane : plane) ->
              let offset =
                metadata_header_fields + (index * metadata_plane_fields)
              in
              set_field offset (Int64.of_int plane.width);
              set_field (offset + 1) (Int64.of_int plane.height);
              set_field (offset + 2) (Int64.of_int plane.bytes_per_element);
              set_field (offset + 3) (Int64.of_int plane.bytes_per_row);
              set_field (offset + 4) plane.size)
            surface.planes;
          Ok metadata

      let decode_metadata operation metadata =
        let malformed detail =
          native_error operation
            ("malformed IOSurface XPC metadata: " ^ detail)
        in
        let magic_length = String.length metadata_magic in
        let minimum_size = magic_length + (metadata_header_fields * 8) in
        if Bytes.length metadata < minimum_size then malformed "wrong byte length"
        else if Bytes.length metadata > metadata_limit then
          malformed "metadata exceeds its protocol bound"
        else if Bytes.sub_string metadata 0 magic_length <> metadata_magic then
          malformed "wrong protocol/version marker"
        else
          let field index =
            Bytes.get_int64_le metadata (magic_length + (index * 8))
          in
          let id = field 0 in
          let allocation_size = field 1 in
          let planar_value = field 2 in
          let plane_count_value = field 3 in
          if id <= 0L || allocation_size <= 0L then
            malformed "invalid identity or allocation size"
          else if planar_value <> 0L && planar_value <> 1L then
            malformed "invalid planar flag"
          else if
            plane_count_value <= 0L
            || plane_count_value > Int64.of_int max_int
          then malformed "invalid plane count"
          else
            let plane_count = Int64.to_int plane_count_value in
            let maximum_plane_count =
              (Bytes.length metadata - minimum_size)
              / (metadata_plane_fields * 8)
            in
            if plane_count > maximum_plane_count then
              malformed "plane count does not match the byte length"
            else
              let expected_size =
                minimum_size + (plane_count * metadata_plane_fields * 8)
              in
              if expected_size <> Bytes.length metadata then
                malformed "plane count does not match the byte length"
              else if planar_value = 0L && plane_count <> 1 then
                malformed "non-planar surface has multiple planes"
              else
                let integer value =
                  if value <= 0L || value > Int64.of_int max_int then None
                  else Some (Int64.to_int value)
                in
                let rec collect index total reversed =
                  if index = plane_count then
                    if allocation_size < total then
                      malformed "allocation is smaller than its plane layout"
                    else
                      Ok
                        ( id
                        , allocation_size
                        , planar_value = 1L
                        , Array.of_list (List.rev reversed) )
                  else
                    let offset =
                      metadata_header_fields + (index * metadata_plane_fields)
                    in
                    match
                      integer (field offset),
                      integer (field (offset + 1)),
                      integer (field (offset + 2)),
                      integer (field (offset + 3))
                    with
                    | Some width, Some height, Some bytes_per_element,
                      Some bytes_per_row
                      when List.mem bytes_per_element [ 1; 2; 4; 8; 16 ]
                           && width <= max_int / bytes_per_element
                           && bytes_per_row >= width * bytes_per_element
                           && bytes_per_row mod bytes_per_element = 0 ->
                        let row64 = Int64.of_int bytes_per_row in
                        let height64 = Int64.of_int height in
                        if height64 > Int64.div Int64.max_int row64 then
                          malformed "plane size overflows 64 bits"
                        else
                          let size = Int64.mul height64 row64 in
                          if field (offset + 4) <> size then
                            malformed
                              "plane size does not match its row layout"
                          else if Int64.sub Int64.max_int total < size then
                            malformed "combined plane size overflows 64 bits"
                          else
                            collect (index + 1) (Int64.add total size)
                              ({ width
                               ; height
                               ; bytes_per_element
                               ; bytes_per_row
                               ; size
                               }
                               :: reversed)
                    | _ -> malformed "invalid plane layout"
                in
                collect 0 0L []

      let wrap_received operation raw metadata =
        let fail_with error_value =
          ignore (Metal_raw.destroy raw);
          error_value
        in
        match decode_metadata operation metadata with
        | Error _ as failure -> fail_with failure
        | Ok (id, allocation_size, planar, planes) ->
            let actual_id, actual_allocation_size, actual_planar, layout =
              Metal_raw.io_surface_info raw
            in
            if
              actual_id <> id || actual_allocation_size <> allocation_size
              || actual_planar <> planar
              || Array.length layout <> Array.length planes * 4
            then
              fail_with
                (native_error operation
                   "received IOSurface does not match its typed XPC metadata")
            else
              let matches = ref true in
              Array.iteri
                (fun index (plane : plane) ->
                  let offset = index * 4 in
                  if
                    layout.(offset) <> plane.width
                    || layout.(offset + 1) <> plane.height
                    || layout.(offset + 2) <> plane.bytes_per_element
                    || layout.(offset + 3) <> plane.bytes_per_row
                  then matches := false)
                planes;
              if not !matches then
                fail_with
                  (native_error operation
                     "received IOSurface changed its checked plane layout")
              else
                Ok
                  { raw
                  ; lifetime = lifetime ()
                  ; id
                  ; allocation_size
                  ; planar
                  ; planes
                  ; label = None
                  }

      let connect ?(max_payload_bytes = 1_048_576) ~service_name () =
        let operation = "Metal.Texture.Io_surface.Xpc.connect" in
        on_main operation (fun () ->
          if not (valid_xpc_service_name service_name) then
            error operation Invalid_argument
              "XPC service name must contain 1-255 bytes and no NUL"
          else if not (valid_xpc_payload_bound max_payload_bytes) then
            error operation Invalid_argument
              "XPC maximum payload must be between one byte and 64 MiB"
          else
            match Metal_raw.xpc_connect 1 service_name max_payload_bytes with
            | Error message -> native_error operation message
            | Ok raw ->
                Ok
                  { raw
                  ; lifetime = lifetime ()
                  ; service_name
                  ; max_payload_bytes
                  })

      let service_name (value : connection) = value.service_name
      let connection_destroyed (value : connection) =
        is_destroyed value.lifetime

      let destroy_connection (value : connection) =
        destroy_leaf "Metal.Texture.Io_surface.Xpc.destroy_connection"
          value.lifetime value.raw (fun () -> ())

      let call ?(timeout_ms = 10_000) (connection : connection) ~operation
          ~(surface : t) data =
        let call_name = "Metal.Texture.Io_surface.Xpc.call" in
        on_main call_name (fun () ->
          match ensure_live call_name connection.lifetime with
          | Error _ as failure -> failure
          | Ok () ->
              (match ensure_live call_name surface.lifetime with
               | Error _ as failure -> failure
               | Ok () when not (valid_xpc_operation operation) ->
                   error call_name Invalid_argument
                     "XPC operation must contain 1-256 bytes and no NUL"
               | Ok () when Bytes.length data > connection.max_payload_bytes ->
                   error call_name Invalid_argument
                     "XPC payload exceeds the connection bound"
               | Ok () when not (valid_xpc_timeout timeout_ms) ->
                   error call_name Invalid_argument
                     "XPC timeout must be between 1 and 300000 milliseconds"
               | Ok () ->
                   (match encode_metadata call_name surface with
                    | Error _ as failure -> failure
                    | Ok metadata ->
                        match
                          Metal_raw.xpc_call connection.raw operation
                            surface.raw metadata data timeout_ms
                        with
                        | Error message -> native_error call_name message
                        | Ok (raw, reply_metadata, reply_data) ->
                            (match
                               wrap_received call_name raw reply_metadata
                             with
                             | Error _ as failure -> failure
                             | Ok reply_surface ->
                                 Ok (reply_surface, reply_data)))))

      let request_operation (value : request) =
        let operation = "Metal.Texture.Io_surface.Xpc.request_operation" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok value.operation)

      let request_surface (value : request) =
        let operation = "Metal.Texture.Io_surface.Xpc.request_surface" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok value.surface)

      let request_data (value : request) =
        let operation = "Metal.Texture.Io_surface.Xpc.request_data" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok (Bytes.copy value.data))

      let request_completed (value : request) = is_destroyed value.lifetime

      let complete_request operation (value : request) native_call =
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            (match native_call () with
             | Error message -> native_error operation message
             | Ok () ->
                 Atomic.set value.lifetime.destroyed true;
                 ignore (Metal_raw.destroy value.raw);
                 detach value.service.lifetime;
                 if dependent_count value.surface.lifetime = 0 then
                   ignore (destroy value.surface);
                 Ok ())

      let reply (value : request) ~(surface : t) data =
        let operation = "Metal.Texture.Io_surface.Xpc.reply" in
        on_main operation (fun () ->
          match ensure_live operation surface.lifetime with
          | Error _ as failure -> failure
          | Ok () when Bytes.length data > value.service.max_payload_bytes ->
              error operation Invalid_argument
                "XPC reply payload exceeds the service bound"
          | Ok () ->
              (match encode_metadata operation surface with
               | Error _ as failure -> failure
               | Ok metadata ->
                   complete_request operation value (fun () ->
                     Metal_raw.xpc_request_reply value.raw surface.raw metadata
                       data)))

      let reject (value : request) message =
        let operation = "Metal.Texture.Io_surface.Xpc.reject" in
        on_main operation (fun () ->
          if message = "" || String.length message > 4096 || contains_nul message
          then
            error operation Invalid_argument
              "XPC rejection must contain 1-4096 bytes and no NUL"
          else
            complete_request operation value (fun () ->
              Metal_raw.xpc_request_reject value.raw message))

      let serve ?(capacity = 16) ?(max_payload_bytes = 1_048_576) handler =
        let operation = "Metal.Texture.Io_surface.Xpc.serve" in
        on_main operation (fun () ->
          if not (valid_xpc_capacity capacity) then
            error operation Invalid_argument
              "XPC request capacity must be between 1 and 1024"
          else if not (valid_xpc_payload_bound max_payload_bytes) then
            error operation Invalid_argument
              "XPC maximum payload must be between one byte and 64 MiB"
          else
            match Metal_raw.xpc_service_create 1 capacity max_payload_bytes with
            | Error message -> native_error operation message
            | Ok raw ->
                let service =
                  { raw; lifetime = lifetime (); max_payload_bytes }
                in
                let reject_raw raw_request raw_surface message =
                  ignore (Metal_raw.xpc_request_reject raw_request message);
                  ignore (Metal_raw.destroy raw_request);
                  Option.iter
                    (fun surface -> ignore (Metal_raw.destroy surface))
                    raw_surface
                in
                let receive raw_request request_operation raw_surface metadata
                    data =
                  if not (valid_xpc_operation request_operation) then
                    reject_raw raw_request (Some raw_surface)
                      "IOSurface XPC operation is malformed"
                  else if Bytes.length data > service.max_payload_bytes then
                    reject_raw raw_request (Some raw_surface)
                      "IOSurface XPC payload exceeds the service bound"
                  else
                    match wrap_received operation raw_surface metadata with
                    | Error error_value ->
                        reject_raw raw_request None error_value.message
                    | Ok surface ->
                        let request =
                          { raw = raw_request
                          ; lifetime = lifetime ()
                          ; service
                          ; operation = request_operation
                          ; surface
                          ; data
                          }
                        in
                        attach service.lifetime;
                        attach_finalizer request request.lifetime
                          service.lifetime;
                        let reject_pending message =
                          if not (request_completed request) then
                            ignore
                              (complete_request operation request (fun () ->
                                 Metal_raw.xpc_request_reject request.raw
                                   message))
                        in
                        (try handler request with _ ->
                           reject_pending
                             "IOSurface XPC handler raised an exception");
                        reject_pending
                          "IOSurface XPC handler returned without a reply"
                in
                let result = Metal_raw.xpc_service_serve raw receive in
                if
                  Atomic.compare_and_set service.lifetime.destroyed false true
                then ignore (Metal_raw.destroy service.raw);
                match result with
                | Ok () -> Ok ()
                | Error message -> native_error operation message)
    end

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

    module Xpc = struct
      type connection =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; device : device
        ; service_name : string
        ; max_payload_bytes : int
        }

      type service =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; device : device
        ; max_payload_bytes : int
        }

      type request =
        { raw : Metal_raw.handle
        ; lifetime : lifetime
        ; service : service
        ; operation : string
        ; handle : t
        ; data : bytes
        }

      let metadata_magic = "PMTLXPC2"
      let metadata_field_count = 18
      let metadata_size = String.length metadata_magic + (metadata_field_count * 8)

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

      let kind_of_code = function
        | 0 -> Some Texture_1d
        | 1 -> Some Texture_1d_array
        | 2 -> Some Texture_2d
        | 3 -> Some Texture_2d_array
        | 4 -> Some Texture_2d_multisample
        | 5 -> Some Texture_cube
        | 6 -> Some Texture_cube_array
        | 7 -> Some Texture_3d
        | 8 -> Some Texture_2d_multisample_array
        | 9 -> Some Texture_buffer
        | _ -> None

      let usage_bits usages =
        List.fold_left
          (fun bits -> function
            | Shader_read -> bits lor 0x1
            | Shader_write -> bits lor 0x2
            | Render_target -> bits lor 0x4
            | Pixel_format_view -> bits lor 0x10
            | Shader_atomic -> bits lor 0x20)
          0 usages

      let usages_of_bits bits =
        if bits land lnot 0x37 <> 0 then None
        else
          Some
            (List.filter_map
               (fun (bit, usage) -> if bits land bit = 0 then None else Some usage)
               [ 0x1, Shader_read; 0x2, Shader_write; 0x4, Render_target
               ; 0x10, Pixel_format_view; 0x20, Shader_atomic
               ])

      let encode_descriptor (descriptor : texture_descriptor) =
        let swizzle_red, swizzle_green, swizzle_blue, swizzle_alpha =
          swizzle_codes descriptor.swizzle
        in
        let fields =
          [| kind_code descriptor.kind; Metal_format.code descriptor.format
           ; descriptor.width; descriptor.height; descriptor.depth
           ; descriptor.mip_levels; descriptor.sample_count
           ; descriptor.array_length; storage_code descriptor.storage
           ; cache_code descriptor.cpu_cache
           ; hazard_code descriptor.hazard_tracking
           ; usage_bits descriptor.usage
           ; if descriptor.allow_gpu_optimized_contents then 1 else 0
           ; compression_code descriptor.compression
           ; swizzle_red; swizzle_green; swizzle_blue; swizzle_alpha
          |]
        in
        let metadata = Bytes.create metadata_size in
        Bytes.blit_string metadata_magic 0 metadata 0
          (String.length metadata_magic);
        Array.iteri
          (fun index field ->
            Bytes.set_int64_le metadata
              (String.length metadata_magic + (index * 8))
              (Int64.of_int field))
          fields;
        metadata

      let decode_descriptor operation metadata label =
        let malformed detail =
          native_error operation ("malformed shared-texture XPC metadata: " ^ detail)
        in
        if Bytes.length metadata <> metadata_size then
          malformed "wrong byte length"
        else if
          Bytes.sub_string metadata 0 (String.length metadata_magic)
          <> metadata_magic
        then malformed "wrong protocol/version marker"
        else
          let field index =
            Bytes.get_int64_le metadata
              (String.length metadata_magic + (index * 8))
          in
          let int_field index =
            let value = field index in
            if value < 0L || value > Int64.of_int max_int then None
            else Some (Int64.to_int value)
          in
          match
            int_field 0, int_field 1, int_field 2, int_field 3,
            int_field 4, int_field 5, int_field 6, int_field 7,
            int_field 8, int_field 9, int_field 10, int_field 11,
            int_field 12, int_field 13, int_field 14, int_field 15,
            int_field 16, int_field 17
          with
          | ( Some kind_code_value, Some format_code, Some width, Some height
            , Some depth, Some mip_levels, Some sample_count
            , Some array_length, Some storage_value, Some cache_value
            , Some hazard_value, Some usage_value, Some optimized_value
            , Some compression_value, Some swizzle_red, Some swizzle_green
            , Some swizzle_blue, Some swizzle_alpha ) ->
              let cpu_cache =
                match cache_value with
                | 0 -> Some Default_cache
                | 1 -> Some Write_combined
                | _ -> None
              in
              let hazard_tracking =
                match hazard_value with
                | 0 -> Some Default_hazard_tracking
                | 1 -> Some Untracked
                | 2 -> Some Tracked
                | _ -> None
              in
              let swizzle =
                match
                  swizzle_channel_of_code swizzle_red,
                  swizzle_channel_of_code swizzle_green,
                  swizzle_channel_of_code swizzle_blue,
                  swizzle_channel_of_code swizzle_alpha
                with
                | Some red, Some green, Some blue, Some alpha ->
                    Some { red; green; blue; alpha }
                | _ -> None
              in
              (match
                 kind_of_code kind_code_value,
                 Metal_format.of_code format_code,
                 storage_value,
                 cpu_cache,
                 hazard_tracking,
                 usages_of_bits usage_value,
                 optimized_value,
                 compression_of_code compression_value,
                 swizzle
               with
               | ( Some kind, Some format, 2, Some cpu_cache
                 , Some hazard_tracking, Some usage, (0 | 1)
                 , Some compression, Some swizzle )
                 when kind <> Texture_buffer && width > 0 && height > 0
                      && depth > 0 && mip_levels > 0 && sample_count > 0
                      && array_length > 0
                      && (swizzle = default_swizzle
                          || not (has_writable_usage usage))
                      &&
                      (compression = Lossless
                       || (optimized_value = 1
                           && kind <> Texture_1d
                           && kind <> Texture_1d_array
                           && not (has_lossy_incompatible_usage usage)
                           && Metal_format.supports_lossy_compression format)) ->
                   Ok
                     { kind
                     ; format
                     ; width
                     ; height
                     ; depth
                     ; mip_levels
                     ; sample_count
                     ; array_length
                     ; storage = Private
                     ; cpu_cache
                     ; hazard_tracking
                     ; usage
                     ; allow_gpu_optimized_contents = optimized_value = 1
                     ; compression
                     ; swizzle
                     ; label
                     }
               | _ -> malformed "invalid descriptor field")
          | _ -> malformed "integer field overflow"

      let wrap_received operation (device : device) raw metadata =
        let fail_with error_value =
          ignore (Metal_raw.destroy raw);
          error_value
        in
        let registry_id, label = Metal_raw.shared_texture_handle_info raw in
        if registry_id <> device.registry_id then
          fail_with
            (error operation Device_mismatch
               "received shared texture belongs to a different Metal device")
        else
          match decode_descriptor operation metadata label with
          | Error _ as failure -> fail_with failure
          | Ok descriptor
            when descriptor.compression = Lossy
                 && not
                      (Metal_raw.device_supports_lossy_texture_compression
                         device.raw) ->
              fail_with
                (error operation Unsupported
                   "received texture requests unsupported lossy compression")
          | Ok descriptor ->
              let handle =
                { raw; lifetime = lifetime (); device; descriptor; label }
              in
              attach device.lifetime;
              attach_finalizer handle handle.lifetime device.lifetime;
              Ok handle

      let connect ?(max_payload_bytes = 1_048_576) ~(device : Device.t)
          ~service_name () =
        let operation = "Metal.Texture.Shared_handle.Xpc.connect" in
        on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as failure -> failure
          | Ok () when not (valid_xpc_service_name service_name) ->
              error operation Invalid_argument
                "XPC service name must contain 1-255 bytes and no NUL"
          | Ok ()
            when not (valid_xpc_payload_bound max_payload_bytes) ->
              error operation Invalid_argument
                "XPC maximum payload must be between one byte and 64 MiB"
          | Ok () ->
              (match
                 Metal_raw.xpc_connect 0 service_name max_payload_bytes
               with
               | Error message -> native_error operation message
               | Ok raw ->
                   let connection =
                     { raw
                     ; lifetime = lifetime ()
                     ; device
                     ; service_name
                     ; max_payload_bytes
                     }
                   in
                   attach device.lifetime;
                   attach_finalizer connection connection.lifetime
                     device.lifetime;
                   Ok connection))

      let service_name (value : connection) = value.service_name
      let connection_destroyed (value : connection) =
        is_destroyed value.lifetime

      let destroy_connection (value : connection) =
        destroy_leaf "Metal.Texture.Shared_handle.Xpc.destroy_connection"
          value.lifetime value.raw (fun () -> detach value.device.lifetime)

      let call ?(timeout_ms = 10_000) (connection : connection) ~operation
          ~(handle : t) data =
        let call_name = "Metal.Texture.Shared_handle.Xpc.call" in
        on_main call_name (fun () ->
          match ensure_live call_name connection.lifetime with
          | Error _ as failure -> failure
          | Ok () ->
              (match ensure_live call_name handle.lifetime with
               | Error _ as failure -> failure
               | Ok () ->
                   (match
                      ensure_same_device call_name connection.device
                        handle.device
                    with
                    | Error _ as failure -> failure
                    | Ok () when not (valid_xpc_operation operation) ->
                        error call_name Invalid_argument
                          "XPC operation must contain 1-256 bytes and no NUL"
                    | Ok () when Bytes.length data > connection.max_payload_bytes ->
                        error call_name Invalid_argument
                          "XPC payload exceeds the connection bound"
                    | Ok () when not (valid_xpc_timeout timeout_ms) ->
                        error call_name Invalid_argument
                          "XPC timeout must be between 1 and 300000 milliseconds"
                    | Ok () ->
                        let metadata = encode_descriptor handle.descriptor in
                        (match
                           Metal_raw.xpc_call connection.raw
                             operation handle.raw metadata data timeout_ms
                         with
                         | Error message -> native_error call_name message
                         | Ok (raw, reply_metadata, reply_data) ->
                             (match
                                wrap_received call_name connection.device raw
                                  reply_metadata
                              with
                              | Error _ as failure -> failure
                              | Ok reply_handle ->
                                  Ok (reply_handle, reply_data))))))

      let request_operation (value : request) =
        let operation = "Metal.Texture.Shared_handle.Xpc.request_operation" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok value.operation)

      let request_handle (value : request) =
        let operation = "Metal.Texture.Shared_handle.Xpc.request_handle" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok value.handle)

      let request_data (value : request) =
        let operation = "Metal.Texture.Shared_handle.Xpc.request_data" in
        on_main operation (fun () ->
          match ensure_live operation value.lifetime with
          | Error _ as failure -> failure
          | Ok () -> Ok (Bytes.copy value.data))

      let request_completed (value : request) = is_destroyed value.lifetime

      let complete_request operation (value : request) native_call =
        match ensure_live operation value.lifetime with
        | Error _ as failure -> failure
        | Ok () ->
            (match native_call () with
             | Error message -> native_error operation message
             | Ok () ->
                 Atomic.set value.lifetime.destroyed true;
                 ignore (Metal_raw.destroy value.raw);
                 detach value.service.lifetime;
                 ignore (destroy value.handle);
                 Ok ())

      let reply (value : request) ~(handle : t) data =
        let operation = "Metal.Texture.Shared_handle.Xpc.reply" in
        on_main operation (fun () ->
          match ensure_live operation handle.lifetime with
          | Error _ as failure -> failure
          | Ok () ->
              (match ensure_same_device operation value.service.device handle.device with
               | Error _ as failure -> failure
               | Ok () when Bytes.length data > value.service.max_payload_bytes ->
                   error operation Invalid_argument
                     "XPC reply payload exceeds the service bound"
               | Ok () ->
                   let metadata = encode_descriptor handle.descriptor in
                   complete_request operation value (fun () ->
                     Metal_raw.xpc_request_reply value.raw
                       handle.raw metadata data)))

      let reject (value : request) message =
        let operation = "Metal.Texture.Shared_handle.Xpc.reject" in
        on_main operation (fun () ->
          if message = "" || String.length message > 4096 || contains_nul message
          then
            error operation Invalid_argument
              "XPC rejection must contain 1-4096 bytes and no NUL"
          else
            complete_request operation value (fun () ->
              Metal_raw.xpc_request_reject value.raw message))

      let serve ?(capacity = 16) ?(max_payload_bytes = 1_048_576)
          ~(device : Device.t) handler =
        let operation = "Metal.Texture.Shared_handle.Xpc.serve" in
        on_main operation (fun () ->
          match ensure_live operation device.lifetime with
          | Error _ as failure -> failure
          | Ok () when not (valid_xpc_capacity capacity) ->
              error operation Invalid_argument
                "XPC request capacity must be between 1 and 1024"
          | Ok ()
            when not (valid_xpc_payload_bound max_payload_bytes) ->
              error operation Invalid_argument
                "XPC maximum payload must be between one byte and 64 MiB"
          | Ok () ->
              (match
                 Metal_raw.xpc_service_create 0 capacity max_payload_bytes
               with
               | Error message -> native_error operation message
               | Ok raw ->
                   let service =
                     { raw
                     ; lifetime = lifetime ()
                     ; device
                     ; max_payload_bytes
                     }
                   in
                   attach device.lifetime;
                   attach_finalizer service service.lifetime device.lifetime;
                   let reject_raw raw_request raw_handle message =
                     ignore
                       (Metal_raw.xpc_request_reject raw_request
                          message);
                     ignore (Metal_raw.destroy raw_request);
                     Option.iter
                       (fun handle -> ignore (Metal_raw.destroy handle))
                       raw_handle
                   in
                   let receive raw_request request_operation raw_handle metadata
                       data =
                     if not (valid_xpc_operation request_operation) then
                       reject_raw raw_request (Some raw_handle)
                         "shared-texture XPC operation is malformed"
                     else if Bytes.length data > service.max_payload_bytes then
                       reject_raw raw_request (Some raw_handle)
                         "shared-texture XPC payload exceeds the service bound"
                     else
                       match
                         wrap_received operation service.device raw_handle
                           metadata
                       with
                       | Error error_value ->
                           reject_raw raw_request None error_value.message
                       | Ok handle ->
                           let request =
                             { raw = raw_request
                             ; lifetime = lifetime ()
                             ; service
                             ; operation = request_operation
                             ; handle
                             ; data
                             }
                           in
                           attach service.lifetime;
                           attach_finalizer request request.lifetime
                             service.lifetime;
                           let reject_pending message =
                             if not (request_completed request) then
                               ignore
                                 (complete_request operation request (fun () ->
                                    Metal_raw.xpc_request_reject
                                      request.raw message))
                           in
                           (try handler request with _ ->
                              reject_pending
                                "shared-texture XPC handler raised an exception");
                           reject_pending
                             "shared-texture XPC handler returned without a reply"
                   in
                   let result =
                     Metal_raw.xpc_service_serve raw receive
                   in
                   if
                     Atomic.compare_and_set service.lifetime.destroyed false
                       true
                   then begin
                     ignore (Metal_raw.destroy service.raw);
                     detach service.device.lifetime
                   end;
                   match result with
                   | Ok () -> Ok ()
                   | Error message -> native_error operation message))
    end
  end

  let make_swizzle ~red ~green ~blue ~alpha = { red; green; blue; alpha }

  let descriptor_2d ?(mipmapped = false) ?(storage = Private)
      ?(usage = [ Shader_read ]) ?(compression = Lossless)
      ?(swizzle = default_swizzle) ?label ~format ~width ~height () =
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
    ; compression
    ; swizzle
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
      descriptor.swizzle <> default_swizzle
      && has_writable_usage descriptor.usage
    then
      invalid
        "texture swizzling is incompatible with shader-write and shader-atomic usage"
    else if descriptor.compression = Lossy && descriptor.storage <> Private then
      invalid "lossy texture compression requires private storage"
    else if
      descriptor.compression = Lossy
      && not descriptor.allow_gpu_optimized_contents
    then invalid "lossy texture compression requires GPU-optimized contents"
    else if
      descriptor.compression = Lossy
      && has_lossy_incompatible_usage descriptor.usage
    then
      invalid
        "lossy texture compression is incompatible with pixel-format views, shader writes, and shader atomics"
    else if
      descriptor.compression = Lossy
      &&
      match descriptor.kind with
      | Texture_1d | Texture_1d_array | Texture_buffer -> true
      | Texture_2d | Texture_2d_array | Texture_2d_multisample | Texture_cube
      | Texture_cube_array | Texture_3d | Texture_2d_multisample_array -> false
    then
      invalid
        "lossy texture compression is incompatible with 1D and buffer textures"
    else if
      descriptor.compression = Lossy
      && not (Metal_format.supports_lossy_compression descriptor.format)
    then invalid "pixel format does not support lossy texture compression"
    else if
      descriptor.compression = Lossy
      && not
           (Metal_raw.device_supports_lossy_texture_compression device.raw)
    then
      error operation Unsupported
        "device does not support lossy texture compression"
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

  let raw_descriptor (descriptor : descriptor) =
    let swizzle_red, swizzle_green, swizzle_blue, swizzle_alpha =
      swizzle_codes descriptor.swizzle
    in
    { Metal_raw.texture_type = kind_code descriptor.kind
    ; pixel_format = format_code descriptor.format
    ; width = descriptor.width
    ; height = descriptor.height
    ; depth = descriptor.depth
    ; mip_levels = descriptor.mip_levels
    ; sample_count = descriptor.sample_count
    ; array_length = descriptor.array_length
    ; storage_mode = storage_code descriptor.storage
    ; cpu_cache_mode = cache_code descriptor.cpu_cache
    ; hazard_tracking_mode = hazard_code descriptor.hazard_tracking
    ; usage = usage_bits descriptor.usage
    ; allow_gpu_optimized_contents = descriptor.allow_gpu_optimized_contents
    ; compression_type = compression_code descriptor.compression
    ; swizzle_red
    ; swizzle_green
    ; swizzle_blue
    ; swizzle_alpha
    }

  let verify_info operation raw descriptor ~heap =
    let info = Metal_raw.texture_info raw in
    let actual_hazard =
      concrete_hazard_tracking ~heap descriptor.hazard_tracking
    in
    if Array.length info <> 18 then
      native_error operation "Metal returned malformed texture properties"
    else
      let swizzle_red, swizzle_green, swizzle_blue, swizzle_alpha =
        swizzle_codes descriptor.swizzle
      in
      let expected =
        [| kind_code descriptor.kind; format_code descriptor.format
         ; descriptor.width; descriptor.height; descriptor.depth
         ; descriptor.mip_levels; descriptor.sample_count
         ; descriptor.array_length; usage_bits descriptor.usage
         ; storage_code descriptor.storage
         ; cache_code descriptor.cpu_cache; hazard_code actual_hazard
         ; if descriptor.allow_gpu_optimized_contents then 1 else 0
         ; compression_code descriptor.compression
         ; swizzle_red; swizzle_green; swizzle_blue; swizzle_alpha
        |]
      in
      if info = expected then
        Ok { descriptor with hazard_tracking = actual_hazard }
      else begin
        let fields =
          [| "texture type"; "pixel format"; "width"; "height"; "depth"
           ; "mip levels"; "sample count"; "array length"; "usage"
           ; "storage mode"; "CPU cache mode"; "hazard tracking mode"
           ; "GPU-optimized contents"; "compression type"; "red swizzle"
           ; "green swizzle"; "blue swizzle"; "alpha swizzle"
          |]
        in
        let rec mismatch index =
          if index = Array.length expected then None
          else if info.(index) <> expected.(index) then Some index
          else mismatch (index + 1)
        in
        match mismatch 0 with
        | None ->
            native_error operation
              "Metal changed a checked texture descriptor during creation"
        | Some index ->
            native_error operation
              (Printf.sprintf "Metal changed texture %s from %d to %d"
                 fields.(index) expected.(index) info.(index))
      end

  let finish_create ?expected_shareable ?placement_sparse_page_size operation
      ~device ~descriptor ~parent ~heap_offset ~allocation raw =
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
        let placement_sparse_page_size =
          match placement_sparse_page_size, parent with
          | Some page_size, _ -> Some page_size
          | None, Texture_view texture -> texture.placement_sparse_page_size
          | None,
            (Texture_resource _ | Texture_buffer_resource _
            | Texture_io_surface_resource _) -> None
        in
        let state =
          match parent with
          | Texture_resource _ -> resource_state ()
          | Texture_buffer_resource backing -> backing.buffer.state
          | Texture_io_surface_resource _ -> resource_state ()
          | Texture_view texture -> texture.state
        in
        let placement_mappings =
          match parent with
          | Texture_view texture -> texture.placement_mappings
          | Texture_resource _ | Texture_buffer_resource _
          | Texture_io_surface_resource _ -> ref []
        in
        let value : t =
          { raw
          ; lifetime = lifetime ()
          ; device
          ; descriptor
          ; parent
          ; heap_offset
          ; placement_sparse_page_size
          ; allocation
          ; state
          ; placement_mappings
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
                 Metal_raw.texture_create device.raw (raw_descriptor descriptor)
                   descriptor.label
               with
               | Error message -> native_error "Metal.Texture.create" message
               | Ok raw ->
                   finish_create ~expected_shareable:false
                     "Metal.Texture.create" ~device ~descriptor
                     ~parent:(Texture_resource (Device_resource device))
                     ~heap_offset:None ~allocation:None raw))

  let create_placement_sparse ~(device : Device.t) ~page_size descriptor =
    let operation = "Metal.Texture.create_placement_sparse" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () when not (Metal_raw.device_supports_placement_sparse device.raw) ->
          error operation Unsupported
            "device does not support placement sparse resources"
      | Ok () ->
          (match validate_descriptor operation device descriptor with
           | Error _ as failure -> failure
           | Ok () when descriptor.kind = Texture_buffer ->
               error operation Invalid_argument
                 "texture-buffer resources must be created from a buffer"
           | Ok () ->
               (match
                  Metal_raw.device_sparse_texture_tile_size device.raw
                    (kind_code descriptor.kind) (format_code descriptor.format)
                    descriptor.sample_count (sparse_page_size_code page_size)
                with
                | Error message -> error operation Unsupported message
                | Ok (width, height, depth)
                  when width <= 0 || height <= 0 || depth <= 0 ->
                    native_error operation
                      "Metal returned invalid placement sparse tile dimensions"
                | Ok _ ->
                    (match
                       Metal_raw.texture_placement_sparse_create device.raw
                         (raw_descriptor descriptor)
                         (sparse_page_size_code page_size)
                     with
                     | Error message -> native_error operation message
                     | Ok raw ->
                         let label_result =
                           match descriptor.label with
                           | None -> Ok ()
                           | Some label -> Metal_raw.texture_set_label raw label
                         in
                         (match label_result with
                          | Error message ->
                              ignore (Metal_raw.destroy raw);
                              native_error operation message
                          | Ok () ->
                              finish_create
                                ~placement_sparse_page_size:page_size operation
                                ~device ~descriptor
                                ~parent:
                                  (Texture_resource (Device_resource device))
                                ~heap_offset:None ~allocation:None raw)))))

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
                   (raw_descriptor descriptor) descriptor.label
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
  let placement_sparse_page_size (value : t) =
    value.placement_sparse_page_size
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

  let sparse_tier (value : t) =
    let operation = "Metal.Texture.sparse_tier" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          let known_sparse =
            Option.is_some value.placement_sparse_page_size
            || option_exists
                 (fun (heap : heap) -> heap.descriptor.kind = Sparse)
                 (texture_heap value)
          in
          if not known_sparse then Ok Not_sparse
          else
            match Metal_raw.texture_sparse_tier value.raw with
            | 1 -> Ok Sparse_tier_1
            | 2 -> Ok Sparse_tier_2
            | -1 -> Ok Sparse_tier_1
            | 0 ->
                native_error operation "sparse texture lost its sparse tier"
            | tier ->
                native_error operation
                  (Printf.sprintf "Metal returned unknown texture sparse tier %d"
                     tier))

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
    let page_size =
      match value.placement_sparse_page_size with
      | Some _ as page_size -> page_size
      | None ->
          (match texture_heap value with
           | Some
               { descriptor =
                   { kind = Sparse; sparse_page_size = Some page_size; _ }
               ; _ } -> Some page_size
           | Some _ | None -> None)
    in
    match page_size with
    | None ->
        if Metal_raw.texture_is_sparse value.raw then
          native_error operation
            "sparse texture has no matching typed page-size metadata"
        else Ok None
    | Some page_size ->
        if not (Metal_raw.texture_is_sparse value.raw) then
          native_error operation "typed sparse texture lost its native identity"
        else
          (match
             Metal_raw.texture_sparse_info value.device.raw value.raw
               (sparse_page_size_code page_size)
           with
           | Error message -> native_error operation message
           | Ok values ->
               (match decode_sparse_info operation page_size values with
                | Error _ as failure -> failure
                | Ok info -> Ok (Some info)))

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
                             surface.raw plane (raw_descriptor descriptor)
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
    if Option.is_some buffer.placement_sparse_page_size then
      error operation Invalid_state
        "placement sparse buffers cannot back linear textures before mapping"
    else if descriptor.compression = Lossy then
      invalid "buffer-backed textures cannot use lossy compression"
    else match
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
                        (raw_descriptor descriptor) offset bytes_per_row
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
    if Option.is_some value.placement_sparse_page_size then
      error operation Invalid_state
        "placement sparse textures have no CPU-visible backing until mapped"
    else if value.descriptor.storage = Private then
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

  let compose_swizzle_channel (parent : swizzle) = function
    | Zero -> Zero
    | One -> One
    | Red -> parent.red
    | Green -> parent.green
    | Blue -> parent.blue
    | Alpha -> parent.alpha

  let compose_swizzle (parent : swizzle) (view : swizzle) =
    { red = compose_swizzle_channel parent view.red
    ; green = compose_swizzle_channel parent view.green
    ; blue = compose_swizzle_channel parent view.blue
    ; alpha = compose_swizzle_channel parent view.alpha
    }

  let create_view (parent : t) ~format ~base_mip ~mip_count ~base_slice
      ~slice_count ?(swizzle = default_swizzle) ?label () =
    on_main "Metal.Texture.create_view" (fun () ->
      match ensure_texture_usable "Metal.Texture.create_view" parent with
      | Error _ as failure -> failure
      | Ok () when !(parent.placement_mappings) <> [] ->
          error "Metal.Texture.create_view" Invalid_state
            "placement sparse texture mappings must be unmapped before creating a view"
      | Ok ()
        when swizzle <> default_swizzle
             && has_writable_usage parent.descriptor.usage ->
          error "Metal.Texture.create_view" Invalid_argument
            "texture-view swizzling is incompatible with writable texture usage"
      | Ok ()
        when not (List.mem Pixel_format_view parent.descriptor.usage)
             && (format <> parent.descriptor.format
                 || swizzle = default_swizzle) ->
          error "Metal.Texture.create_view" Invalid_argument
            "parent texture usage does not permit this texture view"
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
            let effective_swizzle =
              compose_swizzle parent.descriptor.swizzle swizzle
            in
            let descriptor : descriptor =
              { parent.descriptor with
                format
              ; width = mip_dimension parent.descriptor.width base_mip
              ; height = mip_dimension parent.descriptor.height base_mip
              ; depth = mip_dimension parent.descriptor.depth base_mip
              ; mip_levels = mip_count
              ; array_length
              ; swizzle = effective_swizzle
              ; label
              }
            in
            let ( requested_swizzle_red, requested_swizzle_green
                , requested_swizzle_blue, requested_swizzle_alpha ) =
              swizzle_codes swizzle
            in
            let ( effective_swizzle_red, effective_swizzle_green
                , effective_swizzle_blue, effective_swizzle_alpha ) =
              swizzle_codes effective_swizzle
            in
            match
              Metal_raw.texture_create_view parent.raw
                { Metal_raw.pixel_format = format_code format
                ; texture_type = kind_code descriptor.kind
                ; base_mip
                ; mip_count
                ; base_slice
                ; slice_count
                ; requested_swizzle_red
                ; requested_swizzle_green
                ; requested_swizzle_blue
                ; requested_swizzle_alpha
                ; effective_swizzle_red
                ; effective_swizzle_green
                ; effective_swizzle_blue
                ; effective_swizzle_alpha
                }
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Texture.purgeable_state" Invalid_state
            "the placement heap controls physical-page purgeability"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Texture.set_purgeable_state" Invalid_state
            "set purgeability on the placement heap"
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
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Texture.is_aliasable" Invalid_state
            "placement sparse aliasing is controlled by mapping operations"
      | Ok () ->
          (match buffer_backing value with
           | Some backing -> Buffer.is_aliasable backing.buffer
           | None -> Ok (Metal_raw.resource_is_aliasable value.raw)))

  let make_aliasable (value : t) =
    on_main "Metal.Texture.make_aliasable" (fun () ->
      match ensure_live "Metal.Texture.make_aliasable" value.lifetime with
      | Error _ as failure -> failure
      | Ok () when Option.is_some value.placement_sparse_page_size ->
          error "Metal.Texture.make_aliasable" Invalid_state
            "placement sparse aliasing is controlled by mapping operations"
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
      | Automatic, Some _ ->
          error operation Invalid_argument
            "automatic heaps do not accept a sparse page size"
      | Sparse, None ->
          error operation Invalid_argument
            "sparse heaps require an explicit sparse page size"
      | Sparse, Some _
        when descriptor.storage <> Private
             || descriptor.cpu_cache <> Default_cache ->
          error operation Invalid_argument
            "sparse heaps require private default-cache storage"
      | (Automatic | Placement), None -> Ok ()
      | Placement, Some _
        when not (Metal_raw.device_supports_placement_sparse device.raw) ->
          error operation Unsupported
            "device does not support placement sparse resources"
      | Placement, Some page_size ->
          let page_bytes = Sparse_page_size.bytes page_size in
          if Int64.rem descriptor.size page_bytes <> 0L then
            error operation Invalid_argument
              "placement heap size must be a whole number of sparse pages"
          else Ok ()
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
                 (Texture.raw_descriptor descriptor)
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
                        else if Metal_format.is_subsampled descriptor.format then
                          error "Metal.Heap.create_texture" Unsupported
                            "sparse subsampled textures are not in the reviewed format matrix"
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
                                   (Texture.raw_descriptor descriptor) None
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
                        (Texture.raw_descriptor descriptor)
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
                                   (Texture.raw_descriptor descriptor) offset
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

  type reduction_mode = sampler_reduction_mode =
    | Weighted_average
    | Minimum
    | Maximum

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
    ; reduction_mode : reduction_mode
    ; normalized_coordinates : bool
    ; lod_min_clamp : float
    ; lod_max_clamp : float
    ; lod_average : bool
    ; lod_bias : float
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
    ; reduction_mode = Weighted_average
    ; normalized_coordinates = true
    ; lod_min_clamp = 0.
    ; lod_max_clamp = 3.402823466e38
    ; lod_average = false
    ; lod_bias = 0.
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

  let reduction_code = function
    | Weighted_average -> 0
    | Minimum -> 1
    | Maximum -> 2

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
    else if not (Float.is_finite descriptor.lod_bias)
            || descriptor.lod_bias < -16.
            || descriptor.lod_bias > 15.999
    then invalid "sampler LOD bias must be finite and in [-16, 15.999]"
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
    , reduction_code descriptor.reduction_mode
    , descriptor.normalized_coordinates
    , descriptor.lod_min_clamp
    , descriptor.lod_max_clamp
    , descriptor.lod_average
    , descriptor.lod_bias
    , compare_code descriptor.compare_function
    , descriptor.support_argument_buffers )

  let requires_sampler_reduction descriptor =
    descriptor.reduction_mode <> Weighted_average || descriptor.lod_bias <> 0.

  let create ~(device : Device.t) descriptor =
    on_main "Metal.Sampler.create" (fun () ->
      match ensure_live "Metal.Sampler.create" device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate descriptor with
           | Error _ as failure -> failure
           | Ok ()
             when requires_sampler_reduction descriptor
                  && not
                       (Metal_raw.device_supports_sampler_reduction device.raw) ->
               error "Metal.Sampler.create" Unsupported
                 "sampler reduction modes and LOD bias require macOS 26 and Apple GPU family 10"
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

module Shader_type = struct
  type scalar = shader_scalar_type =
    | Float
    | Half
    | Int
    | Uint
    | Short
    | Ushort
    | Char
    | Uchar
    | Bool
    | Long
    | Ulong
    | Bfloat

  type t = shader_data_type =
    | No_type
    | Struct
    | Array
    | Scalar of scalar
    | Vector of scalar * int
    | Matrix of scalar * int * int
    | Texture_type
    | Sampler_type
    | Pointer
    | Other_data_type of int

  let of_code = function
    | 0 -> No_type
    | 1 -> Struct
    | 2 -> Array
    | 3 -> Scalar Float
    | 4 -> Vector (Float, 2)
    | 5 -> Vector (Float, 3)
    | 6 -> Vector (Float, 4)
    | 7 -> Matrix (Float, 2, 2)
    | 8 -> Matrix (Float, 2, 3)
    | 9 -> Matrix (Float, 2, 4)
    | 10 -> Matrix (Float, 3, 2)
    | 11 -> Matrix (Float, 3, 3)
    | 12 -> Matrix (Float, 3, 4)
    | 13 -> Matrix (Float, 4, 2)
    | 14 -> Matrix (Float, 4, 3)
    | 15 -> Matrix (Float, 4, 4)
    | 16 -> Scalar Half
    | 17 -> Vector (Half, 2)
    | 18 -> Vector (Half, 3)
    | 19 -> Vector (Half, 4)
    | 20 -> Matrix (Half, 2, 2)
    | 21 -> Matrix (Half, 2, 3)
    | 22 -> Matrix (Half, 2, 4)
    | 23 -> Matrix (Half, 3, 2)
    | 24 -> Matrix (Half, 3, 3)
    | 25 -> Matrix (Half, 3, 4)
    | 26 -> Matrix (Half, 4, 2)
    | 27 -> Matrix (Half, 4, 3)
    | 28 -> Matrix (Half, 4, 4)
    | 29 -> Scalar Int
    | 30 -> Vector (Int, 2)
    | 31 -> Vector (Int, 3)
    | 32 -> Vector (Int, 4)
    | 33 -> Scalar Uint
    | 34 -> Vector (Uint, 2)
    | 35 -> Vector (Uint, 3)
    | 36 -> Vector (Uint, 4)
    | 37 -> Scalar Short
    | 38 -> Vector (Short, 2)
    | 39 -> Vector (Short, 3)
    | 40 -> Vector (Short, 4)
    | 41 -> Scalar Ushort
    | 42 -> Vector (Ushort, 2)
    | 43 -> Vector (Ushort, 3)
    | 44 -> Vector (Ushort, 4)
    | 45 -> Scalar Char
    | 46 -> Vector (Char, 2)
    | 47 -> Vector (Char, 3)
    | 48 -> Vector (Char, 4)
    | 49 -> Scalar Uchar
    | 50 -> Vector (Uchar, 2)
    | 51 -> Vector (Uchar, 3)
    | 52 -> Vector (Uchar, 4)
    | 53 -> Scalar Bool
    | 54 -> Vector (Bool, 2)
    | 55 -> Vector (Bool, 3)
    | 56 -> Vector (Bool, 4)
    | 58 -> Texture_type
    | 59 -> Sampler_type
    | 60 -> Pointer
    | 81 -> Scalar Long
    | 82 -> Vector (Long, 2)
    | 83 -> Vector (Long, 3)
    | 84 -> Vector (Long, 4)
    | 85 -> Scalar Ulong
    | 86 -> Vector (Ulong, 2)
    | 87 -> Vector (Ulong, 3)
    | 88 -> Vector (Ulong, 4)
    | 121 -> Scalar Bfloat
    | 122 -> Vector (Bfloat, 2)
    | 123 -> Vector (Bfloat, 3)
    | 124 -> Vector (Bfloat, 4)
    | code -> Other_data_type code
end

module Binding = struct
  type access = shader_binding_access =
    | Read_only
    | Read_write
    | Write_only
    | Unknown_access of int

  type buffer = buffer_binding_layout =
    { alignment : int64
    ; data_size : int64
    ; data_type : Shader_type.t
    }

  type texture = texture_binding_layout =
    { texture_kind : Texture.kind
    ; data_type : Shader_type.t
    ; depth : bool
    ; array_length : int64
    }

  type sized = sized_binding_layout =
    { alignment : int64
    ; data_size : int64
    }

  type kind = shader_binding_kind =
    | Buffer_binding of buffer
    | Threadgroup_memory_binding of sized
    | Texture_binding of texture
    | Sampler_binding
    | Imageblock_data_binding
    | Imageblock_binding
    | Visible_function_table_binding
    | Primitive_acceleration_structure_binding
    | Instance_acceleration_structure_binding
    | Intersection_function_table_binding
    | Object_payload_binding of sized
    | Tensor_binding
    | Unknown_binding of int

  type t = shader_binding =
    { name : string
    ; index : int64
    ; access : access
    ; used : bool
    ; argument : bool
    ; kind : kind
    }

  type layout_kind = shader_binding_layout_kind =
    | Buffer_layout
    | Threadgroup_memory_layout
    | Texture_layout
    | Sampler_layout
    | Imageblock_data_layout
    | Imageblock_layout
    | Visible_function_table_layout
    | Primitive_acceleration_structure_layout
    | Instance_acceleration_structure_layout
    | Intersection_function_table_layout
    | Object_payload_layout
    | Tensor_layout
    | Other_binding_layout of int

  type layout = shader_binding_layout =
    { name : string
    ; index : int64
    ; access : access
    ; kind : layout_kind
    ; data_type : Shader_type.t option
    }

  let access_of_code = function
    | 0 -> Read_only
    | 1 -> Read_write
    | 2 -> Write_only
    | code -> Unknown_access code

  let texture_kind_of_code = function
    | 0 -> Some Texture.Texture_1d
    | 1 -> Some Texture.Texture_1d_array
    | 2 -> Some Texture.Texture_2d
    | 3 -> Some Texture.Texture_2d_array
    | 4 -> Some Texture.Texture_2d_multisample
    | 5 -> Some Texture.Texture_cube
    | 6 -> Some Texture.Texture_cube_array
    | 7 -> Some Texture.Texture_3d
    | 8 -> Some Texture.Texture_2d_multisample_array
    | 9 -> Some Texture.Texture_buffer
    | _ -> None

  let of_raw
      ( name
      , kind_code
      , access_code
      , index
      , used
      , argument
      , buffer_alignment
      , buffer_data_size
      , buffer_data_type
      , texture_kind
      , texture_data_type
      , depth
      , array_length
      , threadgroup_alignment
      , threadgroup_data_size
      , object_alignment
      , object_data_size ) =
    let kind =
      match kind_code with
      | 0 ->
          Buffer_binding
            { alignment = buffer_alignment
            ; data_size = buffer_data_size
            ; data_type = Shader_type.of_code buffer_data_type
            }
      | 1 ->
          Threadgroup_memory_binding
            { alignment = threadgroup_alignment
            ; data_size = threadgroup_data_size
            }
      | 2 ->
          (match texture_kind_of_code texture_kind with
           | Some texture_kind ->
               Texture_binding
                 { texture_kind
                 ; data_type = Shader_type.of_code texture_data_type
                 ; depth
                 ; array_length
                 }
           | None -> Unknown_binding kind_code)
      | 3 -> Sampler_binding
      | 16 -> Imageblock_data_binding
      | 17 -> Imageblock_binding
      | 24 -> Visible_function_table_binding
      | 25 -> Primitive_acceleration_structure_binding
      | 26 -> Instance_acceleration_structure_binding
      | 27 -> Intersection_function_table_binding
      | 34 ->
          Object_payload_binding
            { alignment = object_alignment; data_size = object_data_size }
      | 37 -> Tensor_binding
      | code -> Unknown_binding code
    in
    { name; index; access = access_of_code access_code; used; argument; kind }

  let layout (value : t) =
    let kind, data_type =
      match value.kind with
      | Buffer_binding buffer -> Buffer_layout, Some buffer.data_type
      | Threadgroup_memory_binding _ -> Threadgroup_memory_layout, None
      | Texture_binding texture -> Texture_layout, Some texture.data_type
      | Sampler_binding -> Sampler_layout, None
      | Imageblock_data_binding -> Imageblock_data_layout, None
      | Imageblock_binding -> Imageblock_layout, None
      | Visible_function_table_binding -> Visible_function_table_layout, None
      | Primitive_acceleration_structure_binding ->
          Primitive_acceleration_structure_layout, None
      | Instance_acceleration_structure_binding ->
          Instance_acceleration_structure_layout, None
      | Intersection_function_table_binding ->
          Intersection_function_table_layout, None
      | Object_payload_binding _ -> Object_payload_layout, None
      | Tensor_binding -> Tensor_layout, None
      | Unknown_binding code -> Other_binding_layout code, None
    in
    { name = value.name
    ; index = value.index
    ; access = value.access
    ; kind
    ; data_type
    }

  let layout_key (value : layout) = value.kind, value.index, value.name

  let validate_layout ~expected reflected =
    let sort values = List.sort (fun left right -> compare (layout_key left) (layout_key right)) values in
    let expected = sort expected
    and actual = sort (List.map layout reflected) in
    if expected = actual then Ok ()
    else
      let summarize values =
        values
        |> List.map (fun value -> Printf.sprintf "%s@%Ld" value.name value.index)
        |> String.concat ", "
      in
      error "Metal.Binding.validate_layout" Invalid_argument
        (Printf.sprintf "shader bind layout mismatch (expected [%s], reflected [%s])"
           (summarize expected) (summarize actual))
end

module Library = struct
  type t = library

  type kind = library_kind =
    | Executable_library
    | Dynamic_library_source
    | Unknown_library_kind of int

  let kind_of_code = function
    | 0 -> Executable_library
    | 1 -> Dynamic_library_source
    | code -> Unknown_library_kind code

  let make device raw =
    let value : t = { raw; lifetime = lifetime (); device } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let validate_source operation source label =
    if source = "" then
      error operation Invalid_argument "shader source is empty"
    else if contains_nul source then
      error operation Invalid_argument "shader source contains a NUL byte"
    else if option_exists contains_nul label then
      error operation Invalid_argument "library label contains a NUL byte"
    else Ok ()

  let compile_descriptor_raw operation ~(device : Device.t) ?label
      ~library_type ~install_name ~linked_libraries source =
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_source operation source label with
           | Error _ as failure -> failure
           | Ok () when library_type = 1 && Option.is_none install_name ->
               error operation Invalid_argument
                 "a dynamic-library source requires an install name"
           | Ok ()
             when option_exists
                    (fun value -> value = "" || contains_nul value)
                    install_name ->
               error operation Invalid_argument
                 "library install name must be nonempty and contain no NUL byte"
           | Ok () ->
               let descriptor : Metal_raw.library_compile_descriptor =
                 { label; library_type; install_name; linked_libraries }
               in
               match
                 Metal_raw.library_compile_descriptor device.raw source
                   descriptor
               with
               | Error message -> native_error operation message
               | Ok raw -> Ok (make device raw)))

  let compile_source ?label ~(device : Device.t) source =
    on_main "Metal.Library.compile_source" (fun () ->
      match ensure_live "Metal.Library.compile_source" device.lifetime with
      | Error _ as failure -> failure
      | Ok () when source = "" ->
          error "Metal.Library.compile_source" Invalid_argument
            "shader source is empty"
      | Ok () when contains_nul source ->
          error "Metal.Library.compile_source" Invalid_argument
            "shader source contains a NUL byte"
      | Ok () when option_exists contains_nul label ->
          error "Metal.Library.compile_source" Invalid_argument
            "library label contains a NUL byte"
      | Ok () ->
          (match Metal_raw.library_compile device.raw source label with
           | Error message -> native_error "Metal.Library.compile_source" message
           | Ok raw -> Ok (make device raw)))

  let compile_dynamic_source ?label ~(device : Device.t) ~install_name source =
    let operation = "Metal.Library.compile_dynamic_source" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok ()
        when not (Metal_raw.device_supports_dynamic_libraries device.raw) ->
          error operation Unsupported
            "the Metal device has no dynamic-library support"
      | Ok () ->
          compile_descriptor_raw operation ~device ?label ~library_type:1
            ~install_name:(Some install_name) ~linked_libraries:[||] source)

  let load_file ?label ~(device : Device.t) path =
    let operation = "Metal.Library.load_file" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_absolute_path operation path with
           | Error _ as failure -> failure
           | Ok () when option_exists contains_nul label ->
               error operation Invalid_argument
                 "library label contains a NUL byte"
           | Ok () ->
               match Metal_raw.library_load_file device.raw path label with
               | Error message -> native_error operation message
               | Ok raw -> Ok (make device raw)))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Library.label" (fun () ->
      match ensure_live "Metal.Library.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.library_label value.raw))

  let kind (value : t) =
    on_main "Metal.Library.kind" (fun () ->
      match ensure_live "Metal.Library.kind" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (kind_of_code (Metal_raw.library_kind value.raw)))

  let install_name (value : t) =
    on_main "Metal.Library.install_name" (fun () ->
      match ensure_live "Metal.Library.install_name" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.library_install_name value.raw))

  let function_names (value : t) =
    on_main "Metal.Library.function_names" (fun () ->
      match ensure_live "Metal.Library.function_names" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          Ok
            (Metal_raw.library_function_names value.raw
             |> Array.to_list |> List.sort String.compare))

  let destroy (value : t) =
    destroy_parent "Metal.Library.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Function = struct
  type t = function_handle

  type kind = function_kind =
    | Vertex
    | Fragment
    | Kernel
    | Visible
    | Intersection
    | Mesh
    | Object
    | Unknown_function_kind of int

  type constant_value = function_constant_value =
    | Bool_constant of bool
    | Int8_constant of int
    | Uint8_constant of int
    | Int16_constant of int
    | Uint16_constant of int
    | Int32_constant of int32
    | Uint32_constant of int64
    | Int64_constant of int64
    | Uint64_bits_constant of int64
    | Float16_constant of float
    | Float32_constant of float

  type constant = function_constant =
    { name : string
    ; data_type : Shader_type.t
    ; index : int64
    ; required : bool
    }

  let kind_of_code = function
    | 1 -> Vertex
    | 2 -> Fragment
    | 3 -> Kernel
    | 5 -> Visible
    | 6 -> Intersection
    | 7 -> Mesh
    | 8 -> Object
    | code -> Unknown_function_kind code

  let validate_constant_name operation name =
    if name = "" || contains_nul name then
      error operation Invalid_argument
        "function-constant names must be nonempty and contain no NUL byte"
    else Ok ()

  let raw_constant operation (name, value) =
    match validate_constant_name operation name with
    | Error _ as failure -> failure
    | Ok () ->
        let integral tag value = Ok (name, tag, value, 0.) in
        (match value with
         | Bool_constant value -> integral 0 (if value then 1L else 0L)
         | Int8_constant value when value >= -128 && value <= 127 ->
             integral 1 (Int64.of_int value)
         | Uint8_constant value when value >= 0 && value <= 255 ->
             integral 2 (Int64.of_int value)
         | Int16_constant value when value >= -32_768 && value <= 32_767 ->
             integral 3 (Int64.of_int value)
         | Uint16_constant value when value >= 0 && value <= 65_535 ->
             integral 4 (Int64.of_int value)
         | Int32_constant value -> integral 5 (Int64.of_int32 value)
         | Uint32_constant value
           when value >= 0L && value <= 0xffff_ffffL ->
             integral 6 value
         | Int64_constant value -> integral 7 value
         | Uint64_bits_constant value -> integral 8 value
         | Float16_constant value -> Ok (name, 9, 0L, value)
         | Float32_constant value -> Ok (name, 10, 0L, value)
         | Int8_constant _ ->
             error operation Invalid_argument "int8 function constant is out of range"
         | Uint8_constant _ ->
             error operation Invalid_argument "uint8 function constant is out of range"
         | Int16_constant _ ->
             error operation Invalid_argument "int16 function constant is out of range"
         | Uint16_constant _ ->
             error operation Invalid_argument "uint16 function constant is out of range"
         | Uint32_constant _ ->
             error operation Invalid_argument "uint32 function constant is out of range")

  let raw_constants operation constants =
    let rec loop seen reversed = function
      | [] -> Ok (Array.of_list (List.rev reversed))
      | (name, _) as constant :: rest ->
          if List.mem name seen then
            error operation Invalid_argument
              "function-constant list contains a duplicate name"
          else
            (match raw_constant operation constant with
             | Error _ as failure -> failure
             | Ok raw -> loop (name :: seen) (raw :: reversed) rest)
    in
    loop [] [] constants

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

  let label (value : t) =
    on_main "Metal.Function.label" (fun () ->
      match ensure_live "Metal.Function.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.function_label value.raw))

  let kind (value : t) =
    on_main "Metal.Function.kind" (fun () ->
      match ensure_live "Metal.Function.kind" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (kind_of_code (Metal_raw.function_kind value.raw)))

  let constants (value : t) =
    on_main "Metal.Function.constants" (fun () ->
      match ensure_live "Metal.Function.constants" value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          Metal_raw.function_constants value.raw
          |> Array.to_list
          |> List.map (fun (name, data_type, index, required) ->
            { name
            ; data_type = Shader_type.of_code data_type
            ; index
            ; required
            })
          |> List.sort (fun left right ->
            match Int64.compare left.index right.index with
            | 0 -> String.compare left.name right.name
            | order -> order)
          |> Result.ok)

  let specialize ~(library : Library.t) ?label ~constants name =
    let operation = "Metal.Function.specialize" in
    on_main operation (fun () ->
      match ensure_live operation library.lifetime with
      | Error _ as failure -> failure
      | Ok () when name = "" || contains_nul name ->
          error operation Invalid_argument
            "function name must be nonempty and contain no NUL byte"
      | Ok () when option_exists contains_nul label ->
          error operation Invalid_argument
            "function label contains a NUL byte"
      | Ok () ->
          (match raw_constants operation constants with
           | Error _ as failure -> failure
           | Ok raw_constants ->
               match
                 Metal_raw.function_specialize library.raw name raw_constants
                   label
               with
               | Error message -> native_error operation message
               | Ok raw ->
                   let value : t =
                     { raw; lifetime = lifetime (); library }
                   in
                   attach library.lifetime;
                   attach_finalizer value value.lifetime library.lifetime;
                   Ok value))

  let device (value : t) = value.library.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_leaf "Metal.Function.destroy" value.lifetime value.raw
      (fun () -> detach value.library.lifetime)
end

let validate_linked_functions operation device linked_functions =
  let rec loop names = function
    | [] -> Ok ()
    | (linked : Function.t) :: rest ->
        (match ensure_live operation linked.lifetime with
         | Error _ as failure -> failure
         | Ok () ->
             (match ensure_same_device operation device linked.library.device with
              | Error _ as failure -> failure
              | Ok () ->
                  let name = Metal_raw.function_name linked.raw in
                  if List.mem name names then
                    error operation Invalid_argument
                      "linked functions must have unique names"
                  else
                    match Function.kind_of_code (Metal_raw.function_kind linked.raw) with
                    | Function.Visible -> loop (name :: names) rest
                    | _ ->
                        error operation Invalid_argument
                          "linked functions must be visible Metal functions"))
  in
  loop [] linked_functions

let validate_dynamic_libraries operation device libraries =
  let rec loop install_names = function
    | [] -> Ok ()
    | (library : dynamic_library) :: rest ->
        (match ensure_live operation library.lifetime with
         | Error _ as failure -> failure
         | Ok () ->
             (match ensure_same_device operation device library.device with
              | Error _ as failure -> failure
              | Ok () ->
                  let install_name =
                    Metal_raw.dynamic_library_install_name library.raw
                  in
                  if List.mem install_name install_names then
                    error operation Invalid_argument
                      "dynamic-library list contains a duplicate install name"
                  else loop (install_name :: install_names) rest))
  in
  loop [] libraries

let validate_binary_archives operation device archives =
  let rec loop seen = function
    | [] -> Ok ()
    | (archive : binary_archive) :: rest ->
        if
          List.exists
            (fun (value : binary_archive) ->
              value.lifetime == archive.lifetime)
            seen
        then
          error operation Invalid_argument
            "binary-archive list contains a duplicate handle"
        else
          (match ensure_live operation archive.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match ensure_same_device operation device archive.device with
                | Error _ as failure -> failure
                | Ok () -> loop (archive :: seen) rest))
  in
  loop [] archives

module Dynamic_library = struct
  type t = dynamic_library

  let make device raw =
    let value : t = { raw; lifetime = lifetime (); device } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let check_support operation (device : Device.t) =
    match ensure_live operation device.lifetime with
    | Error _ as failure -> failure
    | Ok () when not (Metal_raw.device_supports_dynamic_libraries device.raw) ->
        error operation Unsupported
          "the Metal device has no dynamic-library support"
    | Ok () -> Ok ()

  let create ?label (library : Library.t) =
    let operation = "Metal.Dynamic_library.create" in
    on_main operation (fun () ->
      match ensure_live operation library.lifetime with
      | Error _ as failure -> failure
      | Ok () when option_exists contains_nul label ->
          error operation Invalid_argument
            "dynamic-library label contains a NUL byte"
      | Ok () ->
          let device = library.device in
          (match check_support operation device with
           | Error _ as failure -> failure
           | Ok ()
             when Library.kind_of_code (Metal_raw.library_kind library.raw)
                  <> Library.Dynamic_library_source ->
               error operation Invalid_argument
                 "source library was not compiled as a dynamic library"
           | Ok () ->
               match
                 Metal_raw.dynamic_library_create device.raw library.raw label
               with
               | Error message -> native_error operation message
               | Ok raw -> Ok (make device raw)))

  let load_file ?label ~(device : Device.t) path =
    let operation = "Metal.Dynamic_library.load_file" in
    on_main operation (fun () ->
      match check_support operation device with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_absolute_path operation path with
           | Error _ as failure -> failure
           | Ok () when option_exists contains_nul label ->
               error operation Invalid_argument
                 "dynamic-library label contains a NUL byte"
           | Ok () ->
               match
                 Metal_raw.dynamic_library_load_file device.raw path label
               with
               | Error message -> native_error operation message
               | Ok raw -> Ok (make device raw)))

  let compile_source ?label ~(device : Device.t) ~libraries source =
    let operation = "Metal.Dynamic_library.compile_source" in
    on_main operation (fun () ->
      match check_support operation device with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_dynamic_libraries operation device libraries with
           | Error _ as failure -> failure
           | Ok () ->
               Library.compile_descriptor_raw operation ~device ?label
                 ~library_type:0 ~install_name:None
                 ~linked_libraries:
                   (Array.of_list
                      (List.map (fun (value : t) -> value.raw) libraries))
                 source))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Dynamic_library.label" (fun () ->
      match ensure_live "Metal.Dynamic_library.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.dynamic_library_label value.raw))

  let install_name (value : t) =
    on_main "Metal.Dynamic_library.install_name" (fun () ->
      match ensure_live "Metal.Dynamic_library.install_name" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.dynamic_library_install_name value.raw))

  let serialize (value : t) path =
    let operation = "Metal.Dynamic_library.serialize" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_absolute_path operation path with
           | Error _ as failure -> failure
           | Ok () ->
               match Metal_raw.dynamic_library_serialize value.raw path with
               | Error message -> native_error operation message
               | Ok () -> Ok ()))

  let destroy (value : t) =
    destroy_leaf "Metal.Dynamic_library.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Binary_archive = struct
  type t = binary_archive

  let make device raw =
    let value : t = { raw; lifetime = lifetime (); device } in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let create ?path ?label (device : Device.t) =
    let operation = "Metal.Binary_archive.create" in
    on_main operation (fun () ->
      match ensure_live operation device.lifetime with
      | Error _ as failure -> failure
      | Ok () when option_exists contains_nul label ->
          error operation Invalid_argument
            "binary-archive label contains a NUL byte"
      | Ok () ->
          (match path with
           | Some path ->
               (match validate_absolute_path operation path with
                | Error _ as failure -> failure
                | Ok () ->
                    (match
                       Metal_raw.binary_archive_create device.raw (Some path)
                         label
                     with
                     | Error message -> native_error operation message
                     | Ok raw -> Ok (make device raw)))
           | None ->
               (match Metal_raw.binary_archive_create device.raw None label with
                | Error message -> native_error operation message
                | Ok raw -> Ok (make device raw))))

  let add_compute_functions (value : t) ?(linked_functions = [])
      ?(preloaded_libraries = []) (function_value : Function.t) =
    let operation = "Metal.Binary_archive.add_compute_functions" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match ensure_live operation function_value.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match
                  ensure_same_device operation value.device
                    function_value.library.device
                with
                | Error _ as failure -> failure
                | Ok ()
                  when Function.kind_of_code
                         (Metal_raw.function_kind function_value.raw)
                       <> Function.Kernel ->
                    error operation Invalid_argument
                      "archive compute entry point must be a kernel"
                | Ok () ->
                    (match
                       validate_linked_functions operation value.device
                         linked_functions
                     with
                     | Error _ as failure -> failure
                     | Ok ()
                       when linked_functions <> []
                            && not
                                 (Metal_raw.device_supports_function_pointers
                                    value.device.raw) ->
                         error operation Unsupported
                           "archived linked functions require Metal function-pointer support"
                     | Ok () ->
                         (match
                            validate_dynamic_libraries operation value.device
                              preloaded_libraries
                          with
                          | Error _ as failure -> failure
                          | Ok ()
                            when preloaded_libraries <> []
                                 && not
                                      (Metal_raw.device_supports_dynamic_libraries
                                         value.device.raw) ->
                              error operation Unsupported
                                "archived preloads require Metal dynamic-library support"
                          | Ok () ->
                              match
                                Metal_raw.binary_archive_add_compute value.raw
                                  function_value.raw
                                  (Array.of_list
                                     (List.map
                                        (fun (linked : Function.t) -> linked.raw)
                                        linked_functions))
                                  (Array.of_list
                                     (List.map
                                        (fun (library : Dynamic_library.t) ->
                                          library.raw)
                                        preloaded_libraries))
                              with
                              | Error message -> native_error operation message
                              | Ok () -> Ok ())))))

  let serialize (value : t) path =
    let operation = "Metal.Binary_archive.serialize" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () ->
          (match validate_absolute_path operation path with
           | Error _ as failure -> failure
           | Ok () ->
               match Metal_raw.binary_archive_serialize value.raw path with
               | Error message -> native_error operation message
               | Ok () -> Ok ()))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Binary_archive.label" (fun () ->
      match ensure_live "Metal.Binary_archive.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.binary_archive_label value.raw))

  let destroy (value : t) =
    destroy_leaf "Metal.Binary_archive.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Compute_pipeline = struct
  type t = compute_pipeline

  let make device ~reflection raw raw_bindings =
    let bindings =
      if reflection then Some (Array.map Binding.of_raw raw_bindings) else None
    in
    let value : t =
      { raw
      ; lifetime = lifetime ()
      ; device
      ; bindings
      ; thread_execution_width =
          Metal_raw.compute_pipeline_thread_execution_width raw
      ; max_total_threads = Metal_raw.compute_pipeline_max_total_threads raw
      }
    in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let create ?label ?(linked_functions = []) ?(preloaded_libraries = [])
      ?(binary_archives = []) ?(fail_on_binary_archive_miss = false)
      ?(reflection = false) (function_value : Function.t) =
    let operation = "Metal.Compute_pipeline.create" in
    on_main operation (fun () ->
      let ( let* ) value callback = Result.bind value callback in
      let* () = ensure_live operation function_value.lifetime in
      if option_exists contains_nul label then
        error operation Invalid_argument "pipeline label contains a NUL byte"
      else
        let device = function_value.library.device in
        if
          Function.kind_of_code (Metal_raw.function_kind function_value.raw)
          <> Function.Kernel
        then
          error operation Invalid_argument
            "the pipeline entry point must be a Metal kernel function"
        else
          let* () =
            validate_linked_functions operation device linked_functions
          in
          if
            linked_functions <> []
            && not (Metal_raw.device_supports_function_pointers device.raw)
          then
            error operation Unsupported
              "linked functions require Metal function-pointer support"
          else
            let* () =
              validate_dynamic_libraries operation device preloaded_libraries
            in
            if
              preloaded_libraries <> []
              && not (Metal_raw.device_supports_dynamic_libraries device.raw)
            then
              error operation Unsupported
                "preloaded libraries require Metal dynamic-library support"
            else
              let* () =
                validate_binary_archives operation device binary_archives
              in
              if fail_on_binary_archive_miss && binary_archives = [] then
                error operation Invalid_argument
                  "fail-on-archive-miss requires at least one binary archive"
              else
                let descriptor_required =
                  label <> None || linked_functions <> []
                  || preloaded_libraries <> [] || binary_archives <> []
                  || fail_on_binary_archive_miss || reflection
                in
                let creation =
                  if not descriptor_required then
                    Result.map
                      (fun raw -> raw, [||])
                      (Metal_raw.compute_pipeline_create device.raw
                         function_value.raw)
                  else
                    let descriptor : Metal_raw.compute_pipeline_descriptor =
                      { label
                      ; reflection
                      ; linked_functions =
                          Array.of_list
                            (List.map
                               (fun (value : Function.t) -> value.raw)
                               linked_functions)
                      ; preloaded_libraries =
                          Array.of_list
                            (List.map
                               (fun (value : Dynamic_library.t) -> value.raw)
                               preloaded_libraries)
                      ; binary_archives =
                          Array.of_list
                            (List.map
                               (fun (value : Binary_archive.t) -> value.raw)
                               binary_archives)
                      ; fail_on_binary_archive_miss
                      }
                    in
                    Metal_raw.compute_pipeline_create_descriptor device.raw
                      function_value.raw descriptor
                in
                match creation with
                | Error message -> native_error operation message
                | Ok (raw, raw_bindings) ->
                    Ok (make device ~reflection raw raw_bindings))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let bindings (value : t) = Option.map Array.to_list value.bindings
  let thread_execution_width (value : t) = value.thread_execution_width
  let max_total_threads_per_threadgroup (value : t) = value.max_total_threads
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Compute_pipeline.label" (fun () ->
      match ensure_live "Metal.Compute_pipeline.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.compute_pipeline_label value.raw))

  let destroy (value : t) =
    destroy_leaf "Metal.Compute_pipeline.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

let ensure_metal4 operation (device : Device.t) =
  match ensure_live operation device.lifetime with
  | Error _ as failure -> failure
  | Ok ()
    when not
           (Metal_raw.device_supports_family device.raw
              (Device.family_code Device.Metal4)) ->
      error operation Unsupported "the Metal device does not support Metal 4"
  | Ok () -> Ok ()

module Pipeline_dataset = struct
  type t = pipeline_dataset

  type capture =
    | Descriptors
    | Binaries

  let capture_bit = function Descriptors -> 1 | Binaries -> 2

  let validate_captures operation captures =
    match captures with
    | [] ->
        error operation Invalid_argument
          "at least one pipeline-dataset capture mode is required"
    | _ when List.length captures <> List.length (List.sort_uniq compare captures)
      ->
        error operation Invalid_argument
          "pipeline-dataset capture modes contain a duplicate"
    | _ ->
        Ok
          (List.fold_left
             (fun bits capture -> bits lor capture_bit capture)
             0 captures)

  let create ~device captures =
    let operation = "Metal.Pipeline_dataset.create" in
    on_main operation (fun () ->
      let ( let* ) value callback = Result.bind value callback in
      let* () = ensure_metal4 operation device in
      let* configuration = validate_captures operation captures in
      match Metal_raw.pipeline_dataset_create device.raw configuration with
      | Error message -> native_error operation message
      | Ok raw ->
          let value : t =
            { raw; lifetime = lifetime (); device; configuration }
          in
          attach device.lifetime;
          attach_finalizer value value.lifetime device.lifetime;
          Ok value)

  let captures (value : t) =
    let captured bit capture reversed =
      if value.configuration land bit <> 0 then capture :: reversed
      else reversed
    in
    [] |> captured 1 Descriptors |> captured 2 Binaries |> List.rev

  let serialize_script (value : t) =
    let operation = "Metal.Pipeline_dataset.serialize_script" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.configuration land 1 = 0 ->
          error operation Invalid_state
            "pipeline descriptor capture was not enabled"
      | Ok () ->
          (match Metal_raw.pipeline_dataset_serialize_script value.raw with
           | Error message -> native_error operation message
           | Ok script -> Ok script))

  let serialize_archive (value : t) path =
    let operation = "Metal.Pipeline_dataset.serialize_archive" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when value.configuration land 2 = 0 ->
          error operation Invalid_state "pipeline binary capture was not enabled"
      | Ok () ->
          (match validate_absolute_path operation path with
           | Error _ as failure -> failure
           | Ok () ->
               match
                 Metal_raw.pipeline_dataset_serialize_archive value.raw path
               with
               | Error message -> native_error operation message
               | Ok () -> Ok ()))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let destroy (value : t) =
    destroy_parent "Metal.Pipeline_dataset.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

module Binary_function = struct
  type t = binary_function

  let make device ~pipeline_independent ~name ~kind raw =
    let value : t =
      { raw
      ; lifetime = lifetime ()
      ; device
      ; pipeline_independent
      ; name
      ; kind
      }
    in
    attach device.lifetime;
    attach_finalizer value value.lifetime device.lifetime;
    value

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime
  let pipeline_independent (value : t) = value.pipeline_independent
  let name (value : t) = value.name
  let kind (value : t) = value.kind

  let destroy (value : t) =
    destroy_leaf "Metal.Binary_function.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

let validate_binary_function_source operation device
    (source : Function.t) ~name ~pipeline_independent =
  let ( let* ) value callback = Result.bind value callback in
  let* () = ensure_live operation source.lifetime in
  let* () = ensure_same_device operation device source.library.device in
  if name = "" || contains_nul name then
    error operation Invalid_argument
      "binary-function name must be nonempty and contain no NUL byte"
  else
    match Function.kind_of_code (Metal_raw.function_kind source.raw) with
    | (Function.Visible | Function.Intersection) as kind ->
        if
          pipeline_independent
          && not (Metal_raw.device_supports_function_pointers device.raw)
        then
          error operation Unsupported
            "pipeline-independent binary functions require Metal function-pointer support"
        else Ok kind
    | _ ->
        error operation Invalid_argument
          "binary-function source must be a visible or intersection function"

let binary_function_descriptor (source : Function.t) ~name
    ~pipeline_independent ~lookup_archives =
  ({ library = source.library.raw
   ; source_function = source.raw
   ; binary_name = name
   ; pipeline_independent
   ; lookup_archives
   }
    : Metal_raw.metal4_binary_function_descriptor)

module Pipeline_archive = struct
  type t = pipeline_archive

  let load_file ?label ~device path =
    let operation = "Metal.Pipeline_archive.load_file" in
    on_main operation (fun () ->
      let ( let* ) value callback = Result.bind value callback in
      let* () = ensure_metal4 operation device in
      let* () = validate_absolute_path operation path in
      if option_exists contains_nul label then
        error operation Invalid_argument
          "pipeline-archive label contains a NUL byte"
      else
        match Metal_raw.pipeline_archive_load_file device.raw path label with
        | Error message -> native_error operation message
        | Ok raw ->
            let value : t = { raw; lifetime = lifetime (); device } in
            attach device.lifetime;
            attach_finalizer value value.lifetime device.lifetime;
            Ok value)

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Pipeline_archive.label" (fun () ->
      match ensure_live "Metal.Pipeline_archive.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.pipeline_archive_label value.raw))

  let load_binary_function ?(pipeline_independent = false) (value : t)
      ~(source : Function.t) ~name =
    let operation = "Metal.Pipeline_archive.load_binary_function" in
    on_main operation (fun () ->
      let ( let* ) result callback = Result.bind result callback in
      let* () = ensure_live operation value.lifetime in
      let* kind =
        validate_binary_function_source operation value.device source ~name
          ~pipeline_independent
      in
      let descriptor =
        binary_function_descriptor source ~name ~pipeline_independent
          ~lookup_archives:[||]
      in
      match
        Metal_raw.pipeline_archive_load_binary_function value.raw descriptor
      with
      | Error message -> native_error operation message
      | Ok raw ->
          Ok
            (Binary_function.make value.device ~pipeline_independent ~name
               ~kind raw))

  let destroy (value : t) =
    destroy_leaf "Metal.Pipeline_archive.destroy" value.lifetime value.raw
      (fun () -> detach value.device.lifetime)
end

let validate_binary_functions operation device functions =
  let rec loop names seen = function
    | [] -> Ok ()
    | (function_ : binary_function) :: rest ->
        if
          List.exists
            (fun (value : binary_function) ->
              value.lifetime == function_.lifetime)
            seen
        then
          error operation Invalid_argument
            "binary-function list contains a duplicate handle"
        else
          (match ensure_live operation function_.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match ensure_same_device operation device function_.device with
                | Error _ as failure -> failure
                | Ok () ->
                    if List.mem function_.name names then
                      error operation Invalid_argument
                        "binary-function list contains a duplicate name"
                    else
                      loop (function_.name :: names) (function_ :: seen) rest))
  in
  loop [] [] functions

let validate_pipeline_archives operation device archives =
  let rec loop seen = function
    | [] -> Ok ()
    | (archive : pipeline_archive) :: rest ->
        if
          List.exists
            (fun (value : pipeline_archive) ->
              value.lifetime == archive.lifetime)
            seen
        then
          error operation Invalid_argument
            "pipeline-archive list contains a duplicate handle"
        else
          (match ensure_live operation archive.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match ensure_same_device operation device archive.device with
                | Error _ as failure -> failure
                | Ok () -> loop (archive :: seen) rest))
  in
  loop [] archives

module Compiler = struct
  type t = compiler

  type static_function =
    { library : Library.t
    ; name : string
    }

  type static_linking =
    { functions : static_function list
    ; private_functions : static_function list
    ; groups : (string * static_function list) list
    }

  let validate_static_functions operation device category functions =
    let rec loop names reversed = function
      | [] -> Ok (Array.of_list (List.rev reversed))
      | function_ :: rest ->
          (match ensure_live operation function_.library.lifetime with
           | Error _ as failure -> failure
           | Ok () ->
               (match
                  ensure_same_device operation device function_.library.device
                with
                | Error _ as failure -> failure
                | Ok ()
                  when function_.name = "" || contains_nul function_.name ->
                    error operation Invalid_argument
                      (category
                       ^ " function name must be nonempty and contain no NUL byte")
                | Ok () when List.mem function_.name names ->
                    error operation Invalid_argument
                      (category ^ " function list contains a duplicate name")
                | Ok () ->
                    loop (function_.name :: names)
                      ((function_.library.raw, function_.name) :: reversed)
                      rest))
    in
    loop [] [] functions

  let validate_static_linking operation device = function
    | None -> Ok None
    | Some ({ functions; private_functions; groups } : static_linking) ->
        let ( let* ) result callback = Result.bind result callback in
        if functions = [] && private_functions = [] && groups = [] then
          error operation Invalid_argument
            "static-linking descriptor must contain at least one function"
        else
          let* raw_functions =
            validate_static_functions operation device "public static-linked"
              functions
          in
          let* raw_private_functions =
            validate_static_functions operation device "private static-linked"
              private_functions
          in
          let public_names = List.map (fun value -> value.name) functions in
          let private_names =
            List.map (fun value -> value.name) private_functions
          in
          if List.exists (fun name -> List.mem name private_names) public_names
          then
            error operation Invalid_argument
              "a static-linked function cannot be both public and private"
          else
            let rec validate_groups names reversed = function
              | [] -> Ok (Array.of_list (List.rev reversed))
              | (name, _) :: _
                when name = "" || contains_nul name ->
                  error operation Invalid_argument
                    "static-link group name must be nonempty and contain no NUL byte"
              | (name, _) :: _ when List.mem name names ->
                  error operation Invalid_argument
                    "static-link groups contain a duplicate name"
              | (_, []) :: _ ->
                  error operation Invalid_argument
                    "static-link groups must contain at least one function"
              | (name, functions) :: rest ->
                  let* raw_group =
                    validate_static_functions operation device
                      ("static-link group " ^ name) functions
                  in
                  validate_groups (name :: names)
                    ((name, raw_group) :: reversed) rest
            in
            let* raw_groups = validate_groups [] [] groups in
            if
              (functions <> [] || groups <> [])
              && not
                   (Metal_raw.device_supports_function_pointers device.raw)
            then
              error operation Unsupported
                "public static linking requires Metal function-pointer support"
            else
              Ok
                (Some
                   ({ functions = raw_functions
                    ; private_functions = raw_private_functions
                    ; groups = raw_groups
                    }
                     : Metal_raw.metal4_static_linking_descriptor))

  let make device dataset raw =
    let value : t = { raw; lifetime = lifetime (); device; dataset } in
    attach device.lifetime;
    Option.iter (fun (dataset : pipeline_dataset) -> attach dataset.lifetime)
      dataset;
    attach_finalizer
      ~on_finalize:(fun () ->
        Option.iter
          (fun (dataset : pipeline_dataset) -> detach dataset.lifetime)
          dataset)
      value value.lifetime device.lifetime;
    value

  let create ?label ?dataset device =
    let operation = "Metal.Compiler.create" in
    on_main operation (fun () ->
      let ( let* ) value callback = Result.bind value callback in
      let* () = ensure_metal4 operation device in
      if option_exists contains_nul label then
        error operation Invalid_argument "compiler label contains a NUL byte"
      else
        let* () =
          match dataset with
          | None -> Ok ()
          | Some (dataset : Pipeline_dataset.t) ->
              let* () = ensure_live operation dataset.lifetime in
              ensure_same_device operation device dataset.device
        in
        match
          Metal_raw.compiler_create device.raw
            (Option.map (fun (value : Pipeline_dataset.t) -> value.raw) dataset)
            label
        with
        | Error message -> native_error operation message
        | Ok raw -> Ok (make device dataset raw))

  let compile_source ?name (value : t) source =
    let operation = "Metal.Compiler.compile_source" in
    on_main operation (fun () ->
      match ensure_live operation value.lifetime with
      | Error _ as failure -> failure
      | Ok () when source = "" ->
          error operation Invalid_argument "shader source is empty"
      | Ok () when contains_nul source ->
          error operation Invalid_argument "shader source contains a NUL byte"
      | Ok ()
        when option_exists
               (fun name -> name = "" || contains_nul name)
               name ->
          error operation Invalid_argument
            "library name must be nonempty and contain no NUL byte"
      | Ok () ->
          (match Metal_raw.compiler_compile_library value.raw source name with
           | Error message -> native_error operation message
           | Ok raw -> Ok (Library.make value.device raw)))

  let create_binary_function ?(pipeline_independent = false)
      ?(lookup_archives = []) (value : t) ~(source : Function.t) ~name =
    let operation = "Metal.Compiler.create_binary_function" in
    on_main operation (fun () ->
      let ( let* ) result callback = Result.bind result callback in
      let* () = ensure_live operation value.lifetime in
      let* kind =
        validate_binary_function_source operation value.device source ~name
          ~pipeline_independent
      in
      let* () =
        validate_pipeline_archives operation value.device lookup_archives
      in
      let descriptor =
        binary_function_descriptor source ~name ~pipeline_independent
          ~lookup_archives:
            (Array.of_list
               (List.map
                  (fun (archive : Pipeline_archive.t) -> archive.raw)
                  lookup_archives))
      in
      match Metal_raw.compiler_create_binary_function value.raw descriptor with
      | Error message -> native_error operation message
      | Ok raw ->
          Ok
            (Binary_function.make value.device ~pipeline_independent ~name
               ~kind raw))

  let product3 x y z =
    if x > max_int / y then None
    else
      let xy = x * y in
      if xy > max_int / z then None else Some (xy * z)

  let create_compute_pipeline ?label ?(reflection = false)
      ?(threadgroup_size_multiple = false)
      ?max_total_threads_per_threadgroup ?required_threads_per_threadgroup
      ?(support_binary_linking = false)
      ?(support_indirect_command_buffers = false)
      ?static_linking ?(binary_linked_functions = [])
      ?(preloaded_libraries = []) ?max_call_stack_depth
      ?(lookup_archives = []) (value : t) ~(library : Library.t)
      function_name =
    let operation = "Metal.Compiler.create_compute_pipeline" in
    on_main operation (fun () ->
      let ( let* ) result callback = Result.bind result callback in
      let* () = ensure_live operation value.lifetime in
      let* () = ensure_live operation library.lifetime in
      let* () = ensure_same_device operation value.device library.device in
      if function_name = "" || contains_nul function_name then
        error operation Invalid_argument
          "compute function name must be nonempty and contain no NUL byte"
      else if option_exists contains_nul label then
        error operation Invalid_argument
          "compute-pipeline label contains a NUL byte"
      else
        let* max_total_threads =
          match max_total_threads_per_threadgroup with
          | None -> Ok 0L
          | Some count when count <= 0 ->
              error operation Invalid_argument
                "maximum total threads must be positive"
          | Some count -> Ok (Int64.of_int count)
        in
        let* required_width, required_height, required_depth =
          match required_threads_per_threadgroup with
          | None -> Ok (0L, 0L, 0L)
          | Some (width, height, depth)
            when width <= 0 || height <= 0 || depth <= 0 ->
              error operation Invalid_argument
                "required threadgroup dimensions must be positive"
          | Some (width, height, depth) ->
              (match product3 width height depth with
               | None ->
                   error operation Invalid_argument
                     "required threadgroup cardinality overflows an OCaml integer"
               | Some product
                 when max_total_threads <> 0L
                      && Int64.of_int product <> max_total_threads ->
                   error operation Invalid_argument
                     "configured maximum threads must equal the required threadgroup cardinality"
               | Some _ ->
                   Ok
                     ( Int64.of_int width
                     , Int64.of_int height
                     , Int64.of_int depth ))
        in
        if
          support_binary_linking
          && not
               (Metal_raw.device_supports_function_pointers value.device.raw)
        then
          error operation Unsupported
            "binary linking requires Metal function-pointer support"
        else
          let* () =
            validate_dynamic_libraries operation value.device
              preloaded_libraries
          in
          let* () =
            validate_binary_functions operation value.device
              binary_linked_functions
          in
          let* static_linking =
            validate_static_linking operation value.device static_linking
          in
          if binary_linked_functions <> [] && not support_binary_linking then
            error operation Invalid_argument
              "binary linked functions require binary-linking support"
          else if
            preloaded_libraries <> []
            && not
                 (Metal_raw.device_supports_dynamic_libraries value.device.raw)
          then
            error operation Unsupported
              "preloaded libraries require Metal dynamic-library support"
          else
            let* max_call_stack_depth =
              match max_call_stack_depth with
              | None ->
                  Ok
                    (if
                       preloaded_libraries = []
                       && binary_linked_functions = []
                     then 0L
                     else 1L)
              | Some depth when depth <= 0 ->
                  error operation Invalid_argument
                    "maximum call-stack depth must be positive"
              | Some depth -> Ok (Int64.of_int depth)
            in
            let* () =
              validate_pipeline_archives operation value.device lookup_archives
            in
            let descriptor : Metal_raw.metal4_compute_descriptor =
              { label
              ; library = library.raw
              ; function_name
              ; reflection
              ; threadgroup_size_multiple
              ; max_total_threads
              ; required_threads_width = required_width
              ; required_threads_height = required_height
              ; required_threads_depth = required_depth
              ; support_binary_linking
              ; support_indirect_commands = support_indirect_command_buffers
              ; preloaded_libraries =
                  Array.of_list
                    (List.map
                       (fun (library : Dynamic_library.t) -> library.raw)
                       preloaded_libraries)
              ; max_call_stack_depth
              ; lookup_archives =
                  Array.of_list
                    (List.map
                       (fun (archive : Pipeline_archive.t) -> archive.raw)
                       lookup_archives)
              ; binary_linked_functions =
                  Array.of_list
                    (List.map
                       (fun (function_ : Binary_function.t) -> function_.raw)
                       binary_linked_functions)
              ; static_linking
              }
            in
            match
              Metal_raw.compiler_create_compute_pipeline value.raw descriptor
            with
            | Error message -> native_error operation message
            | Ok (raw, raw_bindings) ->
                Ok
                  (Compute_pipeline.make value.device ~reflection raw
                     raw_bindings))

  let device (value : t) = value.device
  let generation (value : t) = Metal_raw.generation value.raw
  let dataset (value : t) = value.dataset
  let destroyed (value : t) = is_destroyed value.lifetime

  let label (value : t) =
    on_main "Metal.Compiler.label" (fun () ->
      match ensure_live "Metal.Compiler.label" value.lifetime with
      | Error _ as failure -> failure
      | Ok () -> Ok (Metal_raw.compiler_label value.raw))

  let destroy (value : t) =
    destroy_leaf "Metal.Compiler.destroy" value.lifetime value.raw (fun () ->
      detach value.device.lifetime;
      Option.iter
        (fun (dataset : pipeline_dataset) -> detach dataset.lifetime)
        value.dataset)
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
           | Ok () when Option.is_some texture.placement_sparse_page_size ->
               error operation Unsupported
                 "placement sparse mappings require the Metal 4 command queue"
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

module Placement_mapping = struct
  type queue = placement_mapping_queue
  type t = placement_mapping

  type tile_range =
    { offset : int
    ; length : int
    }

  type kind =
    | Buffer
    | Texture

  let ( let* ) value callback = Result.bind value callback
  let operation_prefix name = "Metal.Placement_mapping." ^ name

  let require operation kind condition message =
    if condition then Ok () else error operation kind message

  let create_queue ?label (device : Device.t) =
    let operation = operation_prefix "create_queue" in
    on_main operation (fun () ->
      let* () = ensure_live operation device.lifetime in
      let* () =
        require operation Invalid_argument
          (not (option_exists contains_nul label))
          "queue label contains a NUL byte"
      in
      let* () =
        require operation Unsupported
          (Metal_raw.device_supports_placement_sparse device.raw)
          "device does not support Metal 4 placement mappings"
      in
      match Metal_raw.placement_mapping_queue_create device.raw label with
      | Error message -> native_error operation message
      | Ok raw ->
          let value : queue =
            { raw; lifetime = lifetime (); device; mappings = ref [] }
          in
          attach device.lifetime;
          attach_finalizer value value.lifetime device.lifetime;
          Ok value)

  let queue_device (value : queue) = value.device
  let queue_generation (value : queue) = Metal_raw.generation value.raw
  let queue_destroyed (value : queue) = is_destroyed value.lifetime

  let queue_label (value : queue) =
    let operation = operation_prefix "queue_label" in
    on_main operation (fun () ->
      let* () = ensure_live operation value.lifetime in
      Ok (Metal_raw.placement_mapping_queue_label value.raw))

  let destroy_queue (value : queue) =
    destroy_parent (operation_prefix "destroy_queue") value.lifetime value.raw
      (fun () -> detach value.device.lifetime)

  let kind (value : t) =
    match value.target with
    | Placement_buffer_mapping _ -> Buffer
    | Placement_texture_mapping _ -> Texture

  let heap (value : t) = value.heap
  let page_size (value : t) = value.page_size
  let heap_offset (value : t) = value.heap_offset
  let mapped_bytes (value : t) = value.mapped_bytes
  let destroyed (value : t) = not (Atomic.get value.active)

  let active_mappings (mappings : placement_mapping list ref) =
    let active =
      List.filter
        (fun (mapping : placement_mapping) -> Atomic.get mapping.active)
        !mappings
    in
    mappings := active;
    active

  let ensure_only_mapping_dependents operation lifetime
      (mappings : placement_mapping list ref) =
    let active = active_mappings mappings in
    let* () =
      require operation Parent_has_dependents
        (dependent_count lifetime = List.length active)
        "resource has a live view, CPU mapping, or command dependency"
    in
    Ok active

  let page_compatible maximum requested =
    Sparse_page_size.bytes maximum >= Sparse_page_size.bytes requested

  let validate_heap operation (queue : queue) (heap : Heap.t) ~storage
      ~cpu_cache page_size =
    let* () = ensure_live operation heap.lifetime in
    let* () = ensure_same_device operation queue.device heap.device in
    let* () =
      require operation Invalid_argument
        (heap.descriptor.kind = Placement)
        "placement sparse mappings require a placement heap"
    in
    let* () =
      require operation Invalid_state
        (Atomic.get heap.purgeable = Nonvolatile)
        "placement heap must be nonvolatile before mapping"
    in
    let* () =
      require operation Invalid_argument
        (heap.descriptor.storage = storage
         && heap.descriptor.cpu_cache = cpu_cache)
        "placement heap storage and cache modes must match the resource"
    in
    match heap.descriptor.sparse_page_size with
    | None ->
        error operation Invalid_argument
          "placement heap has no sparse-page compatibility"
    | Some maximum when not (page_compatible maximum page_size) ->
        error operation Invalid_argument
          "placement heap sparse pages are smaller than the resource pages"
    | Some _ -> Ok ()

  let prepare_mapping (value : t)
      (resource_mappings : placement_mapping list ref) =
    let queue = value.queue and heap = value.heap in
    let queue_entries = value :: !(queue.mappings)
    and resource_entries = value :: !resource_mappings
    and allocations = value.allocation :: !(heap.allocations) in
    resource_mappings, queue_entries, resource_entries, allocations

  let register_mapping (value : t)
      (resource_mappings, queue_entries, resource_entries, allocations) =
    let queue = value.queue and heap = value.heap in
    attach queue.lifetime;
    attach heap.lifetime;
    Atomic.incr heap.active_uses;
    (match value.target with
     | Placement_buffer_mapping target -> attach target.buffer.lifetime
     | Placement_texture_mapping target -> attach target.texture.lifetime);
    queue.mappings := queue_entries;
    resource_mappings := resource_entries;
    heap.allocations := allocations

  let validate_physical_span operation (heap : Heap.t) ~page_bytes
      ~physical_tiles ~heap_offset =
    let* () =
      require operation Invalid_argument
        (heap_offset >= 0L && Int64.rem heap_offset page_bytes = 0L)
        "heap offset must be aligned to the resource page size"
    in
    let* () =
      require operation Invalid_argument
        (physical_tiles <= Int64.div Int64.max_int page_bytes)
        "mapped byte cardinality overflows int64"
    in
    let mapped_bytes = Int64.mul physical_tiles page_bytes in
    let required : Heap.size_and_align =
      { size = mapped_bytes; alignment = page_bytes }
    in
    let* () =
      Heap.validate_placement operation heap (Some heap_offset) required
    in
    Ok mapped_bytes

  let make_mapping queue heap target page_size heap_offset mapped_bytes =
    let allocation : heap_allocation =
      { offset = heap_offset; size = mapped_bytes; active = Atomic.make true }
    in
    ({ queue
     ; heap
     ; allocation
     ; target
     ; page_size
     ; heap_offset
     ; mapped_bytes
     ; active = Atomic.make true
     }
      : t)

  let interval_overlaps left_offset left_length right_offset right_length =
    left_offset < Int64.add right_offset right_length
    && right_offset < Int64.add left_offset left_length

  let buffer_range_overlaps tile_offset tile_count (mapping : t) =
    match mapping.target with
    | Placement_buffer_mapping target ->
        interval_overlaps tile_offset tile_count target.tile_offset
          target.tile_count
    | Placement_texture_mapping _ -> false

  let map_buffer (queue : queue) ~(heap : Heap.t) ~heap_offset
      (buffer : Buffer.t) ~(range : tile_range) =
    let operation = operation_prefix "map_buffer" in
    on_main operation (fun () ->
      let* () = ensure_live operation queue.lifetime in
      let* () = ensure_buffer_usable operation buffer in
      let* () = ensure_same_device operation queue.device buffer.device in
      let* page_size =
        match buffer.placement_sparse_page_size with
        | Some page_size -> Ok page_size
        | None ->
            error operation Invalid_argument "buffer is not placement sparse"
      in
      let* () =
        validate_heap operation queue heap ~storage:buffer.storage
          ~cpu_cache:buffer.cpu_cache page_size
      in
      let* active =
        ensure_only_mapping_dependents operation buffer.lifetime
          buffer.placement_mappings
      in
      let* () =
        require operation Invalid_argument
          (range.offset >= 0 && range.length > 0)
          "buffer tile range must be positive"
      in
      let page_bytes = Sparse_page_size.bytes page_size in
      let tile_offset = Int64.of_int range.offset
      and tile_count = Int64.of_int range.length in
      let whole_tiles = Int64.div buffer.length page_bytes in
      let virtual_tiles =
        if Int64.rem buffer.length page_bytes = 0L then whole_tiles
        else Int64.succ whole_tiles
      in
      let* () =
        require operation Invalid_argument
          (tile_offset <= virtual_tiles
           && tile_count <= Int64.sub virtual_tiles tile_offset)
          "buffer tile range exceeds the virtual resource"
      in
      let* () =
        require operation Invalid_state
          (not (List.exists (buffer_range_overlaps tile_offset tile_count) active))
          "buffer tile range overlaps a live mapping"
      in
      let* mapped_bytes =
        validate_physical_span operation heap ~page_bytes
          ~physical_tiles:tile_count ~heap_offset
      in
      let target =
        Placement_buffer_mapping { buffer; tile_offset; tile_count }
      in
      let value =
        make_mapping queue heap target page_size heap_offset mapped_bytes
      in
      let registration = prepare_mapping value buffer.placement_mappings in
      let raw_heap_offset = Int64.div heap_offset page_bytes in
      match
        Metal_raw.placement_mapping_update_buffer queue.raw buffer.raw
          (Some heap.raw) 0
          ( tile_offset
          , tile_count
          , raw_heap_offset
          , sparse_page_size_code page_size )
      with
      | Error message -> native_error operation message
      | Ok () ->
          register_mapping value registration;
          Ok value)

  let texture_regions_overlap left right =
    let lx, ly, lz, lw, lh, ld = left
    and rx, ry, rz, rw, rh, rd = right in
    lx < rx + rw && rx < lx + lw
    && ly < ry + rh && ry < ly + lh
    && lz < rz + rd && rz < lz + ld

  let texture_region_overlaps raw_region mip_level slice (mapping : t) =
    match mapping.target with
    | Placement_texture_mapping target ->
        target.mip_level = mip_level && target.slice = slice
        && texture_regions_overlap raw_region target.region
    | Placement_buffer_mapping _ -> false

  let validate_texture_parent operation (texture : Texture.t) =
    match texture.parent with
    | Texture_resource (Device_resource _) -> Ok ()
    | Texture_view _ ->
        error operation Invalid_argument
          "map the base placement sparse texture, not a view"
    | Texture_buffer_resource _ | Texture_io_surface_resource _
    | Texture_resource (Heap_resource _ | External_resource _) ->
        error operation Invalid_argument
          "texture is not a device-owned placement sparse resource"

  let validate_texture_region operation (texture : Texture.t) ~mip_level
      ~slice (region : Resource_state_encoder.tile_region) =
    let* info =
      match Texture.sparse_info_raw operation texture with
      | Ok (Some info) -> Ok info
      | Ok None -> error operation Invalid_argument "texture is not sparse"
      | Error _ as failure -> failure
    in
    let descriptor = texture.descriptor in
    let* () =
      require operation Invalid_argument
        (mip_level >= 0 && mip_level < descriptor.mip_levels)
        "mapping mip level is outside the texture"
    in
    let* () =
      require operation Invalid_argument
        (slice >= 0 && slice < Texture.total_slices descriptor)
        "mapping slice is outside the texture"
    in
    let mip_width = Texture.mip_dimension descriptor.width mip_level
    and mip_height = Texture.mip_dimension descriptor.height mip_level
    and mip_depth = Texture.mip_dimension descriptor.depth mip_level in
    let tile_width =
      Resource_state_encoder.ceil_div mip_width info.tile_width
    and tile_height =
      Resource_state_encoder.ceil_div mip_height info.tile_height
    and tile_depth =
      Resource_state_encoder.ceil_div mip_depth info.tile_depth
    in
    let* () =
      require operation Invalid_argument
        (Resource_state_encoder.valid_axis region.x region.width tile_width
         && Resource_state_encoder.valid_axis region.y region.height tile_height
         && Resource_state_encoder.valid_axis region.z region.depth tile_depth)
        "texture tile region exceeds the selected mip level"
    in
    let tail = info.first_mip_in_tail = Some mip_level in
    let* () =
      match info.first_mip_in_tail with
      | Some first when mip_level > first ->
          error operation Invalid_argument
            "map a placement sparse mip tail through its first mip level"
      | Some _ when tail
                    && region <>
                       { x = 0; y = 0; z = 0; width = 1; height = 1
                       ; depth = 1
                       } ->
          error operation Invalid_argument
            "a placement sparse mip-tail mapping must cover its single tail tile"
      | None | Some _ -> Ok ()
    in
    let* tile_count =
      Resource_state_encoder.tile_cardinality operation region
    in
    let page_bytes = info.tile_size_in_bytes in
    let physical_tiles =
      if tail then
        let bytes = info.tail_size_in_bytes in
        if bytes = 0L then 0L
        else Int64.succ (Int64.div (Int64.pred bytes) page_bytes)
      else Int64.of_int tile_count
    in
    let* () =
      if physical_tiles > 0L then Ok ()
      else
        native_error operation
          "Metal returned an empty placement sparse mapping"
    in
    Ok (Resource_state_encoder.region_tuple region, page_bytes, physical_tiles)

  let map_texture (queue : queue) ~(heap : Heap.t) ~heap_offset
      (texture : Texture.t) ~mip_level ~slice
      ~(region : Resource_state_encoder.tile_region) =
    let operation = operation_prefix "map_texture" in
    on_main operation (fun () ->
      let* () = ensure_live operation queue.lifetime in
      let* () = ensure_texture_usable operation texture in
      let* () = ensure_same_device operation queue.device texture.device in
      let* () = validate_texture_parent operation texture in
      let* page_size =
        match texture.placement_sparse_page_size with
        | Some page_size -> Ok page_size
        | None ->
            error operation Invalid_argument "texture is not placement sparse"
      in
      let* () =
        validate_heap operation queue heap ~storage:texture.descriptor.storage
          ~cpu_cache:texture.descriptor.cpu_cache page_size
      in
      let* active =
        ensure_only_mapping_dependents operation texture.lifetime
          texture.placement_mappings
      in
      let* raw_region, page_bytes, physical_tiles =
        validate_texture_region operation texture ~mip_level ~slice region
      in
      let* () =
        require operation Invalid_state
          (not
             (List.exists
                (texture_region_overlaps raw_region mip_level slice)
                active))
          "texture tile region overlaps a live mapping"
      in
      let* mapped_bytes =
        validate_physical_span operation heap ~page_bytes ~physical_tiles
          ~heap_offset
      in
      let target =
        Placement_texture_mapping { texture; region = raw_region; mip_level; slice }
      in
      let value =
        make_mapping queue heap target page_size heap_offset mapped_bytes
      in
      let registration = prepare_mapping value texture.placement_mappings in
      let raw_heap_offset = Int64.div heap_offset page_bytes in
      match
        Metal_raw.placement_mapping_update_texture queue.raw texture.raw
          (Some heap.raw)
          ( 0
          , raw_region
          , mip_level
          , slice
          , raw_heap_offset
          , sparse_page_size_code page_size )
      with
      | Error message -> native_error operation message
      | Ok () ->
          register_mapping value registration;
          Ok value)

  let remove_mapping (value : t)
      (resource_mappings : placement_mapping list ref) =
    let keep (retained : placement_mapping) =
      retained != value && Atomic.get retained.active
    in
    value.queue.mappings := List.filter keep !(value.queue.mappings);
    resource_mappings := List.filter keep !resource_mappings;
    Atomic.set value.active false;
    Atomic.set value.allocation.active false;
    Atomic.decr value.heap.active_uses;
    (match value.target with
     | Placement_buffer_mapping target -> detach target.buffer.lifetime
     | Placement_texture_mapping target -> detach target.texture.lifetime);
    detach value.heap.lifetime;
    detach value.queue.lifetime

  let unmap_buffer operation (value : t) (buffer : buffer) ~tile_offset
      ~tile_count =
    let* () = ensure_live operation buffer.lifetime in
    let* _ =
      ensure_only_mapping_dependents operation buffer.lifetime
        buffer.placement_mappings
    in
    match
      Metal_raw.placement_mapping_update_buffer value.queue.raw buffer.raw None 1
        ( tile_offset
        , tile_count
        , 0L
        , sparse_page_size_code value.page_size )
    with
    | Error message -> native_error operation message
    | Ok () ->
        remove_mapping value buffer.placement_mappings;
        Ok ()

  let unmap_texture operation (value : t) (texture : texture) ~region
      ~mip_level ~slice =
    let* () = ensure_live operation texture.lifetime in
    let* _ =
      ensure_only_mapping_dependents operation texture.lifetime
        texture.placement_mappings
    in
    match
      Metal_raw.placement_mapping_update_texture value.queue.raw
        texture.raw None
        ( 1
        , region
        , mip_level
        , slice
        , 0L
        , sparse_page_size_code value.page_size )
    with
    | Error message -> native_error operation message
    | Ok () ->
        remove_mapping value texture.placement_mappings;
        Ok ()

  let unmap (value : t) =
    let operation = operation_prefix "unmap" in
    on_main operation (fun () ->
      if not (Atomic.get value.active) then Ok ()
      else
        let* () = ensure_live operation value.queue.lifetime in
        let* () = ensure_live operation value.heap.lifetime in
        match value.target with
        | Placement_buffer_mapping target ->
            unmap_buffer operation value target.buffer
              ~tile_offset:target.tile_offset ~tile_count:target.tile_count
        | Placement_texture_mapping target ->
            unmap_texture operation value target.texture ~region:target.region
              ~mip_level:target.mip_level ~slice:target.slice)
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
