#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

/* This closure intentionally qualifies legacy selectors that Apple replaced
   but still ships.  Keep every other diagnostic under -Werror. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const char *const kIds[] = {
  "method:-[MTLComputePipelineDescriptor buffers]",
  "method:-[MTLComputePipelineDescriptor insertLibraries]",
  "method:-[MTLComputePipelineDescriptor setInsertLibraries:]",
  "method:-[MTLComputePipelineReflection arguments]",
  "method:-[MTLComputePipelineState functionHandleWithBinaryFunction:]",
  "method:-[MTLComputePipelineState functionHandleWithName:]",
  "method:-[MTLComputePipelineState newComputePipelineStateWithAdditionalBinaryFunctions:error:]",
  "method:-[MTLComputePipelineState newComputePipelineStateWithBinaryFunctions:error:]",
  "property:MTLComputePipelineDescriptor:buffers",
  "property:MTLComputePipelineDescriptor:insertLibraries",
  "property:MTLComputePipelineReflection:arguments",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 11,
              "ComputePipeline11 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  NSError *error = nil;
  NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
    "kernel void cp11(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = i + 7; }";
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library) return 77;
  id<MTLFunction> function = [library newFunctionWithName:@"cp11"];
  if (!function) return 1;

  MTLComputePipelineDescriptor *descriptor = [MTLComputePipelineDescriptor new];
  descriptor.computeFunction = function;
  descriptor.label = @"compute-pipeline11";
  descriptor.buffers[0].mutability = MTLMutabilityImmutable;
  descriptor.insertLibraries = @[];
  if (descriptor.buffers == nil || descriptor.insertLibraries.count != 0) return 2;
  descriptor.insertLibraries = nil;
  if (descriptor.insertLibraries != nil && descriptor.insertLibraries.count != 0)
    return 3;

  MTLComputePipelineReflection *reflection = nil;
  id<MTLComputePipelineState> pipeline =
    [device newComputePipelineStateWithDescriptor:descriptor
      options:MTLPipelineOptionArgumentInfo reflection:&reflection error:&error];
  if (!pipeline) return 77;
  if (reflection == nil || reflection.arguments.count == 0) return 4;
  bool found_buffer = false;
  for (MTLArgument *argument in reflection.arguments)
    if (argument.type == MTLArgumentTypeBuffer && argument.index == 0) found_buffer = true;
  if (!found_buffer) return 5;

  id<MTLFunctionHandle> named = [pipeline functionHandleWithName:@"cp11"];
  if (named != nil && (named.device.registryID != device.registryID ||
                       ![named.name isEqualToString:@"cp11"])) return 6;

  NSError *relink_error = nil;
  id<MTLComputePipelineState> relinked =
    [pipeline newComputePipelineStateWithAdditionalBinaryFunctions:@[] error:&relink_error];
  if ((relinked == nil) == (relink_error == nil)) return 7;
  if (relinked && relinked.device.registryID != device.registryID) return 8;

  /* MTL4 binary functions require a separately constructed MTL4 compiler
     graph.  Exercise the selector only when that graph is available; passing
     fabricated objects would invalidate ownership evidence. */
  if (@available(macOS 26.0, *)) {
    NSError *binary_error = nil;
    id<MTLComputePipelineState> binary =
      [pipeline newComputePipelineStateWithBinaryFunctions:@[] error:&binary_error];
    if ((binary == nil) == (binary_error == nil)) return 9;
    if (binary && binary.device.registryID != device.registryID) return 10;
  }

  id<MTLBuffer> output = [device newBufferWithLength:4 * sizeof(uint32_t)
                                             options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:pipeline]; [encoder setBuffer:output offset:0 atIndex:0];
  [encoder dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  uint32_t *values = static_cast<uint32_t *>(output.contents);
  if (command.status != MTLCommandBufferStatusCompleted || values[0] != 7 || values[3] != 10)
    return 11;
  return 0;
} }
#pragma clang diagnostic pop
