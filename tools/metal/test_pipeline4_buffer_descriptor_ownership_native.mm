#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>

static const char *const kIds[] = {
  "class:MTLPipelineBufferDescriptor",
  "class:MTLPipelineBufferDescriptorArray",
  "method:-[MTLPipelineBufferDescriptorArray objectAtIndexedSubscript:]",
  "method:-[MTLPipelineBufferDescriptorArray setObject:atIndexedSubscript:]",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 4,
              "Pipeline4 buffer descriptor closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  MTLComputePipelineDescriptor *pipeline_descriptor =
    [MTLComputePipelineDescriptor new];
  MTLPipelineBufferDescriptorArray *array = pipeline_descriptor.buffers;
  if (!array || !array[0]) return 1;
  MTLPipelineBufferDescriptor *source = [MTLPipelineBufferDescriptor new];
  source.mutability = MTLMutabilityImmutable;
  __weak MTLPipelineBufferDescriptor *weak_source = source;
  array[0] = source;
  MTLPipelineBufferDescriptor *stored = array[0];
  if (!stored || stored == source || stored.mutability != MTLMutabilityImmutable)
    return 2;
  source.mutability = MTLMutabilityMutable;
  if (stored.mutability != MTLMutabilityImmutable) return 3;
  source = nil;
  if (weak_source != nil) return 4;
  array[0] = nil;
  if (!array[0] || array[0].mutability != MTLMutabilityDefault) return 5;

  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:
    @"#include <metal_stdlib>\nusing namespace metal; kernel void p4(device uint *x [[buffer(0)]]) { x[0]=4; }"
    options:nil error:&error];
  if (!library) return 77;
  pipeline_descriptor.computeFunction = [library newFunctionWithName:@"p4"];
  pipeline_descriptor.buffers[0].mutability = MTLMutabilityImmutable;
  id<MTLComputePipelineState> pipeline =
    [device newComputePipelineStateWithDescriptor:pipeline_descriptor
      options:MTLPipelineOptionNone reflection:nil error:&error];
  if (!pipeline) return 6;
  id<MTLBuffer> output = [device newBufferWithLength:sizeof(uint32_t)
    options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:pipeline]; [encoder setBuffer:output offset:0 atIndex:0];
  [encoder dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted ||
      *static_cast<uint32_t *>(output.contents) != 4) return 7;
  return 0;
} }
