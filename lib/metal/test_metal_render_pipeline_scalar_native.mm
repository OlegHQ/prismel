#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>
#include <type_traits>

template <typename T>
static bool round_trip(T original, T replacement, void (^setter)(T),
                       T (^getter)(void)) {
  setter(replacement);
  const bool matched = getter() == replacement;
  setter(original);
  return matched && getter() == original;
}

#define TYPE_ASSERT(object, property, sdk_type)                                  \
  static_assert(std::is_same_v<decltype((object).property), sdk_type>)

#define ROUND_TRIP(object, property, replacement)                               \
  do {                                                                           \
    const auto original = (object).property;                                     \
    if (!round_trip<decltype(original)>(                                         \
            original, replacement,                                               \
            ^(decltype(original) replacement_value) {                            \
              (object).property = replacement_value;                             \
            },                                                                   \
            ^decltype(original) { return (object).property; }))                   \
      return false;                                                              \
  } while (false)

static bool test_color_attachment() {
  MTLRenderPipelineColorAttachmentDescriptor *value =
      [MTLRenderPipelineColorAttachmentDescriptor new];
  TYPE_ASSERT(value, alphaBlendOperation, MTLBlendOperation);
  TYPE_ASSERT(value, destinationAlphaBlendFactor, MTLBlendFactor);
  TYPE_ASSERT(value, destinationRGBBlendFactor, MTLBlendFactor);
  TYPE_ASSERT(value, pixelFormat, MTLPixelFormat);
  TYPE_ASSERT(value, rgbBlendOperation, MTLBlendOperation);
  TYPE_ASSERT(value, sourceAlphaBlendFactor, MTLBlendFactor);
  TYPE_ASSERT(value, sourceRGBBlendFactor, MTLBlendFactor);
  if (value.pixelFormat != MTLPixelFormatInvalid ||
      value.sourceRGBBlendFactor != MTLBlendFactorOne ||
      value.destinationRGBBlendFactor != MTLBlendFactorZero ||
      value.rgbBlendOperation != MTLBlendOperationAdd ||
      value.sourceAlphaBlendFactor != MTLBlendFactorOne ||
      value.destinationAlphaBlendFactor != MTLBlendFactorZero ||
      value.alphaBlendOperation != MTLBlendOperationAdd)
    return false;
  ROUND_TRIP(value, pixelFormat, MTLPixelFormatBGRA8Unorm);
  ROUND_TRIP(value, sourceRGBBlendFactor, MTLBlendFactorSourceAlpha);
  ROUND_TRIP(value, destinationRGBBlendFactor,
             MTLBlendFactorOneMinusSourceAlpha);
  ROUND_TRIP(value, rgbBlendOperation, MTLBlendOperationSubtract);
  ROUND_TRIP(value, sourceAlphaBlendFactor, MTLBlendFactorSourceAlpha);
  ROUND_TRIP(value, destinationAlphaBlendFactor,
             MTLBlendFactorOneMinusSourceAlpha);
  ROUND_TRIP(value, alphaBlendOperation, MTLBlendOperationMax);
  return true;
}

static bool test_render_descriptor() {
  MTLRenderPipelineDescriptor *value = [MTLRenderPipelineDescriptor new];
  TYPE_ASSERT(value, depthAttachmentPixelFormat, MTLPixelFormat);
  TYPE_ASSERT(value, inputPrimitiveTopology, MTLPrimitiveTopologyClass);
  TYPE_ASSERT(value, maxFragmentCallStackDepth, NSUInteger);
  TYPE_ASSERT(value, maxTessellationFactor, NSUInteger);
  TYPE_ASSERT(value, maxVertexAmplificationCount, NSUInteger);
  TYPE_ASSERT(value, maxVertexCallStackDepth, NSUInteger);
  TYPE_ASSERT(value, rasterSampleCount, NSUInteger);
  TYPE_ASSERT(value, shaderValidation, MTLShaderValidation);
  TYPE_ASSERT(value, stencilAttachmentPixelFormat, MTLPixelFormat);
  TYPE_ASSERT(value, supportAddingFragmentBinaryFunctions, BOOL);
  TYPE_ASSERT(value, supportAddingVertexBinaryFunctions, BOOL);
  TYPE_ASSERT(value, supportIndirectCommandBuffers, BOOL);
  TYPE_ASSERT(value, tessellationControlPointIndexType,
              MTLTessellationControlPointIndexType);
  TYPE_ASSERT(value, tessellationFactorFormat, MTLTessellationFactorFormat);
  TYPE_ASSERT(value, tessellationFactorStepFunction,
              MTLTessellationFactorStepFunction);
  TYPE_ASSERT(value, tessellationOutputWindingOrder, MTLWinding);
  TYPE_ASSERT(value, tessellationPartitionMode, MTLTessellationPartitionMode);
  if (value.depthAttachmentPixelFormat != MTLPixelFormatInvalid ||
      value.stencilAttachmentPixelFormat != MTLPixelFormatInvalid ||
      value.inputPrimitiveTopology != MTLPrimitiveTopologyClassUnspecified ||
      value.maxFragmentCallStackDepth != 1 ||
      value.maxTessellationFactor != 16 ||
      value.maxVertexAmplificationCount != 1 ||
      value.maxVertexCallStackDepth != 1 || value.rasterSampleCount != 1 ||
      value.supportAddingFragmentBinaryFunctions ||
      value.supportAddingVertexBinaryFunctions ||
      value.supportIndirectCommandBuffers ||
      value.tessellationControlPointIndexType !=
          MTLTessellationControlPointIndexTypeNone ||
      value.tessellationFactorFormat != MTLTessellationFactorFormatHalf ||
      value.tessellationFactorStepFunction !=
          MTLTessellationFactorStepFunctionConstant ||
      value.tessellationOutputWindingOrder != MTLWindingClockwise ||
      value.tessellationPartitionMode != MTLTessellationPartitionModePow2)
    return false;
  if (@available(macOS 15.0, *))
    if (value.shaderValidation != MTLShaderValidationDefault)
      return false;
  ROUND_TRIP(value, depthAttachmentPixelFormat, MTLPixelFormatDepth32Float);
  ROUND_TRIP(value, inputPrimitiveTopology, MTLPrimitiveTopologyClassTriangle);
  ROUND_TRIP(value, maxFragmentCallStackDepth, NSUInteger(2));
  ROUND_TRIP(value, maxTessellationFactor, NSUInteger(8));
  ROUND_TRIP(value, maxVertexAmplificationCount, NSUInteger(1));
  ROUND_TRIP(value, maxVertexCallStackDepth, NSUInteger(2));
  ROUND_TRIP(value, rasterSampleCount, NSUInteger(1));
  ROUND_TRIP(value, stencilAttachmentPixelFormat, MTLPixelFormatStencil8);
  ROUND_TRIP(value, supportAddingFragmentBinaryFunctions, YES);
  ROUND_TRIP(value, supportAddingVertexBinaryFunctions, YES);
  ROUND_TRIP(value, supportIndirectCommandBuffers, YES);
  ROUND_TRIP(value, tessellationControlPointIndexType,
             MTLTessellationControlPointIndexTypeUInt16);
  ROUND_TRIP(value, tessellationFactorFormat, MTLTessellationFactorFormatHalf);
  ROUND_TRIP(value, tessellationFactorStepFunction,
             MTLTessellationFactorStepFunctionPerPatch);
  ROUND_TRIP(value, tessellationOutputWindingOrder, MTLWindingCounterClockwise);
  ROUND_TRIP(value, tessellationPartitionMode,
             MTLTessellationPartitionModeFractionalEven);
  if (@available(macOS 15.0, *))
    ROUND_TRIP(value, shaderValidation, MTLShaderValidationEnabled);
  return true;
}

static bool test_mesh_descriptor() {
  if (@available(macOS 13.0, *)) {
    MTLMeshRenderPipelineDescriptor *value =
        [MTLMeshRenderPipelineDescriptor new];
    TYPE_ASSERT(value, depthAttachmentPixelFormat, MTLPixelFormat);
    TYPE_ASSERT(value, maxTotalThreadgroupsPerMeshGrid, NSUInteger);
    TYPE_ASSERT(value, maxTotalThreadsPerMeshThreadgroup, NSUInteger);
    TYPE_ASSERT(value, maxTotalThreadsPerObjectThreadgroup, NSUInteger);
    TYPE_ASSERT(value, maxVertexAmplificationCount, NSUInteger);
    TYPE_ASSERT(value, meshThreadgroupSizeIsMultipleOfThreadExecutionWidth,
                BOOL);
    TYPE_ASSERT(value, objectThreadgroupSizeIsMultipleOfThreadExecutionWidth,
                BOOL);
    TYPE_ASSERT(value, payloadMemoryLength, NSUInteger);
    TYPE_ASSERT(value, rasterSampleCount, NSUInteger);
    TYPE_ASSERT(value, shaderValidation, MTLShaderValidation);
    TYPE_ASSERT(value, stencilAttachmentPixelFormat, MTLPixelFormat);
    TYPE_ASSERT(value, supportIndirectCommandBuffers, BOOL);
    if (value.depthAttachmentPixelFormat != MTLPixelFormatInvalid ||
        value.maxTotalThreadgroupsPerMeshGrid != 0 ||
        value.maxTotalThreadsPerMeshThreadgroup != 0 ||
        value.maxTotalThreadsPerObjectThreadgroup != 0 ||
        value.maxVertexAmplificationCount != 1 ||
        value.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth ||
        value.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth ||
        value.payloadMemoryLength != 0 || value.rasterSampleCount != 1 ||
        value.stencilAttachmentPixelFormat != MTLPixelFormatInvalid ||
        value.supportIndirectCommandBuffers)
      return false;
    if (@available(macOS 15.0, *))
      if (value.shaderValidation != MTLShaderValidationDefault)
        return false;
    ROUND_TRIP(value, depthAttachmentPixelFormat, MTLPixelFormatDepth32Float);
    ROUND_TRIP(value, maxTotalThreadgroupsPerMeshGrid, NSUInteger(2));
    ROUND_TRIP(value, maxTotalThreadsPerMeshThreadgroup, NSUInteger(32));
    ROUND_TRIP(value, maxTotalThreadsPerObjectThreadgroup, NSUInteger(32));
    ROUND_TRIP(value, maxVertexAmplificationCount, NSUInteger(1));
    ROUND_TRIP(value, meshThreadgroupSizeIsMultipleOfThreadExecutionWidth, YES);
    ROUND_TRIP(value, objectThreadgroupSizeIsMultipleOfThreadExecutionWidth,
               YES);
    ROUND_TRIP(value, payloadMemoryLength, NSUInteger(16));
    ROUND_TRIP(value, rasterSampleCount, NSUInteger(1));
    ROUND_TRIP(value, stencilAttachmentPixelFormat, MTLPixelFormatStencil8);
    if (@available(macOS 14.0, *))
      ROUND_TRIP(value, supportIndirectCommandBuffers, YES);
    if (@available(macOS 15.0, *))
      ROUND_TRIP(value, shaderValidation, MTLShaderValidationEnabled);
  }
  return true;
}

static bool test_tile_descriptor() {
  if (@available(macOS 11.0, *)) {
    MTLTileRenderPipelineDescriptor *value =
        [MTLTileRenderPipelineDescriptor new];
    TYPE_ASSERT(value, maxCallStackDepth, NSUInteger);
    TYPE_ASSERT(value, maxTotalThreadsPerThreadgroup, NSUInteger);
    TYPE_ASSERT(value, rasterSampleCount, NSUInteger);
    TYPE_ASSERT(value, shaderValidation, MTLShaderValidation);
    TYPE_ASSERT(value, supportAddingBinaryFunctions, BOOL);
    TYPE_ASSERT(value, threadgroupSizeMatchesTileSize, BOOL);
    if (value.maxCallStackDepth != 1 ||
        value.maxTotalThreadsPerThreadgroup != 0 ||
        value.rasterSampleCount != 1 || value.supportAddingBinaryFunctions ||
        value.threadgroupSizeMatchesTileSize)
      return false;
    if (@available(macOS 15.0, *))
      if (value.shaderValidation != MTLShaderValidationDefault)
        return false;
    ROUND_TRIP(value, maxTotalThreadsPerThreadgroup, NSUInteger(32));
    ROUND_TRIP(value, rasterSampleCount, NSUInteger(1));
    ROUND_TRIP(value, threadgroupSizeMatchesTileSize, YES);
    if (@available(macOS 12.0, *)) {
      ROUND_TRIP(value, maxCallStackDepth, NSUInteger(2));
      ROUND_TRIP(value, supportAddingBinaryFunctions, YES);
    }
    if (@available(macOS 15.0, *))
      ROUND_TRIP(value, shaderValidation, MTLShaderValidationEnabled);
  }
  return true;
}

static bool test_real_pipeline(id<MTLDevice> device) {
  static NSString *source =
      @"#include <metal_stdlib>\n"
       "using namespace metal;\n"
       "vertex float4 rp_vertex(uint i [[vertex_id]]) {\n"
       "  const float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};\n"
       "  return float4(p[i],0,1);\n"
       "}\n"
       "fragment float4 rp_fragment() { return float4(0.25,0.5,0.75,1); }\n";
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:source
                                               options:nil
                                                 error:&error];
  if (library == nil || error != nil)
    return false;
  MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:@"rp_vertex"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"rp_fragment"];
  descriptor.rasterSampleCount = 1;
  descriptor.maxVertexAmplificationCount = 1;
  descriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
  descriptor.colorAttachments[0].destinationRGBBlendFactor =
      MTLBlendFactorZero;
  descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
  descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  descriptor.colorAttachments[0].destinationAlphaBlendFactor =
      MTLBlendFactorZero;
  descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
  error = nil;
  id<MTLRenderPipelineState> pipeline =
      [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (pipeline == nil || error != nil || pipeline.device.registryID != device.registryID)
    return false;

  MTLRenderPipelineDescriptor *invalid = [descriptor copy];
  invalid.rasterSampleCount = 3;
  error = nil;
  id<MTLRenderPipelineState> rejected =
      [device newRenderPipelineStateWithDescriptor:invalid error:&error];
  return rejected == nil && error != nil && error.localizedDescription.length > 0;
}

static bool test_pipeline_release(id<MTLDevice> device) {
  __weak id<MTLRenderPipelineState> weak_pipeline = nil;
  @autoreleasepool {
    NSError *error = nil;
    id<MTLLibrary> library = [device
        newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
                              "vertex float4 v(uint i [[vertex_id]]) { return float4(float(i),0,0,1); }\n"
                              "fragment float4 f() { return float4(1); }\n"
                     options:nil
                       error:&error];
    if (library == nil || error != nil)
      return false;
    MTLRenderPipelineDescriptor *descriptor =
        [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"v"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"f"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (pipeline == nil || error != nil)
      return false;
    weak_pipeline = pipeline;
  }
  return weak_pipeline == nil;
}

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) {
      std::fprintf(stderr, "Metal device unavailable\n");
      return 77;
    }
    if (!test_color_attachment() || !test_render_descriptor() ||
        !test_mesh_descriptor() || !test_tile_descriptor() ||
        !test_real_pipeline(device) || !test_pipeline_release(device)) {
      std::fprintf(stderr, "render-pipeline scalar conformance failed\n");
      return 1;
    }
    std::printf("render-pipeline scalar conformance passed on %s\n",
                device.name.UTF8String);
  }
  return 0;
}
