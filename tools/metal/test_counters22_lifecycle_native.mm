#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>

static const char *const kCounter22Ids[] = {
    "method:-[MTLCounter name]", "method:-[MTLCounterSampleBuffer device]",
    "method:-[MTLCounterSampleBuffer label]",
    "method:-[MTLCounterSampleBuffer resolveCounterRange:]",
    "method:-[MTLCounterSampleBuffer sampleCount]",
    "method:-[MTLCounterSampleBufferDescriptor counterSet]",
    "method:-[MTLCounterSampleBufferDescriptor label]",
    "method:-[MTLCounterSampleBufferDescriptor setCounterSet:]",
    "method:-[MTLCounterSampleBufferDescriptor setLabel:]",
    "method:-[MTLCounterSet counters]", "method:-[MTLCounterSet name]",
    "property:MTLCounter:name", "property:MTLCounterSampleBuffer:device",
    "property:MTLCounterSampleBuffer:label",
    "property:MTLCounterSampleBuffer:sampleCount",
    "property:MTLCounterSampleBufferDescriptor:counterSet",
    "property:MTLCounterSampleBufferDescriptor:label",
    "property:MTLCounterSet:counters", "property:MTLCounterSet:name",
    "protocol:MTLCounter", "protocol:MTLCounterSampleBuffer",
    "protocol:MTLCounterSet",
};
static_assert(sizeof(kCounter22Ids) / sizeof(kCounter22Ids[0]) == 22,
              "Counters22 exact closure drift");

int main() {
  @autoreleasepool {
    (void)kCounter22Ids;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    if (![device supportsCounterSampling:MTLCounterSamplingPointAtBlitBoundary])
      return 77;

    id<MTLCounterSet> timestamps = nil;
    for (id<MTLCounterSet> set in device.counterSets) {
      if (set.name.length == 0 || set.counters.count == 0) return 1;
      for (id<MTLCounter> counter in set.counters)
        if (counter.name.length == 0) return 2;
      if ([set.name isEqualToString:MTLCommonCounterSetTimestamp])
        timestamps = set;
    }
    if (timestamps == nil) return 77;

    MTLCounterSampleBufferDescriptor *descriptor =
        [MTLCounterSampleBufferDescriptor new];
    descriptor.counterSet = timestamps;
    descriptor.label = @"prismel-counters22";
    descriptor.sampleCount = 2;
    descriptor.storageMode = MTLStorageModeShared;
    if (descriptor.counterSet != timestamps ||
        ![descriptor.label isEqualToString:@"prismel-counters22"])
      return 3;

    __weak id<MTLCounterSet> weak_set = timestamps;
    timestamps = nil;
    if (weak_set == nil || descriptor.counterSet != weak_set) return 4;
    NSError *error = nil;
    id<MTLCounterSampleBuffer> samples =
        [device newCounterSampleBufferWithDescriptor:descriptor error:&error];
    if (samples == nil) return error == nil ? 5 : 77;
    if (samples.device.registryID != device.registryID || samples.sampleCount != 2 ||
        ![samples.label isEqualToString:@"prismel-counters22"])
      return 6;

    id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit sampleCountersInBuffer:samples atSampleIndex:0 withBarrier:YES];
    [blit sampleCountersInBuffer:samples atSampleIndex:1 withBarrier:YES];
    [blit endEncoding];
    [command commit];
    [command waitUntilCompleted];
    if (command.status != MTLCommandBufferStatusCompleted) return 7;

    NSData *resolved = [samples resolveCounterRange:NSMakeRange(0, 2)];
    if (resolved == nil || resolved.length == 0) return 8;
    if ([samples resolveCounterRange:NSMakeRange(2, 1)] != nil) return 9;
  }
  return 0;
}
