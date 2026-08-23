open Binding_direct_spec

let availability = [ "AvailabilityAttr" ]

let macos_10_11 = version 10 11
let macos_10_12 = version 10 12
let macos_10_13 = version 10 13
let macos_10_14 = version 10 14
let macos_10_15 = version 10 15
let macos_11 = version 11 0
let macos_12 = version 12 0
let macos_13_3 = version 13 3
let macos_15 = version 15 0
let macos_26 = version 26 0

let mtl_argument_buffers_tier = named_nsuint "MTLArgumentBuffersTier"
let mtl_command_buffer_error_option = named_nsuint "MTLCommandBufferErrorOption"
let mtl_device_location = named_nsuint "MTLDeviceLocation"
let mtl_dispatch_type = named_nsuint "MTLDispatchType"
let mtl_function_options = named_nsuint "MTLFunctionOptions"
let mtl_function_type = named_nsuint "MTLFunctionType"
let mtl_patch_type = named_nsuint "MTLPatchType"
let mtl_read_write_texture_tier = named_nsuint "MTLReadWriteTextureTier"
let mtl_resource_options = named_nsuint "MTLResourceOptions"
let mtl_shader_validation = named_nsint "MTLShaderValidation"

let property ?getter_selector ?setter ~sdk_id ~getter_sdk_id ~owner ~name
    ~header ~signature ~attributes ~macos_introduced ~result () =
  let getter_selector = Option.value ~default:name getter_selector in
  let getter =
    method_entry ~sdk_id:getter_sdk_id ~owner ~selector:getter_selector ~header
      ~signature:("instance () -> " ^ signature) ~attributes
      ~macos_introduced ~arguments:[] ~result:(Some result) ~semantics:Query ()
  in
  let setter =
    Option.map
      (fun (setter_sdk_id, setter_selector) ->
        method_entry ~sdk_id:setter_sdk_id ~owner ~selector:setter_selector
          ~header ~signature:("instance (" ^ signature ^ ") -> void")
          ~attributes ~macos_introduced ~arguments:[ result ] ~result:None
          ~semantics:Command ())
      setter
  in
  property_entry ~sdk_id ~owner ~name ~header ~signature ~attributes
    ~macos_introduced ~getter ?setter ()

let entries : property_entry list =
  [ property
      ~sdk_id:"property:MTL4BinaryFunction:functionType"
      ~getter_sdk_id:"method:-[MTL4BinaryFunction functionType]"
      ~owner:"MTL4BinaryFunction" ~name:"functionType"
      ~header:"Metal/MTL4BinaryFunction.h" ~signature:"MTLFunctionType"
      ~attributes:[] ~macos_introduced:macos_26 ~result:mtl_function_type ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:GPUEndTime"
      ~getter_sdk_id:"method:-[MTLCommandBuffer GPUEndTime]"
      ~owner:"MTLCommandBuffer" ~name:"GPUEndTime"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"CFTimeInterval"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:double ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:GPUStartTime"
      ~getter_sdk_id:"method:-[MTLCommandBuffer GPUStartTime]"
      ~owner:"MTLCommandBuffer" ~name:"GPUStartTime"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"CFTimeInterval"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:double ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:errorOptions"
      ~getter_sdk_id:"method:-[MTLCommandBuffer errorOptions]"
      ~owner:"MTLCommandBuffer" ~name:"errorOptions"
      ~header:"Metal/MTLCommandBuffer.h"
      ~signature:"MTLCommandBufferErrorOption" ~attributes:availability
      ~macos_introduced:macos_11 ~result:mtl_command_buffer_error_option ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:kernelEndTime"
      ~getter_sdk_id:"method:-[MTLCommandBuffer kernelEndTime]"
      ~owner:"MTLCommandBuffer" ~name:"kernelEndTime"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"CFTimeInterval"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:double ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:kernelStartTime"
      ~getter_sdk_id:"method:-[MTLCommandBuffer kernelStartTime]"
      ~owner:"MTLCommandBuffer" ~name:"kernelStartTime"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"CFTimeInterval"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:double ()
  ; property
      ~sdk_id:"property:MTLCommandBuffer:retainedReferences"
      ~getter_sdk_id:"method:-[MTLCommandBuffer retainedReferences]"
      ~owner:"MTLCommandBuffer" ~name:"retainedReferences"
      ~header:"Metal/MTLCommandBuffer.h" ~signature:"BOOL" ~attributes:[]
      ~macos_introduced:macos_10_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLComputeCommandEncoder:dispatchType"
      ~getter_sdk_id:"method:-[MTLComputeCommandEncoder dispatchType]"
      ~owner:"MTLComputeCommandEncoder" ~name:"dispatchType"
      ~header:"Metal/MTLComputeCommandEncoder.h" ~signature:"MTLDispatchType"
      ~attributes:availability ~macos_introduced:macos_10_14
      ~result:mtl_dispatch_type ()
  ; property
      ~sdk_id:"property:MTLComputePipelineState:shaderValidation"
      ~getter_sdk_id:"method:-[MTLComputePipelineState shaderValidation]"
      ~owner:"MTLComputePipelineState" ~name:"shaderValidation"
      ~header:"Metal/MTLComputePipeline.h" ~signature:"MTLShaderValidation"
      ~attributes:availability ~macos_introduced:macos_15
      ~result:mtl_shader_validation ()
  ; property
      ~sdk_id:"property:MTLComputePipelineState:supportIndirectCommandBuffers"
      ~getter_sdk_id:
        "method:-[MTLComputePipelineState supportIndirectCommandBuffers]"
      ~owner:"MTLComputePipelineState" ~name:"supportIndirectCommandBuffers"
      ~header:"Metal/MTLComputePipeline.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:argumentBuffersSupport"
      ~getter_sdk_id:"method:-[MTLDevice argumentBuffersSupport]"
      ~owner:"MTLDevice" ~name:"argumentBuffersSupport"
      ~header:"Metal/MTLDevice.h" ~signature:"MTLArgumentBuffersTier"
      ~attributes:availability ~macos_introduced:macos_10_13
      ~result:mtl_argument_buffers_tier ()
  ; property
      ~sdk_id:"property:MTLDevice:location"
      ~getter_sdk_id:"method:-[MTLDevice location]" ~owner:"MTLDevice"
      ~name:"location" ~header:"Metal/MTLDevice.h"
      ~signature:"MTLDeviceLocation" ~attributes:availability
      ~macos_introduced:macos_10_15 ~result:mtl_device_location ()
  ; property
      ~sdk_id:"property:MTLDevice:locationNumber"
      ~getter_sdk_id:"method:-[MTLDevice locationNumber]" ~owner:"MTLDevice"
      ~name:"locationNumber" ~header:"Metal/MTLDevice.h"
      ~signature:"NSUInteger" ~attributes:availability
      ~macos_introduced:macos_10_15 ~result:nsuint ()
  ; property
      ~sdk_id:"property:MTLDevice:maxArgumentBufferSamplerCount"
      ~getter_sdk_id:"method:-[MTLDevice maxArgumentBufferSamplerCount]"
      ~owner:"MTLDevice" ~name:"maxArgumentBufferSamplerCount"
      ~header:"Metal/MTLDevice.h" ~signature:"NSUInteger"
      ~attributes:availability ~macos_introduced:macos_10_14 ~result:nsuint ()
  ; property
      ~sdk_id:"property:MTLDevice:maxTransferRate"
      ~getter_sdk_id:"method:-[MTLDevice maxTransferRate]" ~owner:"MTLDevice"
      ~name:"maxTransferRate" ~header:"Metal/MTLDevice.h"
      ~signature:"uint64_t" ~attributes:availability
      ~macos_introduced:macos_10_15 ~result:uint64 ()
  ; property
      ~sdk_id:"property:MTLDevice:maximumConcurrentCompilationTaskCount"
      ~getter_sdk_id:
        "method:-[MTLDevice maximumConcurrentCompilationTaskCount]"
      ~owner:"MTLDevice" ~name:"maximumConcurrentCompilationTaskCount"
      ~header:"Metal/MTLDevice.h" ~signature:"NSUInteger"
      ~attributes:availability ~macos_introduced:macos_13_3 ~result:nsuint ()
  ; property
      ~sdk_id:"property:MTLDevice:peerCount"
      ~getter_sdk_id:"method:-[MTLDevice peerCount]" ~owner:"MTLDevice"
      ~name:"peerCount" ~header:"Metal/MTLDevice.h" ~signature:"uint32_t"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:uint32 ()
  ; property
      ~sdk_id:"property:MTLDevice:peerGroupID"
      ~getter_sdk_id:"method:-[MTLDevice peerGroupID]" ~owner:"MTLDevice"
      ~name:"peerGroupID" ~header:"Metal/MTLDevice.h" ~signature:"uint64_t"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:uint64 ()
  ; property
      ~sdk_id:"property:MTLDevice:peerIndex"
      ~getter_sdk_id:"method:-[MTLDevice peerIndex]" ~owner:"MTLDevice"
      ~name:"peerIndex" ~header:"Metal/MTLDevice.h" ~signature:"uint32_t"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:uint32 ()
  ; property
      ~sdk_id:"property:MTLDevice:programmableSamplePositionsSupported"
      ~getter_sdk_id:
        "method:-[MTLDevice areProgrammableSamplePositionsSupported]"
      ~owner:"MTLDevice" ~name:"programmableSamplePositionsSupported"
      ~getter_selector:"areProgrammableSamplePositionsSupported"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_10_13 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:rasterOrderGroupsSupported"
      ~getter_sdk_id:"method:-[MTLDevice areRasterOrderGroupsSupported]"
      ~owner:"MTLDevice" ~name:"rasterOrderGroupsSupported"
      ~getter_selector:"areRasterOrderGroupsSupported"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_10_13 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:readWriteTextureSupport"
      ~getter_sdk_id:"method:-[MTLDevice readWriteTextureSupport]"
      ~owner:"MTLDevice" ~name:"readWriteTextureSupport"
      ~header:"Metal/MTLDevice.h" ~signature:"MTLReadWriteTextureTier"
      ~attributes:availability ~macos_introduced:macos_10_13
      ~result:mtl_read_write_texture_tier ()
  ; property
      ~sdk_id:"property:MTLDevice:shouldMaximizeConcurrentCompilation"
      ~getter_sdk_id:"method:-[MTLDevice shouldMaximizeConcurrentCompilation]"
      ~setter:
        ( "method:-[MTLDevice setShouldMaximizeConcurrentCompilation:]"
        , "setShouldMaximizeConcurrentCompilation:" )
      ~owner:"MTLDevice" ~name:"shouldMaximizeConcurrentCompilation"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_13_3 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supports32BitFloatFiltering"
      ~getter_sdk_id:"method:-[MTLDevice supports32BitFloatFiltering]"
      ~owner:"MTLDevice" ~name:"supports32BitFloatFiltering"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supports32BitMSAA"
      ~getter_sdk_id:"method:-[MTLDevice supports32BitMSAA]"
      ~owner:"MTLDevice" ~name:"supports32BitMSAA"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supportsPrimitiveMotionBlur"
      ~getter_sdk_id:"method:-[MTLDevice supportsPrimitiveMotionBlur]"
      ~owner:"MTLDevice" ~name:"supportsPrimitiveMotionBlur"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supportsPullModelInterpolation"
      ~getter_sdk_id:"method:-[MTLDevice supportsPullModelInterpolation]"
      ~owner:"MTLDevice" ~name:"supportsPullModelInterpolation"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supportsQueryTextureLOD"
      ~getter_sdk_id:"method:-[MTLDevice supportsQueryTextureLOD]"
      ~owner:"MTLDevice" ~name:"supportsQueryTextureLOD"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_11 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supportsRenderDynamicLibraries"
      ~getter_sdk_id:"method:-[MTLDevice supportsRenderDynamicLibraries]"
      ~owner:"MTLDevice" ~name:"supportsRenderDynamicLibraries"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_12 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLDevice:supportsShaderBarycentricCoordinates"
      ~getter_sdk_id:"method:-[MTLDevice supportsShaderBarycentricCoordinates]"
      ~owner:"MTLDevice" ~name:"supportsShaderBarycentricCoordinates"
      ~header:"Metal/MTLDevice.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_10_15 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLFunction:options"
      ~getter_sdk_id:"method:-[MTLFunction options]" ~owner:"MTLFunction"
      ~name:"options" ~header:"Metal/MTLLibrary.h"
      ~signature:"MTLFunctionOptions" ~attributes:availability
      ~macos_introduced:macos_11 ~result:mtl_function_options ()
  ; property
      ~sdk_id:"property:MTLFunction:patchControlPointCount"
      ~getter_sdk_id:"method:-[MTLFunction patchControlPointCount]"
      ~owner:"MTLFunction" ~name:"patchControlPointCount"
      ~header:"Metal/MTLLibrary.h" ~signature:"NSInteger"
      ~attributes:availability ~macos_introduced:macos_10_12 ~result:nsint ()
  ; property
      ~sdk_id:"property:MTLFunction:patchType"
      ~getter_sdk_id:"method:-[MTLFunction patchType]" ~owner:"MTLFunction"
      ~name:"patchType" ~header:"Metal/MTLLibrary.h"
      ~signature:"MTLPatchType" ~attributes:availability
      ~macos_introduced:macos_10_12 ~result:mtl_patch_type ()
  ; property
      ~sdk_id:"property:MTLHeap:resourceOptions"
      ~getter_sdk_id:"method:-[MTLHeap resourceOptions]" ~owner:"MTLHeap"
      ~name:"resourceOptions" ~header:"Metal/MTLHeap.h"
      ~signature:"MTLResourceOptions" ~attributes:availability
      ~macos_introduced:macos_10_15 ~result:mtl_resource_options ()
  ; property
      ~sdk_id:"property:MTLRenderPipelineState:imageblockSampleLength"
      ~getter_sdk_id:"method:-[MTLRenderPipelineState imageblockSampleLength]"
      ~owner:"MTLRenderPipelineState" ~name:"imageblockSampleLength"
      ~header:"Metal/MTLRenderPipeline.h" ~signature:"NSUInteger"
      ~attributes:availability ~macos_introduced:macos_11 ~result:nsuint ()
  ; property
      ~sdk_id:"property:MTLRenderPipelineState:shaderValidation"
      ~getter_sdk_id:"method:-[MTLRenderPipelineState shaderValidation]"
      ~owner:"MTLRenderPipelineState" ~name:"shaderValidation"
      ~header:"Metal/MTLRenderPipeline.h" ~signature:"MTLShaderValidation"
      ~attributes:availability ~macos_introduced:macos_15
      ~result:mtl_shader_validation ()
  ; property
      ~sdk_id:"property:MTLRenderPipelineState:supportIndirectCommandBuffers"
      ~getter_sdk_id:
        "method:-[MTLRenderPipelineState supportIndirectCommandBuffers]"
      ~owner:"MTLRenderPipelineState" ~name:"supportIndirectCommandBuffers"
      ~header:"Metal/MTLRenderPipeline.h" ~signature:"BOOL"
      ~attributes:availability ~macos_introduced:macos_10_14 ~result:bool ()
  ; property
      ~sdk_id:"property:MTLResource:allocatedSize"
      ~getter_sdk_id:"method:-[MTLResource allocatedSize]" ~owner:"MTLResource"
      ~name:"allocatedSize" ~header:"Metal/MTLResource.h"
      ~signature:"NSUInteger" ~attributes:availability
      ~macos_introduced:macos_10_13 ~result:nsuint ()
  ; property
      ~sdk_id:"property:MTLResource:resourceOptions"
      ~getter_sdk_id:"method:-[MTLResource resourceOptions]"
      ~owner:"MTLResource" ~name:"resourceOptions"
      ~header:"Metal/MTLResource.h" ~signature:"MTLResourceOptions"
      ~attributes:availability ~macos_introduced:macos_10_15
      ~result:mtl_resource_options ()
  ; property
      ~sdk_id:"property:MTLTexture:framebufferOnly"
      ~getter_sdk_id:"method:-[MTLTexture isFramebufferOnly]"
      ~getter_selector:"isFramebufferOnly" ~owner:"MTLTexture"
      ~name:"framebufferOnly" ~header:"Metal/MTLTexture.h"
      ~signature:"BOOL" ~attributes:[] ~macos_introduced:macos_10_11
      ~result:bool ()
  ]

let property_count = List.length entries
let getter_count = List.length entries

let setter_count =
  List.fold_left
    (fun count (entry : property_entry) ->
      match entry.setter with
      | None -> count
      | Some _ -> count + 1)
    0 entries

let declaration_ids =
  List.concat_map property_inventory_ids entries

let declaration_count = List.length declaration_ids

let expected_property_count = 40
let expected_getter_count = 40
let expected_setter_count = 1
let expected_declaration_count = 81

let fail format =
  Printf.ksprintf
    (fun message -> invalid_arg ("Metal direct property shard: " ^ message))
    format

let reject_duplicate_sdk_ids identifiers =
  let sorted = List.sort String.compare identifiers in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        if String.equal left right then fail "duplicate SDK ID %s" left;
        loop rest
    | [ _ ] | [] -> ()
  in
  loop sorted

let expected_scalar = function
  | "BOOL" -> bool
  | "NSInteger" -> nsint
  | "NSUInteger" -> nsuint
  | "uint32_t" -> uint32
  | "uint64_t" -> uint64
  | "CFTimeInterval" -> double
  | "MTLArgumentBuffersTier" -> mtl_argument_buffers_tier
  | "MTLCommandBufferErrorOption" -> mtl_command_buffer_error_option
  | "MTLDeviceLocation" -> mtl_device_location
  | "MTLDispatchType" -> mtl_dispatch_type
  | "MTLFunctionOptions" -> mtl_function_options
  | "MTLFunctionType" -> mtl_function_type
  | "MTLPatchType" -> mtl_patch_type
  | "MTLReadWriteTextureTier" -> mtl_read_write_texture_tier
  | "MTLResourceOptions" -> mtl_resource_options
  | "MTLShaderValidation" -> mtl_shader_validation
  | signature -> fail "unsupported property scalar signature %s" signature

let validate_getter (entry : property_entry) =
  let getter : method_entry = entry.getter in
  let expected_property_id =
    "property:" ^ entry.owner ^ ":" ^ entry.name
  in
  let expected_getter_id =
    "method:-[" ^ getter.owner ^ " " ^ getter.selector ^ "]"
  in
  if not (String.equal entry.sdk_id expected_property_id) then
    fail "non-canonical property SDK ID %s" entry.sdk_id;
  if not (String.equal getter.sdk_id expected_getter_id) then
    fail "non-canonical getter SDK ID %s" getter.sdk_id;
  if
    not
      (String.equal getter.owner entry.owner
      && String.equal getter.header entry.header
      && getter.attributes = entry.attributes
      && Binding_availability.equal getter.macos_introduced
           entry.macos_introduced)
  then fail "property/getter metadata mismatch for %s" entry.sdk_id;
  if getter.arguments <> [] || getter.semantics <> Query then
    fail "getter shape mismatch for %s" getter.sdk_id;
  match getter.result with
  | None -> fail "getter has no scalar result for %s" getter.sdk_id
  | Some result ->
      if result <> expected_scalar entry.signature then
        fail "property scalar signedness/width mismatch for %s" entry.sdk_id;
      let objc_type = scalar_objc_type result in
      if not (String.equal entry.signature objc_type) then
        fail "property scalar mismatch for %s" entry.sdk_id;
      let expected_signature = "instance () -> " ^ entry.signature in
      if not (String.equal getter.signature expected_signature) then
        fail "getter signature mismatch for %s" getter.sdk_id

let validate_setter (entry : property_entry) =
  match entry.setter, entry.getter.result with
  | None, _ -> ()
  | Some _, None -> fail "writable property has no getter result: %s" entry.sdk_id
  | Some (setter : method_entry), Some result ->
      let expected_setter_id =
        "method:-[" ^ setter.owner ^ " " ^ setter.selector ^ "]"
      in
      if not (String.equal setter.sdk_id expected_setter_id) then
        fail "non-canonical setter SDK ID %s" setter.sdk_id;
      if
        not
          (String.equal setter.owner entry.owner
          && String.equal setter.header entry.header
          && setter.attributes = entry.attributes
          && Binding_availability.equal setter.macos_introduced
               entry.macos_introduced)
      then fail "property/setter metadata mismatch for %s" entry.sdk_id;
      if setter.arguments <> [ result ] || setter.result <> None
         || setter.semantics <> Command
      then fail "setter shape mismatch for %s" setter.sdk_id;
      let expected_signature =
        "instance (" ^ entry.signature ^ ") -> void"
      in
      if not (String.equal setter.signature expected_signature) then
        fail "setter signature mismatch for %s" setter.sdk_id

let validate () =
  if property_count <> expected_property_count then
    fail "expected %d properties, found %d" expected_property_count
      property_count;
  if getter_count <> expected_getter_count then
    fail "expected %d getters, found %d" expected_getter_count getter_count;
  if setter_count <> expected_setter_count then
    fail "expected %d setters, found %d" expected_setter_count setter_count;
  if declaration_count <> expected_declaration_count then
    fail "expected %d declarations, found %d" expected_declaration_count
      declaration_count;
  reject_duplicate_sdk_ids declaration_ids;
  List.iter validate_getter entries;
  List.iter validate_setter entries;
  let setter_ids =
    List.filter_map
      (fun (entry : property_entry) ->
        Option.map (fun (setter : method_entry) -> setter.sdk_id) entry.setter)
      entries
  in
  if
    setter_ids
    <> [ "method:-[MTLDevice setShouldMaximizeConcurrentCompilation:]" ]
  then fail "writable-property setter set drift"

let () = validate ()
