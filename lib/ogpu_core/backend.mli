type token = int64
type receipt = { epoch:int64 }
type driver_resource = { token:token; write:int64 -> bytes -> (unit,Error.t) result;
  read:int64 -> int -> (bytes,Error.t) result;
  read_into:int64 -> bytes -> int -> int -> (unit,Error.t) result;
  destroy:unit -> (unit,Error.t) result }

(** A function table created from a pipeline with linked functions: an
    intersection table (functions and their argument buffers) or a visible
    function table. *)
type driver_table =
  { table_token:token
  ; table_set_function:index:int -> string -> (unit,Error.t) result
  ; table_set_buffer:index:int -> token -> offset:int64 -> (unit,Error.t) result
  ; destroy_table:unit -> (unit,Error.t) result }
type driver_pipeline =
  { pipeline_token:token
  ; create_table:intersection:bool -> capacity:int -> (driver_table,Error.t) result
  ; destroy_pipeline:unit -> (unit,Error.t) result }
type driver_frame = { frame_token:token }

(** Accumulated GPU execution time reported by the driver for this queue's device. *)
type gpu_timing = { timing_supported:bool; gpu_seconds:float; gpu_samples:int64 }
type driver_surface =
  { surface_token:token
  ; configure:Surface.configuration -> (unit,Error.t) result
  ; acquire:unit -> ([ `Acquired of driver_frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
  ; acquire_sync:unit -> ([ `Acquired of driver_frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
  ; discard:driver_frame -> (unit,Error.t) result
  ; destroy_surface:unit -> (unit,Error.t) result }
type driver_library =
  { library_token:token
  ; create_compute_pipeline_in:entry:string -> constants:(string * Shader.constant_value) list ->
      interface:Shader.binding list -> linked:string list -> archives:token list -> archive_only:bool ->
      (driver_pipeline,Error.t) result
  ; destroy_library:unit -> (unit,Error.t) result }
type accel_sizes = { structure_size:int64; build_scratch_size:int64; refit_scratch_size:int64 }
type driver_keyframe = token * int64
type driver_geometry =
  | Driver_triangles of { vertices:token; offset:int64; length:int64; vertex_stride:int; vertex_count:int }
  | Driver_motion_triangles of { keyframes:driver_keyframe array; vertex_stride:int; vertex_count:int }
  | Driver_boxes of { boxes:driver_keyframe array; stride:int; count:int; opaque:bool; duplicate:bool; table_offset:int }
  | Driver_curves of { control:driver_keyframe array; control_stride:int; control_count:int
                     ; radii:driver_keyframe array; radius_stride:int; indices:token; index_offset:int64
                     ; segment_count:int; per_segment:int; curve_type:int; basis:int; caps:int }
type driver_motion =
  { motion_keyframes:int; motion_start:float; motion_end:float; motion_start_border:int; motion_end_border:int }
type instance_kind = Acceleration.instance_kind = Default_instances | User_id_instances | Motion_instances
type driver_accel_descriptor =
  | Driver_blas of { geometries:driver_geometry array; allow_refit:bool; motion:driver_motion option }
  | Driver_tlas of { instances:token; offset:int64; instance_count:int; kind:instance_kind
                   ; structures:token array; allow_refit:bool; motion_transforms:(token * int64 * int) option }
  | Driver_sized of { size:int64; template:token }
type driver_accel = { accel_token:token; accel_sizes:accel_sizes; destroy_accel:unit -> (unit,Error.t) result }

(** One TLAS instance: a row-major 3×4 affine transform (12 floats), a
    visibility [mask] (32 bits), and the index of its bottom-level structure
    in the TLAS descriptor's [structures]. Packed by the driver into its own
    native layout through [pack_instances]. *)
type instance = { transform:float array; mask:int; structure_index:int }
type driver_compute_encoder =
  { set_pipeline:token -> (unit,Error.t) result
  ; set_buffer:index:int -> offset:int64 -> token -> (unit,Error.t) result
  ; set_bytes:index:int -> bytes -> (unit,Error.t) result
  ; set_texture:index:int -> token -> (unit,Error.t) result
  ; set_accel:index:int -> token -> (unit,Error.t) result
  ; set_table:index:int -> token -> (unit,Error.t) result
  ; dispatch_threads:threads:int * int * int -> threadgroup:int * int * int -> (unit,Error.t) result
  ; dispatch_threadgroups:threadgroups:int * int * int -> threadgroup:int * int * int -> (unit,Error.t) result
  ; compute_use_heap:token -> (unit,Error.t) result
  ; compute_update_fence:token -> (unit,Error.t) result
  ; compute_wait_fence:token -> (unit,Error.t) result
  ; end_compute:unit -> (unit,Error.t) result }
type driver_accel_encoder =
  { build:token -> scratch:token -> scratch_offset:int64 -> (unit,Error.t) result
  ; refit:token -> scratch:token -> scratch_offset:int64 -> (unit,Error.t) result
  ; copy:src:token -> dst:token -> (unit,Error.t) result
  ; compact:src:token -> dst:token -> (unit,Error.t) result
  ; write_compacted_size:token -> dst:token -> offset:int64 -> (unit,Error.t) result
  ; end_accel:unit -> (unit,Error.t) result }
type driver_blit_encoder =
  { copy_buffer:src:token -> src_offset:int64 -> dst:token -> dst_offset:int64 -> length:int64 -> (unit,Error.t) result
  ; fill_buffer:token -> offset:int64 -> length:int64 -> value:int -> (unit,Error.t) result
  ; buffer_to_texture:src:token -> offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> dst:token -> mip:int -> origin:Types.origin -> extent:Types.extent -> (unit,Error.t) result
  ; texture_to_buffer:src:token -> mip:int -> origin:Types.origin -> extent:Types.extent -> dst:token -> offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> (unit,Error.t) result
  ; copy_texture:src:token -> src_mip:int -> src_origin:Types.origin -> dst:token -> dst_mip:int -> dst_origin:Types.origin -> extent:Types.extent -> (unit,Error.t) result
  ; blit_update_fence:token -> (unit,Error.t) result
  ; blit_wait_fence:token -> (unit,Error.t) result
  ; resolve_timestamps:token -> first:int -> count:int -> dst:token -> offset:int64 -> (unit,Error.t) result
  ; end_blit:unit -> (unit,Error.t) result }
type shader_stage = Vertex | Fragment | Object | Mesh | Tile
type winding = Clockwise | Counter_clockwise
type depth_state = { depth_compare:Render_pass.comparison; depth_write:bool; stencil:Render_pass.stencil_state option }
type driver_color_attachment = { color:token; color_resolve:token option; color_load:Render_pass.load; color_store:Render_pass.store; color_clear:float * float * float * float }
type driver_depth_attachment = { depth:token; depth_load:Render_pass.load; depth_store:Render_pass.store; depth_clear:float }
type driver_stencil_attachment = { stencil:token; stencil_load:Render_pass.load; stencil_store:Render_pass.store; stencil_clear:int }
type driver_render_target = { target_colors:driver_color_attachment array; target_depth:driver_depth_attachment option; target_stencil:driver_stencil_attachment option; target_width:int; target_height:int; target_samples:int }
type driver_batch_draw = { batch_pipeline:token; batch_buffers:(shader_stage * int * token * int64) array; batch_primitive:Render_pass.primitive; batch_index:(Render_pass.index_type * token * int64 * int64) option; batch_vertex_start:int; batch_vertex_count:int; batch_instances:int }
type driver_render_encoder =
  { render_set_pipeline:token -> (unit,Error.t) result
  ; set_stage_buffer:shader_stage -> index:int -> offset:int64 -> token -> (unit,Error.t) result
  ; set_stage_bytes:shader_stage -> index:int -> bytes -> (unit,Error.t) result
  ; set_stage_texture:shader_stage -> index:int -> token -> (unit,Error.t) result
  ; set_stage_sampler:shader_stage -> index:int -> token -> (unit,Error.t) result
  ; set_viewport:Render_pass.rect -> (unit,Error.t) result
  ; set_scissor:Render_pass.rect -> (unit,Error.t) result
  ; set_cull:Render_pass.cull -> (unit,Error.t) result
  ; set_winding:winding -> (unit,Error.t) result
  ; set_depth_state:depth_state option -> (unit,Error.t) result
  ; set_stencil_reference:front:int32 -> back:int32 -> (unit,Error.t) result
  ; draw:primitive:Render_pass.primitive -> first:int -> count:int -> instances:int -> (unit,Error.t) result
  ; draw_indexed:primitive:Render_pass.primitive -> index_type:Render_pass.index_type -> token -> offset:int64 -> count:int64 -> instances:int -> (unit,Error.t) result
  ; draw_batch:driver_batch_draw array -> (unit,Error.t) result
  ; use_resources:token list -> (unit,Error.t) result
  ; execute_icb:token -> location:int -> length:int -> (unit,Error.t) result
  ; render_use_heap:token -> (unit,Error.t) result
  ; render_update_fence:token -> (unit,Error.t) result
  ; render_wait_fence:token -> (unit,Error.t) result
  ; draw_mesh:threadgroups:int * int * int -> object_threadgroup:(int * int * int) option -> mesh_threadgroup:int * int * int -> (unit,Error.t) result
  ; dispatch_tile:threads:int * int * int -> (unit,Error.t) result
  ; tile_size:unit -> (int * int,Error.t) result
  ; end_render:unit -> (unit,Error.t) result }
type driver_sampler = { sampler_token:token; destroy_sampler:unit -> (unit,Error.t) result }
type driver_icb =
  { icb_token:token
  ; icb_reset:location:int -> length:int -> (unit,Error.t) result
  ; icb_set_pipeline:index:int -> token -> (unit,Error.t) result
  ; icb_set_buffer:index:int -> shader_stage -> slot:int -> offset:int64 -> token -> (unit,Error.t) result
  ; icb_draw:index:int -> primitive:Render_pass.primitive -> first:int -> count:int -> instances:int -> (unit,Error.t) result
  ; icb_draw_indexed:index:int -> primitive:Render_pass.primitive -> index_type:Render_pass.index_type -> token -> offset:int64 -> count:int64 -> instances:int -> (unit,Error.t) result
  ; destroy_icb:unit -> (unit,Error.t) result }
type driver_argument =
  { argument_token:token; argument_length:int; argument_alignment:int
  ; argument_texture:buffer:token -> offset:int64 -> slot:int -> token -> (unit,Error.t) result
  ; argument_sampler:buffer:token -> offset:int64 -> slot:int -> token -> (unit,Error.t) result
  ; destroy_argument:unit -> (unit,Error.t) result }
type render_pipeline_options = { blend:Pipeline.blend; topology:Render_pass.primitive; indirect:bool; archives:token list; archive_only:bool }

(** {2 Plan G7 driver records: mesh/tile pipelines, dynamic libraries, archives, sparse, upscaling} *)
type driver_mesh_options =
  { mesh_library:token; mesh_object_entry:string option; mesh_entry:string; mesh_fragment_entry:string
  ; mesh_color:Pipeline.color_format; mesh_blend:Pipeline.blend; mesh_threads:int * int * int
  ; object_threads:(int * int * int) option; mesh_archives:token list; mesh_archive_only:bool; mesh_label:string option }
type driver_tile_options =
  { tile_library:token; tile_entry:string; tile_color:Pipeline.color_format; tile_threads:int * int * int
  ; tile_archives:token list; tile_archive_only:bool; tile_label:string option }
type driver_dynamic = { dynamic_token:token; destroy_dynamic:unit -> (unit,Error.t) result }
type driver_archive =
  { archive_token:token
  ; archive_add:token -> (unit,Error.t) result
  ; archive_serialize:string -> (unit,Error.t) result
  ; destroy_archive:unit -> (unit,Error.t) result }
type driver_upscaler = { upscaler_token:token; destroy_upscaler:unit -> (unit,Error.t) result }

(** {2 Plan G6 driver records: heaps, residency, fences, events, timestamps} *)

(** A placement heap. Resources created from it may overlap; [heap_tracked]
    asks the driver to track hazards between them, otherwise fences order
    aliased use. *)
type heap_descriptor = { heap_size:int64; heap_memory:Types.memory; heap_tracked:bool; heap_sparse:bool; heap_label:string option }
type placement = { placement_size:int64; placement_alignment:int64 }
type placement_query = Buffer_placement of Types.memory * int64 | Texture_placement of Types.texture_descriptor
type driver_heap =
  { heap_token:token
  ; heap_buffer:offset:int64 -> Types.buffer_descriptor -> (driver_resource,Error.t) result
  ; heap_texture:offset:int64 -> Types.texture_descriptor -> (driver_resource,Error.t) result
  ; heap_alias:token -> (unit,Error.t) result
  ; destroy_heap:unit -> (unit,Error.t) result }
type residency_item = Resident_buffer of token | Resident_texture of token | Resident_heap of token
type driver_residency =
  { residency_token:token
  ; residency_add:residency_item -> (unit,Error.t) result
  ; residency_remove:residency_item -> (unit,Error.t) result
  ; residency_commit:unit -> (unit,Error.t) result
  ; residency_size:unit -> (int64,Error.t) result
  ; destroy_residency:unit -> (unit,Error.t) result }
type driver_fence = { fence_token:token; destroy_fence:unit -> (unit,Error.t) result }

(** A timeline event: the host reads, signals, and waits on it; commands
    signal and wait on it between encoders. *)
type driver_event =
  { event_token:token
  ; event_value:unit -> (int64,Error.t) result
  ; event_signal:int64 -> (unit,Error.t) result
  ; event_wait:int64 -> timeout_ms:int -> (bool,Error.t) result
  ; destroy_event:unit -> (unit,Error.t) result }

(** GPU timestamps sampled at encoder stage boundaries. *)
type driver_timestamps =
  { timestamps_token:token
  ; timestamps_read:first:int -> count:int -> (int64 array,Error.t) result
  ; destroy_timestamps:unit -> (unit,Error.t) result }
type timestamp_reference = { cpu_nanoseconds:int64; gpu_timestamp:int64; gpu_frequency:int64 }
type driver_sampling = { sampling_token:token; sampling_start:int; sampling_end:int }
type driver_commands =
  { commands_token:token
  ; compute_encoder:driver_sampling option -> (driver_compute_encoder,Error.t) result
  ; accel_encoder:unit -> (driver_accel_encoder,Error.t) result
  ; blit_encoder:driver_sampling option -> (driver_blit_encoder,Error.t) result
  ; render_encoder:driver_sampling option -> driver_render_target -> (driver_render_encoder,Error.t) result
  ; commands_use_residency:token -> (unit,Error.t) result
  ; commands_signal_event:token -> int64 -> (unit,Error.t) result
  ; commands_wait_event:token -> int64 -> (unit,Error.t) result
  ; map_tiles:token -> mip:int -> region:int * int * int * int -> map:bool -> (unit,Error.t) result
  ; upscale:token -> src:token -> dst:token -> (unit,Error.t) result
  ; commit:unit -> (receipt,Error.t) result
  ; commit_present:source:token -> driver_frame -> (receipt,Error.t) result
  ; abandon:unit -> (unit,Error.t) result }

type driver_queue =
  { queue_token:token
  ; complete_through:int64 -> (unit,Error.t) result
  ; poll_through:int64 -> (bool,Error.t) result
  ; completed_epoch:unit -> int64
  ; begin_commands:unit -> (driver_commands,Error.t) result
  ; queue_add_residency:token -> (unit,Error.t) result
  ; queue_remove_residency:token -> (unit,Error.t) result
  ; gpu_duration:int64 -> float option
  ; gpu_timing:unit -> gpu_timing
  ; destroy_queue:unit -> (unit,Error.t) result }
type driver_device =
  { device_token:token; device_handle:Handle.device; capabilities:Caps.t
  ; create_buffer:Types.memory -> Types.buffer_descriptor -> (driver_resource,Error.t) result
  ; create_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_depth_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_stencil_texture:Types.texture_descriptor -> (driver_resource,Error.t) result
  ; create_library:Shader.t -> dynamic:token list -> (driver_library,Error.t) result
  ; create_accel:driver_accel_descriptor -> (driver_accel,Error.t) result
  ; instance_layout:instance_kind -> Acceleration.instance_layout
  ; create_sampler:Types.sampler_descriptor -> (driver_sampler,Error.t) result
  ; create_render_pipeline:render_pipeline_options -> Pipeline.render_descriptor -> (driver_pipeline,Error.t) result
  ; create_icb:max_commands:int -> (driver_icb,Error.t) result
  ; create_argument:pipeline:token -> shader_stage -> index:int -> (driver_argument,Error.t) result
  ; create_queue:unit -> (driver_queue,Error.t) result
  ; create_surface:Surface.configuration -> (driver_surface,Error.t) result
  ; create_heap:heap_descriptor -> (driver_heap,Error.t) result
  ; heap_placement:placement_query -> (placement,Error.t) result
  ; create_residency:capacity:int -> label:string option -> (driver_residency,Error.t) result
  ; create_fence:unit -> (driver_fence,Error.t) result
  ; create_event:unit -> (driver_event,Error.t) result
  ; create_timestamps:count:int -> (driver_timestamps,Error.t) result
  ; timestamp_reference:unit -> (timestamp_reference,Error.t) result
  ; create_mesh_pipeline:driver_mesh_options -> (driver_pipeline,Error.t) result
  ; create_tile_pipeline:driver_tile_options -> (driver_pipeline,Error.t) result
  ; create_dynamic_library:install_name:string -> Shader.t -> (driver_dynamic,Error.t) result
  ; create_archive:path:string option -> (driver_archive,Error.t) result
  ; create_sparse_texture:heap:token -> Types.texture_descriptor -> (driver_resource,Error.t) result
  ; texture_tile:token -> (int * int,Error.t) result
  ; create_upscaler:input:int * int -> output:int * int -> (driver_upscaler,Error.t) result
  ; destroy_device:unit -> (unit,Error.t) result }
type driver = { create_device:unit -> (driver_device,Error.t) result }

type device
type buffer
type texture
type pipeline
type queue
type surface
type frame

val create_device : driver -> (device,Error.t) result
val capabilities : device -> Caps.t
val device_handle : device -> Handle.device
val create_buffer : ?memory:Types.memory -> device -> Types.buffer_descriptor -> (buffer,Error.t) result
val create_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val create_depth_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val create_stencil_texture : device -> Types.texture_descriptor -> (texture,Error.t) result
val create_queue : device -> (queue,Error.t) result
val create_surface : device -> Surface.configuration -> (surface,Error.t) result
val buffer_id : buffer -> int64
val texture_id : texture -> int64
val write_buffer : buffer -> offset:int64 -> bytes -> (unit,Error.t) result
val read_buffer : buffer -> offset:int64 -> length:int -> (bytes,Error.t) result
val read_texture : texture -> bytes_per_row:int -> (bytes,Error.t) result
val read_texture_into : texture -> bytes_per_row:int -> destination:bytes ->
  (unit,Error.t) result
val complete_through : queue -> int64 -> (unit,Error.t) result
val poll_through : queue -> int64 -> (bool,Error.t) result
val completed_epoch : queue -> int64
val configure : surface -> Surface.configuration -> (unit,Error.t) result
val acquire : surface -> ([ `Acquired of frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
val acquire_sync : surface -> ([ `Acquired of frame | `Timeout | `Occluded | `Device_lost ],Error.t) result
val discard : frame -> (unit,Error.t) result
val destroy_buffer : buffer -> (unit,Error.t) result
val destroy_texture : texture -> (unit,Error.t) result
val destroy_pipeline : pipeline -> (unit,Error.t) result
val destroy_queue : queue -> (unit,Error.t) result
val destroy_surface : surface -> (unit,Error.t) result
val destroy_device : device -> (unit,Error.t) result

module Private : sig
  val texture_driver_token : texture -> int64 * int64
  val texture_descriptor : texture -> Types.texture_descriptor
  val texture_destroyed : texture -> bool
end

(** {1 Reusable libraries, acceleration structures, and encoders}

    Immediate-mode command recording modelled on Metal: a [commands] value is
    recorded through one open encoder at a time and committed without
    blocking; [Command_buffer.status] polls its receipt. Drivers translate
    tokens; every state, range, capability, and device check lives here. *)
type library
type accel
type commands
type compute_encoder
type accel_encoder
type blit_encoder
type heap
type residency_set
type fence
type event
type timestamps
type dynamic_library
type archive
type upscaler

(** Geometry for bottom-level structures. A keyframe list holds one entry for
    a static structure and exactly the structure's motion keyframes otherwise.
    Bounding boxes are 24-byte min/max float triples that an intersection
    function resolves; curves are float3 control points with float radii and
    uint32 segment indices. *)
type keyframe = { buffer:buffer; offset:int64 }
type curve_type = Round_curve | Flat_curve
type curve_basis = Bspline | Catmull_rom | Linear_basis | Bezier
type curve_caps = No_caps | Disk_caps | Sphere_caps
type geometry_options = { opaque:bool; duplicate_intersection:bool; table_offset:int }
val default_geometry_options : geometry_options
type geometry =
  | Triangles of { vertices:buffer; offset:int64; length:int64; vertex_stride:int; vertex_count:int }
  | Motion_triangles of { keyframes:keyframe list; vertex_stride:int; vertex_count:int }
  | Bounding_boxes of { boxes:keyframe list; stride:int; count:int; options:geometry_options }
  | Curves of { control_points:keyframe list; control_stride:int; control_point_count:int
              ; radii:keyframe list; radius_stride:int; indices:buffer; index_offset:int64
              ; segment_count:int; control_points_per_segment:int
              ; curve_type:curve_type; basis:curve_basis; caps:curve_caps }
type border = Clamp | Vanish
type motion = { keyframes:int; start_time:float; end_time:float; start_border:border; end_border:border }

(** [Tlas] packs default instance records; [Tlas_of] selects the record kind
    (user ids, or motion instances whose [motion_transforms] buffer holds packed
    4x3 keyframe transforms). [Sized] allocates an empty structure of [size]
    bytes shaped like [template], to be filled by [copy_accel] or
    [compact_accel]. *)
type accel_descriptor =
  | Blas of { geometries:geometry list; allow_refit:bool }
  | Motion_blas of { geometries:geometry list; motion:motion; allow_refit:bool }
  | Tlas of { instances:buffer; offset:int64; instance_count:int; structures:accel list; allow_refit:bool }
  | Tlas_of of { instances:buffer; offset:int64; instance_count:int; kind:instance_kind
               ; structures:accel list; allow_refit:bool; motion_transforms:(buffer * int64 * int) option }
  | Sized of { size:int64; template:accel }
type instance_record = { instance:instance; user_id:int; table_offset:int }
type motion_instance =
  { record:instance_record; transforms_start:int; transforms_count:int
  ; start_time:float; end_time:float; start_border:border; end_border:border }
type function_table

val buffer_memory : buffer -> Types.memory
val buffer_size : buffer -> int64

(** [dynamic] libraries resolve the shader's unresolved symbols and are
    preloaded into every pipeline created from the library; needs
    [Caps.Dynamic_libraries]. *)
val create_library : ?dynamic:dynamic_library list -> device -> Shader.t -> (library,Error.t) result

(** Creates a compute pipeline for [entry] with optional function constants.
    [interface] is the entry point's exact binding set, checked against the
    driver's reflection. *)

(** [linked] names intersection or visible functions of the library that the
    pipeline's function tables may reference; it requires [Caps.Function_tables]. *)
val create_compute_pipeline_from : ?archives:archive list -> ?archive_only:bool -> library -> entry:string ->
  ?constants:(string * Shader.constant_value) list -> interface:Shader.binding list ->
  ?linked:string list -> unit -> (pipeline,Error.t) result
val create_intersection_table : pipeline -> capacity:int -> (function_table,Error.t) result
val create_visible_table : pipeline -> capacity:int -> (function_table,Error.t) result
val table_capacity : function_table -> int
val table_set_function : function_table -> index:int -> string -> (unit,Error.t) result
val table_set_buffer : function_table -> index:int -> ?offset:int64 -> buffer -> (unit,Error.t) result
val destroy_table : function_table -> (unit,Error.t) result
val destroy_library : library -> (unit,Error.t) result
val instance_stride : device -> int
val instance_stride_of : device -> instance_kind -> int
val pack_instances : device -> instance array -> (bytes,Error.t) result
val pack_instance_records : device -> instance_record array -> (bytes,Error.t) result
val pack_motion_instances : device -> motion_instance array -> (bytes,Error.t) result

(** Row-major 3×4 transforms packed into 48-byte keyframe records. *)
val pack_transforms : float array array -> (bytes,Error.t) result
val create_accel : device -> accel_descriptor -> (accel,Error.t) result
val accel_sizes : accel -> accel_sizes
val destroy_accel : accel -> (unit,Error.t) result
val begin_commands : queue -> (commands,Error.t) result

(** [timestamps] samples GPU time into [(timestamps, start, finish)] at the
    encoder's stage boundaries; needs [Caps.Timestamp_queries]. *)
val compute_encoder : ?timestamps:timestamps * int * int -> commands -> (compute_encoder,Error.t) result
val set_pipeline : compute_encoder -> pipeline -> (unit,Error.t) result
val set_buffer : compute_encoder -> index:int -> ?offset:int64 -> buffer -> (unit,Error.t) result
val set_bytes : compute_encoder -> index:int -> bytes -> (unit,Error.t) result
val set_texture : compute_encoder -> index:int -> texture -> (unit,Error.t) result
val set_accel : compute_encoder -> index:int -> accel -> (unit,Error.t) result
val set_table : compute_encoder -> index:int -> function_table -> (unit,Error.t) result
val dispatch_threads : compute_encoder -> threads:int * int * int -> threadgroup:int * int * int -> (unit,Error.t) result
val dispatch_threadgroups : compute_encoder -> threadgroups:int * int * int -> threadgroup:int * int * int -> (unit,Error.t) result
val end_compute : compute_encoder -> (unit,Error.t) result
val accel_encoder : commands -> (accel_encoder,Error.t) result
val build_accel : accel_encoder -> accel -> scratch:buffer -> ?scratch_offset:int64 -> unit -> (unit,Error.t) result
val refit_accel : accel_encoder -> accel -> scratch:buffer -> ?scratch_offset:int64 -> unit -> (unit,Error.t) result

(** [copy_accel] fills a built-or-sized destination with a copy; [compact_accel]
    fills a [Sized] destination (sized from [write_compacted_size]'s uint64) with
    the compacted source. *)
val copy_accel : accel_encoder -> src:accel -> dst:accel -> (unit,Error.t) result
val compact_accel : accel_encoder -> src:accel -> dst:accel -> (unit,Error.t) result
val write_compacted_size : accel_encoder -> accel -> dst:buffer -> ?offset:int64 -> unit -> (unit,Error.t) result
val end_accel : accel_encoder -> (unit,Error.t) result
val blit_encoder : ?timestamps:timestamps * int * int -> commands -> (blit_encoder,Error.t) result
val copy_buffer : blit_encoder -> src:buffer -> ?src_offset:int64 -> dst:buffer -> ?dst_offset:int64 -> length:int64 -> unit -> (unit,Error.t) result
val end_blit : blit_encoder -> (unit,Error.t) result
val commit : commands -> (receipt,Error.t) result
val abandon : commands -> (unit,Error.t) result

(** GPU execution time of a completed receipt when the driver reports one. *)
val gpu_duration : queue -> receipt -> float option
val gpu_timing : queue -> gpu_timing

(** {1 Render path}

    Samplers, portable render pipelines, argument buffers, indirect command
    buffers, and the render encoder recorded into [commands]. *)
type sampler
type icb
type argument
type render_encoder
type color_attachment = { texture:texture; resolve:texture option; load:Render_pass.load; store:Render_pass.store; clear:float * float * float * float }
type depth_attachment = { depth_texture:texture; depth_load:Render_pass.load; depth_store:Render_pass.store; depth_clear:float }
type stencil_attachment = { stencil_texture:texture; stencil_load:Render_pass.load; stencil_store:Render_pass.store; stencil_clear:int }
type render_target = { colors:color_attachment list; depth:depth_attachment option; stencil:stencil_attachment option }
type batch_draw =
  { pipeline:pipeline; buffers:(shader_stage * int * buffer * int64) list; primitive:Render_pass.primitive
  ; index:(Render_pass.index_type * buffer * int64 * int64) option; vertex_start:int; vertex_count:int; instances:int }

val create_sampler : device -> Types.sampler_descriptor -> (sampler,Error.t) result
val sampler_descriptor : sampler -> Types.sampler_descriptor
val sampler_id : sampler -> int64
val destroy_sampler : sampler -> (unit,Error.t) result
val create_render_pipeline : ?blend:Pipeline.blend -> ?topology:Render_pass.primitive -> ?indirect:bool -> ?archives:archive list -> ?archive_only:bool ->
  device -> Pipeline.render_descriptor -> (pipeline,Error.t) result
val pipeline_indirect : pipeline -> bool
val create_icb : device -> max_commands:int -> (icb,Error.t) result
val icb_capacity : icb -> int
val icb_reset : icb -> location:int -> length:int -> (unit,Error.t) result
val icb_set_pipeline : icb -> index:int -> pipeline -> (unit,Error.t) result
val icb_set_buffer : icb -> index:int -> shader_stage -> slot:int -> ?offset:int64 -> buffer -> (unit,Error.t) result
val icb_draw : icb -> index:int -> primitive:Render_pass.primitive -> first:int -> count:int -> ?instances:int -> unit -> (unit,Error.t) result
val icb_draw_indexed : icb -> index:int -> primitive:Render_pass.primitive -> index_type:Render_pass.index_type -> buffer -> offset:int64 -> count:int64 -> ?instances:int -> unit -> (unit,Error.t) result
val destroy_icb : icb -> (unit,Error.t) result
val create_argument : pipeline -> shader_stage -> index:int -> (argument,Error.t) result
val argument_length : argument -> int
val argument_alignment : argument -> int
val argument_texture : argument -> buffer -> offset:int64 -> slot:int -> texture -> (unit,Error.t) result
val argument_sampler : argument -> buffer -> offset:int64 -> slot:int -> sampler -> (unit,Error.t) result
val destroy_argument : argument -> (unit,Error.t) result
val render_encoder : ?timestamps:timestamps * int * int -> commands -> render_target -> (render_encoder,Error.t) result
val set_render_pipeline : render_encoder -> pipeline -> (unit,Error.t) result
val set_stage_buffer : render_encoder -> shader_stage -> index:int -> ?offset:int64 -> buffer -> (unit,Error.t) result
val set_stage_bytes : render_encoder -> shader_stage -> index:int -> bytes -> (unit,Error.t) result
val set_stage_texture : render_encoder -> shader_stage -> index:int -> texture -> (unit,Error.t) result
val set_stage_sampler : render_encoder -> shader_stage -> index:int -> sampler -> (unit,Error.t) result
val set_viewport : render_encoder -> Render_pass.rect -> (unit,Error.t) result
val set_scissor : render_encoder -> Render_pass.rect -> (unit,Error.t) result
val set_cull : render_encoder -> Render_pass.cull -> (unit,Error.t) result
val set_winding : render_encoder -> winding -> (unit,Error.t) result
val set_depth_state : render_encoder -> depth_state option -> (unit,Error.t) result
val set_stencil_reference : render_encoder -> front:int32 -> back:int32 -> (unit,Error.t) result
val draw : render_encoder -> primitive:Render_pass.primitive -> first:int -> count:int -> ?instances:int -> unit -> (unit,Error.t) result
val draw_indexed : render_encoder -> primitive:Render_pass.primitive -> index_type:Render_pass.index_type -> buffer -> offset:int64 -> count:int64 -> ?instances:int -> unit -> (unit,Error.t) result

(** Validates every draw once and hands the whole batch to the driver, which
    may execute it in one native call. *)
val draw_batch : render_encoder -> batch_draw array -> (unit,Error.t) result
val use_resources : render_encoder -> [ `Buffer of buffer | `Texture of texture ] list -> (unit,Error.t) result

(** Executes recorded indirect commands. A render pipeline must be set on the
    encoder first, as Metal validation requires. *)
val execute_icb : render_encoder -> icb -> location:int -> length:int -> (unit,Error.t) result
val end_render : render_encoder -> (unit,Error.t) result
val copy_texture : blit_encoder -> src:texture -> ?src_mip:int -> ?src_origin:Types.origin -> dst:texture -> ?dst_mip:int -> ?dst_origin:Types.origin -> extent:Types.extent -> unit -> (unit,Error.t) result
val buffer_to_texture : blit_encoder -> src:buffer -> ?offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> dst:texture -> ?mip:int -> ?origin:Types.origin -> extent:Types.extent -> unit -> (unit,Error.t) result
val texture_to_buffer : blit_encoder -> src:texture -> ?mip:int -> ?origin:Types.origin -> extent:Types.extent -> dst:buffer -> ?offset:int64 -> bytes_per_row:int64 -> bytes_per_image:int64 -> unit -> (unit,Error.t) result
val fill_buffer : blit_encoder -> buffer -> ?offset:int64 -> length:int64 -> value:int -> unit -> (unit,Error.t) result

(** Commits the recorded commands and presents [source] into the acquired
    frame with the same command buffer; the frame is consumed on success. *)
val commit_present : commands -> source:texture -> frame -> (receipt,Error.t) result

(** {1 Heaps, residency sets, fences, events, and timestamps (plan G6)}

    Each feature is gated by [Caps]; without it every entry point returns a
    typed [Unsupported] error. *)

(** A placement heap of [size] bytes in one memory class. Buffers and textures
    created from it at explicit offsets may alias; with [tracked = false] the
    driver does not track hazards between them and fences order their use.
    The heap outlives its resources: destroying it while any lives is
    [Invalid_state]. *)
val create_heap : device -> ?memory:Types.memory -> ?tracked:bool -> ?sparse:bool -> ?label:string -> size:int64 -> unit -> (heap,Error.t) result
val heap_size : heap -> int64

(** Size and alignment a resource needs inside a heap of this device. *)
val buffer_placement : device -> ?memory:Types.memory -> int64 -> (placement,Error.t) result
val texture_placement : device -> Types.texture_descriptor -> (placement,Error.t) result
val create_heap_buffer : heap -> offset:int64 -> Types.buffer_descriptor -> (buffer,Error.t) result
val create_heap_texture : heap -> offset:int64 -> Types.texture_descriptor -> (texture,Error.t) result
val destroy_heap : heap -> (unit,Error.t) result

(** Marks a heap resource's memory reusable: a later placement may overlap
    it and its own contents become undefined. Overlapping a resource that is
    not aliasable is rejected. *)
val make_aliasable : heap -> [ `Buffer of buffer | `Texture of texture ] -> (unit,Error.t) result
val compute_use_heap : compute_encoder -> heap -> (unit,Error.t) result
val render_use_heap : render_encoder -> heap -> (unit,Error.t) result

(** A residency set makes its allocations resident for every command buffer
    of the queues it is attached to (or for one [commands] value). Changes
    take effect at [residency_commit]. *)
type residency_allocation = [ `Buffer of buffer | `Texture of texture | `Heap of heap ]
val create_residency_set : device -> ?capacity:int -> ?label:string -> unit -> (residency_set,Error.t) result
val residency_add : residency_set -> residency_allocation -> (unit,Error.t) result
val residency_remove : residency_set -> residency_allocation -> (unit,Error.t) result
val residency_commit : residency_set -> (unit,Error.t) result
val residency_size : residency_set -> (int64,Error.t) result
val queue_add_residency : queue -> residency_set -> (unit,Error.t) result
val queue_remove_residency : queue -> residency_set -> (unit,Error.t) result
val use_residency : commands -> residency_set -> (unit,Error.t) result
val destroy_residency_set : residency_set -> (unit,Error.t) result

(** Intra-queue fences: an encoder updates a fence when its work completes
    and a later encoder on the same queue waits for it before starting. *)
type fence_encoder = [ `Compute of compute_encoder | `Blit of blit_encoder | `Render of render_encoder ]
val create_fence : device -> (fence,Error.t) result
val update_fence : fence_encoder -> fence -> (unit,Error.t) result
val wait_fence : fence_encoder -> fence -> (unit,Error.t) result
val destroy_fence : fence -> (unit,Error.t) result

(** Timeline events for CPU/GPU and cross-queue synchronization. Values only
    grow. [signal_event] sets the value from the host; [wait_event] blocks
    the host until the value is reached or the timeout elapses ([Ok false]).
    [commands_signal_event] signals when every earlier encoder of the command
    buffer completes; [commands_wait_event] holds later encoders until the
    value is reached. Both are recorded between encoders. *)
val create_event : device -> (event,Error.t) result
val event_value : event -> (int64,Error.t) result
val signal_event : event -> int64 -> (unit,Error.t) result
val wait_event : event -> value:int64 -> timeout_ms:int -> (bool,Error.t) result
val commands_signal_event : commands -> event -> int64 -> (unit,Error.t) result
val commands_wait_event : commands -> event -> int64 -> (unit,Error.t) result
val destroy_event : event -> (unit,Error.t) result

(** [count] GPU timestamp slots. Encoders sample into them at their stage
    boundaries; [resolve_timestamps] writes [count] 8-byte GPU timestamps
    into a buffer on the GPU and [read_timestamps] reads them on the host
    after completion. [timestamp_reference] pairs a CPU time in nanoseconds
    with the GPU timestamp taken at the same instant and the GPU tick rate. *)
val create_timestamps : device -> count:int -> (timestamps,Error.t) result
val timestamps_count : timestamps -> int
val resolve_timestamps : blit_encoder -> timestamps -> ?first:int -> count:int -> dst:buffer -> ?offset:int64 -> unit -> (unit,Error.t) result
val read_timestamps : timestamps -> ?first:int -> count:int -> unit -> (int64 array,Error.t) result
val timestamp_reference : device -> (timestamp_reference,Error.t) result
val destroy_timestamps : timestamps -> (unit,Error.t) result

(** {1 Mesh and tile pipelines, dynamic libraries, binary archives, sparse
    textures, and upscaling (plan G7)}

    Each feature is gated by [Caps]; without it every entry point returns a
    typed [Unsupported] error. *)

(** A mesh pipeline draws threadgroups: an optional object stage, a mesh
    stage, and a fragment stage from one library. Threadgroup sizes are the
    compiled required sizes and every [draw_mesh] must use them. *)
type mesh_descriptor =
  { mesh_label:string option; mesh_library:library; object_entry:string option; mesh_entry:string
  ; mesh_fragment_entry:string; mesh_color_format:Pipeline.color_format
  ; mesh_threadgroup:int * int * int; object_threadgroup:(int * int * int) option }
val create_mesh_pipeline : ?blend:Pipeline.blend -> ?archives:archive list -> ?archive_only:bool -> device -> mesh_descriptor -> (pipeline,Error.t) result
val draw_mesh : render_encoder -> threadgroups:int * int * int -> ?object_threadgroup:int * int * int -> mesh_threadgroup:int * int * int -> unit -> (unit,Error.t) result

(** A tile pipeline runs a kernel over every tile of the current render pass
    with access to the imageblock; [tile_threadgroup] is its compiled
    required size and every [dispatch_tile] must use it. *)
type tile_descriptor =
  { tile_label:string option; tile_library:library; tile_entry:string
  ; tile_color_format:Pipeline.color_format; tile_threadgroup:int * int * int }
val create_tile_pipeline : ?archives:archive list -> ?archive_only:bool -> device -> tile_descriptor -> (pipeline,Error.t) result
val dispatch_tile : render_encoder -> threads:int * int * int -> (unit,Error.t) result
val tile_size : render_encoder -> (int * int,Error.t) result

(** A dynamic library compiled from MSL with an install name; executable
    libraries created with [create_library ~dynamic] link against it. *)
val create_dynamic_library : device -> install_name:string -> Shader.t -> (dynamic_library,Error.t) result
val destroy_dynamic_library : dynamic_library -> (unit,Error.t) result

(** A binary archive of compiled compute, mesh, and tile pipelines. Without
    [path] it starts empty; with an absolute [path] it loads a serialized one.
    [archive_add] records a pipeline's compiled functions; pipelines created
    with [~archives] look them up first, and with [~archive_only:true] fail
    instead of compiling on a miss. *)
val create_archive : ?path:string -> device -> unit -> (archive,Error.t) result
val archive_add : archive -> pipeline -> (unit,Error.t) result
val archive_serialize : archive -> string -> (unit,Error.t) result
val destroy_archive : archive -> (unit,Error.t) result

(** Sparse textures live in a sparse heap ([create_heap ~sparse:true], which
    accepts no buffers or placed textures) and start with no tiles mapped.
    [texture_tile] is the tile size in texels; [map_tiles] maps or unmaps a
    rectangle of tiles ((x, y, width, height) in tiles) of one mip level
    between encoders. Unmapped tiles read as zero and drop writes. *)
val create_sparse_texture : heap -> Types.texture_descriptor -> (texture,Error.t) result
val texture_tile : texture -> (int * int,Error.t) result
val map_tiles : commands -> texture -> ?mip:int -> region:int * int * int * int -> map:bool -> unit -> (unit,Error.t) result

(** Spatial upscaling behind [Caps.Metal_fx]: [upscale] encodes the scale of
    a whole [src] (input size, texture-binding usage) into [dst] (output
    size, texture-binding plus render-attachment usage) between encoders. *)
val create_upscaler : device -> input:int * int -> output:int * int -> (upscaler,Error.t) result
val upscale : commands -> upscaler -> src:texture -> dst:texture -> (unit,Error.t) result
val destroy_upscaler : upscaler -> (unit,Error.t) result
