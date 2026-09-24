#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>

static const char *const kAccelerationCommand32Ids[] = {
    "class:MTLAccelerationStructurePassDescriptor",
    "class:MTLAccelerationStructurePassSampleBufferAttachmentDescriptor",
    "class:MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray",
    "method:+[MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor]",
    "method:-[MTLAccelerationStructureCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:scratchBufferOffset:]",
    "method:-[MTLAccelerationStructureCommandEncoder copyAccelerationStructure:toAccelerationStructure:]",
    "method:-[MTLAccelerationStructureCommandEncoder copyAndCompactAccelerationStructure:toAccelerationStructure:]",
    "method:-[MTLAccelerationStructureCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:scratchBufferOffset:]",
    "method:-[MTLAccelerationStructureCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:scratchBufferOffset:options:]",
    "method:-[MTLAccelerationStructureCommandEncoder sampleCountersInBuffer:atSampleIndex:withBarrier:]",
    "method:-[MTLAccelerationStructureCommandEncoder updateFence:]",
    "method:-[MTLAccelerationStructureCommandEncoder useHeap:]",
    "method:-[MTLAccelerationStructureCommandEncoder useHeaps:count:]",
    "method:-[MTLAccelerationStructureCommandEncoder useResource:usage:]",
    "method:-[MTLAccelerationStructureCommandEncoder useResources:count:usage:]",
    "method:-[MTLAccelerationStructureCommandEncoder waitForFence:]",
    "method:-[MTLAccelerationStructureCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:offset:]",
    "method:-[MTLAccelerationStructureCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:offset:sizeDataType:]",
    "method:-[MTLAccelerationStructurePassDescriptor sampleBufferAttachments]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor endOfEncoderSampleIndex]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor sampleBuffer]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor setEndOfEncoderSampleIndex:]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor setSampleBuffer:]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor setStartOfEncoderSampleIndex:]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptor startOfEncoderSampleIndex]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray objectAtIndexedSubscript:]",
    "method:-[MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray setObject:atIndexedSubscript:]",
    "property:MTLAccelerationStructurePassDescriptor:sampleBufferAttachments",
    "property:MTLAccelerationStructurePassSampleBufferAttachmentDescriptor:endOfEncoderSampleIndex",
    "property:MTLAccelerationStructurePassSampleBufferAttachmentDescriptor:sampleBuffer",
    "property:MTLAccelerationStructurePassSampleBufferAttachmentDescriptor:startOfEncoderSampleIndex",
    "protocol:MTLAccelerationStructureCommandEncoder",
};
static_assert(sizeof(kAccelerationCommand32Ids) /
                      sizeof(kAccelerationCommand32Ids[0]) ==
                  32,
              "AccelerationCommand32 exact closure drift");

int main() {
  @autoreleasepool {
    (void)kAccelerationCommand32Ids;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    if (![device supportsRaytracing]) return 77;

    const float vertices[] = {0.0f, 0.0f, 0.0f, 1.0f, 0.0f,
                              0.0f, 0.0f, 1.0f, 0.0f};
    id<MTLBuffer> vertex =
        [device newBufferWithBytes:vertices
                            length:sizeof(vertices)
                           options:MTLResourceStorageModeShared];
    MTLAccelerationStructureTriangleGeometryDescriptor *geometry =
        [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
    geometry.vertexBuffer = vertex;
    geometry.vertexStride = 3 * sizeof(float);
    geometry.vertexFormat = MTLAttributeFormatFloat3;
    geometry.triangleCount = 1;
    MTLPrimitiveAccelerationStructureDescriptor *descriptor =
        [MTLPrimitiveAccelerationStructureDescriptor descriptor];
    descriptor.geometryDescriptors = @[ geometry ];
    MTLAccelerationStructureSizes sizes =
        [device accelerationStructureSizesWithDescriptor:descriptor];
    if (sizes.accelerationStructureSize == 0 || sizes.buildScratchBufferSize == 0)
      return 1;

    id<MTLAccelerationStructure> source =
        [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLAccelerationStructure> copy =
        [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLAccelerationStructure> refit =
        [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLBuffer> scratch =
        [device newBufferWithLength:MAX(sizes.buildScratchBufferSize,
                                        sizes.refitScratchBufferSize)
                          options:MTLResourceStorageModePrivate];
    id<MTLBuffer> compacted_sizes =
        [device newBufferWithLength:16 options:MTLResourceStorageModeShared];
    id<MTLFence> fence = [device newFence];
    MTLHeapDescriptor *heap_descriptor = [MTLHeapDescriptor new];
    heap_descriptor.size = 4096;
    heap_descriptor.storageMode = MTLStorageModePrivate;
    id<MTLHeap> heap = [device newHeapWithDescriptor:heap_descriptor];
    if (!source || !copy || !refit || !scratch || !compacted_sizes || !fence ||
        !heap)
      return 2;

    MTLAccelerationStructurePassDescriptor *pass =
        [MTLAccelerationStructurePassDescriptor accelerationStructurePassDescriptor];
    MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *sample =
        pass.sampleBufferAttachments[0];
    sample.startOfEncoderSampleIndex = 0;
    sample.endOfEncoderSampleIndex = 1;
    sample.sampleBuffer = nil;
    pass.sampleBufferAttachments[0] = sample;
    if (pass.sampleBufferAttachments[0].startOfEncoderSampleIndex != 0 ||
        pass.sampleBufferAttachments[0].endOfEncoderSampleIndex != 1 ||
        pass.sampleBufferAttachments[0].sampleBuffer != nil) return 3;

    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLAccelerationStructureCommandEncoder> encoder =
        [command accelerationStructureCommandEncoderWithDescriptor:pass];
    if (encoder == nil) return 4;
    [encoder useResource:vertex usage:MTLResourceUsageRead];
    id<MTLResource> resources[] = {scratch, compacted_sizes};
    [encoder useResources:resources count:2 usage:MTLResourceUsageRead | MTLResourceUsageWrite];
    [encoder useHeap:heap];
    id<MTLHeap> heaps[] = {heap};
    [encoder useHeaps:heaps count:1];
    [encoder buildAccelerationStructure:source descriptor:descriptor
                           scratchBuffer:scratch scratchBufferOffset:0];
    [encoder copyAccelerationStructure:source toAccelerationStructure:copy];
    [encoder refitAccelerationStructure:source descriptor:descriptor
                              destination:refit scratchBuffer:scratch
                     scratchBufferOffset:0];
    [encoder refitAccelerationStructure:source descriptor:descriptor
                              destination:refit scratchBuffer:scratch
                     scratchBufferOffset:0
                                  options:MTLAccelerationStructureRefitOptionVertexData];
    [encoder updateFence:fence];
    [encoder waitForFence:fence];
    [encoder writeCompactedAccelerationStructureSize:source
                                             toBuffer:compacted_sizes offset:0];
    [encoder writeCompactedAccelerationStructureSize:source
                                             toBuffer:compacted_sizes offset:8
                                         sizeDataType:MTLDataTypeULong];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted) return 5;
    uint64_t compacted = 0;
    __builtin_memcpy(&compacted, (uint8_t *)compacted_sizes.contents + 8,
                     sizeof(compacted));
    if (compacted == 0 || compacted > sizes.accelerationStructureSize) return 6;
  }
  return 0;
}
