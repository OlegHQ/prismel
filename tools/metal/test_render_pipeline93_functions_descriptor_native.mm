#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>

int main() {
  @autoreleasepool {
    MTLRenderPipelineFunctionsDescriptor *descriptor =
        [MTLRenderPipelineFunctionsDescriptor new];
    NSArray<id<MTLFunction>> *empty = @[];
    descriptor.vertexAdditionalBinaryFunctions = empty;
    descriptor.fragmentAdditionalBinaryFunctions = empty;
    descriptor.tileAdditionalBinaryFunctions = empty;
    if (descriptor.vertexAdditionalBinaryFunctions.count != 0 ||
        descriptor.fragmentAdditionalBinaryFunctions.count != 0 ||
        descriptor.tileAdditionalBinaryFunctions.count != 0) {
      std::fputs("RenderPipeline93 functions descriptor array drift\n",stderr);
      return 1;
    }
    std::puts("RenderPipeline93 functions descriptor: exact10 arrays passed");
    return 0;
  }
}
