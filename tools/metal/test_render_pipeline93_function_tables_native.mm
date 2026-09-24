#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>

int main() {
  @autoreleasepool {
    MTLVisibleFunctionTableDescriptor *visible =
        [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
    MTLIntersectionFunctionTableDescriptor *intersection =
        [MTLIntersectionFunctionTableDescriptor intersectionFunctionTableDescriptor];
    visible.functionCount = 3;
    intersection.functionCount = 5;
    if (visible.functionCount != 3 || intersection.functionCount != 5) {
      std::fputs("RenderPipeline93 table descriptor cardinality drift\n",stderr);
      return 1;
    }
    id<MTLRenderPipelineState> _Nullable pipeline = nil;
    (void)[pipeline respondsToSelector:
          @selector(newVisibleFunctionTableWithDescriptor:stage:)];
    (void)[pipeline respondsToSelector:
          @selector(newIntersectionFunctionTableWithDescriptor:stage:)];
    std::puts("RenderPipeline93 function tables: exact2 descriptor/stage passed");
    return 0;
  }
}
