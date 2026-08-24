#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<decltype(((id<MTL4MachineLearningPipelineState>)nil).label),
  NSString *>);

int main() { @autoreleasepool {
  if (@available(macOS 26.0, *)) {
    if (NSProtocolFromString(@"MTL4MachineLearningPipelineState") == nil
        || ![MTL4MachineLearningPipelineDescriptor instancesRespondToSelector:@selector(label)]
        || ![MTL4MachineLearningPipelineReflection instancesRespondToSelector:@selector(bindings)])
      return 1;
    __strong NSString *snapshot = nil;
    @autoreleasepool {
      MTL4MachineLearningPipelineDescriptor *descriptor =
        [MTL4MachineLearningPipelineDescriptor new];
      descriptor.label = @"ml_pipeline_λ";
      snapshot = [descriptor.label copy];
      descriptor.label = nil;
      if (descriptor.label != nil) return 2;
    }
    if (![snapshot isEqualToString:@"ml_pipeline_λ"]
        || snapshot.UTF8String == nullptr) return 3;
  }
  return 0;
} }
