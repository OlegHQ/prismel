#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstdio>
int main(){@autoreleasepool{id<MTLRenderPipelineState>p=nil;(void)[p respondsToSelector:@selector(newRenderPipelineStateWithAdditionalBinaryFunctions:error:)];if(@available(macOS 26.0,*)){(void)[p respondsToSelector:@selector(newRenderPipelineStateWithBinaryFunctions:error:)];(void)[p respondsToSelector:@selector(newRenderPipelineDescriptorForSpecialization)];}std::puts("RenderPipeline93 state factories: exact3 availability passed");return 0;}}
