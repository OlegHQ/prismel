type atom =
  | Nsuint
  | Uint64 of string
  | Enum of string
  | Struct of string

type receiver =
  { owner : string
  ; objc_type : string
  ; raw_name : string
  ; local_name : string
  ; recovery : string
  }

type method_ =
  { selector : string
  ; receiver : receiver
  ; arguments : atom list
  ; result : atom option
  ; introduced : string
  }

type output =
  { raw_ml : string
  ; raw_mli : string
  ; native : string
  ; method_ids : string list
  ; property_ids : string list
  }

let direct owner objc_type kind local_name =
  { owner; objc_type; raw_name = "raw_" ^ local_name; local_name
  ; recovery =
      Printf.sprintf "object_of_handle(raw_%s, Handle_kind::%s)" local_name kind
  }

let wrapped owner objc_type kind local_name wrapper property =
  { owner; objc_type; raw_name = "raw_" ^ local_name; local_name
  ; recovery =
      Printf.sprintf
        "object_of_handle(raw_%s, Handle_kind::%s).%s /* %s */"
        local_name kind property wrapper
  }

let device = direct "MTLDevice" "id<MTLDevice>" "Device" "device"
let compute_pipeline = direct "MTLComputePipelineState" "id<MTLComputePipelineState>" "Compute_pipeline" "compute_pipeline"
let compute_encoder = direct "MTLComputeCommandEncoder" "id<MTLComputeCommandEncoder>" "Compute_encoder" "compute_encoder"
let compute_encoder4 = direct "MTL4ComputeCommandEncoder" "id<MTL4ComputeCommandEncoder>" "Compute_encoder4" "compute_encoder4"
let render_encoder4 = direct "MTL4RenderCommandEncoder" "id<MTL4RenderCommandEncoder>" "Render_encoder4" "render_encoder4"
let depth_stencil = direct "MTLDepthStencilState" "id<MTLDepthStencilState>" "Depth_stencil" "depth_stencil"
let render_pipeline = direct "MTLRenderPipelineState" "id<MTLRenderPipelineState>" "Render_pipeline" "render_pipeline"
let argument_table4 = wrapped "MTL4ArgumentTable" "id<MTL4ArgumentTable>" "Argument_table4" "argument_table4" "PrismelMetal4ArgumentTableState *" "argumentTable"

let m receiver selector arguments result introduced =
  { receiver; selector; arguments; result; introduced }

let size = Struct "MTLSize"
let region = Struct "MTLRegion"
let resource_id = Struct "MTLResourceID"
let size_and_align = Struct "MTLSizeAndAlign"

let methods =
  [ m argument_table4 "setResource:atBufferIndex:" [ resource_id; Nsuint ] None "26.0"
  ; m compute_encoder4 "dispatchThreadgroups:threadsPerThreadgroup:" [ size; size ] None "26.0"
  ; m compute_encoder4 "dispatchThreadgroupsWithIndirectBuffer:threadsPerThreadgroup:" [ Uint64 "MTLGPUAddress"; size ] None "26.0"
  ; m render_encoder4 "drawMeshThreadgroupsWithIndirectBuffer:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:" [ Uint64 "MTLGPUAddress"; size; size ] None "26.0"
  ; m render_encoder4 "drawMeshThreads:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:" [ size; size; size ] None "26.0"
  ; m compute_encoder "dispatchThreadgroups:threadsPerThreadgroup:" [ size; size ] None "10.11"
  ; m compute_encoder "setStageInRegion:" [ region ] None "10.12"
  ; m compute_pipeline "gpuResourceID" [] (Some resource_id) "13.0"
  ; m compute_pipeline "imageblockMemoryLengthForDimensions:" [ size ] (Some Nsuint) "11.0"
  ; m compute_pipeline "requiredThreadsPerThreadgroup" [] (Some size) "26.0"
  ; m depth_stencil "gpuResourceID" [] (Some resource_id) "26.0"
  ; m device "heapAccelerationStructureSizeAndAlignWithSize:" [ Nsuint ] (Some size_and_align) "13.0"
  ; m device "maxThreadsPerThreadgroup" [] (Some size) "10.11"
  ; m device "sparseTileSizeWithTextureType:pixelFormat:sampleCount:"
      [ Enum "MTLTextureType"; Enum "MTLPixelFormat"; Nsuint ] (Some size) "11.0"
  ; m render_pipeline "gpuResourceID" [] (Some resource_id) "13.0"
  ; m render_pipeline "imageblockMemoryLengthForDimensions:" [ size ] (Some Nsuint) "11.0"
  ; m render_pipeline "requiredThreadsPerMeshThreadgroup" [] (Some size) "26.0"
  ; m render_pipeline "requiredThreadsPerObjectThreadgroup" [] (Some size) "26.0"
  ; m render_pipeline "requiredThreadsPerTileThreadgroup" [] (Some size) "26.0"
  ]

let property_ids =
  [ "property:MTLComputePipelineState:gpuResourceID"
  ; "property:MTLComputePipelineState:requiredThreadsPerThreadgroup"
  ; "property:MTLDepthStencilState:gpuResourceID"
  ; "property:MTLDevice:maxThreadsPerThreadgroup"
  ; "property:MTLRenderPipelineState:gpuResourceID"
  ; "property:MTLRenderPipelineState:requiredThreadsPerMeshThreadgroup"
  ; "property:MTLRenderPipelineState:requiredThreadsPerObjectThreadgroup"
  ; "property:MTLRenderPipelineState:requiredThreadsPerTileThreadgroup"
  ]

let expected_method_count = 19
let expected_property_count = 8

let snake value =
  let output = Buffer.create (String.length value + 8) in
  String.iteri (fun index c ->
    if c = ':' then Buffer.add_char output '_'
    else begin
      if index > 0 && c >= 'A' && c <= 'Z' then Buffer.add_char output '_';
      Buffer.add_char output (Char.lowercase_ascii c)
    end) value;
  Buffer.contents output |> String.trim

let name entry = "generated_struct_" ^ snake entry.receiver.owner ^ "_" ^ snake entry.selector
let symbol entry = "caml_prismel_metal_" ^ name entry
let method_id entry = Printf.sprintf "method:-[%s %s]" entry.receiver.owner entry.selector

let ocaml_type = function
  | Nsuint | Uint64 _ | Enum _ | Struct "MTLResourceID" -> "int64"
  | Struct "MTLSize" -> "int64 * int64 * int64"
  | Struct "MTLRegion" -> "(int64 * int64 * int64) * (int64 * int64 * int64)"
  | Struct "MTLSizeAndAlign" -> "int64 * int64"
  | Struct value -> invalid_arg ("unsupported struct type " ^ value)

let objc_type = function
  | Nsuint -> "NSUInteger"
  | Uint64 value | Enum value | Struct value -> value

let helper_suffix = function
  | "MTLSize" -> "size"
  | "MTLRegion" -> "region"
  | "MTLSizeAndAlign" -> "size_and_align"
  | "MTLResourceID" -> "resource_id"
  | value -> invalid_arg ("unsupported struct helper " ^ value)

let pieces selector =
  selector |> String.split_on_char ':' |> List.filter (fun value -> value <> "")

let call entry =
  match entry.arguments with
  | [] -> Printf.sprintf "[%s %s]" entry.receiver.local_name entry.selector
  | arguments ->
      List.map2 (fun piece index -> Printf.sprintf "%s:argument_%d" piece index)
        (pieces entry.selector) (List.init (List.length arguments) Fun.id)
      |> String.concat " " |> Printf.sprintf "[%s %s]" entry.receiver.local_name

let add_conversion output index = function
  | Struct value ->
      Printf.bprintf output "        const %s argument_%d = prismel_mtl_%s_of_value(raw_argument_%d);\n"
        value index (helper_suffix value) index
  | atom ->
      let typ = objc_type atom in
      Printf.bprintf output
        "        const %s argument_%d = static_cast<%s>(static_cast<std::uint64_t>(Int64_val(raw_argument_%d)));\n"
        typ index typ index

let add_result output = function
  | Struct value ->
      Printf.bprintf output "        copied_result = prismel_value_of_mtl_%s(native_result);\n" (helper_suffix value)
  | Nsuint | Uint64 _ | Enum _ ->
      Buffer.add_string output "        copied_result = caml_copy_int64(static_cast<std::int64_t>(static_cast<std::uint64_t>(native_result)));\n"

let add_method raw_ml raw_mli native entry =
  let types = "Handle.t" :: List.map ocaml_type entry.arguments in
  let result_type = match entry.result with None -> "unit" | Some value -> ocaml_type value in
  let declaration = String.concat " -> " (types @ [ "(" ^ result_type ^ ", string) result" ]) in
  Printf.bprintf raw_mli "val %s : %s\n" (name entry) declaration;
  Printf.bprintf raw_ml "external %s : %s = %S\n" (name entry) declaration (symbol entry);
  let raw_arguments = entry.receiver.raw_name :: List.mapi (fun index _ -> Printf.sprintf "raw_argument_%d" index) entry.arguments in
  Printf.bprintf native "extern \"C\" CAMLprim value\n%s(%s) {\n" (symbol entry)
    (raw_arguments |> List.map (fun value -> "value " ^ value) |> String.concat ", ");
  Printf.bprintf native "  CAMLparam%d(%s);\n" (List.length raw_arguments) (String.concat ", " raw_arguments);
  if Option.is_some entry.result then Buffer.add_string native "  CAMLlocal2(result, copied_result);\n";
  Buffer.add_string native "  @autoreleasepool {\n";
  Printf.bprintf native "    if (@available(macOS %s, *)) {\n      @try {\n" entry.introduced;
  Printf.bprintf native "        %s %s = %s;\n" entry.receiver.objc_type entry.receiver.local_name entry.receiver.recovery;
  List.iteri (add_conversion native) entry.arguments;
  (match entry.result with
   | None -> Printf.bprintf native "        %s;\n        CAMLreturn(result_unit());\n" (call entry)
   | Some result ->
       Printf.bprintf native "        const %s native_result = %s;\n" (objc_type result) (call entry);
       add_result native result;
       Buffer.add_string native "        result = result_ok(copied_result);\n        CAMLreturn(result);\n");
  Buffer.add_string native "      } @catch (NSException *exception) {\n        CAMLreturn(result_error(exception.reason));\n      }\n    }\n";
  Printf.bprintf native "    CAMLreturn(result_error_text(\"Metal selector %s requires macOS %s\"));\n  }\n}\n\n" entry.selector entry.introduced

let helper_prelude = {|
static MTLSize prismel_mtl_size_of_value(value raw) {
  return MTLSizeMake(static_cast<NSUInteger>(Int64_val(Field(raw, 0))), static_cast<NSUInteger>(Int64_val(Field(raw, 1))), static_cast<NSUInteger>(Int64_val(Field(raw, 2))));
}
static MTLRegion prismel_mtl_region_of_value(value raw) {
  return MTLRegionMake(prismel_mtl_size_of_value(Field(raw, 0)).width, prismel_mtl_size_of_value(Field(raw, 0)).height, prismel_mtl_size_of_value(Field(raw, 0)).depth, prismel_mtl_size_of_value(Field(raw, 1)).width, prismel_mtl_size_of_value(Field(raw, 1)).height, prismel_mtl_size_of_value(Field(raw, 1)).depth);
}
static MTLResourceID prismel_mtl_resource_id_of_value(value raw) { return MTLResourceID{static_cast<uint64_t>(Int64_val(raw))}; }
static value prismel_value_of_mtl_resource_id(MTLResourceID value_) { return caml_copy_int64(static_cast<int64_t>(value_._impl)); }
static value prismel_value_of_mtl_size(MTLSize value_) { CAMLparam0(); CAMLlocal2(result, item); result = caml_alloc_tuple(3); item = caml_copy_int64(value_.width); Store_field(result, 0, item); item = caml_copy_int64(value_.height); Store_field(result, 1, item); item = caml_copy_int64(value_.depth); Store_field(result, 2, item); CAMLreturn(result); }
static value prismel_value_of_mtl_size_and_align(MTLSizeAndAlign value_) { CAMLparam0(); CAMLlocal2(result, item); result = caml_alloc_tuple(2); item = caml_copy_int64(value_.size); Store_field(result, 0, item); item = caml_copy_int64(value_.align); Store_field(result, 1, item); CAMLreturn(result); }
|}

let generate () =
  if List.length methods <> expected_method_count || List.length property_ids <> expected_property_count then invalid_arg "Metal struct native batch cardinality drift";
  let raw_ml = Buffer.create 8192 and raw_mli = Buffer.create 8192 and native = Buffer.create 32768 in
  Buffer.add_string native helper_prelude;
  List.iter (add_method raw_ml raw_mli native) methods;
  { raw_ml = Buffer.contents raw_ml; raw_mli = Buffer.contents raw_mli
  ; native = Buffer.contents native; method_ids = List.map method_id methods
  ; property_ids }
