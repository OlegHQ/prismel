#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype([MTLBlitPassDescriptor blitPassDescriptor]),
    MTLBlitPassDescriptor *>);
static_assert(std::is_same_v<
    decltype(((MTLBlitPassDescriptor *)nil).sampleBufferAttachments),
    MTLBlitPassSampleBufferAttachmentDescriptorArray *>);

int main()
{
  __weak MTLBlitPassDescriptor *weak_pass = nil;
  __weak MTLBlitPassSampleBufferAttachmentDescriptorArray *weak_array = nil;
  __weak id<MTLCounterSampleBuffer> weak_samples = nil;
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil) return 77;
    id<MTLCounterSet> timestamp = nil;
    for (id<MTLCounterSet> set in device.counterSets)
      if ([set.name isEqualToString:MTLCommonCounterSetTimestamp]) {
        timestamp = set;
        break;
      }
    if (timestamp == nil) return 77;

    MTLCounterSampleBufferDescriptor *sample_descriptor =
        [MTLCounterSampleBufferDescriptor new];
    sample_descriptor.counterSet = timestamp;
    sample_descriptor.sampleCount = 8;
    sample_descriptor.storageMode = MTLStorageModeShared;
    NSError *error = nil;
    id<MTLCounterSampleBuffer> samples =
        [device newCounterSampleBufferWithDescriptor:sample_descriptor error:&error];
    if (samples == nil) return 77;
    weak_samples = samples;

    @autoreleasepool {
      MTLBlitPassDescriptor *pass = [MTLBlitPassDescriptor blitPassDescriptor];
      if (pass == nil || pass.sampleBufferAttachments == nil) return 1;
      weak_pass = pass;
      weak_array = pass.sampleBufferAttachments;
      MTLBlitPassSampleBufferAttachmentDescriptor *attachment =
          pass.sampleBufferAttachments[0];
      if (attachment == nil) return 2;
      attachment.sampleBuffer = samples;
      attachment.startOfEncoderSampleIndex = 2;
      attachment.endOfEncoderSampleIndex = 6;
      samples = nil;

      /* The attachment owns its nullable sample buffer, while the pass owns
         the attachment array.  Child lookup preserves all assigned values. */
      if (weak_samples == nil || pass.sampleBufferAttachments != weak_array ||
          pass.sampleBufferAttachments[0].sampleBuffer != weak_samples ||
          pass.sampleBufferAttachments[0].startOfEncoderSampleIndex != 2 ||
          pass.sampleBufferAttachments[0].endOfEncoderSampleIndex != 6)
        return 3;

      pass.sampleBufferAttachments[0].sampleBuffer = nil;
      pass.sampleBufferAttachments[0].startOfEncoderSampleIndex = MTLCounterDontSample;
      pass.sampleBufferAttachments[0].endOfEncoderSampleIndex = MTLCounterDontSample;
      if (pass.sampleBufferAttachments[0].sampleBuffer != nil ||
          pass.sampleBufferAttachments[0].startOfEncoderSampleIndex !=
              MTLCounterDontSample ||
          pass.sampleBufferAttachments[0].endOfEncoderSampleIndex !=
              MTLCounterDontSample)
        return 4;
    }
    if (weak_pass != nil || weak_array != nil) return 5;
  }
  if (weak_samples != nil) return 6;
  return 0;
}
