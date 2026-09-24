#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLFence>)nil).device),
                             id<MTLDevice>>);

int main()
{
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil || ![device supportsFamily:MTLGPUFamilyMetal4]) return 0;
    __weak id<MTLFence> weak_fence = nil;
    @autoreleasepool {
      id<MTL4CommandAllocator> allocator = [device newCommandAllocator];
      id<MTL4CommandBuffer> command = [device newCommandBuffer];
      id<MTLFence> fence = [device newFence];
      if (allocator == nil || command == nil || fence == nil) return 77;
      weak_fence = fence;
      [command beginCommandBufferWithAllocator:allocator];

      id<MTL4ComputeCommandEncoder> producer = command.computeCommandEncoder;
      if (producer == nil || producer.commandBuffer != command) return 1;
      [producer updateFence:fence afterEncoderStages:MTLStageBlit];
      [producer endEncoding];

      id<MTL4ComputeCommandEncoder> consumer = command.computeCommandEncoder;
      if (consumer == nil || consumer.commandBuffer != command) return 2;
      @try {
        [consumer waitForFence:fence beforeEncoderStages:MTLStageBlit];
      } @catch (NSException *exception) {
        (void)exception;
        return 3;
      }
      [consumer endEncoding];
      [command endCommandBuffer];
      /* MTLFence is unretained command metadata. Keep the application-owned
         fence alive until every encoder referring to it has ended. */
      if (weak_fence == nil) return 4;
      fence = nil;
      consumer = nil;
      producer = nil;
      command = nil;
      allocator = nil;
    }
    if (weak_fence != nil) return 5;
  }
  return 0;
}
