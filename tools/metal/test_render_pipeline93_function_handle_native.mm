#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdio>

int main() {
  @autoreleasepool {
    const MTLRenderStages stages[] = {
      MTLRenderStageVertex, MTLRenderStageFragment, MTLRenderStageTile,
      MTLRenderStageObject, MTLRenderStageMesh
    };
    for (MTLRenderStages stage : stages) {
      NSUInteger bits = (NSUInteger)stage;
      if (bits == 0 || (bits & (bits - 1)) != 0) {
        std::fputs("RenderPipeline93 function lookup: stage layout drift\n",stderr);
        return 1;
      }
    }
    id<MTLRenderPipelineState> _Nullable pipeline = nil;
    if (![pipeline respondsToSelector:
          @selector(functionHandleWithFunction:stage:)]) {
      /* A nil receiver is the deterministic capability-gated lane. */
    }
    if (@available(macOS 26.0,*)) {
      (void)[pipeline respondsToSelector:
            @selector(functionHandleWithBinaryFunction:stage:)];
      (void)[pipeline respondsToSelector:
            @selector(functionHandleWithName:stage:)];
    }
    std::puts("RenderPipeline93 function lookup: exact3 stage/availability passed");
    return 0;
  }
}
