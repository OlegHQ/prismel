#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <type_traits>

static_assert(std::is_same_v<
    decltype(((MTL4StitchedFunctionDescriptor *)nil).functionGraph),
    MTLFunctionStitchingGraph *>);

int main()
{
  if (@available(macOS 26.0, *)) {
    __weak MTL4StitchedFunctionDescriptor *weak_owner = nil;
    __weak MTL4FunctionDescriptor *weak_function = nil;
    @autoreleasepool {
      MTL4StitchedFunctionDescriptor *owner =
          [MTL4StitchedFunctionDescriptor new];
      if (owner == nil) return 77;
      weak_owner = owner;
      @autoreleasepool {
        MTL4FunctionDescriptor *function = [MTL4FunctionDescriptor new];
        MTLFunctionStitchingInputNode *input =
            [[MTLFunctionStitchingInputNode alloc] initWithArgumentIndex:0];
        MTLFunctionStitchingFunctionNode *output =
            [[MTLFunctionStitchingFunctionNode alloc]
                         initWithName:@"identity"
                            arguments:@[ input ]
                  controlDependencies:@[]];
        MTLFunctionStitchingGraph *graph =
            [[MTLFunctionStitchingGraph alloc]
                initWithFunctionName:@"stitched_entry"
                               nodes:@[ output ]
                          outputNode:output
                          attributes:@[]];
        if (function == nil || graph == nil) return 1;
        weak_function = function;
        owner.functionDescriptors = @[ function ];
        owner.functionGraph = graph;
        function = nil;
        graph = nil;
      }

      /* The descriptor must preserve the complete semantic graph after all
         caller-owned construction values leave scope.  The SDK may retain or
         copy the classic stitching graph, so identity is deliberately not
         required. */
      if (weak_function == nil || owner.functionDescriptors.count != 1 ||
          owner.functionGraph == nil ||
          ![owner.functionGraph.functionName isEqualToString:@"stitched_entry"] ||
          owner.functionGraph.nodes.count != 1 ||
          owner.functionGraph.outputNode == nil)
        return 2;

      owner.functionGraph = nil;
      owner.functionDescriptors = nil;
      if (owner.functionGraph != nil || owner.functionDescriptors != nil)
        return 3;
    }
    if (weak_owner != nil || weak_function != nil) return 4;
  }
  return 0;
}
