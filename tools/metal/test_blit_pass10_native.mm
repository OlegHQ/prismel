#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static bool valid_index(NSInteger index, NSInteger capacity) {
  return index >= 0 && index < capacity;
}

int main() { @autoreleasepool {
  if (valid_index(-1, 4) || valid_index(4, 4) || !valid_index(3, 4)) return 1;
  MTLBlitPassDescriptor *pass = [MTLBlitPassDescriptor blitPassDescriptor];
  if (pass == nil || pass.sampleBufferAttachments == nil) return 2;
  MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
    pass.sampleBufferAttachments[0];
  if (attachment == nil || attachment.sampleBuffer != nil) return 3;
  attachment.startOfEncoderSampleIndex = 1;
  attachment.endOfEncoderSampleIndex = 3;
  if (attachment.startOfEncoderSampleIndex != 1
      || attachment.endOfEncoderSampleIndex != 3) return 4;
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) return 77;
  id<MTLCounterSet> timestamp = nil;
  for (id<MTLCounterSet> set in device.counterSets)
    if ([set.name isEqualToString:MTLCommonCounterSetTimestamp]) timestamp = set;
  if (timestamp == nil) return 77;
  MTLCounterSampleBufferDescriptor *descriptor = [MTLCounterSampleBufferDescriptor new];
  descriptor.counterSet = timestamp; descriptor.sampleCount = 4;
  descriptor.storageMode = MTLStorageModeShared;
  NSError *error = nil;
  id<MTLCounterSampleBuffer> samples =
    [device newCounterSampleBufferWithDescriptor:descriptor error:&error];
  if (samples == nil) return 77;
  __weak id<MTLCounterSampleBuffer> weak = samples;
  attachment.sampleBuffer = samples; samples = nil;
  if (weak == nil || attachment.sampleBuffer == nil
      || attachment.sampleBuffer.device.registryID != device.registryID) return 5;
  pass.sampleBufferAttachments[0] = attachment;
  if (pass.sampleBufferAttachments[0].sampleBuffer == nil) return 6;
  pass.sampleBufferAttachments[0].sampleBuffer = nil;
  if (pass.sampleBufferAttachments[0].sampleBuffer != nil) return 7;
  return 0;
} }
