include Metal_raw_types
module Registry = (Metal_gen.Make)(Metal_raw_types)
include Registry
let get = function | Ok value -> value | Error message -> failwith message
[@@@ocaml.text
  " Positional native ABI record. Keep field order synchronized with\n    [texture_descriptor] in [metal_bridge.mm]. "]
[@@@ocaml.text
  " Positional native ABI record for texture-view construction. "]
[@@@ocaml.text
  " Positional native ABI value for one function-constant specialization. "]
[@@@ocaml.text " Name, Metal data-type code, index, and required flag. "]
[@@@ocaml.text
  " Positional native ABI value for one reflected pipeline binding. Keep this\n    synchronized with [copy_bindings] in [metal_bridge.mm]. "]
[@@@ocaml.text
  " Library handle and function name used by Metal 4 static linking. "]
[@@@ocaml.text
  " Positional native ABI record for synchronous Metal 4 compute compilation. "]
[@@@ocaml.text
  " Positional native ABI record for one base-level Metal 4 render-pass color\n    attachment and its optional single-sample resolve target. "]
[@@@ocaml.text
  " Positional native ABI record for one base-level Metal 4 render-pass depth\n    attachment. "]
[@@@ocaml.text
  " Positional native ABI record for one base-level Metal 4 render-pass stencil\n    attachment. "]
[@@@ocaml.text " Positional native ABI record for a Metal 4 render pass. "]
[@@@ocaml.text
  " Positional native ABI record for one amplified vertex view. "]
[@@@ocaml.text
  " Positional native ABI record for one Metal scissor rectangle. "]
[@@@ocaml.text
  " Positional native ABI record for one immutable stencil face. "]
[@@@ocaml.text
  " Positional native ABI record for immutable depth/stencil state. "]
[@@@ocaml.text
  " Positional native ABI record for a Metal 4 argument-table descriptor. "]
[@@@ocaml.text
  " Positional native ABI record for a Metal 4 binary-function lookup or\n    compilation. "]
[@@@ocaml.text
  " Resource100 generated raw integration. Internal handles only. "]
[@@@ocaml.text
  " Mesh/tile105 owned descriptor inputs. Field order is the native positional\n    ABI consumed by [prismel_mesh_tile_objects_from_value]. "]
[@@@ocaml.text " Counter and blit-pass bindings. "]
[@@@ocaml.text
  " Authoritative Metal4 lifecycle190 prepared CAML subset. The resource and\n    compute-owner shards currently contain typed native helpers only, not OCaml\n    primitives, so they are intentionally absent here. "]
let buffer_info raw =
  ((get (Registry.buffer_info_length raw)),
    (Int64.to_int (get (Registry.buffer_info_storageMode raw))),
    (Int64.to_int (get (Registry.buffer_info_cpuCacheMode raw))),
    (Int64.to_int (get (Registry.buffer_info_hazardTrackingMode raw))),
    (get (Registry.buffer_info_heapOffset raw)))
let buffer_set_label = Registry.set_buffer_label
let heap_info raw =
  [|(get (Registry.heap_info_size raw));(get
                                           (Registry.heap_info_usedSize raw));(
    get (Registry.heap_info_currentAllocatedSize raw));(get
                                                          (Registry.heap_info_storageMode
                                                             raw));(get
                                                                    (Registry.heap_info_cpuCacheMode
                                                                    raw));(
    get (Registry.heap_info_hazardTrackingMode raw));(get
                                                        (Registry.heap_info_type
                                                           raw))|]
let heap_max_available_size raw alignment =
  if alignment < 0L then invalid_arg "heap alignment must be nonnegative";
  get (Registry.heap_max_available_size raw alignment)
let texture_is_shareable raw = get (Registry.texture_is_shareable raw)
let indirect_render_command = Registry.indirect_render_command
let indirect_render_command_set_pipeline =
  Registry.indirect_render_command_set_pipeline
let library_kind raw = Int64.to_int (get (Registry.library_kind raw))
let function_name raw = get (Registry.function_name raw)
let function_kind raw = Int64.to_int (get (Registry.function_kind raw))
let dynamic_library_install_name raw =
  get (Registry.dynamic_library_install_name raw)
let compute_pipeline_create = Registry.compute_pipeline_create
let compute_pipeline_max_total_threads raw =
  Int64.to_int (get (Registry.compute_pipeline_max_total_threads raw))
let acceleration_encoder_copy = Registry.acceleration_encoder_copy
let acceleration_encoder_copy_and_compact =
  Registry.acceleration_encoder_copy_and_compact
let compute_pipeline_function_handle =
  Registry.compute_pipeline_function_handle
let visible_function_table_set_function =
  Registry.visible_function_table_set_function
let intersection_function_table_set_function =
  Registry.intersection_function_table_set_function
let intersection_function_table_set_buffer =
  Registry.intersection_function_table_set_buffer
let layer_next_drawable = Registry.layer_next_drawable
let compute_encoder_set_pipeline = Registry.compute_encoder_set_pipeline
let compute_encoder_set_buffer = Registry.compute_encoder_set_buffer
let compute_encoder_set_texture = Registry.compute_encoder_set_texture
let compute_encoder_dispatch = Registry.compute_encoder_dispatch
let compute35_acceleration = Registry.compute35_acceleration
let compute35_visible = Registry.compute35_visible
let compute35_intersection = Registry.compute35_intersection
let compute35_dispatch_groups = Registry.compute35_dispatch_groups
let compute35_update_fence = Registry.compute35_update_fence
let compute35_wait_fence = Registry.compute35_wait_fence
let counter_sample_buffer_create = Registry.counter_sample_buffer_create
let blit_pass_attachments = Registry.blit_pass_attachments
let shader_function_argument_encoder raw index =
  if index < 0L
  then Error "argument buffer index must be non-negative"
  else Registry.shader_function_argument_encoder raw index
let command_shared_event_value = Registry.command_shared_event_value
let command_shared_event_set_value = Registry.set_command_shared_event_value
let device_timestamp_frequency = Registry.device_timestamp_frequency
let ( let* ) = Result.bind
let buffer_create device length options =
  if length <= 0L
  then Error "buffer length must be positive"
  else
    if
      ((options land (lnot 0x3ff)) <> 0) ||
        (((options land 0xf) > 1) ||
           ((((options lsr 4) land 0xf) > 2) ||
              (((options lsr 8) land 3) > 2)))
    then invalid_arg "invalid Metal resource options"
    else Registry.buffer_create device length (Int64.of_int options)
let indirect_render_command_draw_primitives raw primitive start count
  instances base =
  if (start < 0L) || ((count < 0L) || ((instances < 0L) || (base < 0L)))
  then Error "invalid indirect draw range"
  else
    Registry.indirect_render_command_draw_primitives raw
      (Int64.of_int primitive) start count instances base
let acceleration_structure_create = Registry.acceleration_structure_create
let command_buffer_present_drawable raw drawable mode time =
  match mode with
  | 0 -> Registry.command_buffer_present raw drawable
  | 1 -> Registry.command_buffer_present_at_time raw drawable time
  | 2 -> Registry.command_buffer_present_after_duration raw drawable time
  | _ -> Error "invalid presentation mode"
let render_pass_descriptor_create = Registry.render_pass_descriptor_create
let pipeline_render_indirect =
  Registry.render_pipeline_state_support_indirect_command_buffers
let counter_descriptor_create = Registry.counter_descriptor_create
let blit_pass_create = Registry.blit_pass_create
let blit_fence raw fence update =
  if update
  then Registry.blit_update_fence raw fence
  else Registry.blit_wait_fence raw fence
let compute_pass_snapshot raw =
  let* dispatchType = Registry.compute_pass_snapshot_dispatchType raw
   in
  let* sampleBufferAttachments =
    Registry.compute_pass_snapshot_sampleBufferAttachments raw
   in Ok ((Int64.to_int dispatchType), sampleBufferAttachments)
let compute_pass_attachment_snapshot raw =
  let* sampleBuffer =
    Registry.compute_pass_attachment_snapshot_sampleBuffer raw
   in
  let* startOfEncoderSampleIndex =
    Registry.compute_pass_attachment_snapshot_startOfEncoderSampleIndex raw
   in
  let* endOfEncoderSampleIndex =
    Registry.compute_pass_attachment_snapshot_endOfEncoderSampleIndex raw
   in Ok (sampleBuffer, startOfEncoderSampleIndex, endOfEncoderSampleIndex)
let blit_pass10_attachment_at raw index =
  if index < 0L
  then Error "blit attachment index is negative"
  else Registry.blit_pass10_attachment_at raw index
let drawable10_snapshot raw =
  let* drawableID = Registry.drawable10_snapshot_drawableID raw
   in
  let* presentedTime = Registry.drawable10_snapshot_presentedTime raw
   in Ok (drawableID, presentedTime)
let indirect_render_command_set_vertex_buffer raw buffer offset index =
  if (offset < 0L) || (index < 0)
  then Error "invalid indirect buffer binding"
  else
    Registry.indirect_render_command_set_vertex_buffer raw buffer offset
      index
let indirect_render_command_set_fragment_buffer raw buffer offset index =
  if (offset < 0L) || (index < 0)
  then Error "invalid indirect buffer binding"
  else
    Registry.indirect_render_command_set_fragment_buffer raw buffer offset
      index
let counter_supports_sampling raw point =
  match point with
  | 0 | 1 | 2 -> Registry.counter_supports_sampling raw (Int64.of_int point)
  | 3 -> Registry.counter_supports_sampling raw 4L
  | _ -> Error "unknown counter sampling point"
let fx_spatial_supported = Registry.fx_spatial_supported
