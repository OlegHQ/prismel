#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main()
{
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLCommandQueue> bounded =
        [device newCommandQueueWithMaxCommandBufferCount:2];
    if (bounded == nil || bounded.device.registryID != device.registryID) return 1;
    if (@available(macOS 26.0, *)) {
      if ([device supportsFamily:MTLGPUFamilyMetal4]) {
        id<MTL4CommandQueue> queue = [device newMTL4CommandQueue];
        if (queue == nil || queue.device.registryID != device.registryID) return 2;
      }
    }
  }
  return 0;
}
