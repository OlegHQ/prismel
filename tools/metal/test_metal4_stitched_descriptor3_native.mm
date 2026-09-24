#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static bool paired(NSUInteger descriptors, BOOL graph, NSUInteger devices,
                   BOOL graphDevice) {
  if (descriptors == 0 && !graph) return devices == 0 && !graphDevice;
  return descriptors > 0 && graph && devices == descriptors && graphDevice;
}

int main() { @autoreleasepool {
  if (!paired(0, NO, 0, NO) || paired(1, NO, 1, NO)
      || paired(1, YES, 0, YES) || !paired(2, YES, 2, YES)) return 1;
  if (@available(macOS 26.0, *)) {
    MTL4StitchedFunctionDescriptor *descriptor = [MTL4StitchedFunctionDescriptor new];
    MTL4FunctionDescriptor *function = [MTL4FunctionDescriptor new];
    MTLFunctionStitchingInputNode *input =
      [[MTLFunctionStitchingInputNode alloc] initWithArgumentIndex:0];
    MTLFunctionStitchingFunctionNode *output = [[MTLFunctionStitchingFunctionNode alloc]
      initWithName:@"identity" arguments:@[input] controlDependencies:@[]];
    MTLFunctionStitchingGraph *graph = [[MTLFunctionStitchingGraph alloc]
      initWithFunctionName:@"stitched" nodes:@[output] outputNode:output attributes:@[]];
    if (descriptor == nil || function == nil || graph == nil) return 77;
    __weak MTLFunctionStitchingGraph *weak = graph;
    descriptor.functionDescriptors = @[function]; descriptor.functionGraph = graph;
    graph = nil;
    /* The SDK may copy the graph on assignment; either copied or retained
       ownership is valid as long as the descriptor preserves the graph. */
    (void)weak;
    if (descriptor.functionGraph == nil
        || descriptor.functionDescriptors.count != 1) return 2;
    descriptor.functionGraph = nil; descriptor.functionDescriptors = nil;
    if (descriptor.functionGraph != nil || descriptor.functionDescriptors != nil) return 3;
  }
  return 0;
} }
