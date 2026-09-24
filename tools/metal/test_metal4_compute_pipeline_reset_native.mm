#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype(((MTL4ComputePipelineDescriptor *)nil).requiredThreadsPerThreadgroup),
    MTLSize>);

static bool has_reset_state(MTL4ComputePipelineDescriptor *descriptor,
                            MTL4IndirectCommandBufferSupportState indirect)
{
  MTLSize threads = descriptor.requiredThreadsPerThreadgroup;
  return descriptor.computeFunctionDescriptor == nil &&
         descriptor.maxTotalThreadsPerThreadgroup == 0 &&
         descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth == NO &&
         threads.width == 0 && threads.height == 0 && threads.depth == 0 &&
         descriptor.supportBinaryLinking == NO &&
         descriptor.staticLinkingDescriptor != nil &&
         descriptor.supportIndirectCommandBuffers == indirect;
}

int main()
{
  if (@available(macOS 26.0, *)) {
    __weak MTL4FunctionDescriptor *weak_function = nil;
    __weak MTL4StaticLinkingDescriptor *weak_linking = nil;
    @autoreleasepool {
      MTL4ComputePipelineDescriptor *descriptor =
          [MTL4ComputePipelineDescriptor new];
      if (descriptor == nil ||
          !has_reset_state(
              descriptor, MTL4IndirectCommandBufferSupportStateDisabled))
        return 1;
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
      if (descriptor.computeFunctionDescriptor == nil ||
          descriptor.staticLinkingDescriptor == nil)
        return 2;
      /* Both descriptor properties copy their source graphs. */
      if (weak_function != nil || weak_linking != nil) return 6;
      [descriptor reset];
      /* Reset preserves the independently configured indirect-command policy. */
      if (!has_reset_state(
              descriptor, MTL4IndirectCommandBufferSupportStateEnabled))
        return 3;
      if (weak_function != nil || weak_linking != nil) return 4;
      /* Reset is safely idempotent and preserves exact defaults. */
      [descriptor reset];
      if (!has_reset_state(
              descriptor, MTL4IndirectCommandBufferSupportStateEnabled))
        return 5;
    }
  }
  return 0;
}
