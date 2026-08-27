#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <type_traits>

static const char *const kIds[] = {
  "class:MTL4MachineLearningPipelineDescriptor",
  "class:MTL4MachineLearningPipelineReflection",
  "method:-[MTL4MachineLearningPipelineState label]",
  "property:MTL4MachineLearningPipelineState:label",
  "protocol:MTL4MachineLearningPipelineState",
  "method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]",
  "method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]",
  "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]",
  "method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]",
  "method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]",
  "method:-[MTL4MachineLearningCommandEncoder dispatchNetworkWithIntermediatesHeap:]",
  "method:-[MTL4MachineLearningCommandEncoder setArgumentTable:]",
  "method:-[MTL4MachineLearningCommandEncoder setPipelineState:]",
  "protocol:MTL4MachineLearningCommandEncoder"
};
static_assert(sizeof(kIds) / sizeof(kIds[0]) == 14);

int main(void) { @autoreleasepool {
  if (@available(macOS 26.0, *)) {
    MTL4MachineLearningPipelineDescriptor *descriptor =
      [MTL4MachineLearningPipelineDescriptor new];
    descriptor.label = @"prismel-ml";
    if (![descriptor.label isEqualToString:@"prismel-ml"] ||
        NSProtocolFromString(@"MTL4MachineLearningPipelineState") == nil ||
        NSProtocolFromString(@"MTL4MachineLearningCommandEncoder") == nil)
      return 1;
    SEL selectors[] = {
      @selector(buildAccelerationStructure:descriptor:scratchBuffer:),
      @selector(copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:),
      @selector(refitAccelerationStructure:descriptor:destination:scratchBuffer:),
      @selector(refitAccelerationStructure:descriptor:destination:scratchBuffer:options:),
      @selector(writeCompactedAccelerationStructureSize:toBuffer:),
      @selector(dispatchNetworkWithIntermediatesHeap:),
      @selector(setArgumentTable:), @selector(setPipelineState:)
    };
    for (SEL selector : selectors) if (selector == nullptr) return 2;
  }
  NSLog(@"MTL4 ML/compute exact14 typed availability conformance passed");
  return 0;
}}
