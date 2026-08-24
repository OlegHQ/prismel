#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype(((id<MTL4ComputeCommandEncoder>)nil).commandBuffer),
    id<MTL4CommandBuffer>>);

int main()
{
  if (@available(macOS 26.0, *)) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device == nil || ![device supportsFamily:MTLGPUFamilyMetal4]) return 0;
    __weak id<MTL4CommandBuffer> weak_command = nil;
    __weak id<MTL4ComputeCommandEncoder> weak_encoder = nil;
    @autoreleasepool {
      id<MTL4CommandAllocator> allocator = [device newCommandAllocator];
      id<MTL4CommandBuffer> command = [device newCommandBuffer];
      if (allocator == nil || command == nil) return 77;
      [command beginCommandBufferWithAllocator:allocator];
      id<MTL4ComputeCommandEncoder> encoder = command.computeCommandEncoder;
      if (encoder == nil || encoder.commandBuffer != command) return 1;
      weak_command = command;
      weak_encoder = encoder;

      SEL selectors[] = {
        @selector(buildAccelerationStructure:descriptor:scratchBuffer:),
        @selector(copyFromTensor:sourceOrigin:sourceDimensions:toTensor:
                  destinationOrigin:destinationDimensions:),
        @selector(refitAccelerationStructure:descriptor:destination:scratchBuffer:),
        @selector(refitAccelerationStructure:descriptor:destination:scratchBuffer:
                  options:),
        @selector(writeCompactedAccelerationStructureSize:toBuffer:)
      };
      for (SEL selector : selectors)
        if (![encoder respondsToSelector:selector]) return 2;

      id<MTLBuffer> scratch =
          [device newBufferWithLength:4096 options:MTLResourceStorageModePrivate];
      if (scratch == nil || scratch.device.registryID != device.registryID ||
          scratch.gpuAddress == 0)
        return 3;
      MTL4BufferRange range = MTL4BufferRangeMake(scratch.gpuAddress, 4096);
      if (range.bufferAddress != scratch.gpuAddress || range.length != 4096)
        return 4;

      /* Resource operations are only issued once valid AS/tensor constructor
         graphs exist.  This fixture proves the real encoder/command owner and
         exact typed range that the safe wrappers must retain through end. */
      [encoder endEncoding];
      [command endCommandBuffer];
      encoder = nil;
      command = nil;
      allocator = nil;
    }
    if (weak_encoder != nil || weak_command != nil) return 5;
  }
  return 0;
}
