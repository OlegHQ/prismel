open Binding_string_spec

let a = [ "AvailabilityAttr" ]

let p ?(attributes = []) ?setter owner name header signature introduced =
  entry ~attributes ?setter ~owner ~name ~header ~signature
    ~macos_introduced:introduced ()

let entries =
  [ p ~setter:true "MTL4AccelerationStructureGeometryDescriptor" "label" "Metal/MTL4AccelerationStructure.h" "NSString * _Nullable" "26.0"
  ; p "MTL4BinaryFunction" "name" "Metal/MTL4BinaryFunction.h" "NSString * _Nullable" "26.0"
  ; p ~setter:true "MTL4CounterHeap" "label" "Metal/MTL4Counters.h" "NSString * _Nullable" "26.0"
  ; p ~setter:true "MTL4MachineLearningPipelineDescriptor" "label" "Metal/MTL4MachineLearningPipeline.h" "NSString * _Nullable" "26.0"
  ; p "MTL4MachineLearningPipelineState" "label" "Metal/MTL4MachineLearningPipeline.h" "NSString * _Nullable" "26.0"
  ; p ~setter:true "MTL4SpecializedFunctionDescriptor" "specializedName" "Metal/MTL4SpecializedFunctionDescriptor.h" "NSString * _Nullable" "26.0"
  ; p ~attributes:a ~setter:true "MTLAccelerationStructureGeometryDescriptor" "label" "Metal/MTLAccelerationStructure.h" "NSString * _Nullable" "12.0"
  ; p "MTLArchitecture" "name" "Metal/MTLDevice.h" "NSString * _Nonnull" "14.0"
  ; p "MTLArgument" "name" "Metal/MTLArgument.h" "NSString * _Nonnull" "10.11"
  ; p ~setter:true "MTLArgumentEncoder" "label" "Metal/MTLArgumentEncoder.h" "NSString * _Nullable" "10.13"
  ; p "MTLAttribute" "name" "Metal/MTLLibrary.h" "NSString * _Nonnull" "10.12"
  ; p ~setter:true "MTLCaptureScope" "label" "Metal/MTLCaptureScope.h" "NSString * _Nullable" "10.13"
  ; p "MTLCommandBufferEncoderInfo" "label" "Metal/MTLCommandBuffer.h" "NSString * _Nonnull" "11.0"
  ; p ~setter:true "MTLCommandEncoder" "label" "Metal/MTLCommandEncoder.h" "NSString * _Nullable" "10.11"
  ; p ~setter:true "MTLCommandQueue" "label" "Metal/MTLCommandQueue.h" "NSString * _Nullable" "10.11"
  ; p ~attributes:a "MTLCounter" "name" "Metal/MTLCounters.h" "NSString * _Nonnull" "10.15"
  ; p ~attributes:a "MTLCounterSampleBuffer" "label" "Metal/MTLCounters.h" "NSString * _Nonnull" "10.15"
  ; p ~attributes:a ~setter:true "MTLCounterSampleBufferDescriptor" "label" "Metal/MTLCounters.h" "NSString * _Nonnull" "10.15"
  ; p ~attributes:a "MTLCounterSet" "name" "Metal/MTLCounters.h" "NSString * _Nonnull" "10.15"
  ; p ~setter:true "MTLEvent" "label" "Metal/MTLEvent.h" "NSString * _Nullable" "10.14"
  ; p ~setter:true "MTLFence" "label" "Metal/MTLFence.h" "NSString * _Nullable" "10.13"
  ; p ~setter:true "MTLFunctionDescriptor" "name" "Metal/MTLFunctionDescriptor.h" "NSString * _Nullable" "11.0"
  ; p ~setter:true "MTLFunctionDescriptor" "specializedName" "Metal/MTLFunctionDescriptor.h" "NSString * _Nullable" "11.0"
  ; p "MTLFunctionHandle" "name" "Metal/MTLFunctionHandle.h" "NSString * _Nonnull" "11.0"
  ; p "MTLFunctionLog" "encoderLabel" "Metal/MTLFunctionLog.h" "NSString * _Nullable" "11.0"
  ; p "MTLFunctionLogDebugLocation" "functionName" "Metal/MTLFunctionLog.h" "NSString * _Nullable" "11.0"
  ; p ~attributes:a "MTLFunctionReflection" "userAnnotation" "Metal/MTLLibrary.h" "NSString * _Nullable" "26.0"
  ; p ~setter:true "MTLFunctionStitchingFunctionNode" "name" "Metal/MTLFunctionStitching.h" "NSString * _Nonnull" "12.0"
  ; p ~setter:true "MTLFunctionStitchingGraph" "functionName" "Metal/MTLFunctionStitching.h" "NSString * _Nonnull" "12.0"
  ; p ~setter:true "MTLIOCommandBuffer" "label" "Metal/MTLIOCommandBuffer.h" "NSString * _Nullable" "13.0"
  ; p ~setter:true "MTLIOCommandQueue" "label" "Metal/MTLIOCommandQueue.h" "NSString * _Nullable" "13.0"
  ; p ~setter:true "MTLIOFileHandle" "label" "Metal/MTLIOCommandQueue.h" "NSString * _Nullable" "13.0"
  ; p ~setter:true "MTLMeshRenderPipelineDescriptor" "label" "Metal/MTLRenderPipeline.h" "NSString * _Nullable" "13.0"
  ; p "MTLRasterizationRateMap" "label" "Metal/MTLRasterizationRate.h" "NSString * _Nullable" "10.15.4"
  ; p ~setter:true "MTLRasterizationRateMapDescriptor" "label" "Metal/MTLRasterizationRate.h" "NSString * _Nullable" "10.15.4"
  ; p ~setter:true "MTLRenderPipelineDescriptor" "label" "Metal/MTLRenderPipeline.h" "NSString * _Nullable" "10.11"
  ; p "MTLResourceViewPool" "label" "Metal/MTLResourceViewPool.h" "NSString * _Nullable" "26.0"
  ; p ~setter:true "MTLResourceViewPoolDescriptor" "label" "Metal/MTLResourceViewPool.h" "NSString * _Nullable" "26.0"
  ; p "MTLSharedEventHandle" "label" "Metal/MTLEvent.h" "NSString * _Nullable" "10.14"
  ; p "MTLStructMember" "name" "Metal/MTLArgument.h" "NSString * _Nonnull" "10.11"
  ; p ~setter:true "MTLTileRenderPipelineDescriptor" "label" "Metal/MTLRenderPipeline.h" "NSString * _Nullable" "11.0"
  ; p "MTLVertexAttribute" "name" "Metal/MTLLibrary.h" "NSString * _Nonnull" "10.11"
  ]

let expected_property_count = 42
let expected_getter_count = 42
let expected_setter_count = 24
let expected_inventory_id_count = 108

