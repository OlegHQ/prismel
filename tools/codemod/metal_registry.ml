(* One-shot, AST-based migration of the legacy raw ABI. Native exceptions are
   registered too; their custom C++ implementation is deliberately retained. *)
open Parsetree

let read path = In_channel.with_open_bin path In_channel.input_all
let write path body =
  let body = Str.global_replace (Str.regexp "[ \t]+$") "" body in
  let body = String.trim body ^ "\n" in
  Out_channel.with_open_bin path (fun out -> output_string out body)
let parse text = Parse.implementation (Lexing.from_string text)
type recipe = { name : string; entries : string list; adapter : string }

let method_ ?(since = "None") ?(error = false) name recv objc feature sel args ret adapter =
  { name; adapter; entries = [ Printf.sprintf
      "Method { recv = %S; objc = %S; sel = %S; args = [ %s ]; ret = %s; error = %b; pool = true; ocaml = %S; since = %s; feature = C.%s }"
      recv objc sel args ret error name since feature ] }

let property ?(since = "None") name recv objc feature field ty access binding adapter =
  { name; adapter; entries = [ Printf.sprintf
      "Property { recv = %S; objc = %S; name = %S; ty = %s; access = %s; ocaml = %S; since = %s; feature = C.%s }"
      recv objc field ty access binding since feature ] }

let alias name = "let " ^ name ^ " = Registry." ^ name
let get name = "let " ^ name ^ " raw = get (Registry." ^ name ^ " raw)"
let int_get name = "let " ^ name ^ " raw = Int64.to_int (get (Registry." ^ name ^ " raw))"

let recipes =
  [ property "buffer_set_label" "Buffer" "id<MTLBuffer>" "Buffer" "label" "Str" "Set" "buffer_label"
      "let buffer_set_label = Registry.set_buffer_label"
  ; property "texture_is_shareable" "Texture" "id<MTLTexture>" "Texture" "shareable" "Scalar Bool" "Get" "texture_is_shareable" (get "texture_is_shareable")
  ; property "library_kind" "Library" "id<MTLLibrary>" "Compute_pipeline" "type" "Enum_of \"MTLLibraryType\"" "Get" "library_kind" (int_get "library_kind")
  ; property "function_name" "Function" "id<MTLFunction>" "Compute_pipeline" "name" "Str" "Get" "function_name" (get "function_name")
  ; property "function_kind" "Function" "id<MTLFunction>" "Compute_pipeline" "functionType" "Enum_of \"MTLFunctionType\"" "Get" "function_kind" (int_get "function_kind")
  ; property "dynamic_library_install_name" "Dynamic_library" "id<MTLDynamicLibrary>" "Dynamic_libraries" "installName" "Str" "Get" "dynamic_library_install_name" (get "dynamic_library_install_name")
  ; property "compute_pipeline_max_total_threads" "Compute_pipeline" "id<MTLComputePipelineState>" "Compute_pipeline" "maxTotalThreadsPerThreadgroup" "Scalar Nsuint" "Get" "compute_pipeline_max_total_threads" (int_get "compute_pipeline_max_total_threads")
  ; property "command_shared_event_value" "Shared_event" "id<MTLSharedEvent>" "Event_synchronization" "signaledValue" "Scalar Nsuint" "Get_set" "command_shared_event_value" (alias "command_shared_event_value")
  ; { name = "command_shared_event_set_value"; entries = [];
      adapter = "let command_shared_event_set_value = Registry.set_command_shared_event_value" }
  ; property "blit_pass_attachments" "Blit_pass_descriptor" "MTLBlitPassDescriptor *" "Timestamp_queries" "sampleBufferAttachments" "Obj \"Blit_sample_attachment_array\"" "Get" "blit_pass_attachments" (alias "blit_pass_attachments")
  ; method_ "compute_pipeline_create" "Device" "id<MTLDevice>" "Compute_pipeline" "newComputePipelineStateWithFunction:error:" "Obj \"Function\"" "Some (Obj \"Compute_pipeline\")" ~error:true (alias "compute_pipeline_create")
  ; method_ "compute_pipeline_function_handle" "Compute_pipeline" "id<MTLComputePipelineState>" "Function_tables" "functionHandleWithFunction:" "Obj \"Function\"" "Some (Obj \"Function_handle\")" (alias "compute_pipeline_function_handle")
  ; method_ "counter_sample_buffer_create" "Device" "id<MTLDevice>" "Timestamp_queries" "newCounterSampleBufferWithDescriptor:error:" "Obj \"Counter_descriptor\"" "Some (Obj \"Counter_sample_buffer\")" ~error:true (alias "counter_sample_buffer_create")
  ; method_ "shader_function_argument_encoder" "Function" "id<MTLFunction>" "Compute_pipeline" "newArgumentEncoderWithBufferIndex:" "Scalar Nsuint" "Some (Obj \"Shader_argument_encoder\")"
      "let shader_function_argument_encoder raw index = if index < 0L then Error \"argument buffer index must be non-negative\" else Registry.shader_function_argument_encoder raw index"
  ; method_ "layer_next_drawable" "Metal_layer" "CAMetalLayer *" "Surface" "nextDrawable" "" "Some (Opt_obj \"Metal_drawable\")" (alias "layer_next_drawable")
  ; method_ ~since:"Some (26, 0)" "device_timestamp_frequency" "Device" "id<MTLDevice>" "Timestamp_queries" "queryTimestampFrequency" "" "Some (Scalar Nsuint)" (alias "device_timestamp_frequency")
  ; method_ "compute_encoder_set_pipeline" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Compute_pipeline" "setComputePipelineState:" "Obj \"Compute_pipeline\"" "None" (alias "compute_encoder_set_pipeline")
  ; method_ "compute_encoder_set_buffer" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Compute_pipeline" "setBuffer:offset:atIndex:" "Obj \"Buffer\"; Scalar Nsuint; Scalar Nsuint" "None"
      "let compute_encoder_set_buffer raw buffer offset index = if offset < 0L || index < 0 then Error \"compute buffer binding is out of range\" else match Registry.buffer_length buffer with Error _ as e -> e | Ok length -> if offset > length then Error \"compute buffer binding is out of range\" else Registry.compute_encoder_set_buffer raw buffer offset (Int64.of_int index)"
  ; property "buffer_info" "Buffer" "id<MTLBuffer>" "Buffer" "length" "Scalar Nsuint" "Get" "buffer_length" ""
  ; method_ "compute_encoder_set_texture" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Compute_pipeline" "setTexture:atIndex:" "Obj \"Texture\"; Scalar Nsuint" "None"
      "let compute_encoder_set_texture raw texture index = if index < 0 then Error \"compute texture index is negative\" else Registry.compute_encoder_set_texture raw texture (Int64.of_int index)"
  ; method_ "compute35_acceleration" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Ray_tracing" "setAccelerationStructure:atBufferIndex:" "Opt_obj \"Acceleration_structure\"; Scalar Nsuint" "None" (alias "compute35_acceleration")
  ; method_ "compute35_visible" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Function_tables" "setVisibleFunctionTable:atBufferIndex:" "Opt_obj \"Visible_function_table\"; Scalar Nsuint" "None" (alias "compute35_visible")
  ; method_ "compute35_intersection" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Function_tables" "setIntersectionFunctionTable:atBufferIndex:" "Opt_obj \"Intersection_function_table\"; Scalar Nsuint" "None" (alias "compute35_intersection")
  ; method_ "compute35_update_fence" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Fences" "updateFence:" "Obj \"Fence\"" "None" (alias "compute35_update_fence")
  ; method_ "compute35_wait_fence" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Fences" "waitForFence:" "Obj \"Fence\"" "None" (alias "compute35_wait_fence")
  ; method_ "visible_function_table_set_function" "Visible_function_table" "id<MTLVisibleFunctionTable>" "Function_tables" "setFunction:atIndex:" "Opt_obj \"Function_handle\"; Scalar Nsuint" "None"
      "let visible_function_table_set_function raw fn index = Registry.visible_function_table_set_function raw fn (Int64.of_int index)"
  ; method_ "intersection_function_table_set_function" "Intersection_function_table" "id<MTLIntersectionFunctionTable>" "Function_tables" "setFunction:atIndex:" "Opt_obj \"Function_handle\"; Scalar Nsuint" "None"
      "let intersection_function_table_set_function raw fn index = Registry.intersection_function_table_set_function raw fn (Int64.of_int index)"
  ; method_ "intersection_function_table_set_buffer" "Intersection_function_table" "id<MTLIntersectionFunctionTable>" "Function_tables" "setBuffer:offset:atIndex:" "Opt_obj \"Buffer\"; Scalar Nsuint; Scalar Nsuint" "None"
      "let intersection_function_table_set_buffer raw buffer offset index = Registry.intersection_function_table_set_buffer raw buffer offset (Int64.of_int index)"
  ; method_ "acceleration_encoder_copy" "Acceleration_encoder" "id<MTLAccelerationStructureCommandEncoder>" "Ray_tracing" "copyAccelerationStructure:toAccelerationStructure:" "Obj \"Acceleration_structure\"; Obj \"Acceleration_structure\"" "None" (alias "acceleration_encoder_copy")
  ; method_ "acceleration_encoder_copy_and_compact" "Acceleration_encoder" "id<MTLAccelerationStructureCommandEncoder>" "Ray_tracing" "copyAndCompactAccelerationStructure:toAccelerationStructure:" "Obj \"Acceleration_structure\"; Obj \"Acceleration_structure\"" "None" (alias "acceleration_encoder_copy_and_compact")
  ; method_ "heap_max_available_size" "Heap" "id<MTLHeap>" "Heaps" "maxAvailableSizeWithAlignment:" "Scalar Nsuint" "Some (Scalar Nsuint)"
      "let heap_max_available_size raw alignment = if alignment < 0L then invalid_arg \"heap alignment must be nonnegative\"; get (Registry.heap_max_available_size raw alignment)"
  ; method_ "indirect_render_command" "Indirect_command_buffer" "id<MTLIndirectCommandBuffer>" "Render_pipeline" "indirectRenderCommandAtIndex:" "Scalar Nsuint" "Some (Obj \"Indirect_render_command\")" (alias "indirect_render_command")
  ; method_ "indirect_render_command_set_pipeline" "Indirect_render_command" "id<MTLIndirectRenderCommand>" "Render_pipeline" "setRenderPipelineState:" "Obj \"Render_pipeline\"" "None" (alias "indirect_render_command_set_pipeline")
  ; method_ "compute_encoder_dispatch" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Compute_pipeline" "dispatchThreads:threadsPerThreadgroup:" "Rec \"Mtl_size\"; Rec \"Mtl_size\"" "None"
      "let compute_encoder_dispatch raw threads group = Registry.compute_encoder_dispatch raw (size threads) (size group)"
  ; method_ "compute35_dispatch_groups" "Compute_encoder" "id<MTLComputeCommandEncoder>" "Compute_pipeline" "dispatchThreadgroups:threadsPerThreadgroup:" "Rec \"Mtl_size\"; Rec \"Mtl_size\"" "None"
      "let compute35_dispatch_groups raw groups group = Registry.compute35_dispatch_groups raw (size groups) (size group)"
  ]

(* These legacy aggregate queries are assembled from generated properties.
   Their original tuple/array ABI remains intact for all existing callers. *)
let snapshot name recv objc feature fields array =
  let entries = List.map (fun (field, ty, _) ->
      let binding = name ^ "_" ^ field in
      (property name recv objc feature field ty "Get" binding "").entries |> List.hd) fields in
  let values = List.map (fun (field, _, as_int) ->
      (if as_int then "Int64.to_int " else "") ^ "(get (Registry." ^ name ^ "_" ^ field ^ " raw))") fields in
  let adapter = Printf.sprintf "let %s raw = %s%s%s" name
      (if array then "[| " else "(") (String.concat (if array then "; " else ", ") values)
      (if array then " |]" else ")") in
  { name; entries; adapter }

let recipes =
  List.filter (fun r -> r.name <> "buffer_info") recipes @
  [ snapshot "buffer_info" "Buffer" "id<MTLBuffer>" "Buffer"
      [ "length", "Scalar Nsuint", false; "storageMode", "Enum_of \"MTLStorageMode\"", true
      ; "cpuCacheMode", "Enum_of \"MTLCPUCacheMode\"", true
      ; "hazardTrackingMode", "Enum_of \"MTLHazardTrackingMode\"", true
      ; "heapOffset", "Scalar Nsuint", false ] false
  ; snapshot "heap_info" "Heap" "id<MTLHeap>" "Heaps"
      [ "size", "Scalar Nsuint", false; "usedSize", "Scalar Nsuint", false
      ; "currentAllocatedSize", "Scalar Nsuint", false
      ; "storageMode", "Enum_of \"MTLStorageMode\"", false
      ; "cpuCacheMode", "Enum_of \"MTLCPUCacheMode\"", false
      ; "hazardTrackingMode", "Enum_of \"MTLHazardTrackingMode\"", false
      ; "type", "Enum_of \"MTLHeapType\"", false ] true
  ]

let class_method name objc feature sel ret =
  { name; adapter = alias name; entries = [ Printf.sprintf
      "Class_method { objc = %S; sel = %S; args = []; ret = Some (Obj %S); ocaml = %S; since = None; feature = C.%s }"
      objc sel ret name feature ] }

let result_snapshot name recv objc feature fields =
  let recipe = snapshot name recv objc feature fields false in
  let reads = List.map (fun (field, _, _) ->
      "let* " ^ field ^ " = Registry." ^ name ^ "_" ^ field ^ " raw in ") fields in
  let values = List.map (fun (field, _, as_int) -> (if as_int then "Int64.to_int " else "") ^ field) fields in
  { recipe with adapter = "let " ^ name ^ " raw = " ^ String.concat "" reads ^ "Ok (" ^ String.concat ", " values ^ ")" }

let recipes = recipes @
  [ { name = "pipeline_render_indirect"; entries = []; adapter =
        "let pipeline_render_indirect = Registry.render_pipeline_state_support_indirect_command_buffers" }
  ; method_ "buffer_create" "Device" "id<MTLDevice>" "Buffer" "newBufferWithLength:options:" "Scalar Nsuint; Enum_of \"MTLResourceOptions\"" "Some (Obj \"Buffer\")"
      "let buffer_create device length options = if length <= 0L then Error \"buffer length must be positive\" else if options land (lnot 0x3ff) <> 0 || options land 0xf > 1 || (options lsr 4) land 0xf > 2 || (options lsr 8) land 3 > 2 then invalid_arg \"invalid Metal resource options\" else Registry.buffer_create device length (Int64.of_int options)"
  ; method_ "acceleration_structure_create" "Device" "id<MTLDevice>" "Ray_tracing" "newAccelerationStructureWithSize:" "Scalar Nsuint" "Some (Obj \"Acceleration_structure\")" (alias "acceleration_structure_create")
  ; class_method "render_pass_descriptor_create" "MTLRenderPassDescriptor" "Render_pipeline" "renderPassDescriptor" "Render_pass_descriptor"
  ; class_method "counter_descriptor_create" "MTLCounterSampleBufferDescriptor" "Timestamp_queries" "new" "Counter_descriptor"
  ; class_method "blit_pass_create" "MTLBlitPassDescriptor" "Timestamp_queries" "blitPassDescriptor" "Blit_pass_descriptor"
  ; result_snapshot "drawable10_snapshot" "Metal_drawable" "id<MTLDrawable>" "Surface"
      [ "drawableID", "Scalar Nsuint", false; "presentedTime", "Scalar Double", false ]
  ; result_snapshot "compute_pass_snapshot" "Compute_pass_descriptor" "MTLComputePassDescriptor *" "Compute_pipeline"
      [ "dispatchType", "Enum_of \"MTLDispatchType\"", true; "sampleBufferAttachments", "Obj \"Compute_sample_attachment_array\"", false ]
  ; result_snapshot "compute_pass_attachment_snapshot" "Compute_sample_attachment" "MTLComputePassSampleBufferAttachmentDescriptor *" "Timestamp_queries"
      [ "sampleBuffer", "Opt_obj \"Counter_sample_buffer\"", false
      ; "startOfEncoderSampleIndex", "Scalar Nsint", false; "endOfEncoderSampleIndex", "Scalar Nsint", false ]
  ; method_ "indirect_render_command_draw_primitives" "Indirect_render_command" "id<MTLIndirectRenderCommand>" "Render_pipeline" "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:" "Enum_of \"MTLPrimitiveType\"; Scalar Nsuint; Scalar Nsuint; Scalar Nsuint; Scalar Nsuint" "None"
      "let indirect_render_command_draw_primitives raw primitive start count instances base = if start < 0L || count < 0L || instances < 0L || base < 0L then Error \"invalid indirect draw range\" else Registry.indirect_render_command_draw_primitives raw (Int64.of_int primitive) start count instances base"
  ; { name = "blit_fence"; entries =
        (method_ "blit_update_fence" "Blit_encoder" "id<MTLBlitCommandEncoder>" "Fences" "updateFence:" "Obj \"Fence\"" "None" "").entries @
        (method_ "blit_wait_fence" "Blit_encoder" "id<MTLBlitCommandEncoder>" "Fences" "waitForFence:" "Obj \"Fence\"" "None" "").entries;
      adapter = "let blit_fence raw fence update = if update then Registry.blit_update_fence raw fence else Registry.blit_wait_fence raw fence" }
  ; { name = "command_buffer_present_drawable"; entries =
        (method_ "command_buffer_present" "Command_buffer" "id<MTLCommandBuffer>" "Surface" "presentDrawable:" "Obj \"Metal_drawable\"" "None" "").entries @
        (method_ "command_buffer_present_at_time" "Command_buffer" "id<MTLCommandBuffer>" "Surface" "presentDrawable:atTime:" "Obj \"Metal_drawable\"; Scalar Double" "None" "").entries @
        (method_ "command_buffer_present_after_duration" "Command_buffer" "id<MTLCommandBuffer>" "Surface" "presentDrawable:afterMinimumDuration:" "Obj \"Metal_drawable\"; Scalar Double" "None" "").entries;
      adapter = "let command_buffer_present_drawable raw drawable mode time = match mode with 0 -> Registry.command_buffer_present raw drawable | 1 -> Registry.command_buffer_present_at_time raw drawable time | 2 -> Registry.command_buffer_present_after_duration raw drawable time | _ -> Error \"invalid presentation mode\"" }
  ; method_ "blit_pass10_attachment_at" "Blit_sample_attachment_array" "MTLBlitPassSampleBufferAttachmentDescriptorArray *" "Timestamp_queries" "objectAtIndexedSubscript:" "Scalar Nsuint" "Some (Opt_obj \"Blit_sample_attachment\")"
      "let blit_pass10_attachment_at raw index = if index < 0L then Error \"blit attachment index is negative\" else Registry.blit_pass10_attachment_at raw index"
  ]

let recipes = recipes @
  [ method_ "indirect_render_command_set_vertex_buffer" "Indirect_render_command" "id<MTLIndirectRenderCommand>" "Render_pipeline" "setVertexBuffer:offset:atIndex:" "Obj \"Buffer\"; Scalar Nsuint; Scalar Nsuint_int" "None"
      "let indirect_render_command_set_vertex_buffer raw buffer offset index = if offset < 0L || index < 0 then Error \"invalid indirect buffer binding\" else Registry.indirect_render_command_set_vertex_buffer raw buffer offset index"
  ; method_ "indirect_render_command_set_fragment_buffer" "Indirect_render_command" "id<MTLIndirectRenderCommand>" "Render_pipeline" "setFragmentBuffer:offset:atIndex:" "Obj \"Buffer\"; Scalar Nsuint; Scalar Nsuint_int" "None"
      "let indirect_render_command_set_fragment_buffer raw buffer offset index = if offset < 0L || index < 0 then Error \"invalid indirect buffer binding\" else Registry.indirect_render_command_set_fragment_buffer raw buffer offset index"
  ; method_ "counter_supports_sampling" "Device" "id<MTLDevice>" "Timestamp_queries" "supportsCounterSampling:" "Enum_of \"MTLCounterSamplingPoint\"" "Some (Scalar Bool)"
      "let counter_supports_sampling raw point = match point with 0 | 1 | 2 -> Registry.counter_supports_sampling raw (Int64.of_int point) | 3 -> Registry.counter_supports_sampling raw 4L | _ -> Error \"unknown counter sampling point\""
  ; { name = "fx_spatial_supported"; adapter = alias "fx_spatial_supported"; entries =
        [ "Class_method { objc = \"MTLFXSpatialScalerDescriptor\"; sel = \"supportsDevice:\"; args = [Obj \"Device\"]; ret = Some (Scalar Bool); ocaml = \"fx_spatial_supported\"; since = Some (13, 0); feature = C.Metal_fx }" ] }
  ]

let recipes = List.map (fun recipe ->
    let name = recipe.name in
    if List.mem name ["compute_encoder_dispatch"; "compute35_dispatch_groups"] then
      { recipe with entries = List.map (fun entry -> Str.global_replace (Str.regexp_string "Rec \"Mtl_size\"") "Tuple \"Mtl_size_int\"" entry) recipe.entries;
                    adapter = alias name }
    else if List.mem name ["compute_encoder_set_buffer"; "compute_encoder_set_texture";
                          "visible_function_table_set_function"; "intersection_function_table_set_function";
                          "intersection_function_table_set_buffer"] then
      { recipe with entries = List.map (fun entry ->
            let index = Str.search_backward (Str.regexp_string "Scalar Nsuint") entry (String.length entry) in
            String.sub entry 0 index ^ "Scalar Nsuint_int" ^ String.sub entry (index + 13) (String.length entry-index-13)) recipe.entries;
                    adapter = alias name }
    else recipe) recipes

let contains text part = try ignore (Str.search_forward (Str.regexp_string part) text 0); true with Not_found -> false

let ensure_tuple_record registry =
  if contains registry "ocaml = \"Mtl_size_int\"" then registry else
    let close = String.rindex registry ']' in
    String.sub registry 0 close ^ "\n  ; Record { sdk = \"MTLSize\"; ocaml = \"Mtl_size_int\"; fields = [\"width\", Nsuint_int; \"height\", Nsuint_int; \"depth\", Nsuint_int]; feature = C.Compute_pipeline }\n  ]\n"

let replace source edits =
  let buffer = Buffer.create (String.length source) in
  let position = List.fold_left (fun position (s, e, replacement) ->
      Buffer.add_substring buffer source position (s-position);
      Buffer.add_string buffer replacement; e) 0 (List.sort compare edits) in
  Buffer.add_substring buffer source position (String.length source-position);
  Buffer.contents buffer

let refresh_adapters () =
  let names = ["compute_encoder_dispatch"; "compute35_dispatch_groups"; "compute_encoder_set_buffer";
               "compute_encoder_set_texture"; "visible_function_table_set_function";
               "intersection_function_table_set_function"; "intersection_function_table_set_buffer"] in
  let registry_path = "lib/metal/gen/registry.ml" and raw_path = "lib/metal/metal_raw.ml" in
  let registry = read registry_path and raw = read raw_path in
  let edits = ref [] in
  let it = { Ast_iterator.default_iterator with expr = (fun self expression ->
      (match expression.pexp_desc with
       | Pexp_construct ({ txt = Longident.Lident "Method"; _ }, Some { pexp_desc = Pexp_record (fields, _); _ }) ->
           List.iter (fun (field, value) -> match Longident.last field.Location.txt, value.pexp_desc with
               | "ocaml", Pexp_constant { pconst_desc = Pconst_string (name, _, _); _ } when List.mem name names ->
                   let recipe = List.find (fun r -> r.name = name) recipes in
                   edits := (expression.pexp_loc.loc_start.pos_cnum, expression.pexp_loc.loc_end.pos_cnum, List.hd recipe.entries) :: !edits
               | _ -> ()) fields
       | _ -> ()); Ast_iterator.default_iterator.expr self expression) } in
  it.structure it (parse registry);
  let registry = replace registry !edits in
  let registry = ensure_tuple_record registry in
  let edits = List.filter_map (fun item -> match item.pstr_desc with
      | Pstr_value (_, [{ pvb_pat = { ppat_desc = Ppat_var name; _ }; _ }]) when List.mem name.txt names ->
          let recipe = List.find (fun r -> r.name = name.txt) recipes in
          Some (item.pstr_loc.loc_start.pos_cnum, item.pstr_loc.loc_end.pos_cnum, recipe.adapter)
      | Pstr_value (_, [{ pvb_pat = { ppat_desc = Ppat_var { txt = "size"; _ }; _ }; _ }]) ->
          Some (item.pstr_loc.loc_start.pos_cnum, item.pstr_loc.loc_end.pos_cnum, "")
      | _ -> None) (parse raw) in
  let raw = replace raw edits in
  List.iter (fun source -> ignore (parse source)) [registry; raw];
  write registry_path registry; write raw_path raw

let reason name signature =
  let specific =
    [ "device_sparse_tile_size_in_bytes", "sparse hardware/page-size validation and nonzero byte-size result"
    ; "device_sparse_texture_tile_size", "sparse hardware/layout validation and native MTLSize result"
    ; "resource_make_aliasable", "heterogeneous resource handles and heap/texture-view aliasing validation"
    ; "resource_is_aliasable", "heterogeneous Buffer/Texture resource handle decoding"
    ; "heap_buffer_size_and_align", "resource-option validation and native MTLSizeAndAlign result"
    ; "heap_texture_size_and_align", "texture descriptor construction and native MTLSizeAndAlign result"
    ; "residency_set_counts", "allocationCount plus NSArray allAllocations snapshot/count"
    ; "residency_set_add_allocation", "heterogeneous MTLAllocation handle decoding"
    ; "residency_set_remove_allocation", "heterogeneous MTLAllocation handle decoding"
    ; "indirect_command_buffer_reset", "checked NSRange assembled from scalar bounds; future record adapter"
    ; "function_find", "checked function name/device identity after SDK lookup"
    ; "command_buffer_render_encoder_attachments", "temporary render-pass descriptor graph and attachment ownership"
    ; "layer_configure", "checked presentation flags/format and native CGSize marshalling"
    ; "drawable_texture", "owned texture plus native dimension/format snapshot"
    ; "presentation_command_snapshot", "completion state, diagnostic string and native timing snapshot"
    ; "render_pass_sample_set", "indexed sample-attachment graph and sample index validation"
    ; "render_pass_resolve_texture", "nullable resolve-texture access through a descriptor child"
    ; "render_pass_color_store_action", "store action on descriptor colorAttachments[0]; future property-path lowering"
    ; "render_pass_color_load_action", "load action on descriptor colorAttachments[0]; future property-path lowering"
    ; "render_encoder_execute_icb_range", "NSRange assembled from scalar bounds; future record adapter"
    ; "render_stage_buffer", "stage/stride selector dispatch with nullable buffer binding"
    ; "render_stage_sampler", "stage/LOD selector dispatch and native sampler validation"
    ; "render_stage_texture", "stage selector dispatch and nullable texture binding"
    ; "render_pass_depth_stencil_actions", "conditional depth/stencil child updates and native clear-value conversion"
    ; "resource_state_encoder_update_texture_mapping", "sparse region/slice validation and native MTLRegion marshalling"
    ; "blit_encoder_copy_buffer_to_texture", "checked packed copy specification and native MTLSize/MTLOrigin marshalling"
    ; "command_buffer_error", "nullable NSError-to-diagnostic-string conversion"
    ; "argument_encoder_snapshot", "nullable label plus length/alignment/device identity snapshot"
    ; "argument_encoder_set_buffer", "buffer-range/device checks and selector dispatch"
    ; "argument_encoder_single", "heterogeneous handle-kind selector dispatch and device/index checks"
    ; "acceleration_encoder_write_type", "compacted-size type selector dispatch and destination range validation"
    ; "blit_copy", "variant copy specification, resource ranges and native struct marshalling"
    ; "blit_fill_mipmap", "fill/mipmap selector dispatch and checked range/value conversion"
    ; "blit_counter", "sample/resolve selector dispatch with sample/destination range validation"
    ; "compute_pass_attachment", "indexed attachment graph and nullable sample-buffer range validation"
    ; "indirect_render_draw_indexed", "index layout, device identity and byte-range/overflow validation"
    ; "blit_pass10_set_sample_buffer", "nullable counter-buffer attachment and authoritative device identity validation"
    ; "binary_archive5_add", "pipeline-kind selector dispatch and checked descriptor graph"
    ; "mesh_tile_descriptor_set_color_format", "mesh/tile descriptor child selection and attachment index validation"
    ; "fx_spatial_encode", "texture dimension/format/usage validation and temporary scaler-slot ownership" ] in
  match List.assoc_opt name specific with
  | Some reason -> reason
  | None ->
  if List.mem name ["is_main_thread"; "generation"; "destroy"; "drain_releases"; "pending_releases"; "live_handles"; "total_created"; "total_released"; "external_deallocations"; "external_deallocation_mismatches"; "resident_bytes"; "default_device"] then
    "platform/handle lifecycle; not an Objective-C instance call"
  else if List.mem name ["command_buffer_wait"; "shared_event_wait"] then
    "blocking wait releases the OCaml runtime lock"
  else if contains name "handler" then "callback root ownership and cancellation"
  else if contains signature "Native_layer_token" then "borrowed native layer ownership/token validation"
  else if contains name "supports_" || contains name "is_sparse" then
    "SDK availability and hardware capability policy"
  else if contains signature "bytes" || name = "device_library_data" then
    "byte buffers/native memory and checked ranges"
  else if contains signature "array" then
    "array/aggregate marshalling and native validation"
  else if contains name "timestamp" then "native out parameters"
  else if contains name "snapshot" || contains name "info" || contains name "counts" || name = "drawable_texture" then
    "aggregate snapshot marshalling; future composite/record results"
  else if contains name "descriptor" || contains name "create" || contains name "compile" || contains name "specialize" || contains name "function_table" then
    "descriptor construction and checked object graphs"
  else if contains name "serialize" || contains name "load_file" then
    "NSString-to-NSURL conversion and NSError handling"
  else "checked native descriptor/object marshalling"

let update_reasons () =
  let path = "lib/metal/gen/registry.ml" in
  let source = read path and edits = ref [] in
  let it = { Ast_iterator.default_iterator with expr = (fun self expression ->
      (match expression.pexp_desc with
       | Pexp_construct ({ txt = Longident.Lident "Native"; _ }, Some { pexp_desc = Pexp_record (fields, _); _ }) ->
           let field name = List.find (fun (field, _) -> Longident.last field.Location.txt = name) fields |> snd in
           let string expression = match expression.pexp_desc with
             | Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ } -> text
             | _ -> failwith "native metadata must be literal strings" in
           let why = field "reason" in
           edits := (why.pexp_loc.loc_start.pos_cnum, why.pexp_loc.loc_end.pos_cnum,
                     Printf.sprintf "%S" (reason (string (field "ocaml")) (string (field "signature")))) :: !edits
       | _ -> ()); Ast_iterator.default_iterator.expr self expression) } in
  it.structure it (parse source);
  write path (replace source !edits)

let preserve_pools legacy =
  let legacy = read legacy in
  let path = "lib/metal/gen/registry.ml" in
  let source = read path and edits = ref [] in
  let original_pool name =
    let symbol = "caml_prismel_metal_" ^ name in
    if not (contains legacy symbol) then true else
      let start = Str.search_forward (Str.regexp_string symbol) legacy 0 in
      match String.index_from_opt legacy start '{' with
      | None -> true
      | Some start ->
          let rec close position depth =
            if position >= String.length legacy then position else match legacy.[position] with
              | '{' -> close (position+1) (depth+1)
              | '}' -> if depth = 1 then position+1 else close (position+1) (depth-1)
              | _ -> close (position+1) depth in
          let stop = close start 0 in
          contains (String.sub legacy start (stop-start)) "@autoreleasepool" in
  let it = { Ast_iterator.default_iterator with expr = (fun self expression ->
      (match expression.pexp_desc with
       | Pexp_construct ({ txt = Longident.Lident "Method"; _ }, Some ({ pexp_desc = Pexp_record (fields, _); _ } as record)) ->
           let field name = List.find (fun (field, _) -> Longident.last field.Location.txt = name) fields |> snd in
           let name = match (field "ocaml").pexp_desc with
             | Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ } -> text
             | _ -> assert false in
           let unit_return = match (field "ret").pexp_desc with Pexp_construct ({ txt = Longident.Lident "None"; _ }, _) -> true | _ -> false in
           let pool = not unit_return || contains (Format.asprintf "%a" Pprintast.expression (field "args")) "Str" || original_pool name in
           let text = Printf.sprintf "%b" pool in
           (match List.find_opt (fun (field, _) -> Longident.last field.Location.txt = "pool") fields with
            | Some (_, value) -> edits := (value.pexp_loc.loc_start.pos_cnum, value.pexp_loc.loc_end.pos_cnum, text) :: !edits
            | None -> let stop = record.pexp_loc.loc_end.pos_cnum - 1 in
                edits := (stop, stop, "; pool = " ^ text ^ " ") :: !edits)
       | _ -> ()); Ast_iterator.default_iterator.expr self expression) } in
  it.structure it (parse source);
  write path (replace source !edits)

let migrate_legacy ~apply =
  let raw_path = "lib/metal/metal_raw.ml" and registry_path = "lib/metal/gen/registry.ml" in
  let raw = read raw_path in
  let tree = parse raw in
  let types = Buffer.create 8192 and adapters = Buffer.create 4096 in
  let entries = ref [] and edits = ref [] and moved = ref 0 and retained = ref 0 in
  List.iter (fun item -> match item.pstr_desc with
      | Pstr_type _ ->
          Buffer.add_string types (Format.asprintf "%a\n\n" Pprintast.structure_item item);
          edits := (item.pstr_loc, "") :: !edits
      | Pstr_module { pmb_name = { txt = Some "Registry"; _ }; _ } -> edits := (item.pstr_loc, "") :: !edits
      | Pstr_primitive vd ->
          let name = vd.pval_name.txt in
          let signature = Format.asprintf "%a" Pprintast.core_type vd.pval_type in
          (match List.find_opt (fun r -> r.name = name) recipes with
           | Some r ->
               incr moved; entries := !entries @ r.entries;
               Buffer.add_string adapters (r.adapter ^ "\n\n");
               Printf.printf "generate\t%s\n" name
           | None ->
               incr retained;
               let reason = reason name signature in
               entries := !entries @ [Printf.sprintf
                   "Native { ocaml = %S; signature = %S; primitives = [ %s ]; reason = %S }"
                   name signature (String.concat "; " (List.map (Printf.sprintf "%S") vd.pval_prim)) reason];
               Printf.printf "native\t%s\t%s\n" name reason);
          edits := (item.pstr_loc, "") :: !edits
      | _ -> ()) tree;
  Printf.printf "%d migrated implementations, %d registered native exceptions\n%!" !moved !retained;
  if apply && !moved + !retained > 0 then begin
    (* Validate every assembled OCaml file before writing any of them. *)
    let registry = read registry_path in
    let close = String.rindex registry ']' in
    let registry = ensure_tuple_record (String.sub registry 0 close ^ "\n  ; " ^ String.concat "\n  ; " !entries ^ "\n  ]\n") in
    let body = Buffer.create (String.length raw) in
    let position = List.fold_left (fun position (loc, replacement) ->
        Buffer.add_substring body raw position (loc.Location.loc_start.pos_cnum - position);
        Buffer.add_string body replacement; loc.loc_end.pos_cnum) 0
        (List.sort (fun (a, _) (b, _) -> compare a.Location.loc_start.pos_cnum b.Location.loc_start.pos_cnum) !edits) in
    Buffer.add_substring body raw position (String.length raw - position);
    let helpers = {|include Metal_raw_types
module Registry = Metal_gen.Make (Metal_raw_types)
include Registry

(* Preserve the legacy internal ABI while all SDK calls come from Registry. *)
let get = function Ok value -> value | Error message -> failwith message
let ( let* ) = Result.bind

|} in
    let raw = helpers ^ Buffer.contents body ^ Buffer.contents adapters in
    (* Length is shared with the legacy buffer snapshot, use its generated name. *)
    let raw = Str.global_replace (Str.regexp_string "Registry.buffer_length") "Registry.buffer_info_length" raw in
    let raw = Str.global_replace (Str.regexp "\n\n\n+") "\n\n" raw in
    let mapper = { Ast_mapper.default_mapper with attributes = (fun _ attrs ->
        List.filter (fun attr -> not (List.mem attr.attr_name.txt ["ocaml.doc"; "ocaml.text"])) attrs) } in
    let raw = Format.asprintf "%a\n" Pprintast.structure (mapper.structure mapper (parse raw)) in
    List.iter (fun source -> ignore (parse source)) [registry; raw; Buffer.contents types];
    write registry_path registry;
    write "lib/metal/metal_raw_types.ml" (Buffer.contents types);
    write raw_path raw
  end

let lower ~apply =
  let path = "lib/metal/gen/registry.ml" in
  let source = read path in
  let edits = ref [] and adapters = Buffer.create 1024 in
  let iterator = { Ast_iterator.default_iterator with expr = (fun self expression ->
      (match expression.pexp_desc with
       | Pexp_construct ({ txt = Longident.Lident "Native"; _ }, Some { pexp_desc = Pexp_record (fields, _); _ }) ->
           let name = List.find_map (fun (field, value) ->
               if Longident.last field.Location.txt = "ocaml" then match value.pexp_desc with
                 | Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ } -> Some text
                 | _ -> None else None) fields in
           Option.iter (fun name -> match List.find_opt (fun r -> r.name = name) recipes with
               | None -> ()
               | Some recipe ->
                   let s = expression.pexp_loc.loc_start.pos_cnum and e = expression.pexp_loc.loc_end.pos_cnum in
                   let s = if recipe.entries = [] then
                       let rec back i = if i > 0 && List.mem source.[i-1] [' '; '\n'; '\t'] then back (i-1) else i in
                       let i = back s in if i > 0 && source.[i-1] = ';' then i-1 else s
                     else s in
                   edits := (s, e, String.concat "\n  ; " recipe.entries) :: !edits;
                   Buffer.add_string adapters (recipe.adapter ^ "\n\n");
                   Printf.printf "generate\t%s\n" name) name
       | _ -> ()); Ast_iterator.default_iterator.expr self expression) } in
  iterator.structure iterator (parse source);
  Printf.printf "%d native exceptions lowered\n%!" (List.length !edits);
  if apply && !edits <> [] then begin
    let buffer = Buffer.create (String.length source) in
    let position = List.fold_left (fun position (s, e, text) ->
        Buffer.add_substring buffer source position (s-position);
        Buffer.add_string buffer text; e) 0 (List.sort compare !edits) in
    Buffer.add_substring buffer source position (String.length source-position);
    let registry = Buffer.contents buffer in
    let raw_path = "lib/metal/metal_raw.ml" in
    let raw = read raw_path in
    let raw = (if contains raw "let ( let* )" || contains raw "let (let*)" then raw
               else raw ^ "\nlet ( let* ) = Result.bind\n") ^ "\n" ^ Buffer.contents adapters in
    List.iter (fun text -> ignore (parse text)) [registry; raw];
    write path registry; write raw_path raw
  end

let migrate ~apply =
  if List.exists (fun item -> match item.pstr_desc with Pstr_primitive _ -> true | _ -> false)
      (parse (read "lib/metal/metal_raw.ml")) then migrate_legacy ~apply
  else lower ~apply;
  if apply then begin
    let path = "lib/metal/metal_bridge.mm" in
    let bridge = read path in
    let bridge = Str.global_replace (Str.regexp_string "#import <MetalFX/MetalFX.h>\n") "" bridge in
    let bridge = Str.replace_first (Str.regexp_string "#import <Metal/Metal.h>\n")
        "#import <Metal/Metal.h>\n#import <MetalFX/MetalFX.h>\n" bridge in
    write path bridge
  end

let format_abi legacy =
  let types = List.filter (fun item -> match item.pstr_desc with Pstr_type _ -> true | _ -> false) (parse (read legacy)) in
  let path = "lib/metal/metal_raw.ml" in
  let mapper = { Ast_mapper.default_mapper with attributes = (fun _ attrs ->
      List.filter (fun attr -> not (List.mem attr.attr_name.txt ["ocaml.doc"; "ocaml.text"])) attrs) } in
  let raw = mapper.structure mapper (parse (read path)) in
  write "lib/metal/metal_raw_types.ml" (Format.asprintf "%a\n" Pprintast.structure types);
  write path (Format.asprintf "%a\n" Pprintast.structure raw)

let audit () =
  let tree = parse (read "lib/metal/gen/registry.ml") in
  let counts = Hashtbl.create 4 in
  let iterator = { Ast_iterator.default_iterator with expr = (fun self expression ->
      (match expression.pexp_desc with
       | Pexp_construct ({ txt = Longident.Lident (("Native" | "Class_method" | "Method" | "Property") as kind); _ }, Some { pexp_desc = Pexp_record (fields, _); _ }) ->
           let string name = List.find_map (fun (field, value) ->
               if Longident.last field.Location.txt = name then match value.pexp_desc with
                 | Pexp_constant { pconst_desc = Pconst_string (text, _, _); _ } -> Some text
                 | _ -> None else None) fields |> Option.value ~default:"" in
           Hashtbl.replace counts kind (1 + Option.value (Hashtbl.find_opt counts kind) ~default:0);
           Printf.printf "%s\t%s\t%s\n" kind (string "ocaml") (string "reason")
       | _ -> ()); Ast_iterator.default_iterator.expr self expression) } in
  iterator.structure iterator tree;
  Hashtbl.iter (fun kind count -> Printf.printf "%s: %d\n" kind count) counts

let rec drop_unused_macros path =
  let source = read path in
  let define = Str.regexp "^#define[ \t]+\\([A-Za-z_][A-Za-z0-9_]*\\)" in
  let undef = Str.regexp "^#undef[ \t]+\\([A-Za-z_][A-Za-z0-9_]*\\)[^\n]*" in
  let ranges = Hashtbl.create 32 in
  let add name range = Hashtbl.replace ranges name (range :: Option.value (Hashtbl.find_opt ranges name) ~default:[]) in
  let rec scan re definition offset = match Str.search_forward re source offset with
    | start ->
        let name = Str.matched_group 1 source in
        let rec line_end offset = match String.index_from_opt source offset '\n' with
          | None -> String.length source
          | Some stop when definition && stop > 0 && source.[stop-1] = '\\' -> line_end (stop+1)
          | Some stop -> stop+1 in
        let stop = line_end (Str.match_end ()) in
        add name (start, stop); scan re definition stop
    | exception Not_found -> () in
  scan define true 0; scan undef false 0;
  let edits = ref [] in
  Hashtbl.iter (fun name locations ->
      let rest = replace source (List.map (fun (s,e) -> s,e,"") locations) in
      if List.exists (fun prefix -> String.starts_with ~prefix name) ["PRISMEL_"; "COMPUTE_"; "C35_"]
         && not (try ignore (Str.search_forward (Str.regexp ("\\b" ^ name ^ "\\b")) rest 0); true with Not_found -> false) then
        edits := List.map (fun (s,e) -> s,e,"") locations @ !edits) ranges;
  if !edits <> [] then (Printf.printf "removed %d unused macro directives\n%!" (List.length !edits);
                       write path (replace source !edits); drop_unused_macros path)

let self_test () =
  assert (List.length recipes = List.length (List.sort_uniq String.compare (List.map (fun r -> r.name) recipes)));
  List.iter (fun r -> List.iter (fun entry -> ignore (parse ("let entry = " ^ entry))) r.entries;
      ignore (parse r.adapter)) recipes;
  assert (reason "command_buffer_wait" "handle -> unit" = "blocking wait releases the OCaml runtime lock");
  assert (reason "texture_read" "handle -> bytes" = "byte buffers/native memory and checked ranges");
  let path = Filename.temp_file "metal-macros" ".mm" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
      write path "#define CAML_NAME_SPACE\n#define PRISMEL_INNER(x) x\n#define PRISMEL_OUTER(x) PRISMEL_INNER(x)\n#define PRISMEL_LIVE(x) x\n#define PRISMEL_DEAD(x) \\\n+  { x; }\n#undef PRISMEL_DEAD\nPRISMEL_LIVE(1)\n";
      drop_unused_macros path;
      let result = read path in
      assert (contains result "CAML_NAME_SPACE");
      assert (contains result "#define PRISMEL_LIVE");
      assert (not (contains result "PRISMEL_INNER"));
      assert (not (contains result "PRISMEL_DEAD")))
