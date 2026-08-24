#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {
  "method:-[MTLCommandEncoder barrierAfterQueueStages:beforeStages:]",
  "method:-[MTLCommandEncoder device]",
  "method:-[MTLCommandEncoder insertDebugSignpost:]",
  "method:-[MTLCommandEncoder label]",
  "method:-[MTLCommandEncoder popDebugGroup]",
  "method:-[MTLCommandEncoder pushDebugGroup:]",
  "method:-[MTLCommandEncoder setLabel:]",
  "property:MTLCommandEncoder:device",
  "property:MTLCommandEncoder:label",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 9,
              "CommandEncoder9 exact closure drift");

static int exercise(id<MTLCommandEncoder> encoder, id<MTLDevice> device,
                    NSString *label, bool stages) {
  if (encoder == nil || encoder.device.registryID != device.registryID) return 1;
  encoder.label = label;
  if (![encoder.label isEqualToString:label]) return 2;
  [encoder insertDebugSignpost:@"command-encoder9-signpost"];
  [encoder pushDebugGroup:@"outer"];
  [encoder pushDebugGroup:@"inner"];
  if (stages &&
      [encoder respondsToSelector:@selector(barrierAfterQueueStages:beforeStages:)])
    [encoder barrierAfterQueueStages:MTLStageDispatch beforeStages:MTLStageDispatch];
  [encoder popDebugGroup]; [encoder popDebugGroup];
  encoder.label = nil;
  if (encoder.label != nil) return 3;
  return 0;
}

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  id<MTLCommandQueue> queue = [device newCommandQueue]; if (!queue) return 77;
  for (NSUInteger iteration = 0; iteration < 256; ++iteration) {
    @autoreleasepool {
      id<MTLCommandBuffer> command = [queue commandBuffer];
      id<MTLComputeCommandEncoder> compute = [command computeCommandEncoder];
      int result = exercise(compute, device, @"compute", true);
      if (result) return result; [compute endEncoding];
      id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
      result = exercise(blit, device, @"blit", false);
      if (result) return result + 3; [blit endEncoding];
      MTLResourceStatePassDescriptor *pass =
        [MTLResourceStatePassDescriptor resourceStatePassDescriptor];
      id<MTLResourceStateCommandEncoder> resource =
        [command resourceStateCommandEncoderWithDescriptor:pass];
      if (resource != nil) {
        result = exercise(resource, device, @"resource-state", false);
        if (result) return result + 6; [resource endEncoding];
      }
      [command commit]; [command waitUntilCompleted];
      if (command.status != MTLCommandBufferStatusCompleted) return 10;
    }
  }
  return 0;
} }
