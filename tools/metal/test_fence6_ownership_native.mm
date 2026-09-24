#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>

static const char *const kIds[] = {
  "method:-[MTLFence device]", "method:-[MTLFence label]",
  "method:-[MTLFence setLabel:]", "property:MTLFence:device",
  "property:MTLFence:label", "protocol:MTLFence",
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 6,
              "Fence6 exact closure drift");

int main() { @autoreleasepool {
  (void)kIds;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice(); if (!device) return 77;
  id<MTLCommandQueue> queue = [device newCommandQueue]; if (!queue) return 77;
  for (NSUInteger iteration = 0; iteration < 256; ++iteration) {
    @autoreleasepool {
      id<MTLFence> fence = [device newFence]; if (!fence) return 1;
      if (fence.device.registryID != device.registryID) return 2;
      NSMutableString *label = [NSMutableString stringWithFormat:@"fence-%lu",
                                (unsigned long)iteration];
      NSString *expected = [label copy]; fence.label = label;
      [label appendString:@"-mutated"];
      if (![fence.label isEqualToString:expected]) return 3;
      fence.label = nil; if (fence.label != nil) return 4;

      id<MTLBuffer> source = [device newBufferWithLength:64
        options:MTLResourceStorageModeShared];
      id<MTLBuffer> destination = [device newBufferWithLength:64
        options:MTLResourceStorageModeShared];
      id<MTLCommandBuffer> command = [queue commandBuffer];
      id<MTLBlitCommandEncoder> producer = [command blitCommandEncoder];
      [producer fillBuffer:source range:NSMakeRange(0,64)
                     value:(uint8_t)(iteration & 0xff)];
      [producer updateFence:fence]; [producer endEncoding];
      id<MTLBlitCommandEncoder> consumer = [command blitCommandEncoder];
      [consumer waitForFence:fence];
      [consumer copyFromBuffer:source sourceOffset:0 toBuffer:destination
             destinationOffset:0 size:64];
      [consumer endEncoding];
      __weak id<MTLFence> weak_fence = fence; fence = nil;
      if (weak_fence == nil) return 5;
      [command commit]; [command waitUntilCompleted];
      if (command.status != MTLCommandBufferStatusCompleted) return 6;
      const uint8_t expected_byte = (uint8_t)(iteration & 0xff);
      const uint8_t *bytes = static_cast<const uint8_t *>(destination.contents);
      for (NSUInteger index=0; index<64; ++index)
        if (bytes[index] != expected_byte) return 7;
    }
  }
  return 0;
} }
