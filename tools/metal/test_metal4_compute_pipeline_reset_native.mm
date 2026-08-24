#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype(((MTL4ComputePipelineDescriptor *)nil).requiredThreadsPerThreadgroup),
    MTLSize>);

static bool is_default(MTL4ComputePipelineDescriptor *descriptor)
{
  MTLSize threads = descriptor.requiredThreadsPerThreadgroup;
  return descriptor.computeFunctionDescriptor == nil &&
         descriptor.maxTotalThreadsPerThreadgroup == 0 &&
         descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth == NO &&
         threads.width == 0 && threads.height == 0 && threads.depth == 0 &&
         descriptor.supportBinaryLinking == NO &&
         descriptor.staticLinkingDescriptor == nil &&
         descriptor.supportIndirectCommandBuffers ==
             MTL4IndirectCommandBufferSupportStateDisabled;
}

int main()
{
  if (@available(macOS 26.0, *)) {
    __weak MTL4FunctionDescriptor *weak_function = nil;
    __weak MTL4StaticLinkingDescriptor *weak_linking = nil;
    @autoreleasepool {
      MTL4ComputePipelineDescriptor *descriptor =
          [MTL4ComputePipelineDescriptor new];
      if (descriptor == nil || !is_default(descriptor)) return 1;
      @autoreleasepool {
        MTL4LibraryFunctionDescriptor *function =
            [MTL4LibraryFunctionDescriptor new];
        MTL4StaticLinkingDescriptor *linking =
            [MTL4StaticLinkingDescriptor new];
        weak_function = function;
        weak_linking = linking;
        descriptor.computeFunctionDescriptor = function;
        descriptor.maxTotalThreadsPerThreadgroup = 128;
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;
        descriptor.requiredThreadsPerThreadgroup = MTLSizeMake(8, 4, 2);
        descriptor.supportBinaryLinking = YES;
        descriptor.staticLinkingDescriptor = linking;
        descriptor.supportIndirectCommandBuffers =
            MTL4IndirectCommandBufferSupportStateEnabled;
      }
      if (weak_function == nil || weak_linking == nil ||
          descriptor.computeFunctionDescriptor == nil ||
          descriptor.staticLinkingDescriptor == nil)
        return 2;
      [descriptor reset];
      if (!is_default(descriptor)) return 3;
      if (weak_function != nil || weak_linking != nil) return 4;
      /* Reset is safely idempotent and preserves exact defaults. */
      [descriptor reset];
      if (!is_default(descriptor)) return 5;
    }
  }
  return 0;
}
