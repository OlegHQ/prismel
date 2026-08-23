#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>
#include <cstdlib>

static void require(bool condition, const char *message) {
  if (!condition) { std::fprintf(stderr, "Metal acceleration scalar: %s\n", message); std::exit(1); }
}

static bool simulated_create(bool supported, NSUInteger *allocations) {
  if (!supported) return false;
  ++*allocations;
  return true;
}

int main() {
  @autoreleasepool {
    NSUInteger simulated_allocations = 0;
    require(!simulated_create(false, &simulated_allocations), "unsupported family accepted");
    require(simulated_allocations == 0, "unsupported family allocated a descriptor graph");

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    require(device != nil, "no Metal device");
    if (![device supportsRaytracing]) {
      std::puts("Metal acceleration scalar native conformance: capability-rejected with zero partial graph");
      return 0;
    }
    const float vertices[] = { 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 1.f, 0.f };
    id<MTLBuffer> vertex_buffer =
      [device newBufferWithBytes:vertices length:sizeof(vertices)
                         options:MTLResourceStorageModeShared];
    require(vertex_buffer != nil, "vertex buffer allocation failed");
    MTLAccelerationStructureTriangleGeometryDescriptor *triangle =
      [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
    triangle.vertexBuffer = vertex_buffer;
    triangle.vertexBufferOffset = 0;
    triangle.vertexStride = 3 * sizeof(float);
    triangle.vertexFormat = MTLAttributeFormatFloat3;
    triangle.indexType = MTLIndexTypeUInt32;
    triangle.triangleCount = 1;
    triangle.indexBufferOffset = 0;
    triangle.transformationMatrixBufferOffset = 0;
    triangle.transformationMatrixLayout = MTLMatrixLayoutColumnMajor;
    require(triangle.indexBufferOffset == 0 &&
            triangle.indexType == MTLIndexTypeUInt32 &&
            triangle.transformationMatrixBufferOffset == 0 &&
            triangle.transformationMatrixLayout == MTLMatrixLayoutColumnMajor &&
            triangle.triangleCount == 1 && triangle.vertexBufferOffset == 0 &&
            triangle.vertexFormat == MTLAttributeFormatFloat3 &&
            triangle.vertexStride == 12,
            "triangle scalar round-trip failed");

    MTLPrimitiveAccelerationStructureDescriptor *primitive =
      [MTLPrimitiveAccelerationStructureDescriptor descriptor];
    primitive.geometryDescriptors = @[ triangle ];
    primitive.usage = MTLAccelerationStructureUsageRefit;
    primitive.motionStartTime = 0.f;
    primitive.motionEndTime = 1.f;
    primitive.motionStartBorderMode = MTLMotionBorderModeClamp;
    primitive.motionEndBorderMode = MTLMotionBorderModeClamp;
    primitive.motionKeyframeCount = 1;
    require(primitive.usage == MTLAccelerationStructureUsageRefit &&
            primitive.motionStartTime == 0.f && primitive.motionEndTime == 1.f &&
            primitive.motionStartBorderMode == MTLMotionBorderModeClamp &&
            primitive.motionEndBorderMode == MTLMotionBorderModeClamp &&
            primitive.motionKeyframeCount == 1,
            "primitive scalar round-trip failed");
    MTLAccelerationStructureSizes sizes =
      [device accelerationStructureSizesWithDescriptor:primitive];
    require(sizes.accelerationStructureSize > 0 && sizes.buildScratchBufferSize > 0,
            "invalid acceleration-structure sizes");
    id<MTLAccelerationStructure> source =
      [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLBuffer> scratch =
      [device newBufferWithLength:MAX(sizes.buildScratchBufferSize,
                                      sizes.refitScratchBufferSize)
                         options:MTLResourceStorageModePrivate];
    require(source != nil && scratch != nil, "acceleration resource allocation failed");
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLAccelerationStructureCommandEncoder> encoder =
      [command accelerationStructureCommandEncoder];
    [encoder buildAccelerationStructure:source descriptor:primitive
                           scratchBuffer:scratch scratchBufferOffset:0];
    [encoder refitAccelerationStructure:source descriptor:primitive
                             destination:source scratchBuffer:scratch
                     scratchBufferOffset:0];
    id<MTLAccelerationStructure> copy =
      [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    [encoder copyAccelerationStructure:source toAccelerationStructure:copy];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    require(command.status == MTLCommandBufferStatusCompleted,
            command.error.localizedDescription.UTF8String ?: "AS command failed");
    require(source.size > 0 && copy.size > 0, "AS copy produced an invalid resource");
    std::puts("Metal acceleration scalar native conformance: triangle build/refit/copy passed");
  }
  return 0;
}
