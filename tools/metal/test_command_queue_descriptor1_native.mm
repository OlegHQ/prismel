#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kIds[] = {"class:MTLCommandQueueDescriptor"};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 1,
              "CommandQueueDescriptor1 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  MTLCommandQueueDescriptor *descriptor = [MTLCommandQueueDescriptor new];
  if (!descriptor) return 1;
  descriptor.maxCommandBufferCount = 4;
  descriptor.logState = nil;
  if (descriptor.maxCommandBufferCount != 4 || descriptor.logState != nil)
    return 2;
  id<MTLCommandQueue> queue = nil;
  @try { queue = [device newCommandQueueWithDescriptor:descriptor]; }
  @catch (NSException *exception) {
    if (![exception.name isEqualToString:NSInvalidArgumentException]) return 3;
    return 77;
  }
  if (!queue || queue.device.registryID != device.registryID) return 4;
  descriptor.maxCommandBufferCount = 1;
  /* Queue construction snapshots descriptor policy; caller mutation and
     release must not invalidate the queue. */
  descriptor = nil;
  id<MTLCommandBuffer> command = [queue commandBuffer];
  id<MTLBlitCommandEncoder> encoder = [command blitCommandEncoder];
  id<MTLBuffer> buffer = [device newBufferWithLength:16
    options:MTLResourceStorageModeShared];
  [encoder fillBuffer:buffer range:NSMakeRange(0,16) value:0xd1];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted) return 5;
  const uint8_t *bytes = static_cast<const uint8_t *>(buffer.contents);
  for (NSUInteger index=0; index<16; ++index) if (bytes[index] != 0xd1) return 6;
  return 0;
} }
