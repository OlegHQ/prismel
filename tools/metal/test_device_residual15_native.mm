#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTLDevice>)nil).architecture),
                             MTLArchitecture *>);
static_assert(std::is_same_v<decltype(((id<MTLFence>)nil).device),
                             id<MTLDevice>>);

int main()
{
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;

    id<MTLFence> fence = [device newFence];
    id<MTLCounterSampleBuffer> samples = nil;
    MTLCounterSampleBufferDescriptor *descriptor =
        [MTLCounterSampleBufferDescriptor new];
    descriptor.sampleCount = 2;
    for (id<MTLCounterSet> set in device.counterSets) {
      if ([set.name isEqualToString:MTLCommonCounterSetTimestamp]) {
        descriptor.counterSet = set;
        break;
      }
    }
    if (descriptor.counterSet != nil) {
      NSError *error = nil;
      samples = [device newCounterSampleBufferWithDescriptor:descriptor
                                                        error:&error];
      if (samples == nil && error == nil) return 1;
    }
    if (fence == nil || fence.device.registryID != device.registryID) return 2;
    if (samples != nil && samples.device.registryID != device.registryID) return 3;

    if (@available(macOS 26.0, *)) {
      if ([device supportsFamily:MTLGPUFamilyMetal4]) {
        id<MTL4CommandQueue> queue = [device newMTL4CommandQueue];
        if (queue == nil) return 4;
      }
    }
  }
  return 0;
}
