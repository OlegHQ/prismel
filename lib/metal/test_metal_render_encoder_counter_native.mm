#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cassert>

int main() {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device != nil);
    if (![device supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary]
        || ![device supportsCounterSampling:MTLCounterSamplingPointAtDrawBoundary])
      return 0; // Render-encoder sampling is unsupported on this device.
    id<MTLCounterSet> timestamp = nil;
    for (id<MTLCounterSet> set in device.counterSets)
      if ([set.name isEqualToString:MTLCommonCounterSetTimestamp]) timestamp = set;
    if (timestamp == nil) return 0; // Honest capability gate.
    MTLCounterSampleBufferDescriptor *counter_descriptor = [MTLCounterSampleBufferDescriptor new];
    counter_descriptor.counterSet = timestamp;
    counter_descriptor.sampleCount = 1;
    counter_descriptor.storageMode = MTLStorageModeShared;
    NSError *error = nil;
    id<MTLCounterSampleBuffer> counters =
      [device newCounterSampleBufferWithDescriptor:counter_descriptor error:&error];
    assert(counters != nil && error == nil);
    MTLTextureDescriptor *td =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                        width:1 height:1 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [device newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    [encoder sampleCountersInBuffer:counters atSampleIndex:0 withBarrier:YES];
    [encoder endEncoding]; [commands commit]; [commands waitUntilCompleted];
    assert(commands.status == MTLCommandBufferStatusCompleted);
  }
  return 0;
}
